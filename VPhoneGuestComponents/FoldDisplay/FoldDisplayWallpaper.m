// Wallpaper: the native orientation pulse, poster scene-host sync, the
// device-to-interface bridge, the traits experiment, and the landscape gate.

#import "FoldDisplayPrivate.h"

static BOOL vpWallpaperOrientationLeaseActive;
static void *vpOriginalWallpaperFeatureLookup;
static IMP vpOriginalWallpaperSetHidden;
static BOOL vpWallpaperTraitsExperimentInstalled;

// MARK: - native orientation pulse

void vpPulseNativeWallpaperOrientation(void) {
    if (!vpLogicalRoleExperiment || vpWallpaperOrientationLeaseActive) return;
    id scene = vpMainInnerWindowScene();
    id wallpaper = vpReadObject(scene, "wallpaperController");
    SEL getter = sel_registerName("_WallpaperOrientationNotForYou");
    SEL update = sel_registerName("willAnimateRotationToInterfaceOrientation:duration:force:");
    SEL boundsUpdate = sel_registerName("_updateWallpaperContainerViewBoundsForOrientation:");
    Method gm = class_getInstanceMethod(object_getClass(wallpaper), getter);
    Method um = class_getInstanceMethod(object_getClass(wallpaper), update);
    Method bm = class_getInstanceMethod(object_getClass(wallpaper), boundsUpdate);
    if (!scene || !gm || !um || strcmp(method_getTypeEncoding(gm), "q16@0:8") != 0 ||
        strcmp(method_getTypeEncoding(um), "v36@0:8q16d24B32") != 0 ||
        !bm || strcmp(method_getTypeEncoding(bm), "v24@0:8q16") != 0) return;
    NSInteger original = ((NSInteger (*)(id, SEL))objc_msgSend)(wallpaper, getter);
    static BOOL vpLoggedWallpaperOrientationSelectors = NO;
    if (!vpLoggedWallpaperOrientationSelectors) {
        vpLoggedWallpaperOrientationSelectors = YES;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(object_getClass(wallpaper), &methodCount);
        NSMutableArray *names = [NSMutableArray array];
        for (unsigned int i = 0; i < methodCount; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            if ([name rangeOfString:@"rientation"].location != NSNotFound ||
                [name rangeOfString:@"otate"].location != NSNotFound) [names addObject:name];
        }
        free(methods);
        vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper orientation selectors: %@", names]);
    }
    NSInteger target = [[vpReadObject(scene, "traitsPipelineManager") valueForKey:@"systemArbitratedInterfaceOrientation"] integerValue];
    // The wallpaper controller takes the device-side orientation, whose
    // landscape names mirror the UI ones (UI landscape-left 4 is device
    // landscape-right 3); passing the raw interface code lands the image
    // a quarter turn off on every landscape. Measured on iPhone19,4:
    // portrait stays 1, interface 4 renders upright as 3.
    if (target == 3) target = 4;
    else if (target == 4) target = 3;
    if (original < 1 || original > 4 || target < 1 || target > 4) return;
    vpWallpaperOrientationLeaseActive = YES;
    @try {
        ((void (*)(id, SEL, NSInteger, double, BOOL))objc_msgSend)(wallpaper, update, target, 0, YES);
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(wallpaper, boundsUpdate, target);
        // Traits-active wallpaper skips the legacy bounds path on this
        // single-Main Duo.  Keep the existing native wallpaper objects but
        // synchronize their frames to the scene's current interface bounds.
        CGSize sceneSize = (target == 3 || target == 4)
            ? CGSizeMake(951, 669) : CGSizeMake(669, 951);
        id wallpaperWindow = vpReadObjectIvar(wallpaper, "_wallpaperWindow");
        id container = vpReadObjectIvar(wallpaper, "_wallpaperContainerView");
        id presenter = vpReadObjectIvar(wallpaper, "_wallpaperPresenter");
        id presenterView = vpReadObject(presenter, "viewIfLoaded");
        id root = vpReadObjectIvar(wallpaper, "_rootWallpaperViewController");
        id rootView = vpReadObject(root, "viewIfLoaded");
        for (id view in @[wallpaperWindow ?: NSNull.null, container ?: NSNull.null, presenterView ?: NSNull.null, rootView ?: NSNull.null]) {
            if (view == NSNull.null) continue;
            @try {
                CGRect rect = CGRectMake(0, 0, sceneSize.width, sceneSize.height);
                NSValue *value = [NSValue value:&rect withObjCType:@encode(CGRect)];
                [view setValue:value forKey:@"frame"];
                [view setValue:value forKey:@"bounds"];
                if ([view respondsToSelector:sel_registerName("setNeedsLayout")])
                    ((void (*)(id, SEL))objc_msgSend)(view, sel_registerName("setNeedsLayout"));
                if ([view respondsToSelector:sel_registerName("layoutIfNeeded")])
                    ((void (*)(id, SEL))objc_msgSend)(view, sel_registerName("layoutIfNeeded"));
            } @catch (NSException *exception) {
                vpFoldDisplayLog([NSString stringWithFormat:@"native wallpaper bounds exception: %@", exception.reason]);
            }
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"native wallpaper transforms: window=%@ container=%@ presenter=%@ root=%@",
            [wallpaperWindow valueForKey:@"transform"], [container valueForKey:@"transform"],
            [presenterView valueForKey:@"transform"], [rootView valueForKey:@"transform"]]);
        vpFoldDisplayLog([NSString stringWithFormat:@"native wallpaper orientation: %ld -> %ld readback=%ld",
            (long)original, (long)target, (long)((NSInteger (*)(id, SEL))objc_msgSend)(wallpaper, getter)]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"native wallpaper orientation exception: %@", exception.reason]);
    }
    // PosterBoard may create its floating editor after the wallpaper
    // presenter was rotated. Reconcile the hosted scene after the native
    // wallpaper pass so a portrait editor remains centered in landscape.
    vpSyncWallpaperSceneHosts();
    // This is now part of the normal Duo orientation pipeline.  Do not roll
    // the wallpaper back after a timer: the scene's current arbitration is
    // the source of truth and a delayed restore recreates the landscape black
    // band.  The next orientation request can update it again.
    vpWallpaperOrientationLeaseActive = NO;
}

