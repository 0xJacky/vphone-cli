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

static void vpInstallWallpaperTraitsExperiment(void) {
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

static void vpInstallLandscapeWallpaperGateDetour(void) {
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
