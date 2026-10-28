// Read-only inspection dumps behind the com.vphone.display.*inspect
// notifications.

#import "FoldDisplayPrivate.h"

// MARK: - system UI and home-screen family

void vpInspectDuoSystemUI(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        NSUInteger found = 0;
        for (id window in vpReadObject(app, "windows")) {
            NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count) {
                id view = pending.lastObject;
                [pending removeLastObject];
                if ([NSStringFromClass([view class]) isEqualToString:@"UICoverSheetButton"]) {
                    id content = vpReadObjectIvar(view, "_contentView");
                    id image = vpReadObjectIvar(view, "_image");
                    id selected = vpReadObjectIvar(view, "_selectedImage");
                    vpFoldDisplayLog([NSString stringWithFormat:@"cover sheet native bounds: button=%@ frame=%@ bounds=%@ contentFrame=%@ contentBounds=%@ imageSize=%@ selectedImageSize=%@ edgeInsets=%@",
                        NSStringFromClass([view class]), [view valueForKey:@"frame"], [view valueForKey:@"bounds"],
                        [content valueForKey:@"frame"], [content valueForKey:@"bounds"], [image valueForKey:@"size"],
                        [selected valueForKey:@"size"], [view valueForKey:@"edgeInsets"]]);
                    found++;
                }
                for (id child in [view valueForKey:@"subviews"] ?: @[]) [pending addObject:child];
            }
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"Duo system UI inventory: coverSheetButtons=%lu", (unsigned long)found]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"Duo system UI inventory exception: %@", exception.reason]);
    }
}
void vpInspectStatusProvider(void) { vpFoldDisplayLog(@"status provider inspection requested"); }
void vpPulseInputTrace(void) { vpFoldDisplayLog(@"input trace pulse requested"); }
void vpRestoreInputTrace(void) { vpFoldDisplayLog(@"input trace restore requested"); }

void vpInspectHomeScreenType(void) {
    void *home = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_LOCAL);
    NSUInteger (*current)(void) = dlsym(home, "SBHScreenTypeForCurrentDevice");
    NSUInteger (*forScreen)(id) = dlsym(home, "SBHScreenTypeForScreen");
    NSString *(*name)(NSUInteger) = dlsym(home, "SBHStringForScreenType");
    NSUInteger (*forContexts)(id, id) = dlsym(home, "SBHScreenTypeForDeviceAndDisplayContexts");
    // Independent native providers only. Compare actual family metrics;
    // never install a provider or change the active icon model/layout.
    Class providerClass = objc_getClass("SBHDefaultIconListLayoutProvider");
    SEL initializerSelector = sel_registerName("initWithScreenType:layoutOptions:");
    Method initializer = class_getInstanceMethod(providerClass, initializerSelector);
    if (initializer && strcmp(method_getTypeEncoding(initializer), "@32@0:8Q16Q24") == 0) {
        @try {
            NSUInteger options = 0;
            SEL optionsSelector = sel_registerName("defaultLayoutOptions");
            if ([providerClass respondsToSelector:optionsSelector])
                options = ((NSUInteger (*)(id, SEL))objc_msgSend)(providerClass, optionsSelector);
            for (NSNumber *family in @[@23, @31, @32]) {
                id provider = ((id (*)(id, SEL, NSUInteger, NSUInteger))objc_msgSend)(
                    [providerClass alloc], initializerSelector, family.unsignedIntegerValue, options);
                for (NSString *symbol in @[@"SBIconLocationRoot", @"SBIconLocationRootWithWidgets"]) {
                    NSString *__unsafe_unretained *address = (NSString *__unsafe_unretained *)dlsym(home, symbol.UTF8String);
                    NSString *location = address ? *address : nil;
                    if (![location isKindOfClass:NSString.class]) continue;
                    id layout = ((id (*)(id, SEL, id))objc_msgSend)(provider, sel_registerName("layoutForIconLocation:"), location);
                    id configuration = vpReadObject(layout, "layoutConfiguration");
                    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
                    for (NSString *key in @[@"numberOfPortraitColumns", @"numberOfPortraitRows", @"numberOfLandscapeColumns", @"numberOfLandscapeRows",
                                            @"portraitListSizeForIconSpacingCalculation", @"landscapeListSizeForIconSpacingCalculation",
                                            @"portraitLayoutInsets", @"landscapeLayoutInsets"])
                        if ([configuration respondsToSelector:NSSelectorFromString(key)])
                            metrics[key] = [[configuration valueForKey:key] description] ?: NSNull.null;
                    vpFoldDisplayLog([NSString stringWithFormat:@"native family layout preview: type=%@ options=%lu location=%@ %@",
                        family, (unsigned long)options, location, metrics]);
                }
            }
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"native family layout preview exception: %@", exception.reason]);
        }
    }
    Class screenClass = objc_getClass("UIScreen");
    if (current && forScreen && name && screenClass) {
        id screen = ((id (*)(id, SEL))objc_msgSend)(screenClass, sel_registerName("mainScreen"));
        NSUInteger globalType = current(), screenType = forScreen(screen);
        vpFoldDisplayLog([NSString stringWithFormat:@"home screen type: current=%lu %@ screen=%lu %@",
            (unsigned long)globalType, name(globalType), (unsigned long)screenType, name(screenType)]);
        id traits = ((id (*)(id, SEL))objc_msgSend)(screen, sel_registerName("traitCollection"));
        SEL artworkGetter = sel_registerName("valueForNSIntegerTrait:");
        Class artwork = objc_getClass("UITraitArtworkSubtype");
        NSMethodSignature *signature = [traits methodSignatureForSelector:artworkGetter];
        if (artwork && signature.numberOfArguments == 3 && signature.methodReturnType[0] == 'q') {
            NSInteger subtype = ((NSInteger (*)(id, SEL, Class))objc_msgSend)(traits, artworkGetter, artwork);
            vpFoldDisplayLog([NSString stringWithFormat:@"home screen artwork subtype: %ld", (long)subtype]);
        }
        Class platformClass = objc_getClass("BSPlatform");
        if ([platformClass respondsToSelector:sel_registerName("sharedInstance")]) {
            id platform = ((id (*)(id, SEL))objc_msgSend)(platformClass, sel_registerName("sharedInstance"));
            vpFoldDisplayLog([NSString stringWithFormat:@"home platform: class=%@ homeButton=%@",
                [platform valueForKey:@"deviceClass"], [platform valueForKey:@"homeButtonType"]]);
        }
        // Classify copies of the native contexts only. This tests whether
        // missing artwork metadata explains the fallback family without
        // modifying a screen, scene or global device context.
        Class deviceContextClass = objc_getClass("UISDeviceContext");
        Class displayContextClass = objc_getClass("UISDisplayContext");
        SEL defaultDevice = sel_registerName("sb_defaultContext");
        SEL defaultDisplay = sel_registerName("sb_defaultContextForDisplayConfiguration:");
        if (forContexts && [deviceContextClass respondsToSelector:defaultDevice] &&
            [displayContextClass respondsToSelector:defaultDisplay]) {
            @try {
                id deviceContext = ((id (*)(id, SEL))objc_msgSend)(deviceContextClass, defaultDevice);
                id configuration = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("FBDisplayManager"), sel_registerName("mainConfiguration"));
                id displayContext = ((id (*)(id, SEL, id))objc_msgSend)(displayContextClass, defaultDisplay, configuration);
                id copy = [displayContext mutableCopy];
                SEL setArtwork = sel_registerName("setArtworkSubtype:");
                Method setter = class_getInstanceMethod(object_getClass(copy), setArtwork);
                if (copy && copy != displayContext && setter && strcmp(method_getTypeEncoding(setter), "v24@0:8Q16") == 0) {
                    id cachedConfiguration = ((id (*)(id, SEL))objc_msgSend)(displayContext, sel_registerName("displayConfiguration"));
                    CGRect cachedBounds = ((CGRect (*)(id, SEL))objc_msgSend)(cachedConfiguration, sel_registerName("bounds"));
                    vpFoldDisplayLog([NSString stringWithFormat:@"native family context: cached configuration %s %gx%g",
                        object_getClassName(cachedConfiguration), cachedBounds.size.width, cachedBounds.size.height]);
                    for (NSNumber *candidate in @[@0, @2034, @2853, @2796]) {
                        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(copy, setArtwork, candidate.unsignedIntegerValue);
                        NSUInteger type = forContexts(deviceContext, copy);
                        vpFoldDisplayLog([NSString stringWithFormat:@"native family preview: artwork=%@ type=%lu %@",
                            candidate, (unsigned long)type, name(type)]);
                    }
                    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(copy, setArtwork, 0);
                    id sourceMode = ((id (*)(id, SEL))objc_msgSend)(configuration, sel_registerName("currentMode"));
                    CGFloat scale = ((CGFloat (*)(id, SEL))objc_msgSend)(sourceMode, sel_registerName("pointScale"));
                    const CGSize candidateSizes[] = {{678, 951}, {669, 951}, {466, 678}};
                    for (NSUInteger index = 0; index < sizeof(candidateSizes) / sizeof(candidateSizes[0]); index++) {
                        CGSize size = candidateSizes[index];
                        id virtualMode = [(id<VPhoneDisplayModeCopying>)sourceMode _copyWithOverrideSize:size scale:scale];
                        id preview = [(id<VPhoneDisplayProjectionCopying>)configuration copyWithOverrideMode:virtualMode];
                        ((void (*)(id, SEL, id))objc_msgSend)(copy, sel_registerName("setDisplayConfiguration:"), preview);
                        NSUInteger type = forContexts(deviceContext, copy);
                        vpFoldDisplayLog([NSString stringWithFormat:@"native family geometry preview: %gx%g type=%lu %@",
                            size.width, size.height, (unsigned long)type, name(type)]);
                    }
                }
            } @catch (NSException *exception) {
                vpFoldDisplayLog([NSString stringWithFormat:@"native family preview exception: %@", exception.reason]);
            }
        }
    }
    Class cls = objc_getClass("SBIconListGridLayoutConfiguration");
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *selector = sel_getName(method_getName(methods[i]));
        if (strstr(selector, "init") || strstr(selector, "creen") || strstr(selector, "ize") || strstr(selector, "ayout"))
            vpFoldDisplayLog([NSString stringWithFormat:@"grid method: %s types: %s", selector, method_getTypeEncoding(methods[i])]);
    }
    free(methods);
    for (NSString *className in @[@"SBHDefaultIconListLayoutProvider", @"SBHCustomIconListLayoutProvider",
                                  @"SBHMappedIconListLayoutProvider", @"SBHAdjustableRootIconListLayoutProvider",
                                  @"SBHIconManager", @"SBIconController"]) {
        Class provider = objc_getClass(className.UTF8String);
        for (int meta = 0; meta < 2; meta++) {
            unsigned int n = 0;
            Method *list = class_copyMethodList(meta ? object_getClass(provider) : provider, &n);
            for (unsigned int i = 0; i < n; i++) {
                const char *selector = sel_getName(method_getName(list[i]));
                if (([className isEqualToString:@"SBHIconManager"] || [className isEqualToString:@"SBIconController"]) &&
                    !strstr(selector, "ayout") && !strstr(selector, "hared") && !strstr(selector, "conManager")) continue;
                vpFoldDisplayLog([NSString stringWithFormat:@"provider %@ %c%s types: %s", className,
                    meta ? '+' : '-', selector, method_getTypeEncoding(list[i])]);
            }
            free(list);
        }
    }
}