void vpDumpWallpaperTree(id view, NSUInteger depth) {
    if (!view || depth > 8) return;
    id layer = nil;
    @try { layer = [view valueForKey:@"layer"]; } @catch (NSException *exception) { }
    NSString *layerInfo = @"";
    if (layer) {
        @try {
            layerInfo = [NSString stringWithFormat:@" layer=%@ gravity=%@ scale=%@ masks=%@ cRect=%@ cCenter=%@ contents=%@",
                [layer valueForKey:@"bounds"], [layer valueForKey:@"contentsGravity"],
                [layer valueForKey:@"contentsScale"], [layer valueForKey:@"masksToBounds"],
                [layer valueForKey:@"contentsRect"], [layer valueForKey:@"contentsCenter"],
                vpDescribeLayerContents([layer valueForKey:@"contents"])];
        } @catch (NSException *exception) { }
    }
    vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper tree depth=%lu class=%@ frame=%@ bounds=%@ transform=%@ hidden=%@ alpha=%@%@",
        (unsigned long)depth, NSStringFromClass([view class]), [view valueForKey:@"frame"], [view valueForKey:@"bounds"],
        [view valueForKey:@"transform"], [view valueForKey:@"hidden"], [view valueForKey:@"alpha"], layerInfo]);
    for (id child in [view valueForKey:@"subviews"] ?: @[])
        vpDumpWallpaperTree(child, depth + 1);
}

// MARK: - poster scene hosts

