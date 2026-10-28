// Interface orientation: root scene orientation, arbitration and actuation
// refresh, scene geometry requests, and the backboardd and embedded
// orientation probes.

#import "FoldDisplayPrivate.h"

static NSMutableDictionary<NSString *, NSDictionary *> *vpSavedSceneOrientations;
static atomic_uint vpSceneOrientationPulseGeneration;
static __weak id vpGeometryRequestScene;
static NSInteger vpGeometryRequestOriginal;
static NSInteger vpGeometryRequestTarget;
static atomic_uint vpGeometryRequestGeneration;
static __weak id vpOrientationEventsManager;
static BOOL vpOriginalOrientationEventsEnabled;
static atomic_uint vpOrientationEventsGeneration;
static IMP vpOriginalTollFreeOrientationConversion;
static __weak id vpCanonicalOrientationScene;
static atomic_uint vpCanonicalOrientationGeneration;
static __weak id vpEmbeddedOrientationApplication;
static __weak id vpEmbeddedOrientationScene;
static NSInteger vpEmbeddedOrientationOriginal, vpEmbeddedOrientationPublished;
static atomic_uint vpEmbeddedOrientationGeneration;

@protocol VPhoneGeometryPreferencesInitializing
- (instancetype)initWithInterfaceOrientations:(NSUInteger)orientations;
@end

// MARK: - root scene orientation

void vpProbeUnknownDisplayPolicy(BOOL restore) {
    static BOOL saved = NO, original = NO;
    @try {
        id monitor = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        SEL getter = sel_registerName("allowsUnknownDisplays");
        SEL setter = sel_registerName("setAllowsUnknownDisplays:");
        Method method = class_getInstanceMethod(object_getClass(monitor), setter);
        if (![monitor respondsToSelector:getter] || !method ||
            strcmp(method_getTypeEncoding(method), "v20@0:8B16") != 0) {
            vpFoldDisplayLog(@"unknown display policy: unavailable");
            return;
        }
        if (!saved) {
            original = ((BOOL (*)(id, SEL))objc_msgSend)(monitor, getter);
            saved = YES;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(monitor, setter, restore ? original : YES);
        BOOL actual = ((BOOL (*)(id, SEL))objc_msgSend)(monitor, getter);
        vpFoldDisplayLog([NSString stringWithFormat:@"unknown display policy: original=%d actual=%d restore=%d",
            original, actual, restore]);
        vpSnapshotMainScene();
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"unknown display policy exception: %@", exception.reason]);
    }
}

static void vpSetRootSceneOrientation(id scene, NSInteger orientation, NSNumber *expected, unsigned int generation) {
    SEL update = sel_registerName("updateUISettingsWithBlock:");
    Method method = class_getInstanceMethod(object_getClass(scene), update);
    if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@?16") != 0) {
        vpFoldDisplayLog(@"root orientation: settings-update ABI unavailable"); return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(scene, update, ^(id settings) {
        @try {
            if (generation != atomic_load_explicit(&vpSceneOrientationPulseGeneration, memory_order_acquire) ||
                ![[settings valueForKey:@"interfaceOrientation"] isEqual:expected]) return;
            SEL setter = sel_registerName("setInterfaceOrientation:");
            NSMethodSignature *signature = [settings methodSignatureForSelector:setter];
            if (!signature || signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v' ||
                strcmp([signature getArgumentTypeAtIndex:2], "q") != 0) return;
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, setter, orientation);
            vpFoldDisplayLog([NSString stringWithFormat:@"root orientation: %@ submitted=%ld frame=%@ generation=%u",
                vpReadObject(scene, "identifier"), (long)orientation, vpReadRectValue(settings, "frame"), generation]);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"root orientation transaction exception: %@", exception.reason]);
        }
    });
}

