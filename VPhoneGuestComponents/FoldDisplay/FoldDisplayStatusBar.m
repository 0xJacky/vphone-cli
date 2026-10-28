// Status bar: native status registration, the clock source, the scene status
// policy, and the visual provider profile lookup.

#import "FoldDisplayPrivate.h"

BOOL vpLogicalRoleExperiment;
static IMP vpOriginalSceneIsMain, vpOriginalStatusManagerInit, vpOriginalStatusManagerEmbedded;
static _Thread_local void *vpStatusManagerInitializingScene;
static _Thread_local BOOL vpStatusManagerMainQueryConsumed;
IMP vpOriginalTimeItemUpdate;
IMP vpOriginalMachClockTick, vpOriginalMachClockObserve;
static atomic_uint vpClockReferenceFallbackCount;
static atomic_uint vpTimeItemTraceCount;
static _Atomic(IMP) vpOriginalStatusProfileFactories[4];
atomic_bool vpStatusProfileLookupEnabled;
static unsigned int vpStatusProfileGeneration;
static unsigned int vpStatusProfileCallCount;
_Thread_local void *vpStatusProfileConstructionScene;
static _Thread_local unsigned int vpStatusProfileFactoryDepth;
static __weak id vpStatusProfileScene;
static void *vpOriginalMainStatusClassLookup;
static atomic_bool vpMainStatusProfileEnabled;
static unsigned int vpMainStatusProfileGeneration, vpMainStatusProfileLogCount;
static __weak id vpMainStatusProfileScene;
static Class vpMainStatusOriginalProviderClass;

// MARK: - status registration and clock

