// Spike: the Duo inner panel as a display of its own. A real iPhone Duo has a
// cover main display and a non-main, always-connected, landscape-native inner
// panel, which PosterKit classifies as auxiliary. This guest has one portrait
// main display. Here backboardd adds a software render display for the inner
// panel, and SpringBoard describes it as a built-in panel everywhere except
// FrontBoard's classification, which sees CADisplay type 4: in
// _FBSCADisplayToDisplayTypes that type is always-connected without being
// UIKit-main-like, so only the real Main claims the cloning source (claiming
// it twice is SpringBoard's "Cloning source already exists" assertion).
//
// Opt-in while the spike runs: both processes act only while
// /var/mobile/Library/Caches/vphone-duo-inner-display exists. Remove the
// file and restart backboardd and SpringBoard to return to the baseline.

#import "FoldDisplayPrivate.h"

static NSString *const vpInnerDisplayName = @"VPhone Duo Inner";
static const char *vpInnerDisplayMarker = "/var/mobile/Library/Caches/vphone-duo-inner-display";
static id vpInnerRenderDisplay;

BOOL vpInnerDisplayRequested(void) {
    return access(vpInnerDisplayMarker, F_OK) == 0;
}

// MARK: - backboardd: the render display

@protocol VPhoneInnerDisplayInitialization
- (instancetype)initWithOptions:(NSDictionary *)options;
@end

// Adds the inner panel's render display once the render server runs. It is
// never removed: FrontBoard keeps identities for the life of the monitor.
static void vpAddInnerRenderDisplay(unsigned int attempt) {
    @try {
        id server = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("CAWindowServer"), sel_registerName("serverIfRunning"));
        if (!server) {
            if (attempt < 30)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(),
                    ^{ vpAddInnerRenderDisplay(attempt + 1); });
            else
                vpFoldDisplayLog(@"inner display: render server never ran");
            return;
        }
        Class cls = objc_getClass("CAWindowServerVirtualDisplay");
        Method initializer = class_getInstanceMethod(cls, sel_registerName("initWithOptions:"));
        if (!initializer || strcmp(method_getTypeEncoding(initializer), "@24@0:8@16") != 0) {
            vpFoldDisplayLog(@"inner display: virtual display initializer ABI unavailable");
            return;
        }
        // The panel's native pixels, landscape: 951x669 points at 3x.
        id display = [(id<VPhoneInnerDisplayInitialization>)[cls alloc] initWithOptions:@{
            @"kCAVirtualDisplayWidth": @2853, @"kCAVirtualDisplayHeight": @2007,
            @"kCAVirtualDisplayUpdateRate": @60, @"kCAVirtualDisplayName": vpInnerDisplayName,
        }];
        if (!display) { vpFoldDisplayLog(@"inner display: initializer returned nil"); return; }
        ((void (*)(id, SEL, id))objc_msgSend)(server, sel_registerName("addDisplay:"), display);
        SEL setEnabled = sel_registerName("setEnabled:");
        Method enable = class_getInstanceMethod(object_getClass(display), setEnabled);
        if (enable && strcmp(method_getTypeEncoding(enable), "v20@0:8B16") == 0)
            ((void (*)(id, SEL, BOOL))objc_msgSend)(display, setEnabled, YES);
        vpTagUnknownDisplay(display);
        vpInnerRenderDisplay = display;
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: render display added %@", display]);
        vpInspectRenderDisplays();
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: render display exception %@", exception.reason]);
    }
}

void vpInstallInnerRenderDisplay(void) {
    if (!vpInnerDisplayRequested()) return;
    dispatch_async(dispatch_get_main_queue(), ^{ vpAddInnerRenderDisplay(0); });
}

// MARK: - SpringBoard: how the system sees it

// The inner panel is a built-in panel (CADisplay type 0) to everything that
// asks: BacklightServices gives a backlight host only to built-in displays,
// and every SpringBoard window scene needs one; SpringBoard's startup waits
// for a scene on every built-in display. Only FrontBoard's configuration
// classification sees type 4, which there is always-connected without being
// UIKit-main-like, so only the real Main claims the cloning source.
static IMP vpOriginalDisplayType, vpOriginalPointScale, vpOriginalExternal, vpOriginalConfigurationInit;
static _Thread_local BOOL vpClassifyingConfiguration;

static BOOL vpIsInnerDisplay(id display) {
    @try {
        for (NSString *key in @[@"name", @"deviceName"]) {
            if ([display respondsToSelector:NSSelectorFromString(key)] &&
                [[display valueForKey:key] isEqual:vpInnerDisplayName]) return YES;
        }
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static long long vpInnerDisplayType(id self, SEL selector) {
    if (!vpIsInnerDisplay(self)) return ((long long (*)(id, SEL))vpOriginalDisplayType)(self, selector);
    return vpClassifyingConfiguration ? 4 : 0;
}

static id vpInnerConfigurationInit(id self, SEL selector, id display, id original, BOOL isMain, BOOL assertIfInvalid) {
    vpClassifyingConfiguration = YES;
    id result = ((id (*)(id, SEL, id, id, BOOL, BOOL))vpOriginalConfigurationInit)(self, selector, display, original, isMain, assertIfInvalid);
    vpClassifyingConfiguration = NO;
    return result;
}

static NSUInteger vpInnerPointScale(id self, SEL selector) {
    return vpIsInnerDisplay(self) ? 3 : ((NSUInteger (*)(id, SEL))vpOriginalPointScale)(self, selector);
}

static BOOL vpInnerExternal(id self, SEL selector) {
    return vpIsInnerDisplay(self) ? NO : ((BOOL (*)(id, SEL))vpOriginalExternal)(self, selector);
}

static IMP vpReplaceDisplayGetter(const char *name, const char *encoding, IMP replacement) {
    Method method = class_getInstanceMethod(objc_getClass("CADisplay"), sel_registerName(name));
    if (!method || strcmp(method_getTypeEncoding(method), encoding) != 0) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: -[CADisplay %s] %s, expected %s", name,
            method ? method_getTypeEncoding(method) : "missing", encoding]);
        return NULL;
    }
    return method_setImplementation(method, replacement);
}