static void vpRestoreRootSceneOrientationsAttempt(unsigned int generation, unsigned int attempt) {
    if (generation != atomic_load_explicit(&vpSceneOrientationPulseGeneration, memory_order_acquire) ||
        !vpSavedSceneOrientations.count) return;
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    NSMutableSet *present = [NSMutableSet set];
    for (id scene in vpRootServerScenes(app)) {
        @try {
            NSString *identifier = vpReadObject(scene, "identifier");
            NSDictionary *saved = vpSavedSceneOrientations[identifier];
            if (!saved) continue;
            [present addObject:identifier];
            // A reconstructed scene with the same identifier owns new state.
            // Never replay an old instance's saved orientation into it.
            if ([saved[@"scope"] anyObject] != scene) {
                [vpSavedSceneOrientations removeObjectForKey:identifier];
                vpFoldDisplayLog(@"root orientation: old scene scope ended");
                continue;
            }
            NSNumber *current = [vpReadObject(scene, "uiSettings") valueForKey:@"interfaceOrientation"];
            if (![current isKindOfClass:NSNumber.class]) continue;
            if ([current isEqual:saved[@"original"]] || ![current isEqual:saved[@"published"]]) {
                [vpSavedSceneOrientations removeObjectForKey:identifier];
                vpFoldDisplayLog([NSString stringWithFormat:@"root orientation: %@ %@",
                    identifier, [current isEqual:saved[@"original"]] ? @"restoration verified" : @"newer setting preserved"]);
                continue;
            }
            vpSetRootSceneOrientation(scene, [saved[@"original"] integerValue], saved[@"published"], generation);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"root orientation restore exception: %@", exception.reason]);
        }
    }
    for (NSString *identifier in [vpSavedSceneOrientations.allKeys copy]) {
        // A temporary profile lookup miss is not proof of scene removal.
        // Keep a live scene's checkpoint for retry; only a cleared weak
        // reference establishes that the original scope has ended.
        if (![present containsObject:identifier] && ![vpSavedSceneOrientations[identifier][@"scope"] anyObject]) {
            [vpSavedSceneOrientations removeObjectForKey:identifier];
            vpFoldDisplayLog([NSString stringWithFormat:@"root orientation: %@ scene removed", identifier]);
        }
    }
    if (vpSavedSceneOrientations.count && attempt < 3) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            vpRestoreRootSceneOrientationsAttempt(generation, attempt + 1);
        });
    } else if (vpSavedSceneOrientations.count) {
        // Keep the checkpoint for an explicit restore retry; submission is
        // not readback proof and must not discard failed cleanup state.
        vpFoldDisplayLog([NSString stringWithFormat:@"root orientation: restoration pending for %lu scene(s)",
            (unsigned long)vpSavedSceneOrientations.count]);
    }
}

void vpRestoreRootSceneOrientations(void) {
    // Cancel delayed publication blocks before starting restoration.
    unsigned int generation = atomic_fetch_add_explicit(&vpSceneOrientationPulseGeneration, 1, memory_order_acq_rel) + 1;
    vpRestoreRootSceneOrientationsAttempt(generation, 0);
}