void vpSyncWallpaperSceneHosts(void) {
    if (!vpLogicalRoleExperiment) { vpFoldDisplayLog(@"wallpaper scene host sync: experiment inactive"); return; }
    @try {
        id scene = vpMainInnerWindowScene();
        id wallpaper = vpReadObject(scene, "wallpaperController");
        id presenter = vpReadObjectIvar(wallpaper, "_wallpaperPresenter");
        id presenterView = vpReadObject(presenter, "viewIfLoaded");
        if (!presenterView) { vpFoldDisplayLog(@"wallpaper scene host sync: no presenter view"); return; }
        CGRect presenterBounds = ((CGRect (*)(id, SEL))objc_msgSend)(presenterView, sel_registerName("bounds"));
        if (presenterBounds.size.width < 100 || presenterBounds.size.height < 100) {
            vpFoldDisplayLog(@"wallpaper scene host sync: presenter bounds unusable");
            return;
        }
        NSMutableArray *pending = [NSMutableArray arrayWithObject:presenterView];
        NSUInteger synced = 0;
        while (pending.count && synced < 32) {
            id view = pending.lastObject;
            [pending removeLastObject];
            NSString *className = NSStringFromClass([view class]);
            CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(view, sel_registerName("bounds"));
            if ([className isEqualToString:@"_UIScenePresentationView"]) {
                id parent = vpReadObject(view, "superview");
                NSString *parentClass = parent ? NSStringFromClass([parent class]) : @"";
                // The floating poster editor remains portrait-native. Keep
                // its scene bounds intact, but center that scene inside the
                // landscape poster host instead of stretching it (stretching
                // restarts its loading transition and leaves the sheet off
                // the visual center). Wallpaper render hosts still fill the
                // presenter below.
                if ([parentClass containsString:@"PosterFloating"] &&
                    bounds.size.width < presenterBounds.size.width &&
                    bounds.size.height > presenterBounds.size.height) {
                    @try {
                        CGRect centered = CGRectMake(
                            floor((presenterBounds.size.width - bounds.size.width) / 2.0),
                            floor((presenterBounds.size.height - bounds.size.height) / 2.0),
                            bounds.size.width, bounds.size.height);
                        [view setValue:[NSValue value:&centered withObjCType:@encode(CGRect)] forKey:@"frame"];
                        ((void (*)(id, SEL))objc_msgSend)(view, sel_registerName("setNeedsLayout"));
                        synced++;
                        vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper scene host center: %@ size=%@ origin={%.0f, %.0f}",
                            parentClass, vpSizeText(bounds.size), centered.origin.x, centered.origin.y]);
                    } @catch (NSException *exception) {
                        vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper scene host center exception: %@", exception.reason]);
                    }
                }
            } else if ([className isEqualToString:@"_UISceneLayerHostContainerView"] ||
                       [className isEqualToString:@"_UITouchPassthroughView"]) {
                if (!CGSizeEqualToSize(bounds.size, presenterBounds.size)) {
                    @try {
                        CGRect rect = CGRectMake(0, 0, presenterBounds.size.width, presenterBounds.size.height);
                        NSValue *value = [NSValue value:&rect withObjCType:@encode(CGRect)];
                        [view setValue:value forKey:@"frame"];
                        [view setValue:value forKey:@"bounds"];
                        ((void (*)(id, SEL))objc_msgSend)(view, sel_registerName("setNeedsLayout"));
                        synced++;
                        vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper scene host sync: %@ %@ -> %@",
                            className, vpSizeText(bounds.size), vpSizeText(presenterBounds.size)]);
                    } @catch (NSException *exception) {
                        vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper scene host node exception: %@", exception.reason]);
                    }
                }
            }
            for (id child in [view valueForKey:@"subviews"] ?: @[]) [pending addObject:child];
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper scene host sync: synced=%lu container=%@",
            (unsigned long)synced, vpSizeText(presenterBounds.size)]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper scene host sync exception: %@", exception.reason]);
    }
}

// MARK: - device-to-interface bridge

