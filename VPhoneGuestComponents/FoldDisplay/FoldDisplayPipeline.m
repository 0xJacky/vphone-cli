// SpringBoard's display configuration pipeline: the main-configuration
// transformer hook, display-monitor observation, and the logged identity and
// configuration getters.

#import "FoldDisplayPrivate.h"

static IMP vpOriginalAlwaysConnected;
static IMP vpOriginalTransform;
static atomic_uint vpTransformLogCount;
static atomic_uint vpConfigurationLogCount;
atomic_bool vpLogicalProjectionEnabled;
__weak id vpLogicalRoleResolver;
IMP vpOriginalStartResolvingDisplay;

// Bumped on every hooked SBMainDisplayConfigurationTransformer call so the
// invalidation pulse can prove the pipeline actually re-ran.
static atomic_uint vpPulseTransformCount;

__weak id vpObservedConfigurationTransformer;

NSHashTable *vpObservedDisplayMonitors;
static IMP vpOriginalPublicMonitorInit;
static IMP vpOriginalCompletionMonitorInit;

// MARK: - transform refresh

// Re-runs the Main configuration transform through the observed display
// monitors, or through the FBDisplayManager compatibility monitor when none
// was observed. It changes no display identity or framebuffer itself.
void vpRefreshMainTransform(void) {
    NSUInteger refreshed = 0;
    @synchronized (vpObservedDisplayMonitors) {
        for (id monitor in vpObservedDisplayMonitors) {
            SEL update = sel_registerName("updateConfigurationWithCompletion:");
            if (![monitor respondsToSelector:update]) continue;
            @try { ((void (*)(id, SEL, id))objc_msgSend)(monitor, update, ^(id error) { (void)error; }); refreshed++; }
            @catch (NSException *exception) { vpFoldDisplayLog([NSString stringWithFormat:@"transform refresh exception: %@", exception.reason]); }
        }
    }
    // This SpringBoard build creates no FBSDisplayMonitor through the
    // observed initializers, but the FBDisplayManager compatibility monitor
    // owns the same configuration pipeline (it holds the transformer whose
    // cover override the flag above arms). The 3803cc4d invalidation pulse
    // drove the cover switch through updateTransformsWithCompletion:; the
    // selector table of that shipped dylib names it, the rewritten source
    // had lost it.
    if (refreshed == 0) {
        id manager = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        SEL transforms = sel_registerName("updateTransformsWithCompletion:");
        Method pulse = manager ? class_getInstanceMethod(object_getClass(manager), transforms) : NULL;
        if (pulse) {
            vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse: selector ABI %s", method_getTypeEncoding(pulse)]);
            if (strcmp(method_getTypeEncoding(pulse), "v24@0:8@?16") == 0) {
                @try {
                    // The Main source sits out the transform pipeline until
                    // its updatable flag is set; the 3803cc4d pulse flipped
                    // it for the duration of one update and restored it in
                    // the completion.
                    NSMutableArray *flippedSources = [NSMutableArray array];
                    static BOOL sourceFlagInventoried;
                    for (id source in vpReadObject(manager, "_sortedSources")) {
                        NSNumber *updatable = nil;
                        @try { updatable = [source valueForKey:@"updatable"]; } @catch (NSException *exception) { }
                        if (!updatable || updatable.boolValue) continue;
                        SEL setUpdatable = sel_registerName("setUpdatable:");
                        Method setter = class_getInstanceMethod(object_getClass(source), setUpdatable);
                        if (!sourceFlagInventoried) {
                            sourceFlagInventoried = YES;
                            vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse: source class %s updatable-getter %@ setter %@",
                                object_getClassName(source),
                                [source methodSignatureForSelector:sel_registerName("updatable")],
                                setter ? [NSString stringWithFormat:@"%s", method_getTypeEncoding(setter)] : @"absent"]);
                        }
                        const char *setterABI = setter ? method_getTypeEncoding(setter) : NULL;
                        if (setterABI && strcmp(setterABI, "v20@0:8B16") == 0)
                            ((void (*)(id, SEL, BOOL))objc_msgSend)(source, setUpdatable, YES);
                        else if (setterABI && strcmp(setterABI, "v20@0:8q16") == 0)
                            ((void (*)(id, SEL, long))objc_msgSend)(source, setUpdatable, 1L);
                        else {
                            // No usable setter: the 3803cc4d pulse worked, so
                            // the flag must be settable another way. Try the
                            // instance variable directly by offset.
                            Ivar flag = class_getInstanceVariable(object_getClass(source), "_updatable");
                            if (!flag) flag = class_getInstanceVariable(object_getClass(source), "updatable");
                            const char *flagType = flag ? ivar_getTypeEncoding(flag) : NULL;
                            if (flag && flagType && (flagType[0] == 'B' || flagType[0] == 'c' || flagType[0] == 'q' || flagType[0] == 'i')) {
                                *(BOOL *)((char *)(__bridge void *)source + ivar_getOffset(flag)) = YES;
                                [flippedSources addObject:source];
                                vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse: source %s flag ivar %s set", object_getClassName(source), flagType]);
                                continue;
                            }
                            vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse: native source flag ABI unavailable (%s setter %s ivar %s)",
                                object_getClassName(source), setterABI ? setterABI : "absent", flagType ?: "absent"]);
                            continue;
                        }
                        [flippedSources addObject:source];
                        vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse: prior updatable=%d", updatable.boolValue]);
                    }
                    unsigned int before = atomic_load_explicit(&vpPulseTransformCount, memory_order_relaxed);
                    ((void (*)(id, SEL, id))objc_msgSend)(manager, transforms, ^(id unused) {
                        (void)unused;
                        for (id source in flippedSources) {
                            SEL setUpdatable = sel_registerName("setUpdatable:");
                            Method setter = class_getInstanceMethod(object_getClass(source), setUpdatable);
                            const char *setterABI = setter ? method_getTypeEncoding(setter) : NULL;
                            if (setterABI && strcmp(setterABI, "v20@0:8B16") == 0)
                                ((void (*)(id, SEL, BOOL))objc_msgSend)(source, setUpdatable, NO);
                            else if (setterABI && strcmp(setterABI, "v20@0:8q16") == 0)
                                ((void (*)(id, SEL, long))objc_msgSend)(source, setUpdatable, 0L);
                            else {
                                Ivar flag = class_getInstanceVariable(object_getClass(source), "_updatable");
                                if (!flag) flag = class_getInstanceVariable(object_getClass(source), "updatable");
                                const char *flagType = flag ? ivar_getTypeEncoding(flag) : NULL;
                                if (flag && flagType && (flagType[0] == 'B' || flagType[0] == 'c' || flagType[0] == 'q' || flagType[0] == 'i'))
                                    *(BOOL *)((char *)(__bridge void *)source + ivar_getOffset(flag)) = NO;
                            }
                        }
                        if (flippedSources.count) vpFoldDisplayLog(@"invalidation pulse: native flag restored");
                        unsigned int after = atomic_load_explicit(&vpPulseTransformCount, memory_order_relaxed);
                        vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse: transform calls %u -> %u", before, after]);
                    });
                    refreshed++;
                    vpFoldDisplayLog(@"invalidation pulse: updateTransformsWithCompletion requested");
                } @catch (NSException *exception) {
                    vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse exception: %@", exception.reason]);
                }
            }
        } else {
            // One-shot inventory of the manager's own pipeline methods, so a
            // renamed selector is visible without another build cycle.
            static BOOL inventoried;
            if (!inventoried) {
                inventoried = YES;
                unsigned int count = 0;
                Class managerClass = object_getClass(manager);
                for (unsigned int level = 0; managerClass && level < 3; level++, managerClass = class_getSuperclass(managerClass)) {
                    Method *methods = class_copyMethodList(managerClass, &count);
                    for (unsigned int i = 0; i < count; i++) {
                        const char *selector = sel_getName(method_getName(methods[i]));
                        if (strstr(selector, "pdate") || strstr(selector, "ransform") || strstr(selector, "onfiguration"))
                            vpFoldDisplayLog([NSString stringWithFormat:@"invalidation pulse: manager method %s %s",
                                selector, method_getTypeEncoding(methods[i])]);
                    }
                    free(methods);
                }
            }
            vpFoldDisplayLog(@"transform refresh: no observed monitors and the manager lacks both update selectors");
        }
    }
}