// Default-off pulse: publish the existing native arbitration result through
// the common root scene contract. No window transform/frame or app mask is
// supplied. Restoration starts after ten seconds and keeps a checkpoint
// until readback proves restoration or a newer setting supersedes it.
void vpSyncRootSceneOrientation(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id windowScene = vpMainInnerWindowScene();
        if (!windowScene) {
            vpFoldDisplayLog(@"root orientation: pulse refused outside the real Main inner scene");
            return;
        }
        id pipeline = vpReadObject(windowScene, "traitsPipelineManager");
        NSInteger orientation = [[pipeline valueForKey:@"systemArbitratedInterfaceOrientation"] integerValue];
        if (orientation < 1 || orientation > 4) return;
        NSString *identifier = vpReadObject(vpReadObject(windowScene, "_FBSScene"), "identifier");
        if (!identifier) return;
        if (!vpSavedSceneOrientations) vpSavedSceneOrientations = [NSMutableDictionary dictionary];
        unsigned int generation = atomic_fetch_add_explicit(&vpSceneOrientationPulseGeneration, 1, memory_order_acq_rel) + 1;
        for (id scene in vpRootServerScenes(app)) {
            if (![vpReadObject(scene, "identifier") isEqual:identifier]) continue;
            id settings = vpReadObject(scene, "uiSettings");
            id uiIdentity = vpReadObject(windowScene, "_fbsDisplayIdentity") ?: vpReadObject(windowScene, "displayIdentity");
            if (![vpReadObject(vpReadObject(settings, "sb_hostedDisplayConfiguration"), "identity") isEqual:uiIdentity]) continue;
            NSNumber *previous = [settings valueForKey:@"interfaceOrientation"];
            if (![previous isKindOfClass:NSNumber.class] || previous.integerValue < 1 || previous.integerValue > 4) continue;
            if (previous.integerValue == orientation) {
                vpFoldDisplayLog(@"root orientation: scene settings already match native arbitration");
                continue;
            }
            NSDictionary *saved = vpSavedSceneOrientations[identifier];
            BOOL sameScope = [saved[@"scope"] anyObject] == scene;
            NSHashTable *scope = sameScope ? saved[@"scope"] : [NSHashTable weakObjectsHashTable];
            if (!sameScope) [scope addObject:scene];
            vpSavedSceneOrientations[identifier] = @{
                @"original": sameScope ? saved[@"original"] : previous,
                @"published": @(orientation), @"scope": scope,
            };
            vpFoldDisplayLog([NSString stringWithFormat:@"root orientation: pulse %@ previous=%@ native=%ld",
                identifier, previous, (long)orientation]);
            vpSetRootSceneOrientation(scene, orientation, previous, generation);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == atomic_load_explicit(&vpSceneOrientationPulseGeneration, memory_order_acquire))
                vpRestoreRootSceneOrientations();
        });
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"root orientation pulse exception: %@", exception.reason]);
    }
}

// MARK: - arbitration scene

id vpMainInnerWindowScene(void) {
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    id scene = vpReadObject(app, "activeDisplayWindowScene") ?: vpUIConfigWindowScene;
    id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
    id identity = vpReadObject(configuration, "identity");
    id uiIdentity = vpReadObject(scene, "_fbsDisplayIdentity") ?: vpReadObject(scene, "displayIdentity");
    BOOL realMain = [uiIdentity isEqual:identity];
    // The only accepted alias is our currently leased UI identity, parented
    // by the unchanged real Main. Do not admit arbitrary external scenes.
    BOOL ownedAlias = scene == vpUIConfigWindowScene && vpUIConfigPublished &&
        [uiIdentity isEqual:vpReadObject(vpUIConfigPublished, "identity")] &&
        [vpReadObject(uiIdentity, "rootIdentity") isEqual:identity] &&
        vpReadObject(vpUIConfigPublished, "CADisplay") == vpReadObject(configuration, "CADisplay");
    if (![[scene valueForKey:@"surfaceType"] isEqual:@2] ||
        !(realMain || ownedAlias) ||
        ![[identity valueForKey:@"isMainRootDisplay"] boolValue]) return nil;
    return scene;
}

// The orientation machinery must also run while the persistent viewport
// holds the cover mode: the active scene is the same SB-main scene under
// the cover identity, and a fold transition must not strand the interface
// at the direction the mode swap computed with the previous panel's pose
// (observed: closed computed landscape from the inner portrait pose and
// nothing re-arbitrated it).  Accept the active scene only while the
// persistent viewport is live and it carries the current Main identity.
id vpOrientationArbitrationScene(void) {
    id inner = vpMainInnerWindowScene();
    if (inner) return inner;
    if (!vpPersistentViewport) return nil;
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    id scene = vpReadObject(app, "activeDisplayWindowScene");
    if (!scene) return nil;
    id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
    id identity = vpReadObject(configuration, "identity");
    id uiIdentity = vpReadObject(scene, "_fbsDisplayIdentity") ?: vpReadObject(scene, "displayIdentity");
    if (!identity || ![uiIdentity isEqual:identity]) return nil;
    return scene;
}