// The wallpaper layer converts the device orientation to its rendering
// interface with the platform-default table; the Duo inner panel mounts
// rotated, so on every landscape the wallpaper bitmap lands a quarter turn
// off while the icons (which consult the scene's mounting table) stay
// upright. Route the wallpaper's conversion through the live scene's own
// device→system-space converter, the one table that is correct here.
static NSInteger (*vpOriginalWallpaperInterfaceForDevice)(id, SEL, NSInteger);
static atomic_uint vpWallpaperBridgeCallCount;
static NSInteger vpWallpaperInterfaceForDevice(id self, SEL cmd, NSInteger device) {
    id scene = vpMainInnerWindowScene();
    SEL convert = sel_registerName("systemSpaceOrientationForDeviceOrientation:");
    if (scene) {
        Method method = class_getInstanceMethod(object_getClass(scene), convert);
        if (method && strcmp(method_getTypeEncoding(method), "q24@0:8q16") == 0) {
            NSInteger mapped = ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(scene, convert, device);
            if (mapped >= 1 && mapped <= 4) {
                if (atomic_load_explicit(&vpWallpaperBridgeCallCount, memory_order_relaxed) < 12) {
                    atomic_fetch_add_explicit(&vpWallpaperBridgeCallCount, 1, memory_order_relaxed);
                    vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper orientation bridge: device %ld -> interface %ld", (long)device, (long)mapped]);
                }
                return mapped;
            }
        }
    }
    return ((NSInteger (*)(id, SEL, NSInteger))vpOriginalWallpaperInterfaceForDevice)(self, cmd, device);
}

BOOL vpInstallWallpaperOrientationBridge(void) {
    id scene = vpOrientationArbitrationScene();
    id wallpaper = vpReadObject(scene, "wallpaperController");
    SEL converter = sel_registerName("_interfaceOrientationForDeviceOrientation:");
    Method method = wallpaper ? class_getInstanceMethod(object_getClass(wallpaper), converter) : NULL;
    if (!wallpaper || !method || strcmp(method_getTypeEncoding(method), "q24@0:8q16") != 0) {
        static unsigned int bridgeFailLogs = 0;
        if (bridgeFailLogs < 6) {
            bridgeFailLogs++;
            vpFoldDisplayLog([NSString stringWithFormat:
                @"wallpaper orientation bridge: unavailable scene=%@ wallpaper=%@ method=%@ types=%s",
                scene ? @"yes" : @"no", wallpaper ? NSStringFromClass(object_getClass(wallpaper)) : @"nil",
                method ? @"yes" : @"no", method ? method_getTypeEncoding(method) : "-"]);
        }
        return NO;
    }
    if (method_getImplementation(method) != (IMP)vpWallpaperInterfaceForDevice) {
        vpOriginalWallpaperInterfaceForDevice = (NSInteger (*)(id, SEL, NSInteger))method_getImplementation(method);
        method_setImplementation(method, (IMP)vpWallpaperInterfaceForDevice);
        vpFoldDisplayLog(@"wallpaper orientation bridge: installed");
    }
    return YES;
}

// MARK: - traits experiment

// One-process experiment for the native wallpaper traits pipeline. The
// shipped domain plist lacks this named flag; every other query is native.
static bool vpWallpaperFeatureLookup(const char *domain, const char *feature) {
    if (domain && feature && strcmp(domain, "SpringBoard") == 0 &&
        strcmp(feature, "TraitsArbiterWallpaperTokyoDrift") == 0) return true;
    return ((bool (*)(const char *, const char *))vpOriginalWallpaperFeatureLookup)(domain, feature);
}
// Mirror the native pre-visibility role-hint assignment used by the managed
// wallpaper branch, scoped to the existing Main-inner wallpaper window.
static void vpWallpaperSetHidden(id self, SEL selector, BOOL hidden) {
    if (!hidden && vpLogicalRoleExperiment && vpWallpaperTraitsExperimentInstalled) {
        @try {
            id scene = vpReadObject(self, "windowScene");
            if (vpIsSingleMainStatusScene(scene, YES) && !vpReadObject(self, "_roleHint")) {
                id __unsafe_unretained *address = (id __unsafe_unretained *)dlsym(RTLD_DEFAULT, "SBTraitsParticipantRoleWallpaper");
                SEL setter = sel_registerName("_setRoleHint:");
                NSMethodSignature *signature = [self methodSignatureForSelector:setter];
                if (address && *address && signature.numberOfArguments == 3 &&
                    strcmp(signature.methodReturnType, "v") == 0 && [signature getArgumentTypeAtIndex:2][0] == '@') {
                    ((void (*)(id, SEL, id))objc_msgSend)(self, setter, *address);
                    vpFoldDisplayLog(@"wallpaper traits experiment: native wallpaper role assigned before visibility");
                }
            }
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper role assignment exception: %@", exception.reason]);
        }
    }
    ((void (*)(id, SEL, BOOL))vpOriginalWallpaperSetHidden)(self, selector, hidden);
}