// MARK: - SB-main scene snapshot

// One bounded JSON line: do not format the arbiter, class inventories or
// controller/model descriptions on SpringBoard's main queue during tests.
void vpSnapshotMainScene(void) {
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id scene = vpReadObject(app, "activeDisplayWindowScene") ?: vpReadObject(app, "embeddedDisplayWindowScene");
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id screen = vpReadObject(scene, "screen");
        NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithDictionary:@{
            @"pid": @(getpid()), @"time": @(started),
            @"viewportGeneration": @(atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed)),
            @"configurationBounds": vpSnapshotRect(configuration, "bounds"),
            @"scene": vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier") ?: NSNull.null,
            @"coordinateBounds": vpSnapshotRect(vpReadObject(scene, "coordinateSpace"), "bounds"),
            @"screenBounds": vpSnapshotRect(screen, "bounds"),
            @"screenNativeBounds": vpSnapshotRect(screen, "nativeBounds"),
        }];
        id pipeline = vpReadObject(scene, "traitsPipelineManager");
        id snapshotIdentity = vpReadObject(configuration, "identity");
        for (NSString *key in @[@"isMainDisplay", @"isMainRootDisplay", @"isRootIdentity", @"isUIKitMainLike", @"isAlwaysConnected"])
            snapshot[[@"identity." stringByAppendingString:key]] = [snapshotIdentity valueForKey:key] ?: NSNull.null;
        for (NSString *key in @[@"isMainDisplayWindowScene", @"isLegacyMainEmbeddedScene"])
            snapshot[[@"scene." stringByAppendingString:key]] = vpReadBoolValue(scene, key.UTF8String) ?: NSNull.null;
        id statusManager = vpReadObject(scene, "statusBarManager");
        snapshot[@"statusManagerClass"] = statusManager ? NSStringFromClass(object_getClass(statusManager)) : NSNull.null;
        snapshot[@"statusManagerEmbedded"] = vpReadBoolValue(statusManager, "_isEmbeddedDisplay") ?: NSNull.null;
        snapshot[@"statusManagerHidden"] = vpReadBoolValue(statusManager, "isStatusBarHidden") ?: NSNull.null;
        snapshot[@"screenUserInterfaceIdiom"] = [screen valueForKey:@"_userInterfaceIdiom"] ?: NSNull.null;
        snapshot[@"screenTraitUserInterfaceIdiom"] = [vpReadObject(screen, "traitCollection") valueForKey:@"userInterfaceIdiom"] ?: NSNull.null;
        id uiConfiguration = vpReadObject(scene, "_sbDisplayConfiguration");
        id clientIdentity = vpReadObject(scene, "_fbsDisplayIdentity");
        snapshot[@"uiConfigurationIdentifier"] = vpReadObject(vpReadObject(uiConfiguration, "identity"), "uniqueIdentifier") ?: NSNull.null;
        snapshot[@"clientDisplayIdentifier"] = vpReadObject(clientIdentity, "uniqueIdentifier") ?: NSNull.null;
        snapshot[@"clientDisplayType"] = [clientIdentity valueForKey:@"type"] ?: NSNull.null;
        id serverSettingsForSnapshot = nil;
        for (id serverScene in vpRootServerScenes(app))
            if ([vpReadObject(serverScene, "identifier") isEqual:@"SB-main"]) { serverSettingsForSnapshot = vpReadObject(serverScene, "uiSettings"); break; }
        snapshot[@"serverHostedIdentifier"] = vpReadObject(vpReadObject(vpReadObject(serverSettingsForSnapshot, "sb_hostedDisplayConfiguration"), "identity"), "uniqueIdentifier") ?: NSNull.null;
        snapshot[@"serverDisplayIdentifier"] = vpReadObject(vpReadObject(serverSettingsForSnapshot, "displayIdentity"), "uniqueIdentifier") ?: NSNull.null;
        snapshot[@"connectedDisplayCount"] = @([vpReadObject(vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance"), "alwaysConnectedIdentities") count]);
        snapshot[@"caDisplayObjectCount"] = @([vpReadObject(objc_getClass("CADisplay"), "displays") count]);
        snapshot[@"sceneScreenType"] = [scene valueForKey:@"sbhScreenType"] ?: NSNull.null;
        void *home = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_LOCAL);
        NSUInteger (*globalFamily)(void) = dlsym(home, "SBHScreenTypeForCurrentDevice");
        NSUInteger (*screenFamily)(id) = dlsym(home, "SBHScreenTypeForScreen");
        if (globalFamily) snapshot[@"globalScreenType"] = @(globalFamily());
        if (screenFamily) snapshot[@"screenScreenType"] = @(screenFamily(screen));
        id geometry = vpReadObject(scene, "effectiveGeometry");
        if ([geometry respondsToSelector:sel_registerName("interfaceOrientation")])
            snapshot[@"effectiveGeometryOrientation"] = [geometry valueForKey:@"interfaceOrientation"];
        for (NSString *name in @[@"systemSpaceOrientationForDeviceOrientation:", @"deviceOrientationForSystemSpaceOrientation:"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = class_getInstanceMethod(object_getClass(scene), selector);
            if (method && strcmp(method_getTypeEncoding(method), "q24@0:8q16") == 0) {
                NSMutableArray *mapping = [NSMutableArray array];
                for (NSInteger direction = 1; direction <= 4; direction++)
                    [mapping addObject:@(((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(scene, selector, direction))];
                snapshot[name] = mapping;
            }
        }
        snapshot[@"providerDirections"] = vpSnapshotPoseDirections(vpReadObjectIvar(pipeline, "_devicePoseProvider"));
        for (NSString *name in @[@"_settingUpPipeline", @"_arbiterRunningUpdatesCount", @"_isCoversheetPresented", @"_isContinuousFoldSettleWindowActive", @"_continuousFoldHolderCount",
                                 @"_continuousFoldPinnedDeviceOrientation", @"_isDevicePoseOverridingOrientationLock"])
            snapshot[name] = vpSnapshotScalarIvar(pipeline, name.UTF8String) ?: NSNull.null;
        for (NSString *name in @[@"activeInterfaceOrientation", @"statusBarOrientationForEmbeddedDisplay", @"statusBarOrientation"])
            if ([app respondsToSelector:NSSelectorFromString(name)])
                snapshot[[@"application." stringByAppendingString:name]] = [app valueForKey:name];
        id deferrals = vpReadObjectIvar(pipeline, "_deviceOrientationUpdateDeferralManager");
        SEL deferred = sel_registerName("isCurrentlyDeferringOrientationUpdatesForWindowScene:");
        Method deferredMethod = class_getInstanceMethod(object_getClass(deferrals), deferred);
        if (deferredMethod && strcmp(method_getTypeEncoding(deferredMethod), "B24@0:8@16") == 0)
            snapshot[@"deferringOrientation"] = @(((BOOL (*)(id, SEL, id))objc_msgSend)(deferrals, deferred, scene));
        for (NSString *getter in @[@"_effectiveUISettings", @"_effectiveUIClientSettings"]) {
            id settings = vpReadObject(scene, getter.UTF8String);
            if ([settings respondsToSelector:sel_registerName("interfaceOrientation")])
                snapshot[getter] = [settings valueForKey:@"interfaceOrientation"];
        }
        for (NSString *name in @[@"interfaceOrientation", @"surfaceType"])
            if ([scene respondsToSelector:NSSelectorFromString(name)]) snapshot[name] = [scene valueForKey:name];
        for (NSString *name in @[@"systemArbitratedDeviceOrientation", @"systemArbitratedInterfaceOrientation", @"continuousFoldPinnedInterfaceOrientation"])
            if ([pipeline respondsToSelector:NSSelectorFromString(name)]) snapshot[name] = [pipeline valueForKey:name];
        NSMutableArray *roots = [NSMutableArray array];
        for (id root in vpRootServerScenes(app)) {
            id settings = vpReadObject(root, "uiSettings");
            [roots addObject:@{@"identifier": vpReadObject(root, "identifier") ?: NSNull.null,
                @"orientation": [settings valueForKey:@"interfaceOrientation"] ?: NSNull.null,
                @"frame": vpSnapshotRect(settings, "frame")}];
        }
        snapshot[@"roots"] = roots;
        NSMutableArray *windows = [NSMutableArray array];
        for (id window in vpReadObject(scene, "windows")) {
            id controller = vpReadObject(window, "rootViewController");
            NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:@{
                @"class": NSStringFromClass(object_getClass(window)),
                @"frame": vpSnapshotRect(window, "frame"), @"bounds": vpSnapshotRect(window, "bounds"),
                @"hidden": [window valueForKey:@"hidden"], @"orientation": [window valueForKey:@"interfaceOrientation"],
                @"rootClass": controller ? NSStringFromClass(object_getClass(controller)) : NSNull.null,
                @"rootFrame": vpSnapshotRect(vpReadObject(controller, "viewIfLoaded"), "frame"),
            }];
            for (NSString *name in @[@"orientation", @"effectiveOrientation", @"supportedInterfaceOrientations"])
                if ([controller respondsToSelector:NSSelectorFromString(name)])
                    row[[@"controller." stringByAppendingString:name]] = [controller valueForKey:name];
            for (NSString *name in @[@"orientation", @"_sbStatusBarWindowShouldRotate", @"_sbStatusBarWindowSupportedOrientations"]) {
                Method method = class_getInstanceMethod(object_getClass(window), NSSelectorFromString(name));
                char *type = method ? method_copyReturnType(method) : NULL;
                if (type && (strcmp(type, "q") == 0 || strcmp(type, "Q") == 0 || strcmp(type, "B") == 0))
                    row[[@"native." stringByAppendingString:name]] = [window valueForKey:name];
                free(type);
            }
            [windows addObject:row];
            if (windows.count == 32) break;
        }
        snapshot[@"windows"] = windows;
        snapshot[@"elapsedMs"] = @((CFAbsoluteTimeGetCurrent() - started) * 1000);
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
        if (data) vpFoldDisplayLog([@"snapshot " stringByAppendingString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"snapshot exception: %@", exception.reason]);
    }
}

// MARK: - device-determined configuration

// Reads the scalar state of a live SBSDeviceDeterminedConfiguration and probes
// its pure class-mapping helpers, so the profile-selection inputs (base class,
// distinguishers, subtype) and the base->effective mapping are both recorded
// from evidence.  Every selector is guarded; setters are never touched.
void vpDumpDeviceConfiguration(id config) {
    if (!config) { vpFoldDisplayLog(@"live device configuration: nil"); return; }
    vpFoldDisplayLog([NSString stringWithFormat:@"live device configuration: %@", [config description]]);
    struct { const char *name; } qNames[] = {
        {"effectiveDeviceClass"}, {"baseDeviceClass"}, {"baseClass"}, {"distinguishers"},
        {"effectiveDeviceGrouping"}, {"baseDeviceGrouping"}, {"_fallbackEffectiveClass"},
    };
    for (size_t i = 0; i < sizeof(qNames) / sizeof(qNames[0]); i++) {
        SEL selector = sel_registerName(qNames[i].name);
        if (![config respondsToSelector:selector]) continue;
        @try {
            unsigned long long value = ((unsigned long long (*)(id, SEL))objc_msgSend)(config, selector);
            vpFoldDisplayLog([NSString stringWithFormat:@"device configuration %s = %llu", qNames[i].name, value]);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"device configuration %s exception: %@", qNames[i].name, exception.reason]);
        }
    }
    const char *iNames[] = {"idiom"};
    for (size_t i = 0; i < 1; i++) {
        SEL selector = sel_registerName(iNames[i]);
        if ([config respondsToSelector:selector]) {
            @try {
                long value = ((long (*)(id, SEL))objc_msgSend)(config, selector);
                vpFoldDisplayLog([NSString stringWithFormat:@"device configuration %s = %ld", iNames[i], value]);
            } @catch (NSException *exception) { }
        }
    }
    const char *qReaderNames[] = {"homeButton", "_deviceSubtype", "_zoomModeDirection"};
    for (size_t i = 0; i < 3; i++) {
        SEL selector = sel_registerName(qReaderNames[i]);
        if (![config respondsToSelector:selector]) continue;
        @try {
            long long value = ((long long (*)(id, SEL))objc_msgSend)(config, selector);
            vpFoldDisplayLog([NSString stringWithFormat:@"device configuration %s = %lld", qReaderNames[i], value]);
        } @catch (NSException *exception) { }
    }
    const char *dNames[] = {"_nativeScale", "_currentScale"};
    for (size_t i = 0; i < 2; i++) {
        SEL selector = sel_registerName(dNames[i]);
        if (![config respondsToSelector:selector]) continue;
        @try {
            double value = ((double (*)(id, SEL))objc_msgSend)(config, selector);
            vpFoldDisplayLog([NSString stringWithFormat:@"device configuration %s = %.6g", dNames[i], value]);
        } @catch (NSException *exception) { }
    }
    SEL sizeSelector = sel_registerName("_effectiveDeviceClassForScreenSize:");
    if ([config respondsToSelector:sizeSelector]) {
        CGSize sizes[] = { CGSizeMake(669, 951), CGSizeMake(951, 669), CGSizeMake(466, 678), CGSizeMake(428, 926) };
        for (size_t i = 0; i < 4; i++) {
            @try {
                unsigned long long value = ((unsigned long long (*)(id, SEL, CGSize))objc_msgSend)(config, sizeSelector, sizes[i]);
                vpFoldDisplayLog([NSString stringWithFormat:@"device configuration effectiveDeviceClassForSize {%.0f,%.0f} = %llu", sizes[i].width, sizes[i].height, value]);
            } @catch (NSException *exception) { }
        }
    }
    SEL baseSelector = sel_registerName("_classForBase:zoom:");
    if ([config respondsToSelector:baseSelector]) {
        for (unsigned long long base = 0; base <= 20; base++) {
            @try {
                unsigned long long value = ((unsigned long long (*)(id, SEL, unsigned long long, long long))objc_msgSend)(config, baseSelector, base, 0);
                vpFoldDisplayLog([NSString stringWithFormat:@"device configuration classForBase %llu zoom0 = %llu", base, value]);
            } @catch (NSException *exception) {
                vpFoldDisplayLog([NSString stringWithFormat:@"device configuration classForBase %llu exception: %@", base, exception.reason]);
                break;
            }
        }
    }
}