// MARK: - monitor and configuration observation

BOOL vpIsDuoInnerBounds(id configuration) {
    SEL selector = sel_registerName("bounds");
    NSMethodSignature *signature = [configuration methodSignatureForSelector:selector];
    if (signature.methodReturnLength != sizeof(CGRect)) return NO;
    CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(configuration, selector);
    // Native size is the acceptance target. Retain the earlier explicit
    // research viewport so its saved restoration controls remain usable.
    return CGRectEqualToRect(bounds, CGRectMake(0, 0, 669, 951)) ||
        CGRectEqualToRect(bounds, CGRectMake(0, 0, 678, 951));
}

static void vpRememberDisplayMonitor(id monitor, id transformer) {
    if (!monitor) return;
    @synchronized (vpObservedDisplayMonitors) {
        [vpObservedDisplayMonitors addObject:monitor];
    }
    vpFoldDisplayLog([NSString stringWithFormat:@"monitor init: %s %p transformer=%s %p",
        object_getClassName(monitor), (__bridge void *)monitor,
        transformer ? object_getClassName(transformer) : "none", (__bridge void *)transformer]);
}

static id vpObservePublicMonitorInit(id self, SEL cmd, id transformer) {
    id monitor = ((id (*)(id, SEL, id))vpOriginalPublicMonitorInit)(self, cmd, transformer);
    vpRememberDisplayMonitor(monitor, transformer);
    return monitor;
}

