// The single-Main logical viewport: cover and inner viewport requests, scene
// bounds adoption after a transform publishes, and the persistent viewport.

#import "FoldDisplayPrivate.h"

atomic_bool vpCoverViewportEnabled;
BOOL vpPersistentViewport;
IMP vpOriginalLogicalSurfaceType;
static _Thread_local BOOL vpReadingLogicalSurface;
atomic_uint vpViewportRequestGeneration;
atomic_bool vpNativeGeometryRefreshEnabled;
static atomic_uint vpWindowGeometryRefreshGeneration;
atomic_bool vpSceneResizePropagationEnabled;
IMP vpOriginalSBWindowResizePolicy;
static __weak id vpSceneResizeScope;
NSMutableDictionary<NSString *, NSNumber *> *vpResizedSceneGenerations;

static void vpApplyRootGeometry(void);

// MARK: - adoption after a transform

// The generation whose post-transform adoption pass already ran.
static atomic_uint vpAdoptionCompletedGeneration;

// The overridden Main configuration keeps its identity, so FrontBoard
// pushes no scene-settings update when only the mode size changed. The
// 3803cc4d root-geometry pass published the active bounds to the SB-main
// root scene through its settings-mutation API; recovered here.
void vpScheduleViewportAdoption(void) {
    unsigned int adoptionGeneration = atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed);
    if (adoptionGeneration == atomic_load_explicit(&vpAdoptionCompletedGeneration, memory_order_relaxed)) return;
    atomic_store_explicit(&vpAdoptionCompletedGeneration, adoptionGeneration, memory_order_relaxed);
    vpApplyRootGeometry();
    if (vpPersistentViewport) {
        vpProcessViewportWorkspaceRequest(YES);
        // The cover arbiter derives its direction once, at the mode swap,
        // from the pre-swap pose, and holds it; vphoned's confirm loop
        // corrects it only after the bounds settle, leaving a landscape
        // frame visible for about a second. Complete the actuation with
        // the cover's native portrait in the same adoption turn.
        if (atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire))
            vpRefreshNativeOrientationActuation();
    }
}
static void vpApplyRootGeometry(void) {
    if (!vpAutomaticMainStatus) return;
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        if (!app || !configuration) return;
        NSArray *bounds = vpSnapshotRect(configuration, "bounds");
        if (![bounds isKindOfClass:NSArray.class] || bounds.count != 4) return;
        // The 3803cc4d pass (___vpUpdateRootSceneGeometry_block_invoke) set
        // the frame on every root scene through updateUISettingsWithBlock:,
        // whose block receives the mutable settings. The native geometry
        // callback then propagates: icon family switch and window resizes.
        CGRect frame = CGRectMake(0, 0, [bounds[2] doubleValue], [bounds[3] doubleValue]);
        // The cover mode is smaller than the physical surface and the scene
        // renders it at the surface's top-left; the host window crops that
        // region and presents it full-bleed, so the origin stays at zero —
        // centering here would desynchronize the two sides.
        for (id scene in vpRootServerScenes(app)) {
            id identifier = vpReadObject(scene, "identifier");
            if (![identifier isEqual:@"SB-main"] &&
                ![identifier isEqual:@"SB-systemAperture"] &&
                ![identifier isEqual:@"SB-systemApertureCurtain"]) continue;
            SEL updateSelector = sel_registerName("updateUISettingsWithBlock:");
            Method update = class_getInstanceMethod(object_getClass(scene), updateSelector);
            if (!update || strcmp(method_getTypeEncoding(update), "v24@0:8@?16") != 0) {
                vpFoldDisplayLog(@"root geometry: settings-update ABI unavailable");
                continue;
            }
            __block BOOL frameSet = NO;
            ((void (*)(id, SEL, id))objc_msgSend)(scene, updateSelector, ^(id settings) {
                @try {
                    if (!settings) return;
                    SEL frameSelector = sel_registerName("setFrame:");
                    Method frameSetter = class_getInstanceMethod(object_getClass(settings), frameSelector);
                    const char *frameABI = frameSetter ? method_getTypeEncoding(frameSetter) : NULL;
                    if (frameABI && strcmp(frameABI, "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16") == 0) {
                        ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, frameSelector, frame);
                        frameSet = YES;
                    } else if (frameABI && strcmp(frameABI, "v48@0:8{CGRect={CGPoint=ff}{CGSize=ff}}16") == 0) {
                        // 32-bit CGFloat ABI: pass the same frame in float slots.
                        ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, frameSelector, frame);
                        frameSet = YES;
                    } else {
                        vpFoldDisplayLog([NSString stringWithFormat:@"root geometry: frame setter ABI %s on %s",
                            frameABI ?: "absent", object_getClassName(settings)]);
                    }
                    Method hosted = class_getInstanceMethod(object_getClass(settings), sel_registerName("sb_setHostedDisplayConfiguration:"));
                    if (hosted && strcmp(method_getTypeEncoding(hosted), "v24@0:8@16") == 0)
                        ((void (*)(id, SEL, id))objc_msgSend)(settings, sel_registerName("sb_setHostedDisplayConfiguration:"), configuration);
                } @catch (NSException *exception) {
                    vpFoldDisplayLog([NSString stringWithFormat:@"root geometry settings exception: %@", exception.reason]);
                }
            });
            vpFoldDisplayLog([NSString stringWithFormat:@"root geometry: %@ settings frame=%@ generation=%u",
                identifier, frameSet ? [NSString stringWithFormat:@"(%.0f, %.0f, %.0f, %.0f)",
                    frame.origin.x, frame.origin.y, frame.size.width, frame.size.height] : @"unset",
                atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed)]);
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"root geometry exception: %@", exception.reason]);
    }
}

