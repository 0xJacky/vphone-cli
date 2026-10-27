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
    Class profile = objc_getClass(inner ? "STUIStatusBarVisualProvider_AxisAlignableSplit2007" :
        "STUIStatusBarVisualProvider_AxisAlignableSplitV68Cover");
    SEL notchSelector = sel_registerName("notchSize");
    NSMethodSignature *notchSignature = [profile methodSignatureForSelector:notchSelector];
    if (notchSignature.methodReturnLength != sizeof(CGSize)) return original(screen, info);
    CGSize notch = ((CGSize (*)(id, SEL))objc_msgSend)(profile, notchSelector);
    Class shapeClass = objc_getClass("UISDisplaySingleRectShape");
    SEL initializer = sel_registerName("initWithRect:");
    NSMethodSignature *shapeSignature = [shapeClass instanceMethodSignatureForSelector:initializer];
    if (shapeSignature.numberOfArguments != 3 ||
        strcmp([shapeSignature getArgumentTypeAtIndex:2], "{CGRect={CGPoint=dd}{CGSize=dd}}") != 0) return original(screen, info);
    VPhoneStatusScreenPreview *preview = [VPhoneStatusScreenPreview alloc];
    preview.source = screen;
    preview.referenceBounds = inner ? CGRectMake(0, 0, 2007, 2853) : CGRectMake(0, 0, 1398, 2034);
    preview.skipEmbeddedCache = YES;
    preview.previewExclusion = ((id (*)(id, SEL, CGRect))objc_msgSend)([shapeClass alloc], initializer,
        CGRectMake(0, 0, notch.width, notch.height));
    Class selected = original(preview, info);
    if (selected != profile) return original(screen, info);
    if (vpMainStatusProfileLogCount++ < 8)
        vpFoldDisplayLog([NSString stringWithFormat:@"Main status profile: native %@ lookup accepted; original data/screen/identity retained", inner ? @"inner" : @"cover"]);
    return selected;
}

static void vpInstallMainStatusLookup(void) {
    void *target = dlsym(RTLD_DEFAULT, "STUIStatusBarGetVisualProviderClassForScreen");
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    if (!target || !install) { vpFoldDisplayLog(@"Main status profile: native lookup/detour API unavailable"); return; }
    MISFixDetourResult result = install("Duo Main native status profile", target, (void *)vpMainStatusClassLookup,
        &vpOriginalMainStatusClassLookup);
    vpFoldDisplayLog([NSString stringWithFormat:@"Main status profile: constructor detour result=%d", result]);
}

static void vpRefreshMainStatusRenderer(void) {
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

static void vpRestoreMainStatusProfile(void) {
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

static void vpPulseMainStatusProfile(void) {
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

static void vpResetManagedStatusProvider(void) {
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

static void vpRestoreStatusProfileLookup(void) {
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

static void vpPulseStatusProfileLookup(void) {
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

static void vpSetCoverViewport(BOOL enabled) {
    unsigned int generation = atomic_fetch_add_explicit(&vpViewportRequestGeneration, 1, memory_order_relaxed) + 1;
    atomic_store_explicit(&vpCoverViewportEnabled, enabled, memory_order_release);