void vpRefreshNativeStatusRegistration(void) {
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
void vpMachClockTick(id self, SEL selector) {
    vpWithUsableClockReference(self, ^id {
        ((void (*)(id, SEL))vpOriginalMachClockTick)(self, selector);
        // A once-a-minute bounded walk re-scales glyph instances that a
        // lock-screen rebuild created at the native factor.
        if (vpAutomaticMainStatus) vpApplyQuickActionGlyphScale();
        return nil;
    });
}
id vpMachClockObserve(id self, SEL selector, id handler) {
    return vpWithUsableClockReference(self, ^id {
        return ((id (*)(id, SEL, id))vpOriginalMachClockObserve)(self, selector, handler);
    });
}

void vpObserveNativeTimeUpdate(id self, SEL selector, id date) {
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

void vpRefreshNativeClockSource(void) {
    if (!vpLogicalRoleExperiment) return;
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    id aggregator = vpReadObject(app, "statusBarStateAggregator");
    SEL refresh = sel_registerName("_restartTimeItemTimer");
    Method method = class_getInstanceMethod(object_getClass(aggregator), refresh);
    if (!method || strcmp(method_getTypeEncoding(method), "v16@0:8") != 0) return;
    ((void (*)(id, SEL))objc_msgSend)(aggregator, refresh);
    vpFoldDisplayLog(@"native clock source: native time-item subscription restarted");
}

// MARK: - scene status policy

BOOL vpIsSingleMainStatusScene(id scene, BOOL constructing) {
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

void vpInstallSceneStatusPolicy(void) {
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

// MARK: - Main status profile

// Used only as an argument to the native, read-only provider factory. Never
// register this proxy with UIKit or publish its reference bounds to a scene.
@interface VPhoneStatusScreenPreview : NSProxy
@property(nonatomic, strong) id source;
@property(nonatomic, strong) id previewExclusion;
@property(nonatomic) CGRect referenceBounds;
@property(nonatomic) BOOL skipEmbeddedCache;
@end
@implementation VPhoneStatusScreenPreview
- (CGRect)_nativeDisplayBounds { return self.referenceBounds; }
- (id)_exclusionArea { return self.previewExclusion ?: vpReadObject(self.source, "_exclusionArea"); }
- (BOOL)_isEmbeddedScreen { return self.skipEmbeddedCache ? NO : vpReadBoolValue(self.source, "_isEmbeddedScreen").boolValue; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.source methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.source]; }
- (BOOL)respondsToSelector:(SEL)selector {
    return selector == @selector(_nativeDisplayBounds) || selector == @selector(_exclusionArea) ||
        selector == @selector(_isEmbeddedScreen) || [self.source respondsToSelector:selector];
}
@end

// Asks the native, read-only provider factory which provider the given
// Duo panel takes, by showing it a preview of the screen with that panel's
// native pixels and an exclusion area of the profile's notch. Every screen
// on this guest carries Main's MobileGestalt panel metrics, so the factory
// would otherwise pick a generic island provider. Nil unless the factory
// itself selects the profile.
static Class vpDuoPanelStatusClass(id screen, id info, BOOL inner) {
    Class (*original)(id, id) = vpOriginalMainStatusClassLookup;
    Class profile = objc_getClass(inner ? "STUIStatusBarVisualProvider_AxisAlignableSplit2007" :
        "STUIStatusBarVisualProvider_AxisAlignableSplitV68Cover");
    SEL notchSelector = sel_registerName("notchSize");
    NSMethodSignature *notchSignature = [profile methodSignatureForSelector:notchSelector];
    if (notchSignature.methodReturnLength != sizeof(CGSize)) return Nil;
    CGSize notch = ((CGSize (*)(id, SEL))objc_msgSend)(profile, notchSelector);
    Class shapeClass = objc_getClass("UISDisplaySingleRectShape");
    SEL initializer = sel_registerName("initWithRect:");
    NSMethodSignature *shapeSignature = [shapeClass instanceMethodSignatureForSelector:initializer];
    if (shapeSignature.numberOfArguments != 3 ||
        strcmp([shapeSignature getArgumentTypeAtIndex:2], "{CGRect={CGPoint=dd}{CGSize=dd}}") != 0) return Nil;
    VPhoneStatusScreenPreview *preview = [VPhoneStatusScreenPreview alloc];
    preview.source = screen;
    preview.referenceBounds = inner ? CGRectMake(0, 0, 2007, 2853) : CGRectMake(0, 0, 1398, 2034);
    preview.skipEmbeddedCache = YES;
    preview.previewExclusion = ((id (*)(id, SEL, CGRect))objc_msgSend)([shapeClass alloc], initializer,
        CGRectMake(0, 0, notch.width, notch.height));
    Class selected = original(preview, info);
    return selected == profile ? selected : Nil;
}

static Class vpMainStatusClassLookup(id screen, id info) {
    Class (*original)(id, id) = vpOriginalMainStatusClassLookup;
    if (!vpMainStatusProfileEnabled || ![NSThread isMainThread]) return original(screen, info);
    id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
    id identity = vpReadObject(screen, "displayIdentity");
    NSArray *bounds = vpSnapshotRect(root, "bounds");
    BOOL inner = [bounds isEqual:@[@0, @0, @669, @951]];
    BOOL cover = [bounds isEqual:@[@0, @0, @466, @678]];
    if (![identity isEqual:vpReadObject(root, "identity")] ||
        screen != vpReadObject(vpMainStatusProfileScene, "screen") ||
        !(inner || cover)) return original(screen, info);
    Class selected = vpDuoPanelStatusClass(screen, info, inner);
    if (!selected) return original(screen, info);
    if (vpMainStatusProfileLogCount++ < 8)
        vpFoldDisplayLog([NSString stringWithFormat:@"Main status profile: native %@ lookup accepted; original data/screen/identity retained", inner ? @"inner" : @"cover"]);
    return selected;
}

// With the inner display published each screen is one panel: the inner
// display's screen is the inner panel and Main's is the cover.
static Class vpDualStatusClassLookup(id screen, id info) {
    Class (*original)(id, id) = vpOriginalMainStatusClassLookup;
    if (![NSThread isMainThread]) return original(screen, info);
    id identity = vpReadObject(vpReadObject(screen, "displayConfiguration"), "identity");
    if (!identity) return original(screen, info);
    BOOL inner = ![[identity description] isEqual:@"Main"];
    Class selected = vpDuoPanelStatusClass(screen, info, inner);
    if (vpMainStatusProfileLogCount++ < 8)
        vpFoldDisplayLog([NSString stringWithFormat:@"status bar: %@ screen takes %@", inner ? @"inner" : @"cover",
            selected ? NSStringFromClass(selected) : @"the native provider"]);
    return selected ?: original(screen, info);
}

void vpInstallDualStatusLookup(void) {
    void *target = dlsym(RTLD_DEFAULT, "STUIStatusBarGetVisualProviderClassForScreen");
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    if (!target || !install) { vpFoldDisplayLog(@"status bar: native lookup/detour API unavailable"); return; }
    MISFixDetourResult result = install("Duo per-panel status profile", target, (void *)vpDualStatusClassLookup,
        &vpOriginalMainStatusClassLookup);
    vpFoldDisplayLog([NSString stringWithFormat:@"status bar: per-panel lookup detour result=%d", result]);
}

void vpInstallMainStatusLookup(void) {
    void *target = dlsym(RTLD_DEFAULT, "STUIStatusBarGetVisualProviderClassForScreen");
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    if (!target || !install) { vpFoldDisplayLog(@"Main status profile: native lookup/detour API unavailable"); return; }
    MISFixDetourResult result = install("Duo Main native status profile", target, (void *)vpMainStatusClassLookup,
        &vpOriginalMainStatusClassLookup);
    vpFoldDisplayLog([NSString stringWithFormat:@"Main status profile: constructor detour result=%d", result]);
}

void vpRefreshMainStatusRenderer(void) {
    id scene = vpMainStatusProfileScene;
    if (!scene) return;
    id wrapper = vpReadObject(vpReadObject(scene, "statusBarManager"), "statusBar");
    id renderer = vpReadObject(wrapper, "statusBar");
    // resetVisualProvider resets region/item/alpha dictionaries only. Clear
    // the native class cache (never assign a replacement class), then use
    // the native full reconstruction that releases provider/foreground.
    Method clear = class_getInstanceMethod(object_getClass(renderer), sel_registerName("_setVisualProviderClass:"));
    if (clear && strcmp(method_getTypeEncoding(clear), "v24@0:8#16") == 0)
        ((void (*)(id, SEL, Class))objc_msgSend)(renderer, sel_registerName("_setVisualProviderClass:"), Nil);
    for (NSString *name in @[@"reinitializeStatusBar", @"setNeedsLayout", @"layoutIfNeeded"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(object_getClass(renderer), selector);
        if (method && strcmp(method_getTypeEncoding(method), "v16@0:8") == 0)
            ((void (*)(id, SEL))objc_msgSend)(renderer, selector);
    }
    Method data = class_getInstanceMethod(object_getClass(wrapper), sel_registerName("forceUpdateData:"));
    if (data && strcmp(method_getTypeEncoding(data), "v20@0:8B16") == 0)
        ((void (*)(id, SEL, BOOL))objc_msgSend)(wrapper, sel_registerName("forceUpdateData:"), YES);
    Method force = class_getInstanceMethod(object_getClass(wrapper), sel_registerName("forceUpdate:"));
    if (force && strcmp(method_getTypeEncoding(force), "v20@0:8B16") == 0)
        ((void (*)(id, SEL, BOOL))objc_msgSend)(wrapper, sel_registerName("forceUpdate:"), YES);
}

void vpRestoreMainStatusProfile(void) {
    if (vpAutomaticMainStatus) { vpRefreshMainStatusRenderer(); return; }
    if (!vpMainStatusProfileEnabled && !vpMainStatusProfileScene) return;
    vpMainStatusProfileEnabled = NO;
    vpMainStatusProfileGeneration++;
    if (!vpMainStatusProfileScene) { vpMainStatusOriginalProviderClass = Nil; return; }
    vpRefreshMainStatusRenderer();
    id wrapper = vpReadObject(vpReadObject(vpMainStatusProfileScene, "statusBarManager"), "statusBar");
    Class current = object_getClass(vpReadObject(vpReadObject(wrapper, "statusBar"), "visualProvider"));
    if (vpMainStatusOriginalProviderClass && current != vpMainStatusOriginalProviderClass) {
        vpFoldDisplayLog(@"Main status profile: provider restoration pending; checkpoint retained"); return;
    }
    vpMainStatusProfileScene = nil;
    vpMainStatusOriginalProviderClass = Nil;
    vpFoldDisplayLog(@"Main status profile: native lookup behavior restored");
}

void vpPulseMainStatusProfile(void) {
    if (!vpOriginalMainStatusClassLookup || vpUIConfigPublished) return;
    if (vpMainStatusProfileScene) {
        id wrapper = vpReadObject(vpReadObject(vpMainStatusProfileScene, "statusBarManager"), "statusBar");
        if (!vpReadObject(vpReadObject(wrapper, "statusBar"), "currentData")) vpRefreshMainStatusRenderer();
        return;
    }
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    id scene = vpReadObject(app, "activeDisplayWindowScene") ?: vpReadObject(app, "embeddedDisplayWindowScene");
    id identity = vpReadObject(scene, "_fbsDisplayIdentity");
    id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
    NSArray *bounds = vpSnapshotRect(root, "bounds");
    if (!scene || ![[identity valueForKey:@"isMainDisplay"] boolValue] ||
        ![identity isEqual:vpReadObject(root, "identity")] ||
        ![vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier") isEqual:@"SB-main"] ||
        (!([bounds isEqual:@[@0, @0, @669, @951]]) && !([bounds isEqual:@[@0, @0, @466, @678]]))) return;
    vpMainStatusProfileScene = scene;
    id wrapper = vpReadObject(vpReadObject(scene, "statusBarManager"), "statusBar");
    vpMainStatusOriginalProviderClass = object_getClass(vpReadObject(vpReadObject(wrapper, "statusBar"), "visualProvider"));
    vpMainStatusProfileLogCount = 0;
    vpMainStatusProfileEnabled = YES;
    unsigned int generation = ++vpMainStatusProfileGeneration;
    vpFoldDisplayLog(vpAutomaticMainStatus ? @"Main status profile: persistent native Duo profile enabled" :
        @"Main status profile: eight-second native metadata lookup lease; no UI identity migration");
    vpRefreshMainStatusRenderer();
    if (vpAutomaticMainStatus) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == vpMainStatusProfileGeneration) vpRestoreMainStatusProfile();
    });
}

// MARK: - visual provider profile lookup

static Class vpStatusProfileFactoryAtIndex(NSUInteger index, id self, SEL selector, id screen, id info) {
    Class (*original)(id, SEL, id, id) = (void *)vpOriginalStatusProfileFactories[index];
    // This is a reference-metric lookup only. Native provider construction
    // continues with its real screen; no UIView geometry/provider class is set.
    if (!vpStatusProfileLookupEnabled || ![NSThread isMainThread] || vpStatusProfileFactoryDepth)
        return original(self, selector, screen, info);
    BOOL ownedConstruction = vpStatusProfileConstructionScene == (__bridge void *)vpStatusProfileScene;
    BOOL sameScreen = screen == vpReadObject(vpStatusProfileScene, "screen");
    if (vpStatusProfileCallCount++ < 12)
        vpFoldDisplayLog([NSString stringWithFormat:@"status profile factory call: class=%@ sameScreen=%d ownedConstruction=%d",
            NSStringFromClass(self), sameScreen, ownedConstruction]);
    if (!vpUIConfigPublished || vpStatusProfileScene != vpUIConfigWindowScene ||
        !(sameScreen || ownedConstruction) || vpMainInnerWindowScene() != vpStatusProfileScene)
        return original(self, selector, screen, info);
    Class profile = objc_getClass("STUIStatusBarVisualProvider_AxisAlignableSplit2007");
    SEL notchSelector = sel_registerName("notchSize");
    NSMethodSignature *notchSignature = [profile methodSignatureForSelector:notchSelector];
    if (notchSignature.methodReturnLength != sizeof(CGSize)) return original(self, selector, screen, info);
    CGSize notch = ((CGSize (*)(id, SEL))objc_msgSend)(profile, notchSelector);
    if (notch.width <= 0 || notch.height <= 0) return original(self, selector, screen, info);
    Class shapeClass = objc_getClass("UISDisplaySingleRectShape");
    SEL initializer = sel_registerName("initWithRect:");
    NSMethodSignature *shapeSignature = [shapeClass instanceMethodSignatureForSelector:initializer];
    if (shapeSignature.numberOfArguments != 3 ||
        strcmp([shapeSignature getArgumentTypeAtIndex:2], "{CGRect={CGPoint=dd}{CGSize=dd}}") != 0)
        return original(self, selector, screen, info);
    VPhoneStatusScreenPreview *preview = [VPhoneStatusScreenPreview alloc];
    preview.source = screen;
    preview.referenceBounds = CGRectMake(0, 0, 2007, 2853);
    preview.previewExclusion = ((id (*)(id, SEL, CGRect))objc_msgSend)([shapeClass alloc], initializer,
        CGRectMake(0, 0, notch.width, notch.height));
    Class selected = Nil;
    vpStatusProfileFactoryDepth++;
    @try { selected = original(self, selector, preview, info); }
    @finally { vpStatusProfileFactoryDepth--; }
    // The native factory, not a returned constant, must accept this profile.
    if (selected != profile) return original(self, selector, screen, info);
    if (vpStatusProfileCallCount++ < 20)
        vpFoldDisplayLog(@"status profile lookup: native factory accepted inner reference metrics; real screen retained");
    return selected;
}

static Class vpStatusProfileFactoryIOS(id self, SEL selector, id screen, id info) { return vpStatusProfileFactoryAtIndex(0, self, selector, screen, info); }
static Class vpStatusProfileFactoryPhone(id self, SEL selector, id screen, id info) { return vpStatusProfileFactoryAtIndex(1, self, selector, screen, info); }
static Class vpStatusProfileFactorySplit(id self, SEL selector, id screen, id info) { return vpStatusProfileFactoryAtIndex(2, self, selector, screen, info); }
static Class vpStatusProfileFactoryAxis(id self, SEL selector, id screen, id info) { return vpStatusProfileFactoryAtIndex(3, self, selector, screen, info); }
static const char *vpStatusProfileFactoryClasses[] = {"STUIStatusBarVisualProvider_iOS", "STUIStatusBarVisualProvider_Phone",
    "STUIStatusBarVisualProvider_Split", "STUIStatusBarVisualProvider_AxisAlignableSplit"};
static IMP vpStatusProfileFactoryReplacements[] = {(IMP)vpStatusProfileFactoryIOS, (IMP)vpStatusProfileFactoryPhone,
    (IMP)vpStatusProfileFactorySplit, (IMP)vpStatusProfileFactoryAxis};

void vpResetManagedStatusProvider(void) {
    id scene = vpStatusProfileScene;
    if (!scene || scene != vpUIConfigWindowScene) return;
    id renderer = vpReadObject(vpReadObject(vpReadObject(scene, "statusBarManager"), "statusBar"), "statusBar");
    SEL reset = sel_registerName("resetVisualProvider");
    Method method = class_getInstanceMethod(object_getClass(renderer), reset);
    void *previousScope = vpStatusProfileConstructionScene;
    @try {
        if (vpStatusProfileLookupEnabled) vpStatusProfileConstructionScene = (__bridge void *)scene;
        if (method && strcmp(method_getTypeEncoding(method), "v16@0:8") == 0)
            ((void (*)(id, SEL))objc_msgSend)(renderer, reset);
        for (NSString *name in @[@"setNeedsLayout", @"layoutIfNeeded"])
            if ([renderer respondsToSelector:NSSelectorFromString(name)]) ((void (*)(id, SEL))objc_msgSend)(renderer, NSSelectorFromString(name));
    } @finally { vpStatusProfileConstructionScene = previousScope; }
}

void vpRestoreStatusProfileLookup(void) {
    if (!vpStatusProfileLookupEnabled) return;
    vpStatusProfileLookupEnabled = NO;
    vpStatusProfileGeneration++;
    for (NSUInteger index = 0; index < 4; index++) {
        Method method = class_getClassMethod(objc_getClass(vpStatusProfileFactoryClasses[index]),
            sel_registerName("visualProviderSubclassForScreen:visualProviderInfo:"));
        if (method && vpOriginalStatusProfileFactories[index] && method_getImplementation(method) == vpStatusProfileFactoryReplacements[index])
            method_setImplementation(method, vpOriginalStatusProfileFactories[index]);
    }
    vpResetManagedStatusProvider();
    vpStatusProfileScene = nil;
    vpFoldDisplayLog(@"status profile lookup: original factory restored");
}

void vpPulseStatusProfileLookup(void) {
    // Single-display only: a published inner display has its own status bar.
    if (vpInnerDisplayRequested()) return;
    @try {
        if (vpStatusProfileLookupEnabled || !vpUIConfigPublished || vpMainInnerWindowScene() != vpUIConfigWindowScene) return;
        Method methods[4];
        for (NSUInteger index = 0; index < 4; index++) {
            methods[index] = class_getClassMethod(objc_getClass(vpStatusProfileFactoryClasses[index]),
                sel_registerName("visualProviderSubclassForScreen:visualProviderInfo:"));
            if (!methods[index] || strcmp(method_getTypeEncoding(methods[index]), "#32@0:8@16@24") != 0) return;
        }
        vpStatusProfileScene = vpUIConfigWindowScene;
        vpStatusProfileCallCount = 0;
        // Publish all original call targets before any replacement can run,
        // including a concurrent factory call that will take the native path.
        for (NSUInteger index = 0; index < 4; index++)
            vpOriginalStatusProfileFactories[index] = method_getImplementation(methods[index]);
        for (NSUInteger index = 0; index < 4; index++)
            method_setImplementation(methods[index], vpStatusProfileFactoryReplacements[index]);
        vpStatusProfileLookupEnabled = YES;
        unsigned int generation = ++vpStatusProfileGeneration;
        vpFoldDisplayLog(@"status profile lookup: eight-second owned UI reference-metric lease");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == vpStatusProfileGeneration) vpRestoreStatusProfileLookup();
        });
    } @catch (NSException *exception) {
        vpRestoreStatusProfileLookup();
        vpFoldDisplayLog([NSString stringWithFormat:@"status profile lookup exception: %@", exception.reason]);
    }
}