// The determined configuration's constructor, swizzled at load so every
// construction in SpringBoard logs its hardware inputs and one instance is
// kept for on-demand mapping probes.  No object-graph walking: the round-5
// crawl crashed SpringBoard on an unsafe-unretained ivar.
typedef id (*vpConfigInitIMP)(id, SEL, unsigned long long, CGSize, int, long long,
                              unsigned long long, long long, CGRect, double, double);
static vpConfigInitIMP vpOriginalConfigInit;
id vpStashedConfig;
static NSUInteger vpConfigInitLogs;

static id vpConfigInitReplacement(id self, SEL cmd, unsigned long long baseDevice, CGSize deviceSize, int idiom,
                                  long long homeButton, unsigned long long distinguishers, long long deviceSubtype,
                                  CGRect nativeBounds, double nativeScale, double currentScale) {
    id result = vpOriginalConfigInit(self, cmd, baseDevice, deviceSize, idiom, homeButton, distinguishers,
                                     deviceSubtype, nativeBounds, nativeScale, currentScale);
    if (vpConfigInitLogs < 8) {
        vpConfigInitLogs++;
        // Identify the construction callsite so the hardware-input source can
        // be corrected rather than guessed.
        Dl_info info = {0};
        void *frame0 = __builtin_return_address(0);
        void *frame1 = __builtin_frame_address(0) ? *(void **)__builtin_frame_address(0) : NULL;
        void *caller1 = frame1 ? *(void **)((char *)frame1 + 8) : NULL;
        dladdr(frame0, &info);
        // Raw pointers too: the shared-cache slide plus this file offset turns
        // the redacted callsite into a decodable static address.
        vpFoldDisplayLog([NSString stringWithFormat:@"config init frame0=%p fbase=%p fname=%s",
            frame0, info.dli_fbase, info.dli_fname ?: "?"]);
        NSString *site1 = @"?";
        if (caller1) {
            Dl_info info1 = {0};
            dladdr(caller1, &info1);
            vpFoldDisplayLog([NSString stringWithFormat:@"config init frame1=%p fbase=%p",
                caller1, info1.dli_fbase]);
            site1 = [NSString stringWithFormat:@"%p", caller1];
        }
        vpFoldDisplayLog([NSString stringWithFormat:
            @"config init: base=%llu size={%.0f,%.0f} idiom=%d home=%lld distinguishers=0x%llx subtype=%lld "
             "native={{%.0f,%.0f},{%.0f,%.0f}} scale=%.4g/%.4g callsite=%@ <- %@ -> %@",
            baseDevice, deviceSize.width, deviceSize.height, idiom, homeButton, distinguishers, deviceSubtype,
            nativeBounds.origin.x, nativeBounds.origin.y, nativeBounds.size.width, nativeBounds.size.height,
            nativeScale, currentScale, [NSString stringWithFormat:@"%p", frame0], site1,
            result ? [result description] : @"nil"]);
    }
    if (result) {
        vpStashedConfig = result;
    }
    return result;
}

