// Home-screen family classification: the inner scene's native family and the
// viewport-scoped family lookups.

#import "FoldDisplayPrivate.h"

IMP vpOriginalSceneScreenType;
static NSUInteger vpInnerNativeScreenType;
static atomic_uint vpInnerFamilyLogCount;
static void *vpOriginalSharedFamilyClassifier;
static void *vpOriginalViewportScreenFamily, *vpOriginalViewportGlobalFamily;
static _Thread_local BOOL vpViewportFamilyLookupActive;
static _Thread_local unsigned int vpGlobalFamilyDepth;
static atomic_uint vpGlobalFamilyTraceCount;
static atomic_uint vpSharedFamilyLogCount;

// Classify a distinct reference context; never publish its 669pt geometry.
// This tests the shared scene family decision used by system consumers,
// including the native status-bar rotation gate, rather than one provider.
NSUInteger vpNativeInnerSceneFamily(id self, SEL selector) {
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

void vpInstallSharedInnerFamily(void) {
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
void vpInstallViewportFamilyLookup(void) {
    MISFixDetourResult (*install)(const char *, void *, void *, void **) = dlsym(RTLD_DEFAULT, "MISFixDetour");
    void *screen = dlsym(RTLD_DEFAULT, "SBHScreenTypeForScreen");
    void *global = dlsym(RTLD_DEFAULT, "SBHScreenTypeForCurrentDevice");
    if (!install || !screen || !global) return;
    MISFixDetourResult a = install("Duo viewport screen family", screen, (void *)vpViewportScreenFamily, &vpOriginalViewportScreenFamily);
    MISFixDetourResult b = install("Duo viewport global family", global, (void *)vpViewportGlobalFamily, &vpOriginalViewportGlobalFamily);
    vpFoldDisplayLog([NSString stringWithFormat:@"viewport native family: screen=%d global=%d", a, b]);
}