static id vpObserveCompletionMonitorInit(id self, SEL cmd, id completion) {
    id monitor = ((id (*)(id, SEL, id))vpOriginalCompletionMonitorInit)(self, cmd, completion);
    vpRememberDisplayMonitor(monitor, nil);
    return monitor;
}

// Transform one native root into distinct logical configurations. The native
// builder preserves root linkage; no render mode or identity array is forged.
static id vpLoggedTransform(id self, SEL _cmd, id configuration) {
    vpObservedConfigurationTransformer = self;
    atomic_fetch_add_explicit(&vpPulseTransformCount, 1, memory_order_relaxed);
    id result = ((id (*)(id, SEL, id))vpOriginalTransform)(self, _cmd, configuration);
    if (atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire) &&
        [result isKindOfClass:NSSet.class] && [result count] == 1) {
        id candidate = [result anyObject];
        id identity = ((id (*)(id, SEL))objc_msgSend)(candidate, sel_registerName("identity"));
        if ([identity respondsToSelector:sel_registerName("isMainRootDisplay")] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(identity, sel_registerName("isMainRootDisplay"))) {
            CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(candidate, sel_registerName("bounds"));
            CGSize cover = bounds.size.width > bounds.size.height ? CGSizeMake(678, 466) : CGSizeMake(466, 678);
            if (cover.width <= bounds.size.width && cover.height <= bounds.size.height) {
                id mode = ((id (*)(id, SEL))objc_msgSend)(candidate, sel_registerName("currentMode"));
                SEL modeCopy = sel_registerName("_copyWithOverrideSize:scale:");
                SEL configurationCopy = sel_registerName("copyWithOverrideMode:");
                Method modeMethod = class_getInstanceMethod(object_getClass(mode), modeCopy);
                Method configurationMethod = class_getInstanceMethod(object_getClass(candidate), configurationCopy);
                if (!modeMethod || !configurationMethod ||
                    strcmp(method_getTypeEncoding(modeMethod), "@40@0:8{CGSize=dd}16d32") != 0 ||
                    strcmp(method_getTypeEncoding(configurationMethod), "@24@0:8@16") != 0) {
                    vpFoldDisplayLog(@"single viewport: complete effective-mode copy ABI unavailable");
                    return result;
                }
                CGFloat scale = ((CGFloat (*)(id, SEL))objc_msgSend)(mode, sel_registerName("pointScale"));
                // These are FBS frontend descriptors. The underlying CADisplay
                // and its hardware mode remain the original objects.
                id coverMode = [(id<VPhoneDisplayModeCopying>)mode _copyWithOverrideSize:cover scale:scale];
                id bounded = [(id<VPhoneDisplayProjectionCopying>)candidate copyWithOverrideMode:coverMode];
                id boundedIdentity = ((id (*)(id, SEL))objc_msgSend)(bounded, sel_registerName("identity"));
                if (bounded && [boundedIdentity isEqual:identity]) {
                    result = [NSSet setWithObject:bounded];
                    vpFoldDisplayLog([NSString stringWithFormat:@"single viewport: native Main cover configuration %@", bounded]);
                    // The publish races any same-run adoption steps: schedule
                    // them for after this transform returns, once per
                    // generation, so the recompute sees the landed bounds.
                    dispatch_async(dispatch_get_main_queue(), ^{ vpScheduleViewportAdoption(); });
                }
            }
        }
    }
    if (atomic_load_explicit(&vpLogicalProjectionEnabled, memory_order_acquire))
        vpFoldDisplayLog([NSString stringWithFormat:@"logical transform called: self=%@ resultClass=%@", self, NSStringFromClass([result class])]);
    // Never expand this set: the native SBFBSDisplayTransformer contract is
    // exactly one effective configuration per source. Derived identities
    // are previewed off to the side until singleton replacement is proven.
    if (atomic_fetch_add_explicit(&vpTransformLogCount, 1, memory_order_relaxed) < 8)
        vpFoldDisplayLog([NSString stringWithFormat:@"transform input=%@ output=%@", configuration, result]);
    return result;
}