// MARK: - logical role and scene bounds

void vpLogicalProjectionControl(NSInteger action) {
    vpFoldDisplayLog([NSString stringWithFormat:@"logical projection control requested action=%ld", (long)action]);
}

void vpSyncLogicalRoleResolver(void) {
    @try {
        id resolver = vpLogicalRoleResolver;
        NSDictionary *proxies = vpReadObjectIvar(resolver, "_displayProxies");
        if (!vpLogicalRoleExperiment || proxies.count != 1) return;
        id proxy = proxies.allValues.firstObject;
        if (![vpReadObject(proxy, "identifier") isEqual:@"legacyMain"] ||
            [[proxy valueForKey:@"isExternal"] boolValue]) return;
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        if (![[vpReadObject(configuration, "identity") valueForKey:@"isMainRootDisplay"] boolValue]) return;
        SEL boundsSelector = sel_registerName("bounds");
        NSMethodSignature *signature = [configuration methodSignatureForSelector:boundsSelector];
        if (signature.methodReturnLength != sizeof(CGRect)) return;
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(configuration, boundsSelector);
        NSInteger role = CGRectEqualToRect(bounds, CGRectMake(0, 0, 669, 951)) ? 2 :
            (CGRectEqualToRect(bounds, CGRectMake(0, 0, 466, 678)) ? 1 : 0);
        SEL setter = sel_registerName("setSurfaceType:");
        SEL update = sel_registerName("_updateResolvedContentModesForDisplays");
        Method sm = class_getInstanceMethod(object_getClass(proxy), setter);
        Method um = class_getInstanceMethod(object_getClass(resolver), update);
        Ivar ready = class_getInstanceVariable(object_getClass(resolver), "_isReadyToResolve");
        if (!role || !sm || strcmp(method_getTypeEncoding(sm), "v24@0:8q16") != 0 ||
            !um || strcmp(method_getTypeEncoding(um), "v16@0:8") != 0 ||
            !ready || strcmp(ivar_getTypeEncoding(ready), "B") != 0) return;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(proxy, setter, role);
        [resolver setValue:@YES forKey:@"isReadyToResolve"];
        ((void (*)(id, SEL))objc_msgSend)(resolver, update);
        vpFoldDisplayLog([NSString stringWithFormat:@"logical surface resolver: single Main role=%ld %@", (long)role, resolver]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"logical surface resolver exception: %@", exception.reason]);
    }
}

BOOL vpAllowScopedMainWindowResize(id self, SEL cmd) {
    BOOL original = ((BOOL (*)(id, SEL))vpOriginalSBWindowResizePolicy)(self, cmd);
    id scope = vpSceneResizeScope;
    return original || (scope && vpReadObject(self, "windowScene") == scope);
}

