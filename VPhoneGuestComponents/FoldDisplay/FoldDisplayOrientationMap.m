// The orientation map vphoned polls (vphone-display-orientation-map.json): the
// scene's native mounting tables and the current viewport.

#import "FoldDisplayPrivate.h"

// The SB-main orientation map is the contract vphoned's Duo rotation and
// posture paths poll (vp_display_orientation_mapping).  Publish the live
// scene geometry on demand, at startup, and after each viewport change;
// without this file the daemon sees "map unavailable" and refuses every
// posture/rotation settle.
void vpExportNativeOrientationMapping(void) {
    vpFoldDisplayLog(@"native orientation mapping export requested");
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        if (!app) return;
        id scene = vpReadObject(app, "activeDisplayWindowScene") ?: vpReadObject(app, "embeddedDisplayWindowScene");
        if (!scene) return;
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        if (!configuration) return;
        id screen = vpReadObject(scene, "screen");
        double scale = 3;
        @try {
            id scaleValue = screen ? [screen valueForKey:@"scale"] : nil;
            if ([scaleValue respondsToSelector:@selector(doubleValue)]) scale = [scaleValue doubleValue];
        } @catch (NSException *exception) { }
        long long interfaceOrientation = 1;
        SEL orientationSelector = sel_registerName("interfaceOrientation");
        if ([scene respondsToSelector:orientationSelector])
            interfaceOrientation = ((long long (*)(id, SEL))objc_msgSend)(scene, orientationSelector);
        unsigned long long surfaceType = 0;
        SEL surfaceSelector = sel_registerName("sbhScreenType");
        if ([scene respondsToSelector:surfaceSelector])
            surfaceType = ((unsigned long long (*)(id, SEL))objc_msgSend)(scene, surfaceSelector);
        // The daemon resolves interface requests through the device table;
        // the native scene owns the real inverse mounting map (the Duo inner
        // panel mounts rotated, measured [3,4,2,1] on iPhone19,4).  The
        // identity table stays only as the fallback for a scene without the
        // conversion selectors.
        NSMutableArray *deviceOrientations = [NSMutableArray arrayWithArray:@[@1, @2, @3, @4]];
        NSMutableArray *systemSpaceOrientations = [NSMutableArray arrayWithArray:@[@1, @2, @3, @4]];
        for (NSString *name in @[@"deviceOrientationForSystemSpaceOrientation:", @"systemSpaceOrientationForDeviceOrientation:"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = class_getInstanceMethod(object_getClass(scene), selector);
            if (!method || strcmp(method_getTypeEncoding(method), "q24@0:8q16") != 0) continue;
            NSMutableArray *table = [NSMutableArray arrayWithCapacity:4];
            for (NSInteger direction = 1; direction <= 4; direction++)
                [table addObject:@(((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(scene, selector, direction))];
            if (![[NSSet setWithArray:table] isEqualToSet:[NSSet setWithArray:@[@1, @2, @3, @4]]]) {
                vpFoldDisplayLog([NSString stringWithFormat:@"native orientation mapping export: %@ returned non-permutation %@; keeping fallback", name, table]);
                continue;
            }
            if ([name hasPrefix:@"deviceOrientation"]) deviceOrientations = table;
            else systemSpaceOrientations = table;
        }
        NSDictionary *map = @{
            @"version": @1,
            @"scene": @"SB-main",
            @"pid": @(getpid()),
            @"generatedUptime": @(NSProcessInfo.processInfo.systemUptime),
            @"available": @YES,
            @"persistentViewport": @(vpPersistentViewport ? YES : NO),
            @"deviceOrientations": deviceOrientations,
            @"systemSpaceOrientations": systemSpaceOrientations,
            @"scale": @(scale),
            @"surfaceType": @(surfaceType),
            @"viewportGeneration": @(atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed)),
            @"interfaceOrientation": @(interfaceOrientation),
            @"configurationBounds": vpSnapshotRect(configuration, "bounds"),
            @"coordinateBounds": vpSnapshotRect(vpReadObject(scene, "coordinateSpace"), "bounds") ?: NSNull.null,
            @"bounds": vpSnapshotRect(configuration, "bounds"),
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:map options:0 error:NULL];
        if (![data writeToFile:@"/var/mobile/Library/Caches/vphone-display-orientation-map.json" atomically:YES]) {
            vpFoldDisplayLog(@"native orientation mapping export: write failed");
            return;
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"native orientation mapping export: generation=%u bounds=%@ interface=%lld persistent=%d",
            atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed),
            map[@"configurationBounds"], interfaceOrientation, vpPersistentViewport ? 1 : 0]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"native orientation mapping export exception: %@", exception.reason]);
    }
}

id vpSnapshotPoseDirections(id provider) {
    SEL selector = sel_registerName("currentPose");
    NSMethodSignature *signature = [provider methodSignatureForSelector:selector];
    // The shipped SBF pose begins with three native q orientations. Match
    // the runtime aggregate ABI, rather than declaring a guessed C struct.
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnLength < 24 ||
        signature.methodReturnLength > 1024 || strncmp(signature.methodReturnType, "{?=qqq", 6) != 0) return NSNull.null;
    NSMutableData *bytes = [NSMutableData dataWithLength:signature.methodReturnLength];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = provider;
    invocation.selector = selector;
    [invocation invoke];
    [invocation getReturnValue:bytes.mutableBytes];
    int64_t directions[3]; memcpy(directions, bytes.bytes, sizeof(directions));
    return @[@(directions[0]), @(directions[1]), @(directions[2])];
}