// MARK: - scene geometry requests

static void vpRequestSceneGeometry(id scene, NSInteger orientation) {
    @try {
        if (!scene || orientation < 1 || orientation > 4) return;
        Class preferencesClass = objc_getClass("UIWindowSceneGeometryPreferencesIOS");
        SEL initializer = sel_registerName("initWithInterfaceOrientations:");
        SEL request = sel_registerName("requestGeometryUpdateWithPreferences:errorHandler:");
        Method initMethod = class_getInstanceMethod(preferencesClass, initializer);
        Method requestMethod = class_getInstanceMethod(object_getClass(scene), request);
        if (!initMethod || strcmp(method_getTypeEncoding(initMethod), "@24@0:8Q16") != 0 ||
            !requestMethod || strcmp(method_getTypeEncoding(requestMethod), "v32@0:8@16@?24") != 0) {
            vpFoldDisplayLog(@"scene geometry request: native API ABI unavailable");
            return;
        }
        // Public iOS geometry API, verified against the local iOS 27.1 SDK.
        // UIKit chooses from supported orientations; this does not change
        // any application's mask or directly rotate a window/layer.
        id preferences = [(id<VPhoneGeometryPreferencesInitializing>)[preferencesClass alloc]
            initWithInterfaceOrientations:1UL << orientation];
        ((void (*)(id, SEL, id, id))objc_msgSend)(scene, request, preferences, ^(NSError *error) {
            vpFoldDisplayLog([NSString stringWithFormat:@"scene geometry request: error %@/%ld %@",
                error.domain, (long)error.code, error.localizedDescription]);
        });
        vpFoldDisplayLog([NSString stringWithFormat:@"scene geometry request: submitted orientation=%ld", (long)orientation]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"scene geometry request exception: %@", exception.reason]);
    }
}

void vpRestoreSceneGeometryRequest(void) {
    atomic_fetch_add_explicit(&vpGeometryRequestGeneration, 1, memory_order_acq_rel);
    id scene = vpGeometryRequestScene;
    vpGeometryRequestScene = nil;
    if (!scene || scene != vpMainInnerWindowScene()) return;
    NSInteger current = [[scene valueForKey:@"interfaceOrientation"] integerValue];
    if (current == vpGeometryRequestTarget || current == vpGeometryRequestOriginal)
        vpRequestSceneGeometry(scene, vpGeometryRequestOriginal);
    else vpFoldDisplayLog(@"scene geometry request: newer direction preserved");
}

void vpProbeSceneGeometryRequest(void) {
    @try {
        id scene = vpMainInnerWindowScene();
        if (!scene) { vpFoldDisplayLog(@"scene geometry request: refused outside Main inner"); return; }
        vpRestoreSceneGeometryRequest();
        NSInteger original = [[scene valueForKey:@"interfaceOrientation"] integerValue];
        NSInteger target = [[vpReadObject(scene, "traitsPipelineManager") valueForKey:@"systemArbitratedInterfaceOrientation"] integerValue];
        if (original < 1 || original > 4 || target < 1 || target > 4) return;
        vpGeometryRequestScene = scene;
        vpGeometryRequestOriginal = original;
        vpGeometryRequestTarget = target;
        unsigned int generation = atomic_fetch_add_explicit(&vpGeometryRequestGeneration, 1, memory_order_acq_rel) + 1;
        vpRequestSceneGeometry(scene, target);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == atomic_load_explicit(&vpGeometryRequestGeneration, memory_order_acquire))
                vpRestoreSceneGeometryRequest();
        });
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"scene geometry probe exception: %@", exception.reason]);
    }
}

// MARK: - native inputs, arbitration and actuation

