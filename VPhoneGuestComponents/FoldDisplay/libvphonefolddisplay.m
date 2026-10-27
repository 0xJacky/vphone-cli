// Experimental, manifest-gated Duo display diagnostics.
// The framebuffer already reports the requested inner dimensions, while the
// home grid retains the narrow family. Identity-count hooks below have not
// been called on the tested guest. Keep their outcome distinct from the
// confirmed mainConfiguration and screen-type observations; see
// Research/Guest/iphone_duo_bringup.md.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../MISFix/MISFixDetour.h"
#include <dlfcn.h>
#include <string.h>
#include <stdatomic.h>
#include <notify.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <stdio.h>

static IMP vpOriginalAlwaysConnected;
static IMP vpOriginalTransform;
static atomic_uint vpTransformLogCount;
static atomic_uint vpConfigurationLogCount;
static atomic_bool vpLogicalProjectionEnabled;
static atomic_bool vpCoverViewportEnabled;
static BOOL vpPersistentViewport;
static IMP vpOriginalLogicalSurfaceType;
static BOOL vpLogicalRoleExperiment;
static __weak id vpLogicalRoleResolver;
static _Thread_local BOOL vpReadingLogicalSurface;
static atomic_uint vpViewportRequestGeneration;
static atomic_bool vpCoordinateRootSceneFrame;
static atomic_bool vpNativeGeometryRefreshEnabled;
static atomic_uint vpWindowGeometryRefreshGeneration;
static IMP vpOriginalSceneGeometryCallback;
static IMP vpOriginalStartResolvingDisplay;
static atomic_bool vpSceneResizePropagationEnabled;
static IMP vpOriginalSBWindowResizePolicy;
static __weak id vpSceneResizeScope;
static NSMutableDictionary<NSString *, NSNumber *> *vpResizedSceneGenerations;
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
static IMP vpOriginalSceneScreenType;
static NSUInteger vpInnerNativeScreenType;
static atomic_uint vpInnerFamilyLogCount;
static void *vpOriginalSharedFamilyClassifier;
static void *vpOriginalViewportScreenFamily, *vpOriginalViewportGlobalFamily;
static _Thread_local BOOL vpViewportFamilyLookupActive;
static _Thread_local unsigned int vpGlobalFamilyDepth;
static atomic_uint vpGlobalFamilyTraceCount;
static atomic_uint vpSharedFamilyLogCount;
static __weak id vpEmbeddedOrientationApplication;
static __weak id vpEmbeddedOrientationScene;
static NSInteger vpEmbeddedOrientationOriginal, vpEmbeddedOrientationPublished;
static atomic_uint vpEmbeddedOrientationGeneration;
static IMP vpOriginalSceneIsMain, vpOriginalStatusManagerInit, vpOriginalStatusManagerEmbedded;
static _Thread_local void *vpStatusManagerInitializingScene;
static _Thread_local BOOL vpStatusManagerMainQueryConsumed;
static IMP vpOriginalTimeItemUpdate;
static IMP vpOriginalMachClockTick, vpOriginalMachClockObserve;
static atomic_uint vpClockReferenceFallbackCount;
static atomic_uint vpTimeItemTraceCount;
static __weak id vpUIConfigWindowScene, vpUIConfigServerScene, vpUIConfigClientScene;
static _Atomic(IMP) vpUIIdentityCopyOriginal;
static _Thread_local void *vpUIIdentityCopySource, *vpUIIdentityCopyReplacement;
static id vpUIConfigOriginalHosted, vpUIConfigOriginalServerDisplay, vpUIConfigOriginalUI, vpUIConfigPublished;
static atomic_uint vpUIConfigGeneration;
static id vpUIOldStatusComponent, vpUINewStatusComponent, vpUIStatusComponentKey;
static BOOL vpUIStatusDetachedBeforeRollback;
static __weak id vpUIOldStatusWindow;
static NSNumber *vpUIOldStatusWindowHidden;
static _Atomic(IMP) vpOriginalStatusProfileFactories[4];
static atomic_bool vpStatusProfileLookupEnabled;
static unsigned int vpStatusProfileGeneration;
static unsigned int vpStatusProfileCallCount;
static _Thread_local void *vpStatusProfileConstructionScene;
static _Thread_local unsigned int vpStatusProfileFactoryDepth;
static __weak id vpStatusProfileScene;
static __weak id vpUITraitsScreen;
static NSNumber *vpUITraitsOriginalIdiom;
static NSInteger vpUITraitsPublishedIdiom;
static NSString *vpUITraitsIdentifier;
static void *vpOriginalMainStatusClassLookup;
static atomic_bool vpMainStatusProfileEnabled;
static unsigned int vpMainStatusProfileGeneration, vpMainStatusProfileLogCount;
static __weak id vpMainStatusProfileScene;
static Class vpMainStatusOriginalProviderClass;
static BOOL vpAutomaticMainStatus;
static void vpFoldDisplayLog(NSString *line);
static BOOL vpWallpaperOrientationLeaseActive;
static void *vpOriginalWallpaperFeatureLookup;
static IMP vpOriginalWallpaperSetHidden;
static BOOL vpWallpaperTraitsExperimentInstalled;
// Bumped on every hooked SBMainDisplayConfigurationTransformer call so the
// invalidation pulse can prove the pipeline actually re-ran.
static atomic_uint vpPulseTransformCount;
// The generation whose post-transform adoption pass already ran.
static atomic_uint vpAdoptionCompletedGeneration;
static __weak id vpObservedConfigurationTransformer;
static IMP vpOriginalExtendedProperties;
static atomic_bool vpInnerSurfaceProbeEnabled;
static atomic_uint vpPrimarySurfaceType = 2;
static unsigned int vpSurfaceProbeGeneration;
static atomic_bool vpCoverSurfaceProbeEnabled;
static atomic_uint vpSurfaceProbeLogCount;
static NSHashTable *vpObservedDisplayMonitors;
static IMP vpOriginalPublicMonitorInit;
static IMP vpOriginalCompletionMonitorInit;
static void vpFoldDisplayLog(NSString *line);
static id vpReadObject(id object, const char *name);
static id vpReadObjectIvar(id object, const char *name);
static id vpMainInnerWindowScene(void);
static void vpRestoreStatusProfileLookup(void);
static void vpResetManagedStatusProvider(void);
static BOOL vpRestoreUIScreenTraits(void);
static void vpRefreshMainStatusRenderer(void);
static void vpProcessViewportWorkspaceRequest(BOOL submit);
static void vpSyncLogicalRoleResolver(void);
static void vpRefreshMainTransform(void);
static void vpInspectDuoSystemUI(void);
static void vpInspectStatusProvider(void);
static void vpPulseInputTrace(void);
static void vpRestoreInputTrace(void);
static void vpExportNativeOrientationMapping(void);
static void vpLogicalProjectionControl(NSInteger action);
static id vpRootServerScenes(id app);
static NSArray *vpSnapshotRect(id object, const char *name);
static void vpProcessViewportWorkspaceRequest(BOOL submit);
static void vpApplyRootGeometry(void);
static void vpScheduleViewportAdoption(void);
static void vpApplyQuickActionGlyphScale(void);

// These helpers are kept at the boundary so the extracted status/wallpaper
// sections can call them without depending on declaration order. They only
// use the existing monitor and diagnostic surfaces; no display identity or
// framebuffer is changed here.
static void vpRefreshMainTransform(void) {
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
// The overridden Main configuration keeps its identity, so FrontBoard
// pushes no scene-settings update when only the mode size changed. The
// 3803cc4d root-geometry pass published the active bounds to the SB-main
// root scene through its settings-mutation API; recovered here.
static void vpScheduleViewportAdoption(void) {
    unsigned int adoptionGeneration = atomic_load_explicit(&vpViewportRequestGeneration, memory_order_relaxed);
    if (adoptionGeneration == atomic_load_explicit(&vpAdoptionCompletedGeneration, memory_order_relaxed)) return;
    atomic_store_explicit(&vpAdoptionCompletedGeneration, adoptionGeneration, memory_order_relaxed);
    vpApplyRootGeometry();
    if (vpPersistentViewport) vpProcessViewportWorkspaceRequest(YES);
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
static void vpInspectDuoSystemUI(void) {
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
static void vpInspectStatusProvider(void) { vpFoldDisplayLog(@"status provider inspection requested"); }
static void vpPulseInputTrace(void) { vpFoldDisplayLog(@"input trace pulse requested"); }
static void vpRestoreInputTrace(void) { vpFoldDisplayLog(@"input trace restore requested"); }
static void vpLogicalProjectionControl(NSInteger action) {
    vpFoldDisplayLog([NSString stringWithFormat:@"logical projection control requested action=%ld", (long)action]);
}

static BOOL vpIsDuoInnerBounds(id configuration) {
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
static void vpFoldDisplayLog(NSString *line) {
    int fd = open("/var/mobile/Library/Caches/vphone-folddisplay.log",
                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    if (fd < 0)
        return;
    NSString *stamp = [NSDateFormatter localizedStringFromDate:NSDate.date
                                                     dateStyle:NSDateFormatterNoStyle
                                                    timeStyle:NSDateFormatterMediumStyle];
    NSString *row = [NSString stringWithFormat:@"%@ %@\n", stamp, line];
    const char *bytes = row.UTF8String;
    if (bytes)
        write(fd, bytes, strlen(bytes));
    close(fd);
}

static BOOL vpConsumeDisplayExperimentFlag(const char *flag) {
    int fd = open(flag, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return NO;
    char value = 0;
    ssize_t length = read(fd, &value, 1);
    close(fd);
    unlink(flag);
    return length == 1 && value == '1';
}

// backboardd's native traits RPC reads DeviceSurfaceType from this dictionary.
// Keep the probe bounded and scoped to the real primary render display. It
// changes neither the framebuffer nor the number/identity of display sources.
static id vpSurfaceExtendedProperties(id self, SEL cmd) {
    id properties = ((id (*)(id, SEL))vpOriginalExtendedProperties)(self, cmd);
    if (!atomic_load_explicit(&vpInnerSurfaceProbeEnabled, memory_order_acquire)) return properties;
    id name = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("deviceName"));
    BOOL primary = [name isEqual:@"primary"];
    BOOL cover = atomic_load_explicit(&vpCoverSurfaceProbeEnabled, memory_order_acquire) &&
        [name isEqual:@"VPhone Cover Probe"];
    if ((!primary && !cover) || (properties && ![properties isKindOfClass:NSDictionary.class])) return properties;
    NSMutableDictionary *derived = properties ? [properties mutableCopy] : [NSMutableDictionary dictionary];
    derived[@"DeviceSurfaceType"] = primary ? @(atomic_load_explicit(&vpPrimarySurfaceType, memory_order_acquire)) : @1;
    if (atomic_fetch_add_explicit(&vpSurfaceProbeLogCount, 1, memory_order_relaxed) < 8)
        vpFoldDisplayLog([NSString stringWithFormat:@"surface probe: %@ traits %@ -> %@", name, properties, derived]);
    return [derived copy];
}

static void vpBeginSurfaceProbe(unsigned int surfaceType, BOOL pair) {
    if (!vpOriginalExtendedProperties) return;
    if (surfaceType != 1 && surfaceType != 2) return;
    unsigned int generation = ++vpSurfaceProbeGeneration;
    atomic_store_explicit(&vpPrimarySurfaceType, surfaceType, memory_order_release);
    atomic_store_explicit(&vpCoverSurfaceProbeEnabled, pair, memory_order_release);
    atomic_store_explicit(&vpInnerSurfaceProbeEnabled, true, memory_order_release);
    vpFoldDisplayLog([NSString stringWithFormat:@"surface probe: primary role=%u enabled for 30 seconds; pairedCover=%d", surfaceType, pair]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation != vpSurfaceProbeGeneration) return;
        atomic_store_explicit(&vpInnerSurfaceProbeEnabled, false, memory_order_release);
        atomic_store_explicit(&vpCoverSurfaceProbeEnabled, false, memory_order_release);
        vpFoldDisplayLog(@"surface probe: primary native role restored");
    });
}

@protocol VPhoneDisplayProjectionCopying
- (instancetype)copyWithOverrideBounds:(CGRect)bounds;
- (instancetype)copyWithOverrideMode:(id)mode;
@end
@protocol VPhoneDisplayModeCopying
- (instancetype)_copyWithOverrideSize:(CGSize)size scale:(CGFloat)scale;
@end
@protocol VPhoneDisplayProjectionBuilding
- (instancetype)initWithConfiguration:(id)configuration;
- (void)setUniqueIdentifier:(NSString *)identifier;
- (void)setDisplayType:(NSInteger)type;
- (void)setUIKitMainLike;
- (id)buildConfigurationWithError:(NSError **)error;
@end
@protocol VPhoneDisplayIdentityInitializing
- (instancetype)_initWithType:(NSInteger)type UIKitMainLike:(BOOL)mainLike displayID:(uint32_t)displayID
    connectionType:(NSInteger)connectionType connectionSeed:(uint32_t)connectionSeed pid:(int)pid
    external:(BOOL)external uniqueIdentifier:(id)identifier secure:(BOOL)secure
    alwaysConnected:(BOOL)alwaysConnected root:(id)root;
@end
@protocol VPhoneGeometryPreferencesInitializing
- (instancetype)initWithInterfaceOrientations:(NSUInteger)orientations;
@end


// Classify a distinct reference context; never publish its 669pt geometry.
// This tests the shared scene family decision used by system consumers,
// including the native status-bar rotation gate, rather than one provider.
static NSUInteger vpNativeInnerSceneFamily(id self, SEL selector) {
    NSUInteger original = ((NSUInteger (*)(id, SEL))vpOriginalSceneScreenType)(self, selector);
    @try {
        if (![[self valueForKey:@"surfaceType"] isEqual:@2]) return original;
        id identity = vpReadObject(self, "displayIdentity");
        // SBWindowScene has no displayConfiguration on this build. Resolve
        // Main through FrontBoard and verify its identity before using it.
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        if (![[identity valueForKey:@"isMainRootDisplay"] boolValue] ||
            ![identity isEqual:vpReadObject(configuration, "identity")]) return original;
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(configuration, sel_registerName("bounds"));
        if (!CGSizeEqualToSize(bounds.size, CGSizeMake(678, 951))) return original;
        if (!vpInnerNativeScreenType) {
            void *home = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_LOCAL);
            NSUInteger (*classify)(id, id) = dlsym(home, "SBHScreenTypeForDeviceAndDisplayContexts");
            id device = vpReadObject(objc_getClass("UISDeviceContext"), "sb_defaultContext");
            id display = vpReadObject(self, "_sbDisplayContext");
            id copy = [display mutableCopy];
            Method setter = class_getInstanceMethod(object_getClass(copy), sel_registerName("setDisplayConfiguration:"));
            if (!classify || !device || !copy || copy == display || !setter ||
                strcmp(method_getTypeEncoding(setter), "v24@0:8@16") != 0) return original;
            id mode = vpReadObject(configuration, "currentMode");
            CGFloat scale = ((CGFloat (*)(id, SEL))objc_msgSend)(mode, sel_registerName("pointScale"));
            id referenceMode = [(id<VPhoneDisplayModeCopying>)mode _copyWithOverrideSize:CGSizeMake(669, 951) scale:scale];
            id reference = [(id<VPhoneDisplayProjectionCopying>)configuration copyWithOverrideMode:referenceMode];
            ((void (*)(id, SEL, id))objc_msgSend)(copy, sel_registerName("setDisplayConfiguration:"), reference);
            NSUInteger candidate = classify(device, copy);
            if (candidate != 32) return original;
            vpInnerNativeScreenType = candidate;
        }
        if (atomic_fetch_add_explicit(&vpInnerFamilyLogCount, 1, memory_order_relaxed) < 4)
            vpFoldDisplayLog([NSString stringWithFormat:@"shared scene family: native reference=%lu original=%lu actual=%gx%g",
                (unsigned long)vpInnerNativeScreenType, (unsigned long)original, bounds.size.width, bounds.size.height]);
        return vpInnerNativeScreenType;
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"shared scene family exception: %@", exception.reason]);
        return original;
    }
}