static NSArray *vpObservedAlwaysConnected(id self, SEL _cmd) {
    NSArray *identities = ((NSArray *(*)(id, SEL))vpOriginalAlwaysConnected)(self, _cmd);
    vpFoldDisplayLog([NSString stringWithFormat:@"observed %s count=%lu", sel_getName(_cmd), (unsigned long)identities.count]);
    return identities;
}

// The measured main configuration is already 678x951. Keep bounded evidence
// here while investigating how that configuration reaches scene traits.
static IMP vpOriginalMainConfiguration;

static id vpLoggedMainConfiguration(id self, SEL _cmd) {
    id (*original)(id, SEL) = (id (*)(id, SEL))vpOriginalMainConfiguration;
    id configuration = original(self, _cmd);
    if (atomic_fetch_add_explicit(&vpConfigurationLogCount, 1, memory_order_relaxed) < 8)
        vpFoldDisplayLog([NSString stringWithFormat:@"mainConfiguration -> %@", configuration]);
    return configuration;
}

static IMP vpOriginalMainIdentity;

static id vpLoggedMainIdentity(id self, SEL _cmd) {
    id (*original)(id, SEL) = (id (*)(id, SEL))vpOriginalMainIdentity;
    id identity = original(self, _cmd);
    vpFoldDisplayLog([NSString stringWithFormat:@"mainIdentity -> %@", identity]);
    return identity;
}

// Observe the native monitor inventory. A count readback alone does not
// establish which native condition selects a home layout family.
static IMP vpOriginalMonitorIdentities;

static NSArray *vpObservedMonitorIdentities(id self, SEL _cmd) {
    NSArray *identities = ((NSArray *(*)(id, SEL))vpOriginalMonitorIdentities)(self, _cmd);
    vpFoldDisplayLog([NSString stringWithFormat:@"observed %s count=%lu", sel_getName(_cmd), (unsigned long)identities.count]);
    return identities;
}