void vpInstallConfigInitSwizzle(void) {
    Class cls = objc_getClass("SBSDeviceDeterminedConfiguration");
    SEL selector = sel_registerName(
        "initMatchingBaseDevice:deviceSize:deviceIdiom:homeButton:distinguishers:deviceSubtype:nativeBounds:nativeScale:currentScale:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) { vpFoldDisplayLog(@"config init swizzle: method absent"); return; }
    vpOriginalConfigInit = (vpConfigInitIMP)method_getImplementation(method);
    method_setImplementation(method, (IMP)vpConfigInitReplacement);
    vpFoldDisplayLog(@"config init swizzle: installed");
}

// Logs who feeds the effective device class into the CoverSheet layout
// controller, and with which value.  The numeric override file that once
// forced a candidate class is gone with the experiment sweep; only the
// capped diagnostic log remains.
static void (*vpOriginalSetEffectiveClass)(id, SEL, unsigned long long);
static NSUInteger vpSetEffectiveClassLogs;

static void vpSetEffectiveClassReplacement(id self, SEL cmd, unsigned long long value) {
    if (vpSetEffectiveClassLogs < 8) {
        vpSetEffectiveClassLogs++;
        Dl_info info = {0};
        void *frame0 = __builtin_return_address(0);
        dladdr(frame0, &info);
        vpFoldDisplayLog([NSString stringWithFormat:@"layout setEffectiveDeviceClass %llu on %s from %p fbase=%p",
            value, object_getClassName(self), frame0, info.dli_fbase]);
    }
    vpOriginalSetEffectiveClass(self, cmd, value);
}

void vpInstallLayoutClassSwizzle(void) {
    Class cls = objc_getClass("CSProminentLayoutController");
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName("setEffectiveDeviceClass:")) : NULL;
    if (!method) { vpFoldDisplayLog(@"layout class swizzle: method absent"); return; }
    vpOriginalSetEffectiveClass = (void (*)(id, SEL, unsigned long long))method_getImplementation(method);
    method_setImplementation(method, (IMP)vpSetEffectiveClassReplacement);
    vpFoldDisplayLog(@"layout class swizzle: installed");
}