static NSUInteger vpSharedInnerFamily(uintptr_t a, uintptr_t b, uintptr_t c, CGRect bounds,
                                     CGFloat scale, CGFloat referenceScale) {
    // The native common helper receives x0..x2 plus the CGRect HFA in
    // d0..d3 and two scalars in d4/d5. Both exported context and screen
    // classifiers use this helper; hooking their wrapper misses UIScreen.
    NSUInteger (*original)(uintptr_t, uintptr_t, uintptr_t, CGRect, CGFloat, CGFloat) = vpOriginalSharedFamilyClassifier;
    NSUInteger native = original(a, b, c, bounds, scale, referenceScale);
    @try {
        if (!CGSizeEqualToSize(bounds.size, CGSizeMake(678, 951))) return native;
        CGRect reference = bounds;
        reference.size.width = 669;
        NSUInteger family = original(a, b, c, reference, scale, referenceScale);
        if (family != 32) return native;
        if (atomic_fetch_add_explicit(&vpSharedFamilyLogCount, 1, memory_order_relaxed) < 6)
            vpFoldDisplayLog([NSString stringWithFormat:@"shared classifier: native=%lu reference=%lu actual=%gx%g",
                (unsigned long)native, (unsigned long)family, bounds.size.width, bounds.size.height]);
        return family;
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"shared classifier exception: %@", exception.reason]);
        return native;
    }
}

static void vpInstallSharedInnerFamily(void) {
    void *home = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_LOCAL);
    void *target = dlsym(home, "_SBHScreenTypeLookupCommon");
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    if (!target || !install) { vpFoldDisplayLog(@"shared classifier: existing detour API unavailable"); return; }
    // The existing constructor-only detour checks relocation and readback,
    // uses process-private COW cache pages, and publishes the trampoline
    // before its jump. Nothing in the on-disk cache or other processes changes.
    MISFixDetourResult result = install("Duo shared screen classifier", target, (void *)vpSharedInnerFamily,
                                       &vpOriginalSharedFamilyClassifier);
    vpFoldDisplayLog([NSString stringWithFormat:@"shared classifier: constructor detour result=%d", result]);
}

// The physical screen's family caches are boot-scoped. During an explicit
// same-Main viewport lease, ask the native context classifier about the
// currently published scene instead; do not overwrite dispatch_once state
// or associated objects, and never affect another screen.
static NSUInteger vpViewportFamily(id requestedScreen, NSUInteger fallback) {
    if (!atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire) ||
        ![NSThread isMainThread] || vpViewportFamilyLookupActive) return fallback;
    vpViewportFamilyLookupActive = YES;
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id scene = vpReadObject(app, "embeddedDisplayWindowScene");
        id screen = vpReadObject(scene, "screen");
        id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        if (!scene || (requestedScreen && requestedScreen != screen) ||
            ![vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier") isEqual:@"SB-main"] ||
            ![vpReadObject(screen, "displayIdentity") isEqual:vpReadObject(root, "identity")]) return fallback;
        id context = vpReadObject(scene, "_sbDisplayContext");
        id device = vpReadObject(objc_getClass("UISDeviceContext"), "sb_defaultContext");
        NSUInteger (*classify)(id, id) = dlsym(RTLD_DEFAULT, "SBHScreenTypeForDeviceAndDisplayContexts");
        if (!context || !device || !classify) return fallback;
        NSUInteger result = classify(device, context);
        return (result == 31 || result == 32) ? result : fallback;
    } @catch (NSException *exception) {
        return fallback;
    } @finally { vpViewportFamilyLookupActive = NO; }
}

static NSUInteger vpViewportScreenFamily(id screen) {
    return vpViewportFamily(screen, ((NSUInteger (*)(id))vpOriginalViewportScreenFamily)(screen));
}
// No Foundation formatting here: classification can be called while native
// once-initializers are holding locks. Bounded raw records also survive a
// blocked main queue and identify which side of the trampoline was reached.
static void vpTraceGlobalFamily(const char *phase, unsigned int sequence, NSUInteger value, void *caller) {
    if (sequence >= 24) return;
    int fd = open("/var/mobile/Library/Caches/vphone-duo-family-trace.log",
        O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0644);
    if (fd < 0) return;
    char line[512];
    int length = snprintf(line, sizeof(line), "pid=%d seq=%u depth=%u phase=%s value=%lu caller=%p",
        getpid(), sequence, vpGlobalFamilyDepth, phase, (unsigned long)value, caller);
    if (length > 0 && length < (int)sizeof(line) - 1) { line[length++] = '\n'; write(fd, line, (size_t)length); }
    close(fd);
}
static NSUInteger vpViewportGlobalFamily(void) {
    unsigned int sequence = atomic_fetch_add_explicit(&vpGlobalFamilyTraceCount, 1, memory_order_relaxed);
    ++vpGlobalFamilyDepth;
    vpTraceGlobalFamily("enter-original", sequence, 0, __builtin_return_address(0));
    NSUInteger original = ((NSUInteger (*)(void))vpOriginalViewportGlobalFamily)();
    vpTraceGlobalFamily("returned-original", sequence, original, __builtin_return_address(0));
    NSUInteger result = vpViewportFamily(nil, original);
    vpTraceGlobalFamily("returned-context", sequence, result, __builtin_return_address(0));
    --vpGlobalFamilyDepth;
    return result;
}
static void vpInstallViewportFamilyLookup(void) {
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    void *screen = dlsym(RTLD_DEFAULT, "SBHScreenTypeForScreen");
    void *global = dlsym(RTLD_DEFAULT, "SBHScreenTypeForCurrentDevice");
    if (!install || !screen || !global) return;
    MISFixDetourResult a = install("Duo viewport screen family", screen, (void *)vpViewportScreenFamily, &vpOriginalViewportScreenFamily);
    MISFixDetourResult b = install("Duo viewport global family", global, (void *)vpViewportGlobalFamily, &vpOriginalViewportGlobalFamily);
    vpFoldDisplayLog([NSString stringWithFormat:@"viewport native family: screen=%d global=%d", a, b]);
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

// Disabling the broad server probe restored startup on the Duo guest. The
// surviving log identified BKDisplayCloneMirroringManager as an evaluator
// owner. Inspect only this class after startup; do not realize every class or
// replace methods until their signatures and purpose have been established.
static void vpInspectServerClass(void) {
    Class cls = objc_getClass("BKDisplayCloneMirroringManager");
    if (!cls) {
        vpFoldDisplayLog(@"targeted server probe: class absent");
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    vpFoldDisplayLog([NSString stringWithFormat:@"targeted server probe: %u methods", count]);
    for (unsigned int i = 0; i < count; i++) {
        vpFoldDisplayLog([NSString stringWithFormat:@"server method: %s types: %s",
            sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i])]);
    }
    free(methods);
    vpFoldDisplayLog(@"targeted server probe: complete");
}

@protocol VPhoneVirtualDisplayInitialization
- (instancetype)initWithOptions:(NSDictionary *)options;
@end

static id vpVirtualDisplayProbe;

static void vpInspectRenderDisplays(void) {
    @try {
        Class cls = objc_getClass("CAWindowServer");
        SEL running = sel_registerName("serverIfRunning");
        if (![cls respondsToSelector:running]) return;
        id server = ((id (*)(id, SEL))objc_msgSend)(cls, running);
        if (![server respondsToSelector:sel_registerName("displays")]) return;
        NSArray *displays = ((id (*)(id, SEL))objc_msgSend)(server, sel_registerName("displays"));
        for (id display in displays) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            for (NSString *key in @[@"name", @"deviceName", @"displayId", @"displayType", @"systemIdentifiers", @"tag", @"enabled", @"extendedProperties"]) {
                if (![display respondsToSelector:NSSelectorFromString(key)]) continue;
                id value = [display valueForKey:key];
                info[key] = value ?: NSNull.null;
            }
            vpFoldDisplayLog([NSString stringWithFormat:@"render display metadata: %@", info]);
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"render display metadata exception: %@", exception.reason]);
    }
}

static void vpEnableVirtualDisplayProbe(void) {
    @try {
        id display = vpVirtualDisplayProbe;
        SEL getter = sel_registerName("enabled"), setter = sel_registerName("setEnabled:");
        Method method = class_getInstanceMethod(object_getClass(display), setter);
        if (!display || ![display respondsToSelector:getter] || !method ||
            strcmp(method_getTypeEncoding(method), "v20@0:8B16") != 0) {
            vpFoldDisplayLog(@"virtual display enable: unavailable");
            return;
        }
        BOOL before = ((BOOL (*)(id, SEL))objc_msgSend)(display, getter);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(display, setter, YES);
        BOOL after = ((BOOL (*)(id, SEL))objc_msgSend)(display, getter);
        vpFoldDisplayLog([NSString stringWithFormat:@"virtual display enable: before=%d after=%d", before, after]);
        vpInspectRenderDisplays();
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"virtual display enable exception: %@", exception.reason]);
    }
}

static void vpTagVirtualDisplayProbe(void) {
    @try {
        NSString *(*describe)(NSUInteger) = dlsym(RTLD_DEFAULT, "NSStringFromBKSDisplayTags");
        SEL setter = sel_registerName("setTag:");
        Method method = class_getInstanceMethod(object_getClass(vpVirtualDisplayProbe), setter);
        if (!describe || !method || strcmp(method_getTypeEncoding(method), "v24@0:8q16") != 0) {
            vpFoldDisplayLog(@"virtual display tag: unavailable");
            return;
        }
        NSUInteger unknown = 0;
        for (unsigned int bit = 0; bit < 24; bit++) {
            NSUInteger candidate = (NSUInteger)1 << bit;
            NSString *label = describe(candidate);
            if (label && [label rangeOfString:@"unknown" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                if (unknown) { vpFoldDisplayLog(@"virtual display tag: ambiguous unknown bit"); return; }
                unknown = candidate;
            }
        }
        if (!unknown) { vpFoldDisplayLog(@"virtual display tag: no unknown bit"); return; }
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(vpVirtualDisplayProbe, setter, (NSInteger)unknown);
        vpFoldDisplayLog([NSString stringWithFormat:@"virtual display tag: %@ (%lu)", describe(unknown), (unsigned long)unknown]);
        vpInspectRenderDisplays();
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"virtual display tag exception: %@", exception.reason]);
    }
}

static void vpVirtualDisplayExperiment(BOOL create) {
    @try {
        Class serverClass = objc_getClass("CAWindowServer");
        SEL running = sel_registerName("serverIfRunning");
        if (![serverClass respondsToSelector:running]) {
            vpFoldDisplayLog(@"virtual display: server accessor absent");
            return;
        }
        id server = ((id (*)(id, SEL))objc_msgSend)(serverClass, running);
        SEL add = sel_registerName("addDisplay:"), remove = sel_registerName("removeDisplay:");
        if (!server || ![server respondsToSelector:add] || ![server respondsToSelector:remove]) {
            vpFoldDisplayLog(@"virtual display: no running render server");
            return;
        }
        if (!create) {
            if (vpVirtualDisplayProbe) {
                ((void (*)(id, SEL, id))objc_msgSend)(server, remove, vpVirtualDisplayProbe);
                vpVirtualDisplayProbe = nil;
            }
            vpFoldDisplayLog(@"virtual display: probe removed");
            id remaining = ((id (*)(id, SEL))objc_msgSend)(server, sel_registerName("displays"));
            vpFoldDisplayLog([NSString stringWithFormat:@"virtual display: server inventory after remove %@", remaining]);
            return;
        }
        if (vpVirtualDisplayProbe) {
            vpFoldDisplayLog(@"virtual display: probe already exists");
            return;
        }
        Class cls = objc_getClass("CAWindowServerVirtualDisplay");
        Method initializer = class_getInstanceMethod(cls, sel_registerName("initWithOptions:"));
        if (!initializer || strcmp(method_getTypeEncoding(initializer), "@24@0:8@16") != 0) {
            vpFoldDisplayLog(@"virtual display: initializer ABI unavailable");
            return;
        }
        // Keys recovered from this guest's QuartzCore initializer. This is
        // an independent software surface, never a new IOMFB hardware mode.
        id display = [(id<VPhoneVirtualDisplayInitialization>)[cls alloc] initWithOptions:@{
            @"kCAVirtualDisplayWidth": @1398, @"kCAVirtualDisplayHeight": @2034,
            @"kCAVirtualDisplayUpdateRate": @60, @"kCAVirtualDisplayName": @"VPhone Cover Probe",
        }];
        if (!display) {
            vpFoldDisplayLog(@"virtual display: initializer returned nil");
            return;
        }
        vpVirtualDisplayProbe = display;
        ((void (*)(id, SEL, id))objc_msgSend)(server, add, display);
        vpFoldDisplayLog([NSString stringWithFormat:@"virtual display: registered %@", display]);
        id inventory = ((id (*)(id, SEL))objc_msgSend)(server, sel_registerName("displays"));
        vpFoldDisplayLog([NSString stringWithFormat:@"virtual display: server inventory after add %@", inventory]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"virtual display exception: %@", exception.reason]);
    }
}