// Native SBHIconManager owns the provider family independently of UIScreen.
// Its native setter rebuilds the provider and updates root-folder and Dock
// consumers; do not replace individual views or reset the user's icon model.
static void vpRefreshSceneIconFamily(id windowScene) {
    if (![vpReadObject(vpReadObject(windowScene, "_FBSScene"), "identifier") isEqual:@"SB-main"]) return;
    Method familyMethod = class_getInstanceMethod(object_getClass(windowScene), sel_registerName("sbhScreenType"));
    if (!familyMethod || strcmp(method_getTypeEncoding(familyMethod), "Q16@0:8") != 0) return;
    NSUInteger family = ((NSUInteger (*)(id, SEL))objc_msgSend)(windowScene, sel_registerName("sbhScreenType"));
    if (family != 31 && family != 32) return;
    for (id window in vpReadObject(windowScene, "windows")) {
        id controller = vpReadObject(window, "rootViewController");
        Class homeClass = objc_getClass("SBHomeScreenViewController");
        if (!homeClass || ![controller isKindOfClass:homeClass]) continue;
        id manager = vpReadObjectIvar(controller, "_iconManager");
        SEL update = sel_registerName("setScreenType:listLayoutProviderLayoutOptions:animated:");
        Method method = class_getInstanceMethod(object_getClass(manager), update);
        Method optionsMethod = class_getInstanceMethod(object_getClass(manager), sel_registerName("listLayoutProviderLayoutOptions"));
        Ivar screenType = class_getInstanceVariable(object_getClass(manager), "_screenType");
        if (!method || strcmp(method_getTypeEncoding(method), "v36@0:8Q16Q24B32") != 0 ||
            !optionsMethod || strcmp(method_getTypeEncoding(optionsMethod), "Q16@0:8") != 0 ||
            !screenType || strcmp(ivar_getTypeEncoding(screenType), "Q") != 0) return;
        NSUInteger before = [[manager valueForKey:@"screenType"] unsignedIntegerValue];
        NSUInteger options = ((NSUInteger (*)(id, SEL))objc_msgSend)(manager, sel_registerName("listLayoutProviderLayoutOptions"));
        ((void (*)(id, SEL, NSUInteger, NSUInteger, BOOL))objc_msgSend)(manager, update, family, options, NO);
        vpFoldDisplayLog([NSString stringWithFormat:@"native icon family: %lu -> %@ requested=%lu provider=%@",
            (unsigned long)before, [manager valueForKey:@"screenType"], (unsigned long)family,
            vpReadObject(manager, "listLayoutProvider")]);
        return;
    }
}

static void vpPropagateSceneBounds(id windowScene, unsigned int generation) {
    if (generation != atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed)) return;
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    NSString *identifier = vpReadObject(vpReadObject(windowScene, "_FBSScene"), "identifier");
    if (!identifier || vpResizedSceneGenerations[identifier].unsignedIntValue == generation) return;
    id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
    id identity = vpReadObject(configuration, "identity");
    BOOL owned = NO;
    for (id scene in vpRootServerScenes(app)) {
        id hosted = vpReadObject(vpReadObject(scene, "uiSettings"), "sb_hostedDisplayConfiguration");
        if ([vpReadObject(scene, "identifier") isEqual:identifier] &&
            [vpReadObject(hosted, "identity") isEqual:identity]) { owned = YES; break; }
    }
    if (!owned) return;
    CGRect target = ((CGRect (*)(id, SEL))objc_msgSend)(configuration, sel_registerName("bounds"));
    CGRect actual = ((CGRect (*)(id, SEL))objc_msgSend)(vpReadObject(windowScene, "coordinateSpace"), sel_registerName("bounds"));
    if (!CGSizeEqualToSize(target.size, actual.size)) return;
    vpResizedSceneGenerations[identifier] = @(generation);
    id previousScope = vpSceneResizeScope;
    NSUInteger notified = 0, changed = 0;
    @try {
        vpSceneResizeScope = windowScene;
        NSArray *windows = [vpReadObject(windowScene, "windows") copy];
        for (id window in windows) {
            if (vpReadObject(window, "windowScene") != windowScene ||
                !vpReadBoolValue(window, "_isSceneSized").boolValue) continue;
            // Preserve SpringBoard's TRA-owned transform/rotation state.
            // The full scene-bounds callback also updates transform layers;
            // only its native sizing substep belongs in this adapter.
            SEL update = sel_registerName("_resizeWindowFrameToSceneBoundsIfNecessary");
            Method method = class_getInstanceMethod(object_getClass(window), update);
            if (!method || strcmp(method_getTypeEncoding(method), "B16@0:8") != 0) continue;
            @try {
                NSValue *before = vpReadRectValue(window, "frame");
                ((BOOL (*)(id, SEL))objc_msgSend)(window, update);
                notified++;
                if (![before isEqual:vpReadRectValue(window, "frame")]) changed++;
            } @catch (NSException *exception) {
                vpFoldDisplayLog([NSString stringWithFormat:@"scene resize propagation window exception: %@", exception.reason]);
            }
        }
        if (vpLogicalRoleExperiment) vpSyncLogicalRoleResolver();
        vpRefreshSceneIconFamily(windowScene);
if (vpAutomaticMainStatus) vpRefreshMainStatusRenderer();
        if (vpPersistentViewport && [identifier isEqual:@"SB-main"])
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation == atomic_load_explicit(&vpViewportRequestGeneration, memory_order_acquire))
                    vpProcessViewportWorkspaceRequest(YES);
            });
    } @finally { vpSceneResizeScope = previousScope; }
    vpFoldDisplayLog([NSString stringWithFormat:@"scene resize propagation: %@ generation=%u native notifications=%lu frames changed=%lu",
        identifier, generation, (unsigned long)notified, (unsigned long)changed]);
}