__attribute__((unused)) static void vpDumpClassSurface(const char *className, NSString *label) {
    Class cls = objc_getClass(className);
    if (!cls) { vpFoldDisplayLog([NSString stringWithFormat:@"%@ class %s absent", label, className]); return; }
    for (Class walk = cls; walk && walk != objc_getClass("UIView"); walk = class_getSuperclass(walk)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(walk, &count);
        vpFoldDisplayLog([NSString stringWithFormat:@"%@ surface %s: %u methods (super=%s)", label,
            class_getName(walk), count, class_getName(class_getSuperclass(walk))]);
        for (unsigned int i = 0; i < count; i++)
            vpFoldDisplayLog([NSString stringWithFormat:@"%@ method[%u] %s %s", label, i,
                sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i])]);
        free(methods);
        unsigned int icount = 0;
        Ivar *ivars = class_copyIvarList(walk, &icount);
        for (unsigned int i = 0; i < icount; i++)
            vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivardecl[%u] %s %s", label, i,
                ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: "?"]);
        free(ivars);
    }
}

// MARK: - windows and presentation

// Full window inventory with two subview levels: identifies which window or
// view owns any on-screen black band in landscape.
void vpInspectAllWindows(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        for (id window in vpReadObject(app, "windows")) {
            vpFoldDisplayLog([NSString stringWithFormat:@"window: class=%@ frame=%@ level=%@ hidden=%@",
                NSStringFromClass([window class]), [window valueForKey:@"frame"],
                [window valueForKey:@"windowLevel"], [window valueForKey:@"hidden"]]);
            BOOL deep = [NSStringFromClass([window class]) containsString:@"HomeScreen"] ||
                [NSStringFromClass([window class]) containsString:@"Wallpaper"];
            for (id child in [window valueForKey:@"subviews"] ?: @[]) {
                vpFoldDisplayLog([NSString stringWithFormat:@"window sub: class=%@ frame=%@ alpha=%@ hidden=%@",
                    NSStringFromClass([child class]), [child valueForKey:@"frame"],
                    [child valueForKey:@"alpha"], [child valueForKey:@"hidden"]]);
                if (deep)
                    vpDumpWallpaperTree(child, 3);
                else
                    for (id grandchild in [child valueForKey:@"subviews"] ?: @[])
                        vpFoldDisplayLog([NSString stringWithFormat:@"window sub2: class=%@ frame=%@ alpha=%@ hidden=%@",
                            NSStringFromClass([grandchild class]), [grandchild valueForKey:@"frame"],
                            [grandchild valueForKey:@"alpha"], [grandchild valueForKey:@"hidden"]]);
            }
        }
        // The device-class selection surfaces and singleton probes were
        // captured in the round-4 dump; the live values now come from the
        // quick-action ivar crawl.
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"window inventory exception: %@", exception.reason]);
    }
}

// Lights the Lock Screen without the Home press icli's wake falls back to,
// so the locked wallpaper and quick actions can be captured lit.
void vpUndimScreenOnly(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    void (*undim)(void) = handle ? dlsym(handle, "SBSUndimScreen") : NULL;
    if (!undim) { vpFoldDisplayLog(@"screen undim: SBSUndimScreen absent"); return; }
    undim();
    vpFoldDisplayLog(@"screen undim: requested");
}