static void vpInspectHomeScreenType(void) {
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

static id vpReadObject(id object, const char *name) {
    SEL selector = sel_registerName(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static id vpReadMultilineDescription(id object) {
    SEL selector = sel_registerName("descriptionWithMultilinePrefix:");
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || strcmp(method_getTypeEncoding(method), "@24@0:8@16") != 0) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(object, selector, @"");
}

static id vpReadObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

// One physical panel can expose only the active fold surface. Test the
// content-readiness boundary without promoting a virtual CADisplay, adding
// a source, or bypassing the native one-result transformer invariant.
// This hook is installed only for an explicitly consumed startup flag.
static void vpResolveSingleInnerDisplay(id self, SEL cmd, id proxy) {
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

static id vpRootServerScenes(id app) {
    return vpReadObject(vpReadObject(app, "displayProfileManager"), "fbScenes");
}

static NSNumber *vpReadBoolValue(id object, const char *name) {
    SEL selector = sel_registerName(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 ||
        (signature.methodReturnType[0] != 'B' && signature.methodReturnType[0] != 'c')) return nil;
    return @(((BOOL (*)(id, SEL))objc_msgSend)(object, selector));
}

static NSValue *vpReadRectValue(id object, const char *name) {
    SEL selector = sel_registerName(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 ||
        strcmp(signature.methodReturnType, "{CGRect={CGPoint=dd}{CGSize=dd}}") != 0) return nil;
    CGRect value = ((CGRect (*)(id, SEL))objc_msgSend)(object, selector);
    return [NSValue value:&value withObjCType:@encode(CGRect)];
}

static void vpSyncLogicalRoleResolver(void) {
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

static BOOL vpAllowScopedMainWindowResize(id self, SEL cmd) {
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

static void vpObserveSceneGeometry(id self, SEL cmd, id windowScene, id previousSpace,
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

static id vpSnapshotRect(id object, const char *name) {
    NSValue *value = vpReadRectValue(object, name);
    if (!value) return NSNull.null;
    CGRect rect;
    [value getValue:&rect size:sizeof(rect)];
    return @[@(rect.origin.x), @(rect.origin.y), @(rect.size.width), @(rect.size.height)];
}

static NSNumber *vpSnapshotScalarIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type) return nil;
    const void *address = (const char *)(__bridge void *)object + ivar_getOffset(ivar);
    if (strcmp(type, "B") == 0 || strcmp(type, "c") == 0) {
        uint8_t value; memcpy(&value, address, sizeof(value)); return @(value != 0);
    }
    if (strcmp(type, "q") == 0) { int64_t value; memcpy(&value, address, sizeof(value)); return @(value); }
    if (strcmp(type, "Q") == 0) { uint64_t value; memcpy(&value, address, sizeof(value)); return @(value); }
    return nil;
}

// The SB-main orientation map is the contract vphoned's Duo rotation and
// posture paths poll (vp_display_orientation_mapping).  Publish the live
// scene geometry on demand, at startup, and after each viewport change;
// without this file the daemon sees "map unavailable" and refuses every
// posture/rotation settle.
static void vpExportNativeOrientationMapping(void) {
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

static id vpSnapshotPoseDirections(id provider) {
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

// One bounded JSON line: do not format the arbiter, class inventories or
// controller/model descriptions on SpringBoard's main queue during tests.
static void vpSnapshotMainScene(void) {
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

static void vpProcessViewportWorkspaceRequest(BOOL submit) {
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

static void vpRefreshNativeStatusRegistration(void) {
    if (!vpLogicalRoleExperiment) return;
    id scene = vpMainInnerWindowScene();
    id bar = vpReadObject(vpReadObject(scene, "statusBarManager"), "statusBar");
    if (!bar || vpReadBoolValue(bar, "serverUpdatesDisabled").boolValue || vpReadBoolValue(bar, "isHidden").boolValue) return;
    SEL toggle = sel_registerName("setServerUpdatesDisabled:");
    SEL update = sel_registerName("forceUpdateData:");
    Method tm = class_getInstanceMethod(object_getClass(bar), toggle);
    Method um = class_getInstanceMethod(object_getClass(bar), update);
    if (!tm || !um || strcmp(method_getTypeEncoding(tm), "v20@0:8B16") != 0 ||
        strcmp(method_getTypeEncoding(um), "v20@0:8B16") != 0) return;
    @try {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, toggle, YES);
    } @finally {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, toggle, NO);
    }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, update, YES);
    vpFoldDisplayLog(@"native status registration: visible scene client re-registered and requested native data");
}

// Native minute scheduling already supports a nil reference view (zero
// frame-phase adjustment). A detached but alive view instead follows the
// nonnil path and divides by its absent screen's0 FPS. Use the native nil
// branch only while the reference cannot supply a valid screen cadence.
static id vpWithUsableClockReference(id provider, id (^operation)(void)) {
    Ivar ivar = class_getInstanceVariable(object_getClass(provider), "_referenceView");
    if (!vpLogicalRoleExperiment || ![NSThread isMainThread] || !ivar || ivar_getTypeEncoding(ivar)[0] != '@') return operation();
    id reference = vpReadObjectIvar(provider, "_referenceView");
    id screen = vpReadObject(vpReadObject(vpReadObject(reference, "window"), "windowScene"), "screen");
    NSMethodSignature *fpsSignature = [screen methodSignatureForSelector:sel_registerName("maximumFramesPerSecond")];
    NSInteger fps = 0;
    if (fpsSignature && fpsSignature.numberOfArguments == 2 &&
        (fpsSignature.methodReturnType[0] == 'q' || fpsSignature.methodReturnType[0] == 'Q'))
        fps = ((NSInteger (*)(id, SEL))objc_msgSend)(screen, sel_registerName("maximumFramesPerSecond"));
    if (!reference || fps > 0) return operation();
    // initWithReferenceView: uses objc_storeWeak for this slot. The runtime
    // setter preserves known weak memory management (objc/runtime.h).
    object_setIvar(provider, ivar, nil);
    @try {
        if (atomic_fetch_add_explicit(&vpClockReferenceFallbackCount, 1, memory_order_relaxed) < 4)
            vpFoldDisplayLog([NSString stringWithFormat:@"native clock reference fallback: class=%s screen=%p fps=%ld", object_getClassName(reference), screen, (long)fps]);
        return operation();
    } @finally {
        if (!object_getIvar(provider, ivar)) object_setIvar(provider, ivar, reference);
    }
}
static void vpMachClockTick(id self, SEL selector) {
    vpWithUsableClockReference(self, ^id {
        ((void (*)(id, SEL))vpOriginalMachClockTick)(self, selector);
        // A once-a-minute bounded walk re-scales glyph instances that a
        // lock-screen rebuild created at the native factor.
        if (vpAutomaticMainStatus) vpApplyQuickActionGlyphScale();
        return nil;
    });
}
static id vpMachClockObserve(id self, SEL selector, id handler) {
    return vpWithUsableClockReference(self, ^id {
        return ((id (*)(id, SEL, id))vpOriginalMachClockObserve)(self, selector, handler);
    });
}

static void vpObserveNativeTimeUpdate(id self, SEL selector, id date) {
    unsigned int count = atomic_fetch_add_explicit(&vpTimeItemTraceCount, 1, memory_order_relaxed);
    NSString *before = count < 20 ? [vpReadObjectIvar(self, "_timeItemTimeString") copy] : nil;
    ((void (*)(id, SEL, id))vpOriginalTimeItemUpdate)(self, selector, date);
    if (count < 20) {
        id current = vpReadObject(vpReadObjectIvar(self, "_dateTimeProvider"), "date");
        id provider = vpReadObjectIvar(self, "_dateTimeProvider");
        id underlying = vpReadObjectIvar(provider, "_underlyingProvider");
        NSString *interval = [date isKindOfClass:NSDate.class] ? [NSString stringWithFormat:@"%.17g", [(NSDate *)date timeIntervalSinceReferenceDate]] : @"not-date";
        vpFoldDisplayLog([NSString stringWithFormat:@"native clock update: input=%@ class=%s interval=%@ current=%@ underlying=%s underlyingDate=%@ before=%@ after=%@ caller=%p",
            date, date ? object_getClassName(date) : "nil", interval, current,
            underlying ? object_getClassName(underlying) : "nil", vpReadObject(underlying, "date"), before,
            vpReadObjectIvar(self, "_timeItemTimeString"), __builtin_return_address(0)]);
    }
}

static void vpRefreshNativeClockSource(void) {
    if (!vpLogicalRoleExperiment) return;
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    id aggregator = vpReadObject(app, "statusBarStateAggregator");
    SEL refresh = sel_registerName("_restartTimeItemTimer");
    Method method = class_getInstanceMethod(object_getClass(aggregator), refresh);
    if (!method || strcmp(method_getTypeEncoding(method), "v16@0:8") != 0) return;
    ((void (*)(id, SEL))objc_msgSend)(aggregator, refresh);
    vpFoldDisplayLog(@"native clock source: native time-item subscription restarted");
}

static void vpPulseNativeWallpaperOrientation(void) {
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
    NSInteger target = [[vpReadObject(scene, "traitsPipelineManager") valueForKey:@"systemArbitratedInterfaceOrientation"] integerValue];
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
    // This is now part of the normal Duo orientation pipeline.  Do not roll
    // the wallpaper back after a timer: the scene's current arbitration is
    // the source of truth and a delayed restore recreates the landscape black
    // band.  The next orientation request can update it again.
    vpWallpaperOrientationLeaseActive = NO;
}

static NSString *vpDescribeLayerContents(id contents) {
    if (!contents) return @"nil";
    @try {
        if (CFGetTypeID((CFTypeRef)contents) == CGImageGetTypeID()) {
            CGImageRef image = (CGImageRef)(__bridge void *)contents;
            return [NSString stringWithFormat:@"image %zux%zu", CGImageGetWidth(image), CGImageGetHeight(image)];
        }
    } @catch (NSException *exception) { }
    NSString *text = [contents description];
    if (text.length > 60) text = [text substringToIndex:60];
    return [NSString stringWithFormat:@"%s %@", object_getClassName(contents), text];
}

static void vpDumpWallpaperTree(id view, NSUInteger depth) {
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

// Reads one ivar by its type encoding so numeric and struct state appear
// without calling arbitrary getters.  Unknown layouts stay "?"; nothing is
// synthesized.
static NSString *vpFormatIvarValue(id object, Ivar ivar) {
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type) return @"?";
    void *ptr = (void *)((char *)(__bridge void *)object + ivar_getOffset(ivar));
    switch (type[0]) {
        case 'd': return [NSString stringWithFormat:@"%.6g", *(double *)ptr];
        case 'f': return [NSString stringWithFormat:@"%.6g", (double)*(float *)ptr];
        case 'B': return *(BOOL *)ptr ? @"YES" : @"NO";
        case 'c': return @(*(int8_t *)ptr).stringValue;
        case 'C': return @(*(uint8_t *)ptr).stringValue;
        case 's': return @(*(int16_t *)ptr).stringValue;
        case 'S': return @(*(uint16_t *)ptr).stringValue;
        case 'i': case 'l': return @(*(int32_t *)ptr).stringValue;
        case 'I': case 'L': return @(*(uint32_t *)ptr).stringValue;
        case 'q': return @(*(int64_t *)ptr).stringValue;
        case 'Q': return @(*(uint64_t *)ptr).stringValue;
        case '@': {
            id value = object_getIvar(object, ivar);
            if (!value) return @"nil";
            if ([value isKindOfClass:NSNumber.class]) return [NSString stringWithFormat:@"@ %@", value];
            if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSValue.class])
                return [NSString stringWithFormat:@"%s %@", object_getClassName(value), value];
            NSString *text = [value description];
            if (text.length > 90) text = [text substringToIndex:90];
            return [NSString stringWithFormat:@"%s %@", object_getClassName(value), text];
        }
        case '{': {
            if (strncmp(type, "{CGRect", 6) == 0) {
                CGRect rect = *(CGRect *)ptr;
                return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
            }
            if (strncmp(type, "{CGSize", 6) == 0) {
                CGSize size = *(CGSize *)ptr;
                return [NSString stringWithFormat:@"{%g, %g}", size.width, size.height];
            }
            if (strncmp(type, "{CGPoint", 7) == 0) {
                CGPoint point = *(CGPoint *)ptr;
                return [NSString stringWithFormat:@"{%g, %g}", point.x, point.y];
            }
            if (strncmp(type, "{UIEdgeInsets", 13) == 0) {
                // {top,left,bottom,right} as four CGFloats; a local layout so
                // UIKit is not a dependency of this dylib.
                const CGFloat *edges = (const CGFloat *)ptr;
                return [NSString stringWithFormat:@"insets{%g,%g,%g,%g}", edges[0], edges[1], edges[2], edges[3]];
            }
            if (strncmp(type, "{CGAffineTransform", 18) == 0) {
                CGAffineTransform transform = *(CGAffineTransform *)ptr;
                return [NSString stringWithFormat:@"transform{%g,%g,%g,%g,%g,%g}", transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty];
            }
            return @"{struct}";
        }
        case '^': return [NSString stringWithFormat:@"%p", *(void **)ptr];
        default: return @"?";
    }
}

static void vpDumpObjectIvars(id object, NSString *label, NSUInteger limit) {
    if (!object) { vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivars: nil", label]); return; }
    Class cls = object_getClass(object);
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivars: class=%s count=%u", label, class_getName(cls), count]);
    for (unsigned int i = 0; i < count && i < limit; i++) {
        @try {
            vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivar[%u] %s (%s) = %@", label, i,
                ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: "?",
                vpFormatIvarValue(object, ivars[i])]);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"%@ ivar[%u] %s exception: %@", label, i,
                ivar_getName(ivars[i]), exception.reason]);
        }
    }
    free(ivars);
}