// Observe configuration counts; never invent a second hardware identity.
static IMP vpOriginalLockConfigurations;

static NSArray *vpObservedLockConfigurations(id self, SEL _cmd) {
    NSArray *configurations = ((NSArray *(*)(id, SEL))vpOriginalLockConfigurations)(self, _cmd);
    vpFoldDisplayLog([NSString stringWithFormat:@"observed %s count=%lu", sel_getName(_cmd), (unsigned long)configurations.count]);
    return configurations;
}

// This initializer was not called in the baseline. Preserve its input exactly
// if a different display transition eventually exercises it.
static IMP vpOriginalMonitorInit;

static id vpObservedMonitorInit(id self, SEL _cmd,
                              NSArray *displays, id mainDisplay,
                              id bookendObserver, id transformer) {
    id (*original)(id, SEL, NSArray *, id, id, id) = (id (*)(id, SEL, NSArray *, id, id, id))vpOriginalMonitorInit;
    return original(self, _cmd, displays, mainDisplay, bookendObserver, transformer);
}

// MARK: - single inner readiness

// One physical panel can expose only the active fold surface. Test the
// content-readiness boundary without promoting a virtual CADisplay, adding
// a source, or bypassing the native one-result transformer invariant.
// This hook is installed only for an explicitly consumed startup flag.
void vpResolveSingleInnerDisplay(id self, SEL cmd, id proxy) {
    ((void (*)(id, SEL, id))vpOriginalStartResolvingDisplay)(self, cmd, proxy);
    if (vpLogicalRoleExperiment) {
        vpLogicalRoleResolver = self;
        vpSyncLogicalRoleResolver();
        return;
    }
    @try {
        NSDictionary *proxies = vpReadObjectIvar(self, "_displayProxies");
        if (proxies.count != 1 || proxies.allValues.firstObject != proxy ||
            [[self valueForKey:@"isReadyToResolve"] boolValue] ||
            [[proxy valueForKey:@"isExternal"] boolValue] ||
            [[proxy valueForKey:@"surfaceType"] integerValue] != 2) return;
        id monitor = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id identity = vpReadObject(configuration, "identity");
        NSSet *connected = vpReadObject(monitor, "connectedIdentities");
        if (connected.count != 1 || ![connected containsObject:identity] ||
            ![[identity valueForKey:@"isMainRootDisplay"] boolValue]) return;
        Ivar ready = class_getInstanceVariable(object_getClass(self), "_isReadyToResolve");
        SEL update = sel_registerName("_updateResolvedContentModesForDisplays");
        Method method = class_getInstanceMethod(object_getClass(self), update);
        if (!ready || strcmp(ivar_getTypeEncoding(ready), "B") != 0 ||
            !method || strcmp(method_getTypeEncoding(method), "v16@0:8") != 0) return;
        [self setValue:@YES forKey:@"isReadyToResolve"];
        vpFoldDisplayLog(@"single inner readiness: one real Main, one nonexternal inner proxy; native content resolution requested");
        ((void (*)(id, SEL))objc_msgSend)(self, update);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"single inner readiness exception: %@", exception.reason]);
    }
}

// MARK: - installation