void vpRefreshNativeOrientationInputs(BOOL rereadPose) {
    @try {
        id scene = vpOrientationArbitrationScene();
        if (!scene) { vpFoldDisplayLog(@"orientation refresh: refused outside Main inner"); return; }
        id pipeline = vpReadObject(scene, "traitsPipelineManager");
        SEL selector = sel_registerName(rereadPose ? "_updateDeviceOrientationAnimated:forReason:" : "_noteInputsNeedUpdateAnimated:reason:");
        Method method = class_getInstanceMethod(object_getClass(pipeline), selector);
        if (!method || strcmp(method_getTypeEncoding(method), "v28@0:8B16@20") != 0) {
            vpFoldDisplayLog(@"orientation refresh: native API ABI unavailable");
            return;
        }
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(pipeline, selector, NO, @"vphone settled pose/input refresh");
        vpFoldDisplayLog([NSString stringWithFormat:@"orientation refresh: native %@ requested", rereadPose ? @"pose" : @"inputs"]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"orientation refresh exception: %@", exception.reason]);
    }
}

void vpForceNativeOrientationResolution(void) {
    @try {
        id scene = vpOrientationArbitrationScene();
        if (!scene) { vpFoldDisplayLog(@"orientation arbitration: refused outside Main inner"); return; }
        id arbiter = vpReadObject(scene, "traitsArbiter");
        SEL factory = sel_registerName("_defaultUpdateContextWithReason:animatable:");
        SEL mark = sel_registerName("setNeedsUpdateArbitrationWithContext:");
        SEL update = sel_registerName("updateArbitrationIfNeeded");
        Method fm = class_getInstanceMethod(object_getClass(arbiter), factory);
        Method mm = class_getInstanceMethod(object_getClass(arbiter), mark);
        Method um = class_getInstanceMethod(object_getClass(arbiter), update);
        if (!fm || strcmp(method_getTypeEncoding(fm), "@28@0:8@16B24") != 0 ||
            !mm || strcmp(method_getTypeEncoding(mm), "v24@0:8@16") != 0 ||
            !um || strcmp(method_getTypeEncoding(um), "v16@0:8") != 0) {
            vpFoldDisplayLog(@"orientation arbitration: native context API unavailable"); return;
        }
        id context = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(arbiter, factory, @"vphone coherent orientation resolution", NO);
        SEL force = sel_registerName("setForceOrientationResolution:");
        Method forceMethod = class_getInstanceMethod(object_getClass(context), force);
        if (!forceMethod || strcmp(method_getTypeEncoding(forceMethod), "v20@0:8B16") != 0) return;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(context, force, YES);
        ((void (*)(id, SEL, id))objc_msgSend)(arbiter, mark, context);
        ((void (*)(id, SEL))objc_msgSend)(arbiter, update);
        vpFoldDisplayLog(@"orientation arbitration: native force-resolution context submitted");
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"orientation arbitration exception: %@", exception.reason]);
    }
}

// Real inner panels use a rotated mounting convention. The single Main VM
// retains the portrait framebuffer. Use the native paired conversion branch
// for one explicitly scoped experiment; never write individual window angles.
static BOOL vpCanonicalOrientationConversion(id self, SEL selector) {
    if (self == vpCanonicalOrientationScene && [[self valueForKey:@"surfaceType"] isEqual:@2]) return YES;
    return ((BOOL (*)(id, SEL))vpOriginalTollFreeOrientationConversion)(self, selector);
}