// Reads the scalar state of a live SBSDeviceDeterminedConfiguration and probes
// its pure class-mapping helpers, so the profile-selection inputs (base class,
// distinguishers, subtype) and the base->effective mapping are both recorded
// from evidence.  Every selector is guarded; setters are never touched.
static void vpDumpDeviceConfiguration(id config) {
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
static id vpStashedConfig;
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

static void vpInstallConfigInitSwizzle(void) {
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

static void vpInstallLayoutClassSwizzle(void) {
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

// Lock-screen quick-action diagnostics: locate live CSQuickAction* views,
// record their geometry, traits and raw ivar state, and dump the native
// class surfaces so the profile selection can be read from evidence.
static void vpInspectQuickActions(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id device = vpReadObject(objc_getClass("UIDevice"), "currentDevice");
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action device: model=%@ name=%@ idiom=%ld orientation=%ld",
            [device valueForKey:@"model"], [device valueForKey:@"name"],
            (long)((NSInteger (*)(id, SEL))objc_msgSend)(device, sel_registerName("userInterfaceIdiom")),
            (long)((NSInteger (*)(id, SEL))objc_msgSend)(device, sel_registerName("orientation"))]);
        NSUInteger found = 0;
        for (id window in vpReadObject(app, "windows")) {
            NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count) {
                id view = pending.lastObject;
                [pending removeLastObject];
                NSString *className = NSStringFromClass([view class]);
                BOOL quickAction = [className containsString:@"QuickAction"];
                BOOL prominent = [className containsString:@"Prominent"];
                if ((quickAction || prominent) && found < 10) {
                    found++;
                    vpFoldDisplayLog([NSString stringWithFormat:@"quick action view: class=%@ frame=%@ alpha=%@ hidden=%@",
                        className, [view valueForKey:@"frame"], [view valueForKey:@"alpha"], [view valueForKey:@"hidden"]]);
                    vpDumpObjectIvars(view, @"quick action instance", 48);
                    if ([className isEqualToString:@"CSQuickActionsButton"]) {
                        // Read-only computed getters; they reveal which metric
                        // row the native layout resolved for this instance.
                        // These selectors belong to the button, not the glyph.
                        SEL sizeSelector = sel_registerName("iconImageSize");
                        SEL frameSelector = sel_registerName("iconImageFrame");
                        SEL diameterSelector = sel_registerName("buttonDiameter");
                        if ([view respondsToSelector:sizeSelector]) {
                            CGSize size = ((CGSize (*)(id, SEL))objc_msgSend)(view, sizeSelector);
                            vpFoldDisplayLog([NSString stringWithFormat:@"quick action computed: iconImageSize={%g, %g}", size.width, size.height]);
                        }
                        if ([view respondsToSelector:frameSelector]) {
                            CGRect rect = ((CGRect (*)(id, SEL))objc_msgSend)(view, frameSelector);
                            vpFoldDisplayLog([NSString stringWithFormat:@"quick action computed: iconImageFrame={{%g, %g}, {%g, %g}}",
                                rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]);
                        }
                        if ([view respondsToSelector:diameterSelector]) {
                            double diameter = ((double (*)(id, SEL))objc_msgSend)(view, diameterSelector);
                            vpFoldDisplayLog([NSString stringWithFormat:@"quick action computed: buttonDiameter=%.6g", diameter]);
                        }
                    }
                    if ([className isEqualToString:@"CSQuickActionsView"]) {
                        vpDumpObjectIvars(vpReadObjectIvar(view, "_quickActionsSettings"), @"quick action settings", 96);
                        vpDumpObjectIvars(vpReadObjectIvar(view, "_buttonContainerView"), @"quick action buttons container", 48);
                    }
                }
                for (id child in [view valueForKey:@"subviews"] ?: @[]) [pending addObject:child];
            }
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action inventory: views=%lu", (unsigned long)found]);
        // The layout controller, its adaptive time context, and the determined
        // configuration hang off the quick-action objects' ivar graph.
        if (vpStashedConfig) {
            vpDumpDeviceConfiguration(vpStashedConfig);
        } else {
            vpFoldDisplayLog(@"live device configuration: not constructed yet");
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action exception: %@", exception.reason]);
    }
}

// The user-validated glyph factor, applied without any experiment opt-in:
// over a SpringBoard startup ladder, after every orientation actuation
// refresh, after viewport transitions, and once per clock tick, because
// lock-screen rebuilds create fresh glyph instances.  The glyph class's
// method list is never touched (round-12/13); a plain transform walk is
// the only safe lever.
static double const vpQuickActionGlyphScale = 0.68;

static void vpApplyQuickActionGlyphScale(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        if (!app) return;
        NSUInteger touched = 0, rescaled = 0;
        for (id window in vpReadObject(app, "windows")) {
            NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count) {
                id view = pending.lastObject;
                [pending removeLastObject];
                if ([view isKindOfClass:objc_getClass("CSQuickActionImageGlyphView")]) {
                    SEL transformSelector = sel_registerName("transform");
                    if (![view respondsToSelector:transformSelector]) continue;
                    CGAffineTransform current = ((CGAffineTransform (*)(id, SEL))objc_msgSend)(view, transformSelector);
                    touched++;
                    if (fabs(current.a - vpQuickActionGlyphScale) < 0.001 &&
                        fabs(current.d - vpQuickActionGlyphScale) < 0.001) continue;
                    CGAffineTransform scaled = CGAffineTransformMakeScale(vpQuickActionGlyphScale, vpQuickActionGlyphScale);
                    NSValue *value = [NSValue value:&scaled withObjCType:@encode(CGAffineTransform)];
                    [view setValue:value forKey:@"transform"];
                    rescaled++;
                }
                for (id child in [view valueForKey:@"subviews"] ?: @[]) [pending addObject:child];
            }
        }
        if (rescaled)
            vpFoldDisplayLog([NSString stringWithFormat:@"quick action glyph scale: %lu of %lu views at %.2f",
                (unsigned long)rescaled, (unsigned long)touched, vpQuickActionGlyphScale]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action glyph scale exception: %@", exception.reason]);
    }
}