void vpInstallWallpaperTraitsExperiment(void) {
    void *target = dlsym(RTLD_DEFAULT, "_os_feature_enabled_impl");
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    if (!target || !install) { vpFoldDisplayLog(@"wallpaper traits experiment: native feature lookup unavailable"); return; }
    MISFixDetourResult result = install("Duo wallpaper traits experiment", target, (void *)vpWallpaperFeatureLookup, &vpOriginalWallpaperFeatureLookup);
    vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper traits experiment: feature lookup result=%d", result]);
    if (result == MISFixDetourOK) {
        vpWallpaperTraitsExperimentInstalled = YES;
        Class window = objc_getClass("_SBWallpaperSecureWindow");
        SEL hidden = sel_registerName("setHidden:");
        Method method = class_getInstanceMethod(window, hidden);
        if (method && strcmp(method_getTypeEncoding(method), "v20@0:8B16") == 0) {
            vpOriginalWallpaperSetHidden = method_getImplementation(method);
            BOOL installed = class_addMethod(window, hidden, (IMP)vpWallpaperSetHidden, method_getTypeEncoding(method));
            vpFoldDisplayLog([NSString stringWithFormat:@"wallpaper traits experiment: scoped visibility hook=%d", installed]);
        }
    }
}

// MARK: - landscape gate

// The landscape-wallpaper gate soft-links PF_IS_PAD_DEVICE, which answers for
// the whole process; a global YES would leak the pad answer everywhere.  The
// detour below answers YES only when the caller is inside the implementations
// of the two supportsLandscapeWallpaperContents selectors, so the wallpaper
// controller alone sees a pad-class answer where its native branch demands it.
static bool (*vpOriginalPFIsPadDevice)(void);
static uintptr_t vpLandscapeSupportImpRange[2][2];

static bool vpPFIsPadDeviceReplacement(void) {
    void *caller = __builtin_return_address(0);
    uintptr_t address = (uintptr_t)caller;
    for (int i = 0; i < 2; i++) {
        if (vpLandscapeSupportImpRange[i][0] && address >= vpLandscapeSupportImpRange[i][0] &&
            address < vpLandscapeSupportImpRange[i][1])
            return true;
    }
    return ((bool (*)(void))vpOriginalPFIsPadDevice)();
}

void vpInstallLandscapeWallpaperGateDetour(void) {
    void *padSymbol = dlsym(RTLD_DEFAULT, "PF_IS_PAD_DEVICE");
    if (!padSymbol) { vpFoldDisplayLog(@"landscape gate: PF_IS_PAD_DEVICE absent"); return; }
    Class remote = objc_getClass("PBUIPosterWallpaperRemoteViewController");
    if (!remote) { vpFoldDisplayLog(@"landscape gate: remote view controller absent"); return; }
    SEL selectors[2] = {
        sel_registerName("supportsLandscapeWallpaperContents"),
        sel_registerName("supportsLandscapeWallpaperContentsForDisplayConfiguration:"),
    };
    NSUInteger ranges = 0;
    for (int i = 0; i < 2; i++) {
        Method method = class_getClassMethod(remote, selectors[i]);
        if (!method) method = class_getInstanceMethod(remote, selectors[i]);
        if (!method) continue;
        uintptr_t imp = (uintptr_t)method_getImplementation(method);
        vpLandscapeSupportImpRange[ranges][0] = imp;
        // The gate check sits within the first pages of each implementation.
        vpLandscapeSupportImpRange[ranges][1] = imp + 0x1000;
        ranges++;
    }
    if (!ranges) { vpFoldDisplayLog(@"landscape gate: no supportsLandscape selector found"); return; }
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    if (!install) { vpFoldDisplayLog(@"landscape gate: MISFixDetour absent"); return; }
    MISFixDetourResult result = install("Duo landscape wallpaper gate", padSymbol, (void *)vpPFIsPadDeviceReplacement, (void **)&vpOriginalPFIsPadDevice);
    vpFoldDisplayLog([NSString stringWithFormat:@"landscape gate: ranges=%lu detour=%d", (unsigned long)ranges, result]);
}