void vpInspectNativePresentation(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id scene = vpReadObject(app, "activeDisplayWindowScene") ?: vpReadObject(app, "embeddedDisplayWindowScene");
        id wallpaper = vpReadObject(scene, "wallpaperController");
        id presenter = vpReadObjectIvar(wallpaper, "_wallpaperPresenter");
        id presenterView = vpReadObject(presenter, "viewIfLoaded");
        vpDumpWallpaperTree(presenterView, 0);
        vpDumpObjectIvars(wallpaper, @"wallpaper controller", 96);
        vpDumpObjectIvars(presenter, @"wallpaper presenter", 96);
        // The presenter hosts the wallpaper through a remote CAContext; its
        // full description carries the scale/scene fields a short dump cuts,
        // and the overlay/transfer containers may hold the clip geometry.
        vpFoldDisplayLog([NSString stringWithFormat:@"presenter full: %@", [presenter description]]);
        // The inner poster controller composes portrait while the wallpaper
        // controller is landscape; find its orientation-control surface.
        for (NSString *className in @[@"PBUIPosterViewController", @"PBUIPosterWallpaperViewController",
                                      @"PBUIPosterLockViewController", @"PBUIWallpaperView"]) {
            Class cls = objc_getClass(className.UTF8String);
            if (!cls) { vpFoldDisplayLog([NSString stringWithFormat:@"poster class %@ absent", className]); continue; }
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int i = 0; i < methodCount; i++) {
                const char *name = sel_getName(method_getName(methods[i]));
                if (strstr(name, "rientation") || strstr(name, "andscape") || strstr(name, "ontentMode") || strstr(name, "ize")) {
                    vpFoldDisplayLog([NSString stringWithFormat:@"poster surface %@ method %s %s", className, name,
                        method_getTypeEncoding(methods[i])]);
                }
            }
            free(methods);
        }
        for (NSString *containerKey in @[@"_wallpaperOverlayContainerView", @"_transferContainerView"]) {
            id container = vpReadObjectIvar(wallpaper, containerKey.UTF8String);
            vpFoldDisplayLog([NSString stringWithFormat:@"container %@: %@", containerKey, container ? [container description] : @"nil"]);
            vpDumpWallpaperTree(container, 1);
        }
        id rootController = vpReadObjectIvar(wallpaper, "_rootWallpaperViewController");
        vpDumpObjectIvars(rootController, @"wallpaper root", 64);
        id manager = vpReadObject(scene, "statusBarManager");
        id sceneBar = vpReadObject(manager, "statusBar");
        id mainBar = vpReadObject(app, "statusBarForEmbeddedDisplay");
        NSMutableArray *bars = [NSMutableArray array];
        for (id bar in @[sceneBar ?: NSNull.null, mainBar ?: NSNull.null]) {
            if (bar == NSNull.null) { [bars addObject:NSNull.null]; continue; }
            id provider = vpReadObject(bar, "inProcessStateProvider");
            NSMutableDictionary *row = [@{@"bar": [NSString stringWithFormat:@"%p %s", bar, object_getClassName(bar)],
                @"provider": provider ? [NSString stringWithFormat:@"%p %s", provider, object_getClassName(provider)] : (id)NSNull.null,
                @"server": [vpReadObject(bar, "statusBarServer") description] ?: (id)NSNull.null,
                @"bounds": vpSnapshotRect(bar, "bounds")} mutableCopy];
            for (NSString *key in @[@"timeCloaked", @"allButBatteryCloaked", @"telephonyAndBluetoothCloaked"]) {
                Ivar ivar = class_getInstanceVariable(object_getClass(provider), [[@"_" stringByAppendingString:key] UTF8String]);
                if (ivar && strcmp(ivar_getTypeEncoding(ivar), "B") == 0) row[key] = [provider valueForKey:key] ?: NSNull.null;
            }
            row[@"serverUpdatesDisabled"] = vpReadBoolValue(bar, "serverUpdatesDisabled") ?: (id)NSNull.null;
            row[@"homeItemsDisabled"] = vpReadBoolValue(bar, "homeItemsDisabled") ?: (id)NSNull.null;
            id renderer = vpReadObject(bar, "statusBar");
            for (NSString *key in @[@"currentData", @"currentAggregatedData", @"additionalDataDelegate"]) {
                NSString *description = [vpReadObject(renderer, key.UTF8String) description];
                row[key] = description ? [description substringToIndex:MIN(description.length, 6000)] : (id)NSNull.null;
            }
            row[@"enabledParts"] = vpReadObjectIvar(bar, "_enabledPartIdentifiers") ?: (id)NSNull.null;
            row[@"disabledParts"] = vpReadObjectIvar(bar, "_disabledPartIdentifiers") ?: (id)NSNull.null;

            id serverClient = vpReadObject(vpReadObject(bar, "statusBarServer"), "statusBar");
            row[@"serverClient"] = serverClient ? [NSString stringWithFormat:@"%p %s", serverClient, object_getClassName(serverClient)] : (id)NSNull.null;
            for (NSString *key in @[@"registered", @"foreground", @"hidden"]) {
                Ivar ivar = class_getInstanceVariable(object_getClass(bar), [[@"_" stringByAppendingString:key] UTF8String]);
                if (ivar && strcmp(ivar_getTypeEncoding(ivar), "B") == 0) row[key] = [bar valueForKey:key] ?: NSNull.null;
            }

            [bars addObject:row];
        }
        NSMutableDictionary *wall = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"activeVariant", @"activeOrientationSource", @"activeInterfaceOrientationSourcesDescriptions", @"isWallpaperRequired", @"_isTraitsArbiterWallpaperActive"])
            if ([wallpaper respondsToSelector:NSSelectorFromString(key)]) wall[key] = [[wallpaper valueForKey:key] description] ?: NSNull.null;
        for (NSString *key in @[@"_wallpaperWindow", @"_wallpaperContainerView", @"_wallpaperPresenter", @"_rootWallpaperViewController"]) {
            id object = vpReadObjectIvar(wallpaper, key.UTF8String);
            wall[key] = object ? @{@"class": NSStringFromClass(object_getClass(object)),
                @"frame": vpSnapshotRect(object, "frame"), @"bounds": vpSnapshotRect(object, "bounds"),
                @"hidden": vpReadBoolValue(object, "isHidden") ?: (id)NSNull.null} : (id)NSNull.null;
        }
        id wallpaperWindow = vpReadObjectIvar(wallpaper, "_wallpaperWindow");
        id participant = vpReadObject(wallpaperWindow, "sb_traitsParticipant");
        wall[@"participant"] = [participant description] ?: (id)NSNull.null;
        for (NSString *key in @[@"role", @"settings", @"preferences"])
            wall[[@"participant." stringByAppendingString:key]] = [vpReadObject(participant, key.UTF8String) description] ?: (id)NSNull.null;
        id delegate = vpReadObject(scene, "_abstractWindowSceneDelegate");
        wall[@"delegateClass"] = delegate ? NSStringFromClass(object_getClass(delegate)) : (id)NSNull.null;
        wall[@"individuallyManagedRoles"] = [vpReadObject(object_getClass(delegate), "_individuallyManagedRoles") description] ?: (id)NSNull.null;
        id __unsafe_unretained *roleAddress = (id __unsafe_unretained *)dlsym(RTLD_DEFAULT, "SBTraitsParticipantRoleWallpaper");
        SEL manages = sel_registerName("_shouldManageParticipantWithRole:");
        Method managesMethod = class_getInstanceMethod(object_getClass(delegate), manages);
        if (roleAddress && *roleAddress && managesMethod && strcmp(method_getTypeEncoding(managesMethod), "B24@0:8@16") == 0)
            wall[@"delegateManagesWallpaper"] = @(((BOOL (*)(id, SEL, id))objc_msgSend)(delegate, manages, *roleAddress));
        for (NSString *key in @[@"_wallpaperPresenter", @"_rootWallpaperViewController"]) {
            id view = vpReadObject(vpReadObjectIvar(wallpaper, key.UTF8String), "viewIfLoaded");
            wall[[key stringByAppendingString:@".view"]] = view ? @{
                @"class": NSStringFromClass(object_getClass(view)), @"frame": vpSnapshotRect(view, "frame"),
                @"bounds": vpSnapshotRect(view, "bounds"), @"hidden": vpReadBoolValue(view, "isHidden") ?: (id)NSNull.null,
                @"alpha": [view valueForKey:@"alpha"] ?: (id)NSNull.null} : (id)NSNull.null;
        }
        id mainProvider = vpReadObject(app, "mainStatusBarStateProvider");
        id aggregator = vpReadObject(app, "statusBarStateAggregator");
        NSMutableDictionary *source = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"timeCloaked", @"allButBatteryCloaked", @"telephonyAndBluetoothCloaked"]) {
            Ivar ivar = class_getInstanceVariable(object_getClass(mainProvider), [[@"_" stringByAppendingString:key] UTF8String]);
            if (ivar && strcmp(ivar_getTypeEncoding(ivar), "B") == 0) source[key] = [mainProvider valueForKey:key] ?: NSNull.null;
        }
        for (NSString *key in @[@"_dateTimeProvider", @"_dateTimeProviderToken", @"_timeItemDateFormatter", @"_shortTimeItemDateFormatter", @"_timeItemTimeString"])
            source[key] = [vpReadObjectIvar(aggregator, key.UTF8String) description] ?: (id)NSNull.null;
        source[@"nativeDate"] = [vpReadObject(vpReadObjectIvar(aggregator, "_dateTimeProvider"), "date") description] ?: (id)NSNull.null;
        for (NSString *key in @[@"_timeItemDateFormatter", @"_shortTimeItemDateFormatter"]) {
            id formatter = vpReadObjectIvar(aggregator, key.UTF8String);
            if ([formatter isKindOfClass:NSDateFormatter.class]) {
                NSDateFormatter *native = formatter;
                source[[key stringByAppendingString:@"Config"]] = @{
                    @"format": native.dateFormat ?: (id)NSNull.null,
                    @"dateStyle": @(native.dateStyle), @"timeStyle": @(native.timeStyle),
@"locale": native.locale.localeIdentifier ?: (id)NSNull.null,
                    @"nativeFormattedDate": [native stringFromDate:vpReadObject(vpReadObjectIvar(aggregator, "_dateTimeProvider"), "date")] ?: (id)NSNull.null};
            }
        }
        NSDictionary *record = @{@"scene": vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier") ?: (id)NSNull.null,
            @"barsSceneThenEmbedded": bars, @"wallpaper": wall, @"mainStateSource": source};
        NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:NULL];
        if (data) vpFoldDisplayLog([@"native presentation " stringByAppendingString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"native presentation exception: %@", exception.reason]);
    }
}

// MARK: - display state