void vpSetCanonicalOrientationProbe(BOOL enabled) {
    @try {
        id scene = enabled ? vpMainInnerWindowScene() : vpCanonicalOrientationScene;
        if (enabled && !scene) { vpFoldDisplayLog(@"canonical orientation: refused outside Main inner"); return; }
        if (enabled) {
            id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
            if (![vpSnapshotRect(configuration, "bounds") isEqual:@[@0, @0, @678, @951]]) {
                vpFoldDisplayLog(@"canonical orientation: refused unexpected panel bounds"); return;
            }
            if (!vpOriginalTollFreeOrientationConversion) {
                Method method = class_getInstanceMethod(object_getClass(scene), sel_registerName("_hasTollFreeDeviceAndInterfaceOrientationConversion"));
                if (!method || strcmp(method_getTypeEncoding(method), "B16@0:8") != 0) return;
                vpOriginalTollFreeOrientationConversion = method_setImplementation(method, (IMP)vpCanonicalOrientationConversion);
            }
        }
        unsigned int generation = atomic_fetch_add_explicit(&vpCanonicalOrientationGeneration, 1, memory_order_acq_rel) + 1;
        vpCanonicalOrientationScene = enabled ? scene : nil;
        vpFoldDisplayLog([NSString stringWithFormat:@"canonical orientation: %@ generation=%u", enabled ? @"enabled" : @"restored", generation]);
        if (scene == vpMainInnerWindowScene()) vpForceNativeOrientationResolution();
        if (enabled) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == atomic_load_explicit(&vpCanonicalOrientationGeneration, memory_order_acquire))
                vpSetCanonicalOrientationProbe(NO);
        });
    } @catch (NSException *exception) {
        vpCanonicalOrientationScene = nil;
        vpFoldDisplayLog([NSString stringWithFormat:@"canonical orientation exception: %@", exception.reason]);
    }
}

void vpRefreshNativeOrientationActuation(void) {
    @try {
        id scene = vpOrientationArbitrationScene();
        if (!scene) { vpFoldDisplayLog(@"orientation actuation: refused outside Main inner"); return; }
        // The bridge must exist before the first rotation the wallpaper
        // follows; installing on every actuation keeps it armed across
        // wallpaper controller re-creation.
        vpInstallWallpaperOrientationBridge();
        NSInteger direction = [[vpReadObject(scene, "traitsPipelineManager") valueForKey:@"systemArbitratedInterfaceOrientation"] integerValue];
        // The cover presentation is portrait-native, but the single-scene
        // emulation's arbiter carries the direction the mode swap computed
        // from the inner panel's rotated pose and no input channel reopens
        // it (pose, pose-refresh, arbitration, accelerometer all verified
        // portrait while the pipeline stays landscape). Complete the same
        // native callback chain with the cover's native direction instead
        // of the latched one.
        if (scene != vpMainInnerWindowScene()) {
            if (direction != 1) vpFoldDisplayLog([NSString stringWithFormat:
                @"orientation actuation: cover direction %ld overridden to portrait", (long)direction]);
            direction = 1;
        }
        if (direction < 1 || direction > 4) return;
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        SEL selector = sel_registerName("_notePipelineManagerChangedInterfaceOrientation:onWindowScene:duration:force:logMessage:");
        Method method = class_getInstanceMethod(object_getClass(app), selector);
        if (!method || strcmp(method_getTypeEncoding(method), "v52@0:8q16@24d32B40@44") != 0) return;
        // Replay the existing shared native pipeline callback with its own
        // resolved direction; no status-window setter or custom mask is used.
        ((void (*)(id, SEL, NSInteger, id, CGFloat, BOOL, id))objc_msgSend)(app, selector,
            direction, scene, 0, YES, @"vphone native orientation actuation refresh");
        vpFoldDisplayLog([NSString stringWithFormat:@"orientation actuation: native callback direction=%ld", (long)direction]);
        // The Main mode keeps portrait dimensions on this platform, so a
        // rotation also needs UIKit to re-deliver the scene's coordinate
        // space; otherwise the portrait layout renders sideways inside the
        // rotated framebuffer. The public geometry request for the actuated
        // direction makes the space swap (951x669) and the icon family and
        // windows re-flow.
        vpRequestSceneGeometry(scene, direction);
        vpScheduleQuickActionGlyphScale();
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"orientation actuation exception: %@", exception.reason]);
    }
}

// MARK: - embedded orientation probe