void vpObserveSceneGeometry(id self, SEL cmd, id windowScene, id previousSpace,
                                   NSInteger previousOrientation, id previousTraits) {
    ((void (*)(id, SEL, id, id, NSInteger, id))vpOriginalSceneGeometryCallback)(
        self, cmd, windowScene, previousSpace, previousOrientation, previousTraits);
    if (!atomic_load_explicit(&vpNativeGeometryRefreshEnabled, memory_order_acquire) &&
        !atomic_load_explicit(&vpSceneResizePropagationEnabled, memory_order_acquire)) return;
    unsigned int generation = atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed);
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (generation != atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed)) return;
            if (atomic_load_explicit(&vpSceneResizePropagationEnabled, memory_order_acquire))
                vpPropagateSceneBounds(windowScene, generation);
            if (!atomic_load_explicit(&vpNativeGeometryRefreshEnabled, memory_order_acquire) ||
                generation == atomic_load_explicit(&vpWindowGeometryRefreshGeneration, memory_order_relaxed)) return;
            if (![vpReadObject(vpReadObject(windowScene, "_FBSScene"), "identifier") isEqual:@"SB-main"]) return;
            id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
            CGRect target = ((CGRect (*)(id, SEL))objc_msgSend)(configuration, sel_registerName("bounds"));
            id space = vpReadObject(windowScene, "coordinateSpace");
            CGRect actual = ((CGRect (*)(id, SEL))objc_msgSend)(space, sel_registerName("bounds"));
            if (!CGSizeEqualToSize(target.size, actual.size)) return;
            id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
            SEL update = sel_registerName("_notePipelineManagerChangedInterfaceOrientation:onWindowScene:duration:force:logMessage:");
            Method method = class_getInstanceMethod(object_getClass(app), update);
            if (!method || strcmp(method_getTypeEncoding(method), "v52@0:8q16@24d32B40@44") != 0) {
                vpFoldDisplayLog(@"native geometry refresh: pipeline callback ABI unavailable");
                return;
            }
            NSInteger orientation = ((NSInteger (*)(id, SEL))objc_msgSend)(windowScene, sel_registerName("interfaceOrientation"));
            if (orientation < 1 || orientation > 4) return;
            atomic_store_explicit(&vpWindowGeometryRefreshGeneration, generation, memory_order_relaxed);
            ((void (*)(id, SEL, NSInteger, id, CGFloat, BOOL, id))objc_msgSend)(app, update,
                orientation, windowScene, 0, YES, @"vphone logical display geometry refresh");
            vpFoldDisplayLog([NSString stringWithFormat:@"native geometry refresh: orientation=%ld generation=%u",
                (long)orientation, generation]);
            if (!atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire) &&
                generation == atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed))
                atomic_store_explicit(&vpNativeGeometryRefreshEnabled, false, memory_order_release);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"native geometry refresh exception: %@", exception.reason]);
        }
    });
}

// MARK: - viewport requests