void vpInspectDisplayState(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id provider = vpReadObject(app, "devicePoseProvider");
        id coordinator = vpReadObject(app, "displayContentModeCoordinator");
        for (id scene in vpRootServerScenes(app)) {
            id settings = vpReadObject(scene, "uiSettings") ?: vpReadObject(scene, "settings");
            NSMutableDictionary *fields = [NSMutableDictionary dictionary];
            for (NSString *property in @[@"frame", @"interfaceOrientation"]) {
                @try {
                    if ([settings respondsToSelector:NSSelectorFromString(property)])
                        fields[property] = [settings valueForKey:property] ?: NSNull.null;
                } @catch (NSException *exception) { fields[property] = exception.reason ?: @"unavailable"; }
            }
            @try {
                fields[@"hostedDisplayConfiguration"] = vpReadObject(settings, "sb_hostedDisplayConfiguration") ?: NSNull.null;
            } @catch (NSException *exception) { fields[@"hostedDisplayConfiguration"] = exception.reason ?: @"unavailable"; }
            vpFoldDisplayLog([NSString stringWithFormat:@"root server scene: %@ class=%s settings=%s %@",
                vpReadObject(scene, "identifier"), object_getClassName(scene), object_getClassName(settings), fields]);
        }
        id resolver = vpReadObjectIvar(coordinator, "_resolver");
        vpFoldDisplayLog([NSString stringWithFormat:@"display resolver: %@", resolver]);
        for (NSString *name in @[@"_policies", @"_resolution", @"_displayProxies"])
            vpFoldDisplayLog([NSString stringWithFormat:@"display resolver %@: %@", name,
                vpReadObjectIvar(resolver, name.UTF8String)]);
        Class cover = objc_getClass("SBCoverDisplayConfigurationTransformer");
        NSMutableDictionary *coverState = [NSMutableDictionary dictionary];
        for (NSString *name in @[@"activeTransformMode", @"appliedCoverInsets", @"rotationAngle", @"scaleX", @"scaleY",
                                @"transformedDisplayConfigurationHardwareIdentifier", @"insetDisplayConfigurationHardwareIdentifier"])
            if ([cover respondsToSelector:NSSelectorFromString(name)])
                coverState[name] = [cover valueForKey:name] ?: NSNull.null;
        vpFoldDisplayLog([NSString stringWithFormat:@"cover transform state: %@", coverState]);
        vpFoldDisplayLog([NSString stringWithFormat:@"display state logical projection enabled=%d", atomic_load_explicit(&vpLogicalProjectionEnabled, memory_order_acquire)]);
        vpFoldDisplayLog([NSString stringWithFormat:@"display state: app=%s poseProvider=%@ coordinator=%@",
            object_getClassName(app), provider, coordinator]);
        id monitor = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        NSMutableArray *compatibilitySourceFlags = [NSMutableArray array];
        for (id source in vpReadObject(monitor, "_sortedSources"))
            [compatibilitySourceFlags addObject:[source valueForKey:@"updatable"] ?: NSNull.null];
        vpFoldDisplayLog([NSString stringWithFormat:@"compatibility monitor source updatable=%@", compatibilitySourceFlags]);
        NSArray *observedMonitors;
        @synchronized (vpObservedDisplayMonitors) {
            observedMonitors = vpObservedDisplayMonitors.allObjects;
        }
        for (id observed in observedMonitors) {
            id transformer = vpReadObject(observed, "transformer");
            NSMutableArray *sourceFlags = [NSMutableArray array];
            for (id source in vpReadObject(observed, "_sortedSources"))
                [sourceFlags addObject:[source valueForKey:@"updatable"] ?: NSNull.null];
            vpFoldDisplayLog([NSString stringWithFormat:@"observed monitor: %s %p transformer=%s %p updatable=%@",
                object_getClassName(observed), (__bridge void *)observed,
                transformer ? object_getClassName(transformer) : "none", (__bridge void *)transformer, sourceFlags]);
        }
        id mainConfiguration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id caDisplay = vpReadObject(mainConfiguration, "CADisplay");
        id uuid = vpReadObject(caDisplay, "uniqueId");
        id service = vpReadObject(objc_getClass("BKSDisplayService"), "sharedInstance");
        SEL traitsSelector = sel_registerName("traitsForDisplayUUID:");
        if ([service respondsToSelector:traitsSelector]) {
            id traits = ((id (*)(id, SEL, id))objc_msgSend)(service, traitsSelector, uuid);
            vpFoldDisplayLog([NSString stringWithFormat:@"display native traits uuid=%@: %@", uuid, traits]);
            Class displayClass = objc_getClass("CADisplay");
            // New untagged software displays do not refresh every client's
            // inventory automatically. Invalidate only this read cache.
            SEL refresh = sel_registerName("updateDisplays");
            if ([displayClass respondsToSelector:refresh])
                ((void (*)(id, SEL))objc_msgSend)(displayClass, refresh);
            id displays = vpReadObject(displayClass, "displays");
            for (id display in displays) {
                id displayName = vpReadObject(display, "deviceName");
                if (![displayName isEqual:@"VPhone Cover Probe"]) continue;
                id displayUUID = vpReadObject(display, "uniqueId");
                if (!displayUUID) continue;
                id displayTraits = ((id (*)(id, SEL, id))objc_msgSend)(service, traitsSelector, displayUUID);
                vpFoldDisplayLog([NSString stringWithFormat:@"display native software traits name=%@ uuid=%@: %@",
                    displayName, displayUUID, displayTraits]);
            }
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"display state monitor=%@ transformer=%@ observedTransformer=%@",
            monitor, vpReadObject(monitor, "transformer"), vpObservedConfigurationTransformer]);
        id connected = vpReadObject(monitor, "connectedIdentities");
        id permanent = vpReadObject(monitor, "alwaysConnectedIdentities");
        vpFoldDisplayLog([NSString stringWithFormat:@"display state monitor connected=%@ always=%@", connected, permanent]);
        for (id identity in connected) {
            NSMutableDictionary *fields = [NSMutableDictionary dictionary];
            for (NSString *key in @[@"displayID", @"type", @"connectionType", @"isAlwaysConnected", @"isUIKitMainLike",
                                    @"isExternal", @"isVirtualized", @"uniqueIdentifier"]) {
                if ([identity respondsToSelector:NSSelectorFromString(key)]) fields[key] = [identity valueForKey:key] ?: NSNull.null;
            }
            vpFoldDisplayLog([NSString stringWithFormat:@"display identity fields: %@", fields]);
        }
        NSArray *sources = vpReadObject(monitor, "_sortedSources");
        vpFoldDisplayLog([NSString stringWithFormat:@"display state sources: %@", sources]);
        static BOOL sourceMethodsLogged;
        if (!sourceMethodsLogged && sources.count) {
            sourceMethodsLogged = YES;
            Class sourceClass = object_getClass(sources.firstObject);
            for (unsigned int level = 0; sourceClass && level < 2; level++, sourceClass = class_getSuperclass(sourceClass)) {
                unsigned int count = 0;
                Method *methods = class_copyMethodList(sourceClass, &count);
                for (unsigned int i = 0; i < count; i++) {
                    const char *selector = sel_getName(method_getName(methods[i]));
                    if (strstr(selector, "ransform") || strstr(selector, "pdate") || strstr(selector, "onfiguration"))
                        vpFoldDisplayLog([NSString stringWithFormat:@"display source method %@ %s types: %s",
                            NSStringFromClass(sourceClass), selector, method_getTypeEncoding(methods[i])]);
                }
                free(methods);
            }
        }
        // Legacy Main can display the home screen while the fold coordinator
        // has no selected primary scene. Inspect SpringBoard's actual scene
        // accessors as well; a nil coordinator entry is not an absent UI.
        for (NSString *key in @[@"primaryWindowScene", @"activeWindowScene", @"embeddedDisplayWindowScene",
                                @"activeDisplayWindowScene", @"currentTransitionContext"]) {
            id owner = [key hasSuffix:@"DisplayWindowScene"] ? app : coordinator;
            id value = vpReadObject(owner, key.UTF8String);
            vpFoldDisplayLog([NSString stringWithFormat:@"display state %@: %@", key, value]);
            if ([key hasSuffix:@"WindowScene"] && value) {
                for (NSString *property in @[@"displayConfiguration", @"displayConfigurationContext", @"displayIdentity", @"screen", @"traitCollection"])
                    vpFoldDisplayLog([NSString stringWithFormat:@"display scene %@: %@", property,
                        vpReadObject(value, property.UTF8String)]);
                id coordinateSpace = vpReadObject(value, "coordinateSpace");
                if ([coordinateSpace respondsToSelector:sel_registerName("bounds")])
                    vpFoldDisplayLog([NSString stringWithFormat:@"display scene coordinate bounds: %@",
                        [coordinateSpace valueForKey:@"bounds"]]);
                id screen = vpReadObject(value, "screen");
                id pipeline = vpReadObject(value, "traitsPipelineManager");
                NSMutableDictionary *pipelineState = [NSMutableDictionary dictionary];
                pipelineState[@"sceneSurfaceType"] = [value valueForKey:@"surfaceType"] ?: NSNull.null;
                pipelineState[@"nativeOrientationState"] = vpReadObject(pipeline, "_orientationStateDescription") ?: NSNull.null;
                id arbiter = vpReadObject(value, "traitsArbiter");
                pipelineState[@"arbiter"] = arbiter ?: NSNull.null;
                pipelineState[@"arbiterDetails"] = vpReadMultilineDescription(arbiter) ?: NSNull.null;
                for (NSString *stage in @[@"inputsValidationStage", @"orientationResolutionStage"])
                    pipelineState[stage] = vpReadMultilineDescription(vpReadObject(arbiter, stage.UTF8String)) ?: NSNull.null;
                for (NSString *property in @[@"supportsLiveDeviceRotation", @"systemArbitratedDeviceOrientation",
                                             @"systemArbitratedInterfaceOrientation", @"continuousFoldPinnedInterfaceOrientation",
                                             @"lastNonFlatDeviceOrientation", @"inputs"])
                    if ([pipeline respondsToSelector:NSSelectorFromString(property)])
                        pipelineState[property] = [pipeline valueForKey:property] ?: NSNull.null;
                vpFoldDisplayLog([NSString stringWithFormat:@"display pipeline state %s: %@", object_getClassName(pipeline), pipelineState]);
                static BOOL arbiterMethodsLogged;
                if (arbiter && !arbiterMethodsLogged) {
                    arbiterMethodsLogged = YES;
                    unsigned int count = 0;
                    Method *methods = class_copyMethodList(object_getClass(arbiter), &count);
                    for (unsigned int i = 0; i < count; i++) {
                        const char *name = sel_getName(method_getName(methods[i]));
                        if (strstr(name, "tage") || strstr(name, "articipant") || strstr(name, "esolved") || strstr(name, "escription"))
                            vpFoldDisplayLog([NSString stringWithFormat:@"arbiter method %s %s types: %s", object_getClassName(arbiter), name, method_getTypeEncoding(methods[i])]);
                    }
                    free(methods);
                }
                NSMutableDictionary *screenBounds = [NSMutableDictionary dictionary];
                for (NSString *property in @[@"_referenceBounds", @"_unjailedReferenceBounds", @"_mainSceneReferenceBounds", @"nativeBounds"])
                    screenBounds[property] = vpReadRectValue(screen, property.UTF8String) ?: NSNull.null;
                vpFoldDisplayLog([NSString stringWithFormat:@"display screen geometry: %@", screenBounds]);
                NSUInteger visibleWindowCount = 0;
                for (id window in vpReadObject(value, "windows")) {
                    if (![[window valueForKey:@"hidden"] boolValue] && visibleWindowCount++ < 8) {
                        vpFoldDisplayLog([NSString stringWithFormat:@"display visible window %s frame=%@ bounds=%@",
                            object_getClassName(window), [window valueForKey:@"frame"], [window valueForKey:@"bounds"]]);
                        NSMutableDictionary *policy = [NSMutableDictionary dictionary];
                        for (NSString *property in @[@"_shouldResizeWithScene", @"_isHostedInAnotherProcess", @"_isSceneSized", @"resizesToFullScreen"])
                            policy[property] = vpReadBoolValue(window, property.UTF8String) ?: NSNull.null;
                        policy[@"classTransformRotationsEnabled"] = vpReadBoolValue(object_getClass(window), "_transformLayerRotationsAreEnabled") ?: NSNull.null;
                        policy[@"sceneBoundsInWindowOrientation"] = vpReadRectValue(window, "_sceneBoundsInWindowOrientation") ?: NSNull.null;
                        id controller = vpReadObject(window, "rootViewController");
                        id view = vpReadObject(controller, "viewIfLoaded");
                        policy[@"rootController"] = controller ? NSStringFromClass([controller class]) : @"none";
                        policy[@"rootViewFrame"] = vpReadRectValue(view, "frame") ?: NSNull.null;
                        policy[@"rootViewBounds"] = vpReadRectValue(view, "bounds") ?: NSNull.null;
                        policy[@"windowTransform"] = [window valueForKey:@"transform"] ?: NSNull.null;
                        policy[@"rootViewTransform"] = view ? [view valueForKey:@"transform"] : NSNull.null;
                        policy[@"interfaceOrientation"] = [window valueForKey:@"interfaceOrientation"] ?: NSNull.null;
                        vpFoldDisplayLog([NSString stringWithFormat:@"display window resize policy %s: %@", object_getClassName(window), policy]);
                        // Read-only: separate UIKit scene orientation from the
                        // home controller's native orientation/layout caches.
                        NSMutableDictionary *controllerState = [NSMutableDictionary dictionary];
                        for (NSString *property in @[@"orientation", @"effectiveOrientation", @"supportedInterfaceOrientations"])
                            if ([controller respondsToSelector:NSSelectorFromString(property)])
                                controllerState[property] = [controller valueForKey:property] ?: NSNull.null;
                        id manager = vpReadObjectIvar(controller, "_iconManager");
                        id folder = vpReadObject(manager, "rootFolderController");
                        controllerState[@"iconManager"] = manager ?: NSNull.null;
                        controllerState[@"folderController"] = folder ?: NSNull.null;
                        controllerState[@"contentView"] = vpReadObjectIvar(controller, "_iconContentView") ?: NSNull.null;
                        vpFoldDisplayLog([NSString stringWithFormat:@"display controller layout %s: %@", object_getClassName(controller), controllerState]);
                    }
                }
                SEL mode = sel_registerName("displayContentModeForWindowScene:");
                Method method = class_getInstanceMethod(object_getClass(coordinator), mode);
                if (method && strcmp(method_getTypeEncoding(method), "q24@0:8@16") == 0) {
                    NSInteger selected = ((NSInteger (*)(id, SEL, id))objc_msgSend)(coordinator, mode, value);
                    vpFoldDisplayLog([NSString stringWithFormat:@"display state %@ mode=%ld", key, (long)selected]);
                }
            }
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"display state inspection exception: %@", exception.reason]);
    }
}