void vpRestoreEmbeddedOrientation(void) {
    atomic_fetch_add_explicit(&vpEmbeddedOrientationGeneration, 1, memory_order_acq_rel);
    id app = vpEmbeddedOrientationApplication;
    id scene = vpEmbeddedOrientationScene;
    if (!app || scene != vpMainInnerWindowScene()) {
        vpEmbeddedOrientationApplication = nil;
        vpEmbeddedOrientationScene = nil;
        return;
    }
    @try {
        NSInteger current = [[app valueForKey:@"statusBarOrientationForEmbeddedDisplay"] integerValue];
        if (current != vpEmbeddedOrientationPublished) {
            vpEmbeddedOrientationApplication = nil;
            vpEmbeddedOrientationScene = nil;
            vpFoldDisplayLog(@"embedded orientation: newer native value preserved"); return;
        }
        ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(app,
            sel_registerName("setStatusBarOrientation:forEmbeddedDisplayAnimated:"), vpEmbeddedOrientationOriginal, NO);
        NSInteger readback = [[app valueForKey:@"statusBarOrientationForEmbeddedDisplay"] integerValue];
        if (readback == vpEmbeddedOrientationOriginal) {
            vpEmbeddedOrientationApplication = nil;
            vpEmbeddedOrientationScene = nil;
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"embedded orientation: restore original=%ld readback=%ld verified=%d",
            (long)vpEmbeddedOrientationOriginal, (long)readback, readback == vpEmbeddedOrientationOriginal]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"embedded orientation restore exception: %@", exception.reason]);
    }
}

void vpProbeEmbeddedOrientation(void) {
    @try {
        vpRestoreEmbeddedOrientation();
        if (vpEmbeddedOrientationApplication) {
            vpFoldDisplayLog(@"embedded orientation: prior restoration pending"); return;
        }
        id scene = vpMainInnerWindowScene();
        if (!scene) { vpFoldDisplayLog(@"embedded orientation: refused outside Main inner"); return; }
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        NSInteger target = [[vpReadObject(scene, "traitsPipelineManager") valueForKey:@"systemArbitratedInterfaceOrientation"] integerValue];
        NSInteger original = [[app valueForKey:@"statusBarOrientationForEmbeddedDisplay"] integerValue];
        SEL setter = sel_registerName("setStatusBarOrientation:forEmbeddedDisplayAnimated:");
        Method method = class_getInstanceMethod(object_getClass(app), setter);
        if (!method || strcmp(method_getTypeEncoding(method), "v28@0:8q16B24") != 0 ||
            original < 1 || original > 4 || target < 1 || target > 4 || original == target) return;
        vpEmbeddedOrientationApplication = app;
        vpEmbeddedOrientationScene = scene;
        vpEmbeddedOrientationOriginal = original;
        vpEmbeddedOrientationPublished = target;
        unsigned int generation = atomic_fetch_add_explicit(&vpEmbeddedOrientationGeneration, 1, memory_order_acq_rel) + 1;
        // Synchronize the native embedded-display direction slot with the
        // existing arbiter output. No individual window receives a direction.
        ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(app, setter, target, NO);
        vpFoldDisplayLog([NSString stringWithFormat:@"embedded orientation: pulse %ld -> %ld readback=%@",
            (long)original, (long)target, [app valueForKey:@"statusBarOrientationForEmbeddedDisplay"]]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == atomic_load_explicit(&vpEmbeddedOrientationGeneration, memory_order_acquire))
                vpRestoreEmbeddedOrientation();
        });
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"embedded orientation pulse exception: %@", exception.reason]);
    }
}

// MARK: - backboardd orientation events

static id vpBackboardOrientationManager(void) {
    return vpReadObject(objc_getClass("BKOrientationManager"), "sharedInstance");
}