// Full window inventory with two subview levels: identifies which window or
// view owns any on-screen black band in landscape.
static void vpInspectAllWindows(void) {
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

// Experiment: the poster extension's hosted scene presentation views keep
// their portrait 669x951 bounds inside the landscape wallpaper tree.  This
// opt-in pulse resizes those scene-host nodes to the wallpaper presenter's
// current bounds and requests layout, mirroring the outer frame
// synchronization already part of the Duo wallpaper pulse.  Nothing runs
// without this notification; a later rotation can redo it.
static NSString *vpSizeText(CGSize size) {
    return [NSString stringWithFormat:@"{%.0f, %.0f}", size.width, size.height];
}

static void vpSyncWallpaperSceneHosts(void) {
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
            if ([className isEqualToString:@"_UIScenePresentationView"] ||
                [className isEqualToString:@"_UISceneLayerHostContainerView"] ||
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

// Lights the Lock Screen without the Home press icli's wake falls back to,
// so the locked wallpaper and quick actions can be captured lit.
static void vpUndimScreenOnly(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    void (*undim)(void) = handle ? dlsym(handle, "SBSUndimScreen") : NULL;
    if (!undim) { vpFoldDisplayLog(@"screen undim: SBSUndimScreen absent"); return; }
    undim();
    vpFoldDisplayLog(@"screen undim: requested");
}

static void vpInspectNativePresentation(void) {
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

static void vpInspectDisplayState(void) {
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

static void vpProbeUnknownDisplayPolicy(BOOL restore) {
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

static void vpRestoreRootSceneOrientations(void) {
    // Cancel delayed publication blocks before starting restoration.
    unsigned int generation = atomic_fetch_add_explicit(&vpSceneOrientationPulseGeneration, 1, memory_order_acq_rel) + 1;
    vpRestoreRootSceneOrientationsAttempt(generation, 0);
}

// Default-off pulse: publish the existing native arbitration result through
// the common root scene contract. No window transform/frame or app mask is
// supplied. Restoration starts after ten seconds and keeps a checkpoint
// until readback proves restoration or a newer setting supersedes it.
static void vpSyncRootSceneOrientation(void) {
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

static id vpMainInnerWindowScene(void) {
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

static BOOL vpIsSingleMainStatusScene(id scene, BOOL constructing) {
    if (![vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier") isEqual:@"SB-main"]) return NO;
    NSInteger surface = [[scene valueForKey:@"surfaceType"] integerValue];
    // During UIKit status-manager construction SB's surface property may
    // still be default. This path is armed only for the explicit inner boot.
    if (surface != 2 && !(constructing && surface == 0)) return NO;
    id identity = vpReadObject(scene, "_fbsDisplayIdentity") ?: vpReadObject(scene, "displayIdentity");
    id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
    return [[identity valueForKey:@"isMainRootDisplay"] boolValue] &&
        [identity isEqual:vpReadObject(configuration, "identity")] &&
        [vpSnapshotRect(configuration, "bounds") isEqual:@[@0, @0, @669, @951]];
}

static BOOL vpSceneMainDuringStatusConstruction(id self, SEL selector) {
if ((__bridge void *)self == vpStatusManagerInitializingScene && !vpStatusManagerMainQueryConsumed) {
        vpStatusManagerMainQueryConsumed = YES;
        vpFoldDisplayLog([NSString stringWithFormat:@"scene status construction: single Main query redirected caller=%p", __builtin_return_address(0)]);
        return NO;
    }
    return ((BOOL (*)(id, SEL))vpOriginalSceneIsMain)(self, selector);
}

static id vpConstructSceneStatusManager(id self, SEL selector, id scene) {
    void *previous = vpStatusManagerInitializingScene;
    BOOL previousConsumed = vpStatusManagerMainQueryConsumed;
    @try {
        vpFoldDisplayLog([NSString stringWithFormat:@"scene status construction: scene=%@ identity=%@ surface=%@",
            vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier"),
            vpReadObject(scene, "_fbsDisplayIdentity"), [scene valueForKey:@"surfaceType"]]);
        if (vpIsSingleMainStatusScene(scene, YES)) {
            vpStatusManagerInitializingScene = (__bridge void *)scene;
            vpStatusManagerMainQueryConsumed = NO;
            vpFoldDisplayLog(@"scene status policy: native per-scene construction for Main inner");
        }
        return ((id (*)(id, SEL, id))vpOriginalStatusManagerInit)(self, selector, scene);
    } @finally { vpStatusManagerInitializingScene = previous; vpStatusManagerMainQueryConsumed = previousConsumed; }
}

static BOOL vpSceneStatusUsesEmbeddedLegacySlot(id self, SEL selector) {
    if (vpIsSingleMainStatusScene(vpReadObjectIvar(self, "_windowScene"), NO)) return NO;
    return ((BOOL (*)(id, SEL))vpOriginalStatusManagerEmbedded)(self, selector);
}

static void vpInstallSceneStatusPolicy(void) {
    Class sceneClass = objc_getClass("SBWindowScene");
    Class managerClass = objc_getClass("SBWindowSceneStatusBarManager");
    SEL mainSelector = sel_registerName("isMainDisplayWindowScene");
    Method main = class_getInstanceMethod(sceneClass, mainSelector);
    Method init = class_getInstanceMethod(managerClass, sel_registerName("initWithScene:"));
    Method embedded = class_getInstanceMethod(managerClass, sel_registerName("_isEmbeddedDisplay"));
    if (!main || strcmp(method_getTypeEncoding(main), "B16@0:8") != 0 ||
        !init || strcmp(method_getTypeEncoding(init), "@24@0:8@16") != 0 ||
        !embedded || strcmp(method_getTypeEncoding(embedded), "B16@0:8") != 0) {
        vpFoldDisplayLog(@"scene status policy: native ABI unavailable"); return;
    }
    vpOriginalSceneIsMain = method_getImplementation(main);
    // Add an override to SBWindowScene itself if the method is inherited;
    // never replace UIWindowScene's implementation for all scene classes.
    if (!class_addMethod(sceneClass, mainSelector, (IMP)vpSceneMainDuringStatusConstruction, method_getTypeEncoding(main)))
        method_setImplementation(main, (IMP)vpSceneMainDuringStatusConstruction);
    vpOriginalStatusManagerInit = method_setImplementation(init, (IMP)vpConstructSceneStatusManager);
    vpOriginalStatusManagerEmbedded = method_setImplementation(embedded, (IMP)vpSceneStatusUsesEmbeddedLegacySlot);
    vpFoldDisplayLog(@"scene status policy: one-instance native per-scene adapter installed");
}

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

static void vpRestoreSceneGeometryRequest(void) {
    atomic_fetch_add_explicit(&vpGeometryRequestGeneration, 1, memory_order_acq_rel);
    id scene = vpGeometryRequestScene;
    vpGeometryRequestScene = nil;
    if (!scene || scene != vpMainInnerWindowScene()) return;
    NSInteger current = [[scene valueForKey:@"interfaceOrientation"] integerValue];
    if (current == vpGeometryRequestTarget || current == vpGeometryRequestOriginal)
        vpRequestSceneGeometry(scene, vpGeometryRequestOriginal);
    else vpFoldDisplayLog(@"scene geometry request: newer direction preserved");
}

static void vpProbeSceneGeometryRequest(void) {
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

static void vpRefreshNativeOrientationInputs(BOOL rereadPose) {
    @try {
        id scene = vpMainInnerWindowScene();
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

static void vpForceNativeOrientationResolution(void) {
    @try {
        id scene = vpMainInnerWindowScene();
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

static void vpSetCanonicalOrientationProbe(BOOL enabled) {
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

static void vpRefreshNativeOrientationActuation(void) {
    @try {
        id scene = vpMainInnerWindowScene();
        if (!scene) { vpFoldDisplayLog(@"orientation actuation: refused outside Main inner"); return; }
        NSInteger direction = [[vpReadObject(scene, "traitsPipelineManager") valueForKey:@"systemArbitratedInterfaceOrientation"] integerValue];
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
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"orientation actuation exception: %@", exception.reason]);
    }
}

static void vpRestoreEmbeddedOrientation(void) {
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

static void vpProbeEmbeddedOrientation(void) {
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

static void vpSnapshotBackboardOrientation(void) {
    // Native getters synchronize with the orientation manager and may query
    // CoreAnimation. Keep the backboardd main run loop free while observing.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        vpSnapshotBackboardOrientationNow();
    });
}

static void vpRestoreBackboardOrientationEvents(void) {
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

static void vpProbeBackboardOrientationEvents(void) {
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

static id vpCreateUIConfiguration(id configuration) {
    Class cls = objc_getClass("FBSDisplayConfigurationBuilder");
    Method type = class_getInstanceMethod(cls, sel_registerName("setDisplayType:"));
    Method mainLike = class_getInstanceMethod(cls, sel_registerName("setUIKitMainLike"));
    if (!type || strcmp(method_getTypeEncoding(type), "v24@0:8q16") != 0 ||
        !mainLike || strcmp(method_getTypeEncoding(mainLike), "v16@0:8") != 0) return nil;
    id<VPhoneDisplayProjectionBuilding> builder = [(id<VPhoneDisplayProjectionBuilding>)[cls alloc] initWithConfiguration:configuration];
    [builder setUniqueIdentifier:@"vphone-duo-ui-preview"];
    [builder setDisplayType:7];
    [builder setUIKitMainLike];
    NSError *error = nil;
    id result = [builder buildConfigurationWithError:&error];
    if (!result) vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration build failed: %@", error]);
    return result;
}

static id vpUIIdentityDuringUnpublishedCopy(id self, SEL selector) {
    if ((__bridge void *)self == vpUIIdentityCopySource) return (__bridge id)vpUIIdentityCopyReplacement;
    return ((id (*)(id, SEL))vpUIIdentityCopyOriginal)(self, selector);
}

static id vpCreateNonEmbeddedUIConfiguration(id root) {
    // The native builder can set MainLike but has no clear operation. Copy
    // from a distinct, unpublished UI configuration whose identity getter is
    // substituted only on this thread for the duration of the native build.
    // The physical Main and its accessors are never substituted.
    id source = vpCreateUIConfiguration(root);
    id identity = vpReadObject(source, "identity");
    if (!source || source == root || [[identity valueForKey:@"isMainDisplay"] boolValue] ||
        ![vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")]) return nil;
    Class cls = objc_getClass("FBSDisplayIdentity");
    SEL initializer = sel_registerName("_initWithType:UIKitMainLike:displayID:connectionType:connectionSeed:pid:external:uniqueIdentifier:secure:alwaysConnected:root:");
    Method method = class_getInstanceMethod(cls, initializer);
    if (!method || strcmp(method_getTypeEncoding(method), "@76@0:8q16B24I28q32I40i44B48@52B60B64@68") != 0) return nil;
    id replacement = [(id<VPhoneDisplayIdentityInitializing>)[cls alloc]
        _initWithType:[[identity valueForKey:@"type"] integerValue] UIKitMainLike:NO
        displayID:[[identity valueForKey:@"displayID"] unsignedIntValue]
        connectionType:[[identity valueForKey:@"connectionType"] integerValue]
        connectionSeed:[[identity valueForKey:@"connectionSeed"] unsignedIntValue]
        pid:[[identity valueForKey:@"pid"] intValue] external:[[identity valueForKey:@"isExternal"] boolValue]
        uniqueIdentifier:vpReadObject(identity, "uniqueIdentifier")
        secure:[[identity valueForKey:@"expectsSecureRendering"] boolValue]
        alwaysConnected:[[identity valueForKey:@"isAlwaysConnected"] boolValue] root:vpReadObject(identity, "rootIdentity")];
    if (!replacement || [[replacement valueForKey:@"isUIKitMainLike"] boolValue]) return nil;
    id<VPhoneDisplayProjectionBuilding> builder = [(id<VPhoneDisplayProjectionBuilding>)[objc_getClass("FBSDisplayConfigurationBuilder") alloc]
        initWithConfiguration:source];
    [builder setUniqueIdentifier:@"vphone-duo-ui-unembedded-preview"];
    [builder setDisplayType:7];
    SEL getter = sel_registerName("identity");
    Method identityMethod = class_getInstanceMethod(object_getClass(source), getter);
    if (!identityMethod || strcmp(method_getTypeEncoding(identityMethod), "@16@0:8") != 0 || vpUIIdentityCopySource) return nil;
    vpUIIdentityCopyOriginal = method_getImplementation(identityMethod);
    vpUIIdentityCopySource = (__bridge void *)source;
    vpUIIdentityCopyReplacement = (__bridge void *)replacement;
    id result = nil;
    @try {
        method_setImplementation(identityMethod, (IMP)vpUIIdentityDuringUnpublishedCopy);
        NSError *error = nil;
        result = [builder buildConfigurationWithError:&error];
        if (!result) vpFoldDisplayLog([NSString stringWithFormat:@"nonembedded UI copy failed: %@", error]);
    } @finally {
        if (method_getImplementation(identityMethod) == (IMP)vpUIIdentityDuringUnpublishedCopy)
            method_setImplementation(identityMethod, vpUIIdentityCopyOriginal);
        vpUIIdentityCopySource = NULL; vpUIIdentityCopyReplacement = NULL;
    }
    if ([[vpReadObject(result, "identity") valueForKey:@"isUIKitMainLike"] boolValue] ||
        vpReadObject(result, "CADisplay") != vpReadObject(root, "CADisplay")) return nil;
    return result;
}

static void vpPreviewNonEmbeddedUIConfiguration(void) {
    @try {
        id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id result = vpCreateNonEmbeddedUIConfiguration(root);
        id identity = vpReadObject(result, "identity");
        NSDictionary *fields = @{@"built": @(result != nil),
            @"mainLike": [identity valueForKey:@"isUIKitMainLike"] ?: NSNull.null,
            @"main": [identity valueForKey:@"isMainDisplay"] ?: NSNull.null,
            @"rootMatchesMain": @([vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")]),
            @"sameCADisplay": @(result && vpReadObject(result, "CADisplay") == vpReadObject(root, "CADisplay")),
            @"physicalMainLike": [vpReadObject(root, "identity") valueForKey:@"isUIKitMainLike"] ?: NSNull.null,
            @"bounds": vpSnapshotRect(result, "bounds"), @"previewOnly": @YES};
        NSData *data = [NSJSONSerialization dataWithJSONObject:fields options:0 error:NULL];
        if (data) vpFoldDisplayLog([@"nonembedded UI preview " stringByAppendingString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"nonembedded UI preview exception: %@", exception.reason]);
    }
}

static BOOL vpUIObjectsEqual(id a, id b) { return a == b || [a isEqual:b]; }

static void vpPropagateUIScreenTraits(id screen) {
    SEL update = sel_registerName("_updateTraits");
    Method updateMethod = class_getInstanceMethod(object_getClass(screen), update);
    if (updateMethod && strcmp(method_getTypeEncoding(updateMethod), "v16@0:8") == 0)
        ((void (*)(id, SEL))objc_msgSend)(screen, update);
    SEL selector = sel_registerName("_notifyTraitsChangedAndPropagate");
    Method method = class_getInstanceMethod(object_getClass(screen), selector);
    if (method && strcmp(method_getTypeEncoding(method), "v16@0:8") == 0)
        ((void (*)(id, SEL))objc_msgSend)(screen, selector);
}

static BOOL vpRestoreUIScreenTraits(void) {
    id screen = vpUITraitsScreen;
    if (!vpUITraitsOriginalIdiom) return YES;
    id identity = vpReadObject(screen, "displayIdentity");
    if (screen && ![[identity valueForKey:@"isMainDisplay"] boolValue] &&
        [vpReadObject(identity, "uniqueIdentifier") isEqual:vpUITraitsIdentifier] &&
        [[screen valueForKey:@"_userInterfaceIdiom"] integerValue] == vpUITraitsPublishedIdiom) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(screen, sel_registerName("_setUserInterfaceIdiom:"), vpUITraitsOriginalIdiom.integerValue);
        vpPropagateUIScreenTraits(screen);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: restored idiom=%@ readback=%@",
            vpUITraitsOriginalIdiom, [screen valueForKey:@"_userInterfaceIdiom"]]);
        if (![[screen valueForKey:@"_userInterfaceIdiom"] isEqual:vpUITraitsOriginalIdiom]) return NO;
    } else vpFoldDisplayLog(@"UI screen traits: detached screen gone or newer identity/value preserved");
    vpUITraitsScreen = nil; vpUITraitsOriginalIdiom = nil; vpUITraitsIdentifier = nil;
    return YES;
}

static void vpSyncUIScreenTraits(void) {
    @try {
        if (vpUITraitsOriginalIdiom || !vpUIConfigPublished) return;
        id scene = vpUIConfigWindowScene;
        id screen = vpReadObject(scene, "screen");
        id identity = vpReadObject(screen, "displayIdentity");
        id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id mainScreen = vpReadObject(vpReadObject(root, "identity"), "UIScreen");
        if (!scene || !screen || screen == mainScreen || !mainScreen ||
            [[identity valueForKey:@"isMainDisplay"] boolValue] ||
            ![identity isEqual:vpReadObject(vpUIConfigPublished, "identity")] ||
            ![vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")]) {
            vpFoldDisplayLog(@"UI screen traits: owned alias/Main screen binding unavailable"); return;
        }
        SEL selector = sel_registerName("_setUserInterfaceIdiom:");
        Method setter = class_getInstanceMethod(object_getClass(screen), selector);
        NSNumber *source = [mainScreen valueForKey:@"_userInterfaceIdiom"];
        NSNumber *original = [screen valueForKey:@"_userInterfaceIdiom"];
        if (!setter || strcmp(method_getTypeEncoding(setter), "v24@0:8q16") != 0 ||
            ![source isKindOfClass:NSNumber.class] || ![original isKindOfClass:NSNumber.class] || source.integerValue != 0) {
            vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: native setter/source unavailable source=%@ original=%@", source, original]); return;
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: source=%@ alias=%@ trait=%@",
            source, original, [vpReadObject(screen, "traitCollection") valueForKey:@"userInterfaceIdiom"]]);
        vpUITraitsScreen = screen; vpUITraitsOriginalIdiom = original;
        vpUITraitsPublishedIdiom = source.integerValue;
        vpUITraitsIdentifier = vpReadObject(identity, "uniqueIdentifier");
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(screen, selector, source.integerValue);
        vpPropagateUIScreenTraits(screen);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: native phone inheritance idiom=%@ trait=%@ embedded=%@",
            [screen valueForKey:@"_userInterfaceIdiom"], [vpReadObject(screen, "traitCollection") valueForKey:@"userInterfaceIdiom"],
            vpReadBoolValue(screen, "_isEmbeddedScreen")]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits exception: %@", exception.reason]);
    }
}

static void vpUIStatusLifecycle(id component, const char *name, id scene) {
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(component), selector);
    if (method && strcmp(method_getTypeEncoding(method), "v24@0:8@16") == 0)
        ((void (*)(id, SEL, id))objc_msgSend)(component, selector, scene);
}

static BOOL vpUIStatusRegistryAvailable(id scene) {
    Method reg = class_getInstanceMethod(object_getClass(scene), sel_registerName("_registerSceneComponent:forKey:"));
    Method unreg = class_getInstanceMethod(object_getClass(scene), sel_registerName("_unregisterSceneComponentForKey:"));
    return reg && unreg && strcmp(method_getTypeEncoding(reg), "v32@0:8@16@24") == 0 &&
        strcmp(method_getTypeEncoding(unreg), "v24@0:8@16") == 0;
}

static void vpDetachUIStatusComponent(void) {
    id scene = vpUIConfigWindowScene;
    if (!scene || !vpUINewStatusComponent || !vpUIStatusComponentKey) return;
    id current = vpReadObject(scene, "statusBarManager");
    if (current != vpUINewStatusComponent) return;
    id replacementWindow = vpReadObject(current, "statusBarWindow");
    if (replacementWindow && replacementWindow != vpUIOldStatusWindow)
        ((void (*)(id, SEL, BOOL))objc_msgSend)(replacementWindow, sel_registerName("setHidden:"), YES);
    vpUIStatusLifecycle(current, "windowSceneDidDisconnect:", scene);
    // Keep a registered component while UIKit processes the identity rollback;
    // replace it only after the original identity has been acknowledged.
    vpUIStatusDetachedBeforeRollback = YES;
    vpFoldDisplayLog(@"UI configuration: replacement native component detached before identity rollback");
}

static BOOL vpRestoreUIStatusComponent(void) {
    if (!vpUIOldStatusComponent) return YES;
    id scene = vpUIConfigWindowScene;
    if (!scene) {
        vpUIOldStatusComponent = nil; vpUINewStatusComponent = nil; vpUIStatusComponentKey = nil;
        vpUIOldStatusWindow = nil; vpUIOldStatusWindowHidden = nil;
        vpUIStatusDetachedBeforeRollback = NO; return YES;
    }
    id current = vpReadObject(scene, "statusBarManager");
    if (current && current != vpUIOldStatusComponent && current != vpUINewStatusComponent) return NO;
    if (current == vpUINewStatusComponent) {
        if (!vpUIStatusDetachedBeforeRollback) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(scene, sel_registerName("_unregisterSceneComponentForKey:"), vpUIStatusComponentKey);
        current = nil;
    }
    if (!current)
        ((void (*)(id, SEL, id, id))objc_msgSend)(scene, sel_registerName("_registerSceneComponent:forKey:"), vpUIOldStatusComponent, vpUIStatusComponentKey);
    id window = vpReadObject(vpUIOldStatusComponent, "statusBarWindow");
    if (!vpReadObject(window, "windowScene")) {
        Method setter = class_getInstanceMethod(object_getClass(window), sel_registerName("setWindowScene:"));
        if (setter && strcmp(method_getTypeEncoding(setter), "v24@0:8@16") == 0)
            ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("setWindowScene:"), scene);
    }
    vpUIStatusLifecycle(vpUIOldStatusComponent, "windowSceneDidConnect:", scene);
    BOOL verified = vpReadObject(scene, "statusBarManager") == vpUIOldStatusComponent;
    if (verified && vpUIOldStatusWindowHidden && vpUIOldStatusWindow) {
        if (window != vpUIOldStatusWindow) return NO;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setHidden:"), vpUIOldStatusWindowHidden.boolValue);
        verified = [vpReadBoolValue(window, "isHidden") isEqual:vpUIOldStatusWindowHidden];
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: original window visibility restored=%d", verified]);
    }
    if (verified) {
        vpUIOldStatusComponent = nil; vpUINewStatusComponent = nil; vpUIStatusComponentKey = nil;
        vpUIOldStatusWindow = nil; vpUIOldStatusWindowHidden = nil;
        vpUIStatusDetachedBeforeRollback = NO;
    }
    vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: original component restore verified=%d", verified]);
    return verified;
}

static void vpRefreshUIStatusComponent(void) {
    @try {
        id scene = vpUIConfigWindowScene;
        id identity = vpReadObject(scene, "_fbsDisplayIdentity");
        if (!scene || !vpUIConfigPublished || vpUIOldStatusComponent ||
            ![vpReadObject(identity, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")] ||
            !vpUIStatusRegistryAvailable(scene)) return;
        id __unsafe_unretained *keyAddress = (id __unsafe_unretained *)dlsym(RTLD_DEFAULT, "_UIStatusBarManagerWindowSceneComponentKey");
        id key = keyAddress ? *keyAddress : nil;
        id old = vpReadObject(scene, "statusBarManager");
        Method init = class_getInstanceMethod(object_getClass(old), sel_registerName("initWithScene:"));
        if (!key || !old || !init || strcmp(method_getTypeEncoding(init), "@24@0:8@16") != 0) return;
        id registered = ((id (*)(id, SEL, id))objc_msgSend)(scene, sel_registerName("_sceneComponentForKey:"), key);
        if (registered != old) { vpFoldDisplayLog(@"UI configuration: native component key did not match"); return; }
        vpUIOldStatusComponent = old;
        vpUIOldStatusWindow = vpReadObject(old, "statusBarWindow");
        vpUIOldStatusWindowHidden = vpReadBoolValue(vpUIOldStatusWindow, "isHidden");
        vpUIStatusComponentKey = key;
        vpUIStatusDetachedBeforeRollback = NO;
        vpUIStatusLifecycle(old, "windowSceneDidDisconnect:", scene);
        ((void (*)(id, SEL, id))objc_msgSend)(scene, sel_registerName("_unregisterSceneComponentForKey:"), key);
        id replacement = nil;
        void *previousScope = vpStatusProfileConstructionScene;
        @try {
            if (vpStatusProfileLookupEnabled) vpStatusProfileConstructionScene = (__bridge void *)scene;
            replacement = ((id (*)(id, SEL, id))objc_msgSend)([object_getClass(old) alloc], sel_registerName("initWithScene:"), scene);
        } @finally { vpStatusProfileConstructionScene = previousScope; }
        vpUINewStatusComponent = replacement;
        if (!replacement) { vpFoldDisplayLog(@"UI configuration: native replacement unavailable; restore checkpoint retained"); return; }
        ((void (*)(id, SEL, id, id))objc_msgSend)(scene, sel_registerName("_registerSceneComponent:forKey:"), replacement, key);
        vpUIStatusLifecycle(replacement, "windowSceneDidConnect:", scene);
        if (vpStatusProfileLookupEnabled) vpResetManagedStatusProvider();
        id replacementWindow = vpReadObject(replacement, "statusBarWindow");
        if (vpUIOldStatusWindow && replacementWindow && vpUIOldStatusWindow != replacementWindow && vpUIOldStatusWindowHidden) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(vpUIOldStatusWindow, sel_registerName("setHidden:"), YES);
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: previous profile window deactivated hidden=%@",
                vpReadBoolValue(vpUIOldStatusWindow, "isHidden")]);
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: native component recreated=%d embedded=%@",
            vpReadObject(scene, "statusBarManager") == replacement, vpReadBoolValue(replacement, "_isEmbeddedDisplay")]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration component exception: %@", exception.reason]);
    }
}

static BOOL vpUIConfigurationOwnedByLease(id configuration) {
    id identity = vpReadObject(configuration, "identity");
    return [vpReadObject(identity, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")];
}

static BOOL vpNotifyUIConfiguration(id scene, id configuration) {
    SEL selector = sel_registerName("_noteDisplayIdentityDidChangeWithConfiguration:");
    Method method = class_getInstanceMethod(object_getClass(scene), selector);
    if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@16") != 0) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(scene, selector, configuration);
    return YES;
}

static void vpSetUISceneConfigurations(id configuration, id displayConfiguration, id expected, id expectedDisplay, unsigned int generation) {
    id server = vpUIConfigServerScene;
    SEL update = sel_registerName("updateUISettingsWithBlock:");
    Method method = class_getInstanceMethod(object_getClass(server), update);
    if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@?16") != 0) {
        vpFoldDisplayLog(@"UI configuration: server settings-update ABI unavailable"); return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(server, update, ^(id settings) {
        if (generation != atomic_load_explicit(&vpUIConfigGeneration, memory_order_acquire) || server != vpUIConfigServerScene ||
            !vpUIObjectsEqual(vpReadObject(settings, "sb_hostedDisplayConfiguration"), expected) ||
            !vpUIObjectsEqual(vpReadObject(settings, "displayConfiguration"), expectedDisplay)) return;
        SEL setter = sel_registerName("sb_setHostedDisplayConfiguration:");
        Method method = class_getInstanceMethod(object_getClass(settings), setter);
        if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@16") != 0) return;
        SEL displaySetter = sel_registerName("setDisplayConfiguration:");
        NSMethodSignature *signature = [settings methodSignatureForSelector:displaySetter];
        // Generated settings accessors include @"FBSDisplayConfiguration"
        // in their encoding. Validate the semantic object ABI, not spelling.
        if (!signature || signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, "v") != 0 ||
            [signature getArgumentTypeAtIndex:2][0] != '@') return;
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(settings, displaySetter, displayConfiguration);
            ((void (*)(id, SEL, id))objc_msgSend)(settings, setter, configuration);
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: hosted/display transaction generation=%u actual=%@",
                generation, vpReadObject(vpReadObject(settings, "displayIdentity"), "uniqueIdentifier")]);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration transaction exception: %@", exception.reason]);
        }
    });
}

static void vpFinishUIConfigurationRestore(unsigned int generation, unsigned int attempt) {
    if (generation != atomic_load_explicit(&vpUIConfigGeneration, memory_order_acquire) || !vpUIConfigPublished) return;
    @try {
        id server = vpUIConfigServerScene;
        if (!server) {
            if (!vpRestoreUIScreenTraits()) return;
            vpUIConfigPublished = nil; vpUIConfigOriginalHosted = nil; vpUIConfigOriginalServerDisplay = nil; vpUIConfigOriginalUI = nil;
            vpUIOldStatusComponent = nil; vpUINewStatusComponent = nil; vpUIStatusComponentKey = nil;
            vpUIOldStatusWindow = nil; vpUIOldStatusWindowHidden = nil;
            vpUIStatusDetachedBeforeRollback = NO;
            vpUIConfigWindowScene = nil; vpUIConfigClientScene = nil; return;
        }
        id current = vpReadObject(vpReadObject(server, "uiSettings"), "sb_hostedDisplayConfiguration");
        id currentDisplay = vpReadObject(vpReadObject(server, "uiSettings"), "displayConfiguration");
        if (!vpUIObjectsEqual(current, vpUIConfigOriginalHosted) || !vpUIObjectsEqual(currentDisplay, vpUIConfigOriginalServerDisplay)) {
            if ((!vpUIObjectsEqual(current, vpUIConfigPublished) && !vpUIObjectsEqual(current, vpUIConfigOriginalHosted)) ||
                (!vpUIObjectsEqual(currentDisplay, vpUIConfigPublished) && !vpUIObjectsEqual(currentDisplay, vpUIConfigOriginalServerDisplay))) {
                vpFoldDisplayLog(@"UI configuration: newer hosted value preserved; checkpoint retained"); return;
            }
            vpSetUISceneConfigurations(vpUIConfigOriginalHosted, vpUIConfigOriginalServerDisplay, current, currentDisplay, generation);
        } else {
            id scene = vpUIConfigWindowScene;
            id liveIdentityBeforeRestore = vpReadObject(scene, "_fbsDisplayIdentity");
            BOOL uiOwnedBeforeRestore = vpUIConfigurationOwnedByLease(vpReadObject(scene, "_sbDisplayConfiguration")) ||
                [vpReadObject(liveIdentityBeforeRestore, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")];
            if (scene && vpReadObject(scene, "_FBSScene") == vpUIConfigClientScene && uiOwnedBeforeRestore)
                vpNotifyUIConfiguration(scene, vpUIConfigOriginalUI);
            id liveIdentity = vpReadObject(scene, "_fbsDisplayIdentity");
            BOOL uiStillOwned = scene && (vpUIConfigurationOwnedByLease(vpReadObject(scene, "_sbDisplayConfiguration")) ||
                [vpReadObject(liveIdentity, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")]);
            if (!uiStillOwned && vpRestoreUIStatusComponent() && vpRestoreUIScreenTraits()) {
                vpUIConfigPublished = nil; vpUIConfigOriginalHosted = nil; vpUIConfigOriginalServerDisplay = nil; vpUIConfigOriginalUI = nil;
                vpUIConfigWindowScene = nil; vpUIConfigServerScene = nil; vpUIConfigClientScene = nil;
                vpFoldDisplayLog(@"UI configuration: original hosted/UI configuration verified"); return;
            }
        }
        if (attempt < 5) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 5), dispatch_get_main_queue(), ^{
            vpFinishUIConfigurationRestore(generation, attempt + 1);
        });
        else vpFoldDisplayLog(@"UI configuration: restore pending; checkpoint retained");
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration restore exception: %@", exception.reason]);
    }
}

static void vpRestoreUIConfiguration(void) {
    vpRestoreStatusProfileLookup();
    @try { vpDetachUIStatusComponent(); } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration component detach exception: %@", exception.reason]);
    }
    unsigned int generation = atomic_fetch_add_explicit(&vpUIConfigGeneration, 1, memory_order_acq_rel) + 1;
    vpFinishUIConfigurationRestore(generation, 0);
}

static void vpActivateUIConfiguration(void) {
    @try {
        id scene = vpUIConfigWindowScene;
        id current = vpReadObject(vpReadObject(vpUIConfigServerScene, "uiSettings"), "sb_hostedDisplayConfiguration");
        if (!scene || vpReadObject(scene, "_FBSScene") != vpUIConfigClientScene ||
            !vpUIConfigPublished || !vpUIObjectsEqual(current, vpUIConfigPublished)) {
            vpFoldDisplayLog(@"UI configuration: activation refused without current hosted lease"); return;
        }
        BOOL submitted = vpNotifyUIConfiguration(scene, vpUIConfigPublished);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: native client activation submitted=%d", submitted]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration activation exception: %@", exception.reason]);
    }
}

static void vpPulseUIConfiguration(BOOL nonEmbedded) {
    @try {
        if (vpUIConfigPublished) { vpFoldDisplayLog(@"UI configuration: prior lease must restore first"); return; }
        id scene = vpMainInnerWindowScene();
        id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id monitor = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        if (!scene || ![vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier") isEqual:@"SB-main"] ||
            !vpIsDuoInnerBounds(root) ||
            [vpReadObject(monitor, "alwaysConnectedIdentities") count] != 1) return;
        id candidate = nonEmbedded ? vpCreateNonEmbeddedUIConfiguration(root) : vpCreateUIConfiguration(root);
        id render = vpReadObject(root, "CADisplay");
        id identity = vpReadObject(candidate, "identity");
        if (!candidate || !render || vpReadObject(candidate, "CADisplay") != render ||
            ![vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")] ||
            [[identity valueForKey:@"isUIKitMainLike"] boolValue] == nonEmbedded || [[identity valueForKey:@"isExternal"] boolValue]) return;
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id server = nil;
        for (id candidateServer in vpRootServerScenes(app))
            if ([vpReadObject(candidateServer, "identifier") isEqual:@"SB-main"]) { server = candidateServer; break; }
        Method update = class_getInstanceMethod(object_getClass(server), sel_registerName("updateUISettingsWithBlock:"));
        id client = vpReadObject(scene, "_FBSScene");
        if (!client || !update || strcmp(method_getTypeEncoding(update), "v24@0:8@?16") != 0) {
            vpFoldDisplayLog(@"UI configuration: writable SB-main server unavailable"); return;
        }
        id settingsCopy = [vpReadObject(server, "uiSettings") mutableCopy];
        for (NSString *name in @[@"setDisplayConfiguration:", @"_setDisplayConfiguration:", @"setDisplayIdentity:"]) {
            SEL selector = NSSelectorFromString(name);
            BOOL available = [settingsCopy respondsToSelector:selector];
            Method method = available ? class_getInstanceMethod(object_getClass(settingsCopy), selector) : NULL;
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: mutable %@ %s ABI=%s",
                NSStringFromClass(object_getClass(settingsCopy)), name.UTF8String, method ? method_getTypeEncoding(method) : "unavailable"]);
        }
        vpUIConfigWindowScene = scene;
        vpUIConfigServerScene = server;
        vpUIConfigClientScene = client;
        vpUIConfigOriginalHosted = vpReadObject(vpReadObject(vpUIConfigServerScene, "uiSettings"), "sb_hostedDisplayConfiguration");
        vpUIConfigOriginalServerDisplay = vpReadObject(vpReadObject(vpUIConfigServerScene, "uiSettings"), "displayConfiguration");
        vpUIConfigOriginalUI = vpReadObject(scene, "_sbDisplayConfiguration") ?: root;
        vpUIConfigPublished = candidate;
        unsigned int generation = atomic_fetch_add_explicit(&vpUIConfigGeneration, 1, memory_order_acq_rel) + 1;
        vpSetUISceneConfigurations(candidate, candidate, vpUIConfigOriginalHosted, vpUIConfigOriginalServerDisplay, generation);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: ten-second hosted lease generation=%u", generation]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == atomic_load_explicit(&vpUIConfigGeneration, memory_order_acquire)) vpRestoreUIConfiguration();
        });
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration pulse exception: %@", exception.reason]);
    }
}

static void vpPreviewUISceneConfiguration(void) {
    @try {
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id rootIdentity = vpReadObject(configuration, "identity");
        if (![[rootIdentity valueForKey:@"isMainRootDisplay"] boolValue]) return;
        NSArray *physicalBefore = vpReadObject(objc_getClass("CADisplay"), "displays");
        NSUInteger physicalCountBefore = physicalBefore.count;
        id monitor = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        id identitiesBefore = vpReadObject(monitor, "alwaysConnectedIdentities");
        NSUInteger connectedCountBefore = [identitiesBefore count];
        Class builderClass = objc_getClass("FBSDisplayConfigurationBuilder");
        Method setType = class_getInstanceMethod(builderClass, sel_registerName("setDisplayType:"));
        Method mainLike = class_getInstanceMethod(builderClass, sel_registerName("setUIKitMainLike"));
        if (!setType || strcmp(method_getTypeEncoding(setType), "v24@0:8q16") != 0 ||
            !mainLike || strcmp(method_getTypeEncoding(mainLike), "v16@0:8") != 0) return;
        id<VPhoneDisplayProjectionBuilding> builder = [(id<VPhoneDisplayProjectionBuilding>)[builderClass alloc] initWithConfiguration:configuration];
        [builder setUniqueIdentifier:@"vphone-duo-ui-preview"];
        // Unknown (7) is native-valid (type 2 is reserved/invalid). Retain
        // the integrated, nonexternal Main backing and mark the UI view main-like.
        [builder setDisplayType:7];
        [builder setUIKitMainLike];
        NSError *error = nil;
        id preview = [builder buildConfigurationWithError:&error];
        if (!preview) { vpFoldDisplayLog([NSString stringWithFormat:@"UI context preview build failed: %@", error]); return; }
        id identity = vpReadObject(preview, "identity");
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"isMainDisplay", @"isMainRootDisplay", @"isRootIdentity", @"isUIKitMainLike",
                                 @"isAlwaysConnected", @"isExternal", @"connectionType", @"type", @"displayID", @"uniqueIdentifier"])
            result[key] = [identity valueForKey:key] ?: NSNull.null;
        result[@"rootIdentity"] = vpReadObject(vpReadObject(identity, "rootIdentity"), "uniqueIdentifier") ?: NSNull.null;
        result[@"rootMatchesOriginal"] = @([vpReadObject(identity, "rootIdentity") isEqual:rootIdentity]);
        result[@"bounds"] = vpSnapshotRect(preview, "bounds");
        id originalRender = vpReadObject(configuration, "CADisplay");
        id previewRender = vpReadObject(preview, "CADisplay");
        result[@"renderAccessorAvailable"] = @(originalRender != nil && previewRender != nil);
        result[@"sameRenderDisplay"] = originalRender && previewRender ? @(originalRender == previewRender) : NSNull.null;
        result[@"caDisplayObjectCountBefore"] = @(physicalCountBefore);
        result[@"caDisplayObjectCountAfter"] = @([vpReadObject(objc_getClass("CADisplay"), "displays") count]);
        result[@"connectedCountBefore"] = @(connectedCountBefore);
        result[@"connectedCountAfter"] = @([vpReadObject(monitor, "alwaysConnectedIdentities") count]);
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        for (id serverScene in vpRootServerScenes(app)) {
            if (![vpReadObject(serverScene, "identifier") isEqual:@"SB-main"]) continue;
            id original = vpReadObject(serverScene, "uiSettings");
            id copy = [original mutableCopy];
            Method setter = class_getInstanceMethod(object_getClass(copy), sel_registerName("sb_setHostedDisplayConfiguration:"));
            if (!copy || copy == original || !setter || strcmp(method_getTypeEncoding(setter), "v24@0:8@16") != 0) continue;
            ((void (*)(id, SEL, id))objc_msgSend)(copy, sel_registerName("sb_setHostedDisplayConfiguration:"), preview);
            result[@"originalHostedIdentity"] = vpReadObject(vpReadObject(vpReadObject(original, "sb_hostedDisplayConfiguration"), "identity"), "uniqueIdentifier") ?: NSNull.null;
            result[@"copiedHostedIdentity"] = vpReadObject(vpReadObject(vpReadObject(copy, "sb_hostedDisplayConfiguration"), "identity"), "uniqueIdentifier") ?: NSNull.null;
            result[@"originalFrame"] = vpSnapshotRect(original, "frame");
            result[@"copiedFrame"] = vpSnapshotRect(copy, "frame");
        }
        result[@"published"] = @NO;
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        if (data) vpFoldDisplayLog([@"UI context preview " stringByAppendingString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI context preview exception: %@", exception.reason]);
    }
}

#include "StatusProfile.inc"
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
static NSInteger vpLogicalSurfaceType(id self, SEL selector) {
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

#include "WallpaperTraitsExperiment.inc"

static void vpSetPersistentViewport(BOOL cover) {
    if (!vpAutomaticMainStatus || !vpOriginalSceneGeometryCallback || !vpOriginalSBWindowResizePolicy) return;
    if (vpPersistentViewport && atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire) == cover) return;
    vpPersistentViewport = YES;
    atomic_store_explicit(&vpNativeGeometryRefreshEnabled, false, memory_order_release);
    atomic_store_explicit(&vpSceneResizePropagationEnabled, true, memory_order_release);
    atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
    vpSetCoverViewport(cover);
}

__attribute__((constructor)) static void vpInstallFoldDisplay(void) {
    if (strcmp(getprogname(), "backboardd") == 0) {
        Method extended = class_getInstanceMethod(objc_getClass("CAWindowServerDisplay"), sel_registerName("extendedProperties"));
        if (extended && strcmp(method_getTypeEncoding(extended), "@16@0:8") == 0) {
            vpOriginalExtendedProperties = method_setImplementation(extended, (IMP)vpSurfaceExtendedProperties);
            vpFoldDisplayLog(@"surface probe: extendedProperties observer installed, inactive");
        }
        static int surfaceToken, surfacePairToken, surfaceCoverToken;
        notify_register_dispatch("com.vphone.display.surface.inner", &surfaceToken, dispatch_get_main_queue(),
            ^(int token) { vpBeginSurfaceProbe(2, NO); });
        notify_register_dispatch("com.vphone.display.surface.pair", &surfacePairToken, dispatch_get_main_queue(),
            ^(int token) { vpBeginSurfaceProbe(2, YES); });
        notify_register_dispatch("com.vphone.display.surface.cover", &surfaceCoverToken, dispatch_get_main_queue(),
            ^(int token) { vpBeginSurfaceProbe(1, NO); });
        static int createToken, removeToken, serverInspectToken, enableToken, tagToken;
        notify_register_dispatch("com.vphone.display.virtual.create", &createToken, dispatch_get_main_queue(),
            ^(int token) { vpVirtualDisplayExperiment(YES); });
        notify_register_dispatch("com.vphone.display.virtual.remove", &removeToken, dispatch_get_main_queue(),
            ^(int token) { vpVirtualDisplayExperiment(NO); });
        notify_register_dispatch("com.vphone.display.server.inspect", &serverInspectToken, dispatch_get_main_queue(),
            ^(int token) { vpInspectServerClass(); vpInspectRenderDisplays(); });
        static int orientationInspectToken, orientationEnableToken, orientationRestoreToken;
        notify_register_dispatch("com.vphone.display.server.orientation.inspect", &orientationInspectToken, dispatch_get_main_queue(),
            ^(int token) { vpSnapshotBackboardOrientation(); });
        notify_register_dispatch("com.vphone.display.server.orientation.enable", &orientationEnableToken, dispatch_get_main_queue(),
            ^(int token) { vpProbeBackboardOrientationEvents(); });
        notify_register_dispatch("com.vphone.display.server.orientation.restore", &orientationRestoreToken, dispatch_get_main_queue(),
            ^(int token) { vpRestoreBackboardOrientationEvents(); });
        notify_register_dispatch("com.vphone.display.virtual.enable", &enableToken, dispatch_get_main_queue(),
            ^(int token) { vpEnableVirtualDisplayProbe(); });
        notify_register_dispatch("com.vphone.display.virtual.tag-unknown", &tagToken, dispatch_get_main_queue(),
            ^(int token) { vpTagVirtualDisplayProbe(); });
        return;
    }
    if (strcmp(getprogname(), "SpringBoard") != 0)
        return;
    char product[128] = {0};
    size_t productLength = sizeof(product);
    vpAutomaticMainStatus = sysctlbyname("hw.machine", product, &productLength, NULL, 0) == 0 &&
        strcmp(product, "iPhone19,4") == 0;
    // The round-16 landscape wallpaper gate is now part of the Duo startup
    // path.  The one-shot marker remains accepted for older guests, but a
    // fresh boot must not silently fall back to the portrait wallpaper
    // admission path (which recreates the black bands).
    if (vpAutomaticMainStatus || vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-wallpaper-traits.once")) {
        vpInstallWallpaperTraitsExperiment();
        vpInstallLandscapeWallpaperGateDetour();
    }
    BOOL requestedFamily = vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-viewport-family.once");
    if (vpAutomaticMainStatus || requestedFamily)
        vpInstallViewportFamilyLookup();
    // Duo has one physical Main, but SpringBoard's native scene policy still
    // needs the inner role to participate in orientation and status-bar
    // arbitration.  The role adapter preserves the physical identity and is
    // now part of the normal Duo path; the old once marker remains accepted
    // for older guests but is no longer required.
    if (vpAutomaticMainStatus || vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-logical-role.once")) {
        Method surface = class_getInstanceMethod(objc_getClass("SBWindowScene"), sel_registerName("surfaceType"));
        if (surface && strcmp(method_getTypeEncoding(surface), "q16@0:8") == 0) {
            vpLogicalRoleExperiment = YES;
            Class clock = objc_getClass("SBFMachNextMinuteDateProvider");
            Method tick = class_getInstanceMethod(clock, sel_registerName("_onMachTimer"));
            Method observe = class_getInstanceMethod(clock, sel_registerName("observeMinuteUpdatesWithHandler:"));
            if (tick && observe && strcmp(method_getTypeEncoding(tick), "v16@0:8") == 0 &&
                strcmp(method_getTypeEncoding(observe), "@24@0:8@?16") == 0) {
                vpOriginalMachClockTick = method_setImplementation(tick, (IMP)vpMachClockTick);
                vpOriginalMachClockObserve = method_setImplementation(observe, (IMP)vpMachClockObserve);
                vpFoldDisplayLog(@"native clock reference: detached-view scheduling adapter installed");
            }
            Method timeUpdate = class_getInstanceMethod(objc_getClass("SBStatusBarStateAggregator"), sel_registerName("_updateTimeItemsWithDate:"));
            if (timeUpdate && strcmp(method_getTypeEncoding(timeUpdate), "v24@0:8@16") == 0)
                vpOriginalTimeItemUpdate = method_setImplementation(timeUpdate, (IMP)vpObserveNativeTimeUpdate);
            vpOriginalLogicalSurfaceType = method_setImplementation(surface, (IMP)vpLogicalSurfaceType);
            vpFoldDisplayLog(@"logical surface: native-size scoped SB-main role adapter installed");
        }
    }
    vpObservedDisplayMonitors = [NSHashTable weakObjectsHashTable];
    vpResizedSceneGenerations = [NSMutableDictionary dictionary];
    Method resizePolicy = class_getInstanceMethod(objc_getClass("SBWindow"), sel_registerName("_shouldResizeWithScene"));
    if (resizePolicy && strcmp(method_getTypeEncoding(resizePolicy), "B16@0:8") == 0)
        vpOriginalSBWindowResizePolicy = method_setImplementation(resizePolicy, (IMP)vpAllowScopedMainWindowResize);
    Method sceneGeometry = class_getInstanceMethod(objc_getClass("SBAbstractWindowSceneDelegate"),
        sel_registerName("windowScene:didUpdateCoordinateSpace:interfaceOrientation:traitCollection:"));
    if (sceneGeometry && strcmp(method_getTypeEncoding(sceneGeometry), "v48@0:8@16@24q32@40") == 0)
        vpOriginalSceneGeometryCallback = method_setImplementation(sceneGeometry, (IMP)vpObserveSceneGeometry);
    // Retired: promoting a software CADisplay to builtin asserted in cloning.
    // Consume stale markers without ever installing that type/scale override.
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-internal-panel.once"))
        vpFoldDisplayLog(@"panel adapter: retired builtin promotion marker discarded");
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-shared-family.once"))
        vpInstallSharedInnerFamily();
    BOOL requestedMainStatus = vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-main-status.once");
    if (vpAutomaticMainStatus || requestedMainStatus) vpInstallMainStatusLookup();
    if (vpAutomaticMainStatus) {
        static int mainStatusStartupToken;
        notify_register_dispatch("com.apple.springboard.finishedstartup", &mainStatusStartupToken, dispatch_get_main_queue(),
            ^(int token) { vpPulseMainStatusProfile(); });
        // The library may load before scene construction or after the startup
        // notification. Bounded retries establish the existing Main renderer.
        for (unsigned int retry = 1; retry <= 12; ++retry)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, retry * NSEC_PER_SEC), dispatch_get_main_queue(),
                ^{ vpPulseMainStatusProfile(); });
        // The same ladder establishes the default quick-action glyph scale
        // on every lock-screen construction timing without any opt-in file.
        for (unsigned int retry = 1; retry <= 12; ++retry)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, retry * NSEC_PER_SEC), dispatch_get_main_queue(),
                ^{ vpApplyQuickActionGlyphScale(); });
    }
    if (vpAutomaticMainStatus || vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-scene-status.once"))
        vpInstallSceneStatusPolicy();
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-root-scene-policy.once"))
        vpFoldDisplayLog(@"root scene policy: retired global Main conversion marker discarded");
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-inner-family.once")) {
        Method family = class_getInstanceMethod(objc_getClass("SBWindowScene"), sel_registerName("sbhScreenType"));
        if (family && strcmp(method_getTypeEncoding(family), "Q16@0:8") == 0) {
            vpOriginalSceneScreenType = method_setImplementation(family, (IMP)vpNativeInnerSceneFamily);
            vpFoldDisplayLog(@"shared scene family: one-instance classifier adapter installed");
        }
    }
    BOOL requestedSingleInner = vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-single-inner.once");
    if (vpLogicalRoleExperiment || requestedSingleInner) {
        Method resolve = class_getInstanceMethod(objc_getClass("SBFDisplayContentModeResolver"),
            sel_registerName("_startResolvingContentModeOfDisplay:"));
        if (resolve && strcmp(method_getTypeEncoding(resolve), "v24@0:8@16") == 0) {
            vpOriginalStartResolvingDisplay = method_setImplementation(resolve, (IMP)vpResolveSingleInnerDisplay);
            vpFoldDisplayLog(@"single inner readiness: one-instance adapter installed");
        } else vpFoldDisplayLog(@"single inner readiness: native callback ABI unavailable");
    }
    // SBFBSDisplayTransformer requires one result per source. The startup
    // two-result experiment asserted before monitor initialization; retain
    // native builder preview only, never arm that publication again.
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-logical-panel.once"))
        vpFoldDisplayLog(@"logical projection: unsupported startup marker discarded");
static int persistentCoverToken, persistentInnerToken;
    notify_register_dispatch("com.vphone.display.viewport.apply.cover", &persistentCoverToken, dispatch_get_main_queue(),
        ^(int token) { vpSetPersistentViewport(YES); });
    notify_register_dispatch("com.vphone.display.viewport.apply.inner", &persistentInnerToken, dispatch_get_main_queue(),
        ^(int token) { vpSetPersistentViewport(NO); });
    static int workspaceRefreshToken;
    notify_register_dispatch("com.vphone.display.workspace.refresh", &workspaceRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpProcessViewportWorkspaceRequest(YES); });
    static int workspacePreviewToken;
    notify_register_dispatch("com.vphone.display.workspace.preview", &workspacePreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpProcessViewportWorkspaceRequest(NO); });
    static int presentationWallpaperToken;
    notify_register_dispatch("com.vphone.display.presentation.wallpaper.pulse", &presentationWallpaperToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseNativeWallpaperOrientation(); });
    static int presentationClockToken;
    notify_register_dispatch("com.vphone.display.presentation.clock.refresh", &presentationClockToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeClockSource(); });
    static int presentationRegistrationToken;
    notify_register_dispatch("com.vphone.display.presentation.registration.refresh", &presentationRegistrationToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeStatusRegistration(); });
    static int presentationInspectToken;
    notify_register_dispatch("com.vphone.display.presentation.inspect", &presentationInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectNativePresentation(); });
    static int quickActionInspectToken;
    notify_register_dispatch("com.vphone.display.quickaction.inspect", &quickActionInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectQuickActions(); });
    // Installed before SpringBoard builds its cover sheet, so the first
    // SBSDeviceDeterminedConfiguration construction is captured.
    vpInstallConfigInitSwizzle();
    vpInstallLayoutClassSwizzle();
    static int windowsInspectToken;
    notify_register_dispatch("com.vphone.display.windows.inspect", &windowsInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectAllWindows(); });
    static int wallpaperSceneHostSyncToken;
    notify_register_dispatch("com.vphone.display.wallpaper.scenehost.sync", &wallpaperSceneHostSyncToken, dispatch_get_main_queue(),
        ^(int token) { vpSyncWallpaperSceneHosts(); });
    // Keep a fresh SB-main orientation map from the first minute of boot:
    // vphoned's rotation and posture paths refuse to settle without it.
    for (unsigned int retry = 2; retry <= 12; retry += 2)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retry * NSEC_PER_SEC)), dispatch_get_main_queue(),
            ^{ vpExportNativeOrientationMapping(); });
    static int screenUndimToken;
    notify_register_dispatch("com.vphone.display.screen.undim", &screenUndimToken, dispatch_get_main_queue(),
        ^(int token) { vpUndimScreenOnly(); });
    static int displayStateToken;
    notify_register_dispatch("com.vphone.display.inspect", &displayStateToken, dispatch_get_main_queue(),
        ^(int token) { vpSnapshotMainScene(); });
    static int displayDetailsToken, homeFamilyToken;
    notify_register_dispatch("com.vphone.display.inspect.detail", &displayDetailsToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectDisplayState(); });
    notify_register_dispatch("com.vphone.display.families.inspect", &homeFamilyToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectHomeScreenType(); });
    static int uiContextPreviewToken;
    notify_register_dispatch("com.vphone.display.ui_context.preview", &uiContextPreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpPreviewUISceneConfiguration(); });
    static int duoSystemUIInspectToken;
    notify_register_dispatch("com.vphone.display.duo_system_ui.inspect", &duoSystemUIInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectDuoSystemUI(); });
    static int statusProviderInspectToken;
    notify_register_dispatch("com.vphone.display.status_provider.inspect", &statusProviderInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectStatusProvider(); });
    static int statusProfilePulseToken, statusProfileRestoreToken;
    notify_register_dispatch("com.vphone.display.status_profile.pulse", &statusProfilePulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseStatusProfileLookup(); });
    notify_register_dispatch("com.vphone.display.status_profile.restore", &statusProfileRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreStatusProfileLookup(); });
    static int inputTracePulseToken, inputTraceRestoreToken;
    notify_register_dispatch("com.vphone.display.input_trace.pulse", &inputTracePulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseInputTrace(); });
    notify_register_dispatch("com.vphone.display.input_trace.restore", &inputTraceRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreInputTrace(); });
    static int mainStatusPulseToken, mainStatusRestoreToken;
    notify_register_dispatch("com.vphone.display.main_status.pulse", &mainStatusPulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseMainStatusProfile(); });
    notify_register_dispatch("com.vphone.display.main_status.restore", &mainStatusRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreMainStatusProfile(); });
    static int orientationMappingToken;
    notify_register_dispatch("com.vphone.display.orientation.mapping.request", &orientationMappingToken, dispatch_get_main_queue(),
        ^(int token) { vpExportNativeOrientationMapping(); });
    static int uiContextPulseToken, uiContextActivateToken, uiContextRestoreToken;
    notify_register_dispatch("com.vphone.display.ui_context.pulse", &uiContextPulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseUIConfiguration(NO); });
    static int uiNonEmbeddedPreviewToken, uiNonEmbeddedPulseToken;
    notify_register_dispatch("com.vphone.display.ui_context.unembedded.preview", &uiNonEmbeddedPreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpPreviewNonEmbeddedUIConfiguration(); });
    notify_register_dispatch("com.vphone.display.ui_context.unembedded.pulse", &uiNonEmbeddedPulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseUIConfiguration(YES); });
    static int uiScreenTraitsToken;
    notify_register_dispatch("com.vphone.display.ui_context.traits.sync", &uiScreenTraitsToken, dispatch_get_main_queue(),
        ^(int token) { vpSyncUIScreenTraits(); });
    notify_register_dispatch("com.vphone.display.ui_context.activate", &uiContextActivateToken, dispatch_get_main_queue(),
        ^(int token) { vpActivateUIConfiguration(); });
    notify_register_dispatch("com.vphone.display.ui_context.restore", &uiContextRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreUIConfiguration(); });
    static int uiContextComponentToken;
    notify_register_dispatch("com.vphone.display.ui_context.components.refresh", &uiContextComponentToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshUIStatusComponent(); });
    static int invalidationPulseToken;
    notify_register_dispatch("com.vphone.display.invalidation.pulse", &invalidationPulseToken, dispatch_get_main_queue(),
        ^(int token) {
            if (!atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire)) vpRefreshMainTransform();
        });
    static int coverViewportToken, innerViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.cover", &coverViewportToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCoverViewport(YES); });
    notify_register_dispatch("com.vphone.display.viewport.inner", &innerViewportToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCoverViewport(NO); });
    static int orientationSyncToken, orientationRestoreToken;
    notify_register_dispatch("com.vphone.display.orientation.sync", &orientationSyncToken, dispatch_get_main_queue(),
        ^(int token) { vpSyncRootSceneOrientation(); });
    notify_register_dispatch("com.vphone.display.orientation.restore", &orientationRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreRootSceneOrientations(); });
    static int geometryRequestToken, geometryRestoreToken, poseRefreshToken, inputsRefreshToken;
    notify_register_dispatch("com.vphone.display.orientation.geometry", &geometryRequestToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeSceneGeometryRequest(); });
    notify_register_dispatch("com.vphone.display.orientation.geometry.restore", &geometryRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreSceneGeometryRequest(); });
    notify_register_dispatch("com.vphone.display.orientation.pose.refresh", &poseRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeOrientationInputs(YES); });
    notify_register_dispatch("com.vphone.display.orientation.inputs.refresh", &inputsRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeOrientationInputs(NO); });
    static int arbitrationRefreshToken;
    notify_register_dispatch("com.vphone.display.orientation.arbitration.refresh", &arbitrationRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpForceNativeOrientationResolution(); });
    static int actuationRefreshToken;
    notify_register_dispatch("com.vphone.display.orientation.actuation.refresh", &actuationRefreshToken, dispatch_get_main_queue(),
        ^(int token) {
            vpRefreshNativeOrientationActuation();
            // Rotation pulses rebuild lock-screen presentation; fresh glyph
            // instances render at the native factor until re-scaled.
            if (vpAutomaticMainStatus) vpApplyQuickActionGlyphScale();
        });
    static int embeddedOrientationToken, embeddedOrientationRestoreToken;
    notify_register_dispatch("com.vphone.display.orientation.embedded.sync", &embeddedOrientationToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeEmbeddedOrientation(); });
    notify_register_dispatch("com.vphone.display.orientation.embedded.restore", &embeddedOrientationRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreEmbeddedOrientation(); });
    static int canonicalOrientationToken, canonicalOrientationRestoreToken;
    notify_register_dispatch("com.vphone.display.orientation.canonical", &canonicalOrientationToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCanonicalOrientationProbe(YES); });
    notify_register_dispatch("com.vphone.display.orientation.canonical.restore", &canonicalOrientationRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCanonicalOrientationProbe(NO); });
    static int sceneViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.scene.cover", &sceneViewportToken, dispatch_get_main_queue(),
        ^(int token) {
            atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
            vpSetCoverViewport(YES);
        });
    static int pipelineViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.pipeline.cover", &pipelineViewportToken, dispatch_get_main_queue(),
        ^(int token) {
            if (!vpOriginalSceneGeometryCallback) return;
            atomic_store_explicit(&vpNativeGeometryRefreshEnabled, true, memory_order_release);
            atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
            vpSetCoverViewport(YES);
        });
    static int resizeViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.resize.cover", &resizeViewportToken, dispatch_get_main_queue(),
        ^(int token) {
            if (!vpOriginalSceneGeometryCallback || !vpOriginalSBWindowResizePolicy) return;
            atomic_store_explicit(&vpNativeGeometryRefreshEnabled, false, memory_order_release);
            atomic_store_explicit(&vpSceneResizePropagationEnabled, true, memory_order_release);
            atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
            vpSetCoverViewport(YES);
        });
    static int allowUnknownToken, restoreUnknownToken;
    notify_register_dispatch("com.vphone.display.unknown.allow", &allowUnknownToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeUnknownDisplayPolicy(NO); });
    notify_register_dispatch("com.vphone.display.unknown.restore", &restoreUnknownToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeUnknownDisplayPolicy(YES); });
    static int projectionPreviewToken, projectionEnableToken, projectionDisableToken;
    notify_register_dispatch("com.vphone.display.logical.preview", &projectionPreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpLogicalProjectionControl(0); });
    notify_register_dispatch("com.vphone.display.logical.enable", &projectionEnableToken, dispatch_get_main_queue(),
        ^(int token) { vpFoldDisplayLog(@"logical projection publication rejected: native transformer requires one result"); });
    notify_register_dispatch("com.vphone.display.logical.disable", &projectionDisableToken, dispatch_get_main_queue(),
        ^(int token) { vpLogicalProjectionControl(2); });
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