void vpProcessViewportWorkspaceRequest(BOOL submit) {
    @try {
        id workspace = vpReadObject(objc_getClass("SBMainWorkspace"), "sharedInstance");
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        SEL create = sel_registerName("createRequestWithOptions:displayConfiguration:");
        Method method = class_getInstanceMethod(object_getClass(workspace), create);
        if (!workspace || !configuration || !method || strcmp(method_getTypeEncoding(method), "@32@0:8Q16@24") != 0) {
            vpFoldDisplayLog(@"viewport workspace preview: factory unavailable"); return;
        }
        // Native factory and local finalization only; never submit or run this preview.
        id request = ((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(workspace, create, 0, configuration);
        id context = vpReadObject(request, "applicationContext");
        vpFoldDisplayLog([NSString stringWithFormat:@"viewport workspace preview: request=%@ context=%@ from=%@ to=%@",
            vpReadMultilineDescription(request) ?: request, vpReadMultilineDescription(context) ?: context,
            vpReadObject(request, "fromApplicationSceneEntities"), vpReadObject(request, "toApplicationSceneEntities")]);
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id scene = vpReadObject(app, "activeDisplayWindowScene") ?: vpReadObject(app, "embeddedDisplayWindowScene");
        id coordinator = vpReadObject(scene, "layoutStateTransitionCoordinator");
id provider = vpReadObject(scene, "layoutStateProvider");
        id state = vpReadObject(provider, "layoutState");
        vpFoldDisplayLog([NSString stringWithFormat:@"viewport workspace current layout: scene=%@ coordinator=%@ provider=%@ state=%@",
            vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier"), coordinator, provider,
            vpReadMultilineDescription(state) ?: state]);
        NSArray *elements = [vpReadObject(state, "elements") allObjects];
        SEL previousSetter = sel_registerName("setPreviousEntity:forLayoutRole:");
        SEL targetSetter = sel_registerName("setEntity:forLayoutRole:");
        Method previousMethod = class_getInstanceMethod(object_getClass(context), previousSetter);
        Method targetMethod = class_getInstanceMethod(object_getClass(context), targetSetter);
        Method finalize = class_getInstanceMethod(object_getClass(request), sel_registerName("finalize"));
        vpFoldDisplayLog([NSString stringWithFormat:@"viewport workspace guard: elements=%lu previous=%d target=%d finalize=%d",
            (unsigned long)elements.count, previousMethod != NULL, targetMethod != NULL, finalize != NULL]);
        if (elements.count != 1 || !previousMethod || !targetMethod || !finalize ||
            strcmp(method_getTypeEncoding(previousMethod), "v32@0:8@16q24") != 0 ||
            strcmp(method_getTypeEncoding(targetMethod), "v32@0:8@16q24") != 0 ||
            strcmp(method_getTypeEncoding(finalize), "v16@0:8") != 0) return;
        id element = elements.firstObject;
        id entity = vpReadObject(element, "workspaceEntity");
        Method roleMethod = class_getInstanceMethod(object_getClass(element), sel_registerName("layoutRole"));
        if (!entity || !roleMethod || strcmp(method_getTypeEncoding(roleMethod), "q16@0:8") != 0) return;
        NSInteger role = ((NSInteger (*)(id, SEL))objc_msgSend)(element, sel_registerName("layoutRole"));
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(context, previousSetter, entity, role);
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(context, targetSetter, entity, role);
SEL attributesSelector = sel_registerName("layoutAttributesForElement:");
        SEL requestedAttributes = sel_registerName("setRequestedLayoutAttributes:forEntity:");
        Method attributesMethod = class_getInstanceMethod(object_getClass(state), attributesSelector);
        Method requestedMethod = class_getInstanceMethod(object_getClass(context), requestedAttributes);
        if (!attributesMethod || strcmp(method_getTypeEncoding(attributesMethod), "@24@0:8@16") != 0 ||
            !requestedMethod || strcmp(method_getTypeEncoding(requestedMethod), "v32@0:8@16@24") != 0) return;
        id attributes = ((id (*)(id, SEL, id))objc_msgSend)(state, attributesSelector, element);
        if (!attributes) return;
        ((void (*)(id, SEL, id, id))objc_msgSend)(context, requestedAttributes, attributes, entity);
        // Finalize the local request before optional controlled submission. Native context binds
        // its request and resolves entities/layout; no transaction is run.
        ((void (*)(id, SEL))objc_msgSend)(request, sel_registerName("finalize"));
        vpFoldDisplayLog([NSString stringWithFormat:@"viewport workspace finalized preview: role=%ld entity=%@ from=%@ to=%@ context=%@",
            (long)role, entity, vpReadObject(request, "fromApplicationSceneEntities"),
            vpReadObject(request, "toApplicationSceneEntities"), vpReadMultilineDescription(context) ?: context]);
        if (submit) {
            id identifier = vpReadObject(element, "uniqueIdentifier");
            NSSet *from = vpReadObject(request, "fromApplicationSceneEntities");
            NSSet *to = vpReadObject(request, "toApplicationSceneEntities");
            Class applicationEntity = objc_getClass("SBApplicationSceneEntity");
            if (!applicationEntity || ![entity isKindOfClass:applicationEntity] || role != 1 ||
                !identifier || from.count != 1 || to.count != 1 ||
                ![vpReadObject(from.anyObject, "uniqueIdentifier") isEqual:identifier] ||
                ![vpReadObject(to.anyObject, "uniqueIdentifier") isEqual:identifier] ||
                vpReadObject(provider, "layoutState") != state ||
                vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration") != configuration ||
                atomic_load_explicit(&vpViewportRequestGeneration, memory_order_acquire) == 0) {
                vpFoldDisplayLog(@"viewport workspace refresh: preservation guard refused"); return;
            }
            SEL execute = sel_registerName("executeTransitionRequest:");
            Method executeMethod = class_getInstanceMethod(object_getClass(workspace), execute);
            if (!executeMethod || strcmp(method_getTypeEncoding(executeMethod), "B24@0:8@16") != 0) return;
            BOOL accepted = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, execute, request);
            vpFoldDisplayLog([NSString stringWithFormat:@"viewport workspace refresh: submitted=%d same entity=%@", accepted, identifier]);
        }

    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"viewport workspace preview exception: %@", exception.reason]);
    }
}