static void vpSnapshotBackboardOrientationNow(void) {
    @try {
        id manager = vpBackboardOrientationManager();
        NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithDictionary:@{
            @"pid": @(getpid()), @"time": @(CFAbsoluteTimeGetCurrent())}];
        for (NSString *key in @[@"isOrientationEventsEnabled", @"isDeviceOrientationLocked"])
            snapshot[key] = vpReadBoolValue(manager, key.UTF8String) ?: NSNull.null;
        for (NSString *key in @[@"currentRawDeviceOrientation", @"effectiveDeviceOrientation", @"currentUserInterfaceOrientation", @"lastEffectiveInterfaceOrientation"]) {
            SEL getter = NSSelectorFromString(key);
            NSMethodSignature *signature = [manager methodSignatureForSelector:getter];
            if (signature.numberOfArguments == 2 && strcmp(signature.methodReturnType, "q") == 0)
                snapshot[key] = @(((NSInteger (*)(id, SEL))objc_msgSend)(manager, getter));
        }
        id display = vpReadObject(objc_getClass("CADisplay"), "mainDisplay");
        if (!display) for (id candidate in vpReadObject(objc_getClass("CADisplay"), "displays"))
            if ([vpReadObject(candidate, "deviceName") isEqual:@"primary"]) { display = candidate; break; }
        SEL supports = sel_registerName("displaySupportsRotation:");
        Method method = class_getInstanceMethod(object_getClass(manager), supports);
        if (display && method && strcmp(method_getTypeEncoding(method), "B24@0:8@16") == 0)
            snapshot[@"primarySupportsRotation"] = @(((BOOL (*)(id, SEL, id))objc_msgSend)(manager, supports, display));
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
        if (data) vpFoldDisplayLog([@"backboard orientation " stringByAppendingString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"backboard orientation snapshot exception: %@", exception.reason]);
    }
}

void vpSnapshotBackboardOrientation(void) {
    // Native getters synchronize with the orientation manager and may query
    // CoreAnimation. Keep the backboardd main run loop free while observing.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        vpSnapshotBackboardOrientationNow();
    });
}

void vpRestoreBackboardOrientationEvents(void) {
    @try {
        atomic_fetch_add_explicit(&vpOrientationEventsGeneration, 1, memory_order_acq_rel);
        id manager = vpOrientationEventsManager;
        if (!manager || manager != vpBackboardOrientationManager()) { vpOrientationEventsManager = nil; return; }
        SEL setter = sel_registerName("setOrientationEventsEnabled:");
        Method method = class_getInstanceMethod(object_getClass(manager), setter);
        if (!method || strcmp(method_getTypeEncoding(method), "v20@0:8B16") != 0) return;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(manager, setter, vpOriginalOrientationEventsEnabled);
        vpOrientationEventsManager = nil;
        vpSnapshotBackboardOrientation();
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"backboard orientation events restore exception: %@", exception.reason]);
    }
}

void vpProbeBackboardOrientationEvents(void) {
    @try {
        if (!atomic_load_explicit(&vpInnerSurfaceProbeEnabled, memory_order_acquire) || atomic_load_explicit(&vpPrimarySurfaceType, memory_order_acquire) != 2) {
            vpFoldDisplayLog(@"backboard orientation events: refused outside inner metadata probe"); return;
        }
        if (vpOrientationEventsManager) vpRestoreBackboardOrientationEvents();
        id manager = vpBackboardOrientationManager();
        NSNumber *enabled = vpReadBoolValue(manager, "isOrientationEventsEnabled");
        SEL setter = sel_registerName("setOrientationEventsEnabled:");
        Method method = class_getInstanceMethod(object_getClass(manager), setter);
        if (!enabled || !method || strcmp(method_getTypeEncoding(method), "v20@0:8B16") != 0) return;
        if (enabled.boolValue) {
            vpFoldDisplayLog(@"backboard orientation events: already enabled, no mutation");
            vpSnapshotBackboardOrientation();
            return;
        }
        vpOrientationEventsManager = manager;
        vpOriginalOrientationEventsEnabled = enabled.boolValue;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(manager, setter, YES);
        vpFoldDisplayLog([NSString stringWithFormat:@"backboard orientation events: temporary enable, original=%@", enabled]);
        vpSnapshotBackboardOrientation();
        unsigned int generation = atomic_fetch_add_explicit(&vpOrientationEventsGeneration, 1, memory_order_acq_rel) + 1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == atomic_load_explicit(&vpOrientationEventsGeneration, memory_order_acquire))
                vpRestoreBackboardOrientationEvents();
        });
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"backboard orientation events exception: %@", exception.reason]);
    }
}