// Installed before SpringBoard's display monitor reads the render displays.
// CADisplay has no always-connected getter; FrontBoard derives that from
// the type.
void vpInstallInnerDisplayAdapter(void) {
    if (!vpInnerDisplayRequested()) return;
    // Type 0 without the FrontBoard scope is a second UIKit-main-like
    // display, so no scope means no adapter.
    Method configurationInit = class_getInstanceMethod(objc_getClass("FBSDisplayConfiguration"),
        sel_registerName("_initWithImmutableDisplay:originalDisplay:isMainDisplay:assertIfInvalid:"));
    const char *encoding = configurationInit ? method_getTypeEncoding(configurationInit) : "missing";
    if (strcmp(encoding, "@40@0:8@16@24B32B36") != 0) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: configuration initializer %s, adapter off", encoding]);
        return;
    }
    vpOriginalConfigurationInit = method_setImplementation(configurationInit, (IMP)vpInnerConfigurationInit);
    vpOriginalDisplayType = vpReplaceDisplayGetter("displayType", "q16@0:8", (IMP)vpInnerDisplayType);
    vpOriginalPointScale = vpReplaceDisplayGetter("pointScale", "Q16@0:8", (IMP)vpInnerPointScale);
    vpOriginalExternal = vpReplaceDisplayGetter("isExternal", "B16@0:8", (IMP)vpInnerExternal);
    vpFoldDisplayLog([NSString stringWithFormat:@"inner display: adapter type=%d scale=%d external=%d",
        vpOriginalDisplayType != NULL, vpOriginalPointScale != NULL, vpOriginalExternal != NULL]);
}

// MARK: - Stage 0 report

// The spike's pass criteria, read live: the always-connected identities,
// the window scenes and their displays, and PosterKit's own rotation answer
// for each display's configuration.
void vpInspectInnerDisplay(void) {
    @try {
        // The render displays as this process sees them, through the adapter.
        for (id display in vpReadObject(objc_getClass("CADisplay"), "displays") ?: @[]) {
            NSMutableString *line = [NSMutableString stringWithString:@"inner display: CADisplay"];
            for (NSString *key in @[@"name", @"deviceName", @"displayId", @"displayType", @"tag", @"pointScale", @"isExternal", @"bounds"]) {
                id value = nil;
                @try { value = [display valueForKey:key]; } @catch (__unused NSException *exception) {}
                [line appendFormat:@" %@=%@", key, value];
            }
            [line appendFormat:@" modes=%lu", (unsigned long)[vpReadObject(display, "availableModes") count]];
            vpFoldDisplayLog(line);
        }
        Class manager = objc_getClass("FBDisplayManager");
        id instance = vpReadObject(manager, "sharedInstance");
        for (NSString *key in @[@"connectedIdentities", @"alwaysConnectedIdentities"]) {
            id value = nil;
            @try { value = [instance valueForKey:key]; } @catch (__unused NSException *exception) {}
            if (!value && [manager respondsToSelector:NSSelectorFromString(key)]) value = [manager valueForKey:key];
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: %@ = %@", key, value]);
        }
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        BOOL (*supports)(id, id, NSInteger) = dlsym(RTLD_DEFAULT, "PFContextSupportsDynamicRotation");
        id (*displayType)(id) = dlsym(RTLD_DEFAULT, "PRDisplayTypeFromFBSDisplayConfiguration");
        NSInteger (*deviceClass)(void) = dlsym(RTLD_DEFAULT, "PFCurrentDeviceClass");
        id __unsafe_unretained *lockRole = (id __unsafe_unretained *)dlsym(RTLD_DEFAULT, "PFPosterRoleLockScreen");
        for (id scene in [vpReadObject(app, "connectedScenes") allObjects] ?: @[]) {
            id configuration = nil;
            @try { configuration = vpReadObject(vpReadObject(scene, "_FBSScene"), "settings"); configuration = vpReadObject(configuration, "displayConfiguration"); }
            @catch (__unused NSException *exception) {}
            id type = configuration && displayType ? displayType(configuration) : nil;
            BOOL rotates = type && supports && deviceClass && lockRole && *lockRole ? supports(*lockRole, type, deviceClass()) : NO;
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: scene %@ %@ display=%@ bounds=%@ posterType=%@ dynamicRotation=%d",
                NSStringFromClass([scene class]), vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier"),
                vpReadObject(configuration, "identity"), [configuration valueForKey:@"bounds"], type, rotates]);
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: inspect exception %@", exception.reason]);
    }
}