// Installed last in the constructor: an early return here leaves the
// monitor half of the observation idle and nothing after it unset.
void vpInstallDisplayPipelineObservation(void) {
    Class transformer = objc_getClass("SBMainDisplayConfigurationTransformer");
    Method transform = class_getInstanceMethod(transformer, sel_registerName("transformDisplayConfiguration:"));
    if (transform && strcmp(method_getTypeEncoding(transform), "@24@0:8@16") == 0) {
        vpOriginalTransform = method_setImplementation(transform, (IMP)vpLoggedTransform);
        vpFoldDisplayLog(@"transform probe installed");
    } else {
        vpFoldDisplayLog([NSString stringWithFormat:@"transform probe unavailable: %s",
            transform ? method_getTypeEncoding(transform) : "missing"]);
    }
    dlopen("/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard",
           RTLD_LAZY | RTLD_LOCAL);
    Class manager = objc_getClass("FBDisplayManager");
    Method alwaysConnected = manager
        ? class_getClassMethod(manager, sel_registerName("alwaysConnectedIdentities"))
        : NULL;
    if (!alwaysConnected) {
        vpFoldDisplayLog(@"FBDisplayManager alwaysConnectedIdentities missing — idle");
        return;
    }
    vpOriginalAlwaysConnected = method_getImplementation(alwaysConnected);
    method_setImplementation(alwaysConnected, (IMP)vpObservedAlwaysConnected);
    vpFoldDisplayLog(@"observation installed over +alwaysConnectedIdentities");

    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
           RTLD_LAZY | RTLD_LOCAL);
    Class monitor = objc_getClass("FBSDisplayMonitor");
    Method publicInit = class_getInstanceMethod(monitor, sel_registerName("initWithTransformer:"));
    if (publicInit && strcmp(method_getTypeEncoding(publicInit), "@24@0:8@16") == 0)
        vpOriginalPublicMonitorInit = method_setImplementation(publicInit, (IMP)vpObservePublicMonitorInit);
    Method completionInit = class_getInstanceMethod(monitor, sel_registerName("initWithInitializationCompletion:"));
    if (completionInit && strcmp(method_getTypeEncoding(completionInit), "@24@0:8@?16") == 0)
        vpOriginalCompletionMonitorInit = method_setImplementation(completionInit, (IMP)vpObserveCompletionMonitorInit);
    Method monitorInit = monitor
        ? class_getInstanceMethod(monitor,
              sel_registerName("_initWithDisplays:mainDisplay:bookendObserver:transformer:"))
        : NULL;
    if (!monitorInit) {
        vpFoldDisplayLog(@"FBSDisplayMonitor init missing — monitor half idle");
        return;
    }
    vpOriginalMonitorInit = method_getImplementation(monitorInit);
    method_setImplementation(monitorInit, (IMP)vpObservedMonitorInit);
    vpFoldDisplayLog(@"observation installed over _initWithDisplays:mainDisplay:bookendObserver:transformer:");

    Method identities = class_getInstanceMethod(monitor, sel_registerName("alwaysConnectedIdentities"));
    if (identities) {
        vpOriginalMonitorIdentities = method_getImplementation(identities);
        method_setImplementation(identities, (IMP)vpObservedMonitorIdentities);
        vpFoldDisplayLog(@"observation installed over -[FBSDisplayMonitor alwaysConnectedIdentities]");
    } else {
        vpFoldDisplayLog(@"FBSDisplayMonitor alwaysConnectedIdentities missing");
    }
    for (NSString *name in @[@"mainConfiguration", @"mainIdentity"]) {
        SEL selector = sel_registerName(name.UTF8String);
        Method method = class_getClassMethod(manager, selector);
        if (!method) {
            vpFoldDisplayLog([NSString stringWithFormat:@"FBDisplayManager %@ missing", name]);
            continue;
        }
        if (selector == sel_registerName("mainConfiguration")) {
            vpOriginalMainConfiguration = method_getImplementation(method);
            method_setImplementation(method, (IMP)vpLoggedMainConfiguration);
        } else {
            vpOriginalMainIdentity = method_getImplementation(method);
            method_setImplementation(method, (IMP)vpLoggedMainIdentity);
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"log installed over +[%@ %@]",
                          NSStringFromClass(manager), name]);
    }
    Method configurations = class_getInstanceMethod(monitor, sel_registerName("_lock_alwaysConnectedConfigurations"));
    if (configurations) {
        vpOriginalLockConfigurations = method_getImplementation(configurations);
        method_setImplementation(configurations, (IMP)vpObservedLockConfigurations);
        vpFoldDisplayLog(@"observation installed over _lock_alwaysConnectedConfigurations");
    }
}