void vpSetCoverViewport(BOOL enabled) {
    unsigned int generation = atomic_fetch_add_explicit(&vpViewportRequestGeneration, 1, memory_order_relaxed) + 1;
    atomic_store_explicit(&vpCoverViewportEnabled, enabled, memory_order_release);
    vpFoldDisplayLog([NSString stringWithFormat:@"single viewport: requested %@ generation=%u",
        enabled ? @"cover" : @"native inner", generation]);
    vpRefreshMainTransform();
    // The inner revert runs no transform branch of its own; a short delay
    // lets the native pipeline re-publish first, and the generation dedupe
    // keeps a transform-side schedule from double-running.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(),
        ^{ vpScheduleViewportAdoption(); });
    // The posture path polls the map for the applied bounds; publish after
    // the viewport settles so its confirmation loop sees the new size.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(),
        ^{ vpExportNativeOrientationMapping(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(),
        ^{
            vpExportNativeOrientationMapping();
            vpApplyQuickActionGlyphScale();
        });
    if (enabled && !vpPersistentViewport) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed) == generation &&
                atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire)) {
                vpFoldDisplayLog(@"single viewport: timed native-configuration restore");
                vpSetCoverViewport(NO);
            }
        });
    }
}

// A single physical Main remains a single hardware source. Its active
// logical SB-main surface follows the native canonical viewport dimensions.
// Scoped experiment: do not change CADisplay type or resolver source count.
NSInteger vpLogicalSurfaceType(id self, SEL selector) {
    NSInteger native = ((NSInteger (*)(id, SEL))vpOriginalLogicalSurfaceType)(self, selector);
    if (vpReadingLogicalSurface || !vpAutomaticMainStatus) return native;
    vpReadingLogicalSurface = YES;
    @try {
        if (![vpReadObject(vpReadObject(self, "_FBSScene"), "identifier") isEqual:@"SB-main"]) return native;
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        if (![vpReadObject(self, "displayIdentity") isEqual:vpReadObject(configuration, "identity")]) return native;
        NSArray *bounds = vpSnapshotRect(configuration, "bounds");
        if ([bounds isEqual:@[@0, @0, @669, @951]]) return 2;
        if ([bounds isEqual:@[@0, @0, @466, @678]]) return 1;
        return native;
    } @catch (NSException *exception) { return native; }
    @finally { vpReadingLogicalSurface = NO; }
}

void vpSetPersistentViewport(BOOL cover) {
    if (!vpAutomaticMainStatus || !vpOriginalSceneGeometryCallback || !vpOriginalSBWindowResizePolicy) return;
    if (vpPersistentViewport && atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire) == cover) return;
    vpPersistentViewport = YES;
    atomic_store_explicit(&vpNativeGeometryRefreshEnabled, false, memory_order_release);
    atomic_store_explicit(&vpSceneResizePropagationEnabled, true, memory_order_release);
    atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
    vpSetCoverViewport(cover);
}
