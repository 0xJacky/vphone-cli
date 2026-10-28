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
static BOOL vpIsInnerDisplay(id display);
static void vpWatchInnerDisplayResolution(void);

BOOL vpInnerDisplayRequested(void) {
    return access(vpInnerDisplayMarker, F_OK) == 0;
}

// MARK: - backboardd: the render display

@protocol VPhoneInnerDisplayInitialization
- (instancetype)initWithOptions:(NSDictionary *)options;
@end

// Adds the inner panel's render display to a render server, once. It is
// never removed: FrontBoard keeps identities for the life of the monitor.
// Normally called from the server's display detection (FoldDisplayInnerBoot.m),
// so the display exists before any client reads the inventory.
BOOL vpAddInnerRenderDisplayToServer(id server) {
    if (vpInnerRenderDisplay || !server) return NO;
    @try {
        Class cls = objc_getClass("CAWindowServerVirtualDisplay");
        Method initializer = class_getInstanceMethod(cls, sel_registerName("initWithOptions:"));
        if (!initializer || strcmp(method_getTypeEncoding(initializer), "@24@0:8@16") != 0) {
            vpFoldDisplayLog(@"inner display: virtual display initializer ABI unavailable");
            return NO;
        }
        // The panel's native pixels, landscape: 951x669 points at 3x.
        id display = [(id<VPhoneInnerDisplayInitialization>)[cls alloc] initWithOptions:@{
            @"kCAVirtualDisplayWidth": @2853, @"kCAVirtualDisplayHeight": @2007,
            @"kCAVirtualDisplayUpdateRate": @60, @"kCAVirtualDisplayName": vpInnerDisplayName,
        }];
        if (!display) { vpFoldDisplayLog(@"inner display: initializer returned nil"); return NO; }
        ((void (*)(id, SEL, id))objc_msgSend)(server, sel_registerName("addDisplay:"), display);
        SEL setEnabled = sel_registerName("setEnabled:");
        Method enable = class_getInstanceMethod(object_getClass(display), setEnabled);
        if (enable && strcmp(method_getTypeEncoding(enable), "v20@0:8B16") == 0)
            ((void (*)(id, SEL, BOOL))objc_msgSend)(display, setEnabled, YES);
        vpTagUnknownDisplay(display);
        vpInnerRenderDisplay = display;
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: render display added %@ uniqueId=%@", display,
            [display respondsToSelector:sel_registerName("uniqueId")] ? [display valueForKey:@"uniqueId"] : @"-"]);
        vpInspectRenderDisplays();
        return YES;
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: render display exception %@", exception.reason]);
    }
    return NO;
}

// The fallback for a render server that was already running when this
// library loaded: add the display once the server answers.
static void vpAddInnerRenderDisplay(unsigned int attempt) {
    if (vpInnerRenderDisplay) return;
    id server = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("CAWindowServer"), sel_registerName("serverIfRunning"));
    if (server)
        vpAddInnerRenderDisplayToServer(server);
    else if (attempt < 30)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(),
            ^{ vpAddInnerRenderDisplay(attempt + 1); });
    else
        vpFoldDisplayLog(@"inner display: render server never ran");
}

// The surface type backboardd reports for a render display, from the
// iPhone19,4 device tree: display0 (the primary, cover) 1, display1 (inner) 2.
NSNumber *vpInnerDisplaySurfaceType(id deviceName) {
    if (!vpInnerDisplayRequested()) return nil;
    if ([deviceName isEqual:@"primary"]) return @1;
    if ([deviceName isEqual:vpInnerDisplayName]) return @2;
    return nil;
}

// MARK: - backboardd: one digitizer for two panels

// A real Duo has a digitizer per panel; this guest has one, bound to the
// primary display (an empty display UUID). While the inner display is lit
// (the device is open) that digitizer belongs to the inner display, so
// backboardd hit-tests touches on the inner display's own contexts.
// backboardd asks for a digitizer's display on every event and keeps
// digitizer state per display, so the state is created under the inner
// display the first time it is missing there.
static IMP vpOriginalDigitizerDisplayUUID, vpOriginalDigitizerState;
static BOOL vpLoggedDigitizerSwitch;

static BOOL vpInnerPanelLit(void) {
    id inner = vpInnerRenderDisplay;
    return inner && [[inner valueForKey:@"enabled"] boolValue] && ![[inner valueForKey:@"isBlanked"] boolValue];
}

static id vpInnerDigitizerDisplayUUID(id self, SEL selector, id service) {
    id uuid = ((id (*)(id, SEL, id))vpOriginalDigitizerDisplayUUID)(self, selector, service);
    if ([uuid length] || !vpInnerPanelLit()) return uuid;
    id inner = [vpInnerRenderDisplay valueForKey:@"uniqueId"];
    return [inner length] ? inner : uuid;
}

static id vpInnerDigitizerState(id self, SEL selector, id service) {
    id state = ((id (*)(id, SEL, id))vpOriginalDigitizerState)(self, selector, service);
    if (state || !vpInnerPanelLit()) return state;
    ((id (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_queue_addDigitizerStateForService:"), service);
    state = ((id (*)(id, SEL, id))vpOriginalDigitizerState)(self, selector, service);
    if (!vpLoggedDigitizerSwitch) {
        vpLoggedDigitizerSwitch = YES;
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: digitizer %@ now on %@ (state %@)",
            service, [vpInnerRenderDisplay valueForKey:@"uniqueId"], state]);
    }
    return state;
}

// The inner panel is mounted at 270 degrees (device tree display1), so its
// digitizer reports positions in the panel's portrait frame, and the panel
// shows the inner display turned to match. This guest's single digitizer
// reports positions on the portrait cover panel, which backboardd would
// stretch onto the inner display's landscape space unturned; while the
// inner display has the digitizer, each finger's normalized position is
// turned by the mount first.
typedef struct __IOHIDEvent *VPHIDEventRef;
static IMP vpOriginalHandleDirectTouch;
static CFArrayRef (*vpHIDEventChildren)(VPHIDEventRef);
static uint32_t (*vpHIDEventType)(VPHIDEventRef);
static double (*vpHIDEventGetFloat)(VPHIDEventRef, uint32_t);
static void (*vpHIDEventSetFloat)(VPHIDEventRef, uint32_t, double);

static void vpTurnDigitizerPosition(VPHIDEventRef event) {
    static const uint32_t digitizer = 11, x = 11 << 16, y = (11 << 16) | 1;
    if (vpHIDEventType(event) == digitizer) {
        double nx = vpHIDEventGetFloat(event, x), ny = vpHIDEventGetFloat(event, y);
        vpHIDEventSetFloat(event, x, 1 - ny);
        vpHIDEventSetFloat(event, y, nx);
    }
    CFArrayRef children = vpHIDEventChildren(event);
    for (CFIndex index = 0; children && index < CFArrayGetCount(children); index++)
        vpTurnDigitizerPosition((VPHIDEventRef)CFArrayGetValueAtIndex(children, index));
}

static void vpInnerHandleDirectTouch(id self, SEL selector, void *event, id service) {
    if (event && vpInnerPanelLit()) vpTurnDigitizerPosition((VPHIDEventRef)event);
    ((void (*)(id, SEL, void *, id))vpOriginalHandleDirectTouch)(self, selector, event, service);
}

static void vpInstallInnerDigitizerTurn(Class processor) {
    Method handle = class_getInstanceMethod(processor, sel_registerName("_handleDirectTouchEvent:service:"));
    const char *encoding = handle ? method_getTypeEncoding(handle) : "missing";
    vpHIDEventChildren = dlsym(RTLD_DEFAULT, "IOHIDEventGetChildren");
    vpHIDEventType = dlsym(RTLD_DEFAULT, "IOHIDEventGetType");
    vpHIDEventGetFloat = dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    vpHIDEventSetFloat = dlsym(RTLD_DEFAULT, "IOHIDEventSetFloatValue");
    size_t length = strlen(encoding);
    if (!vpHIDEventChildren || !vpHIDEventType || !vpHIDEventGetFloat || !vpHIDEventSetFloat ||
        strncmp(encoding, "v32@0:8", 7) != 0 || length < 3 || strcmp(encoding + length - 3, "@24") != 0) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: digitizer turn ABI unavailable (%s)", encoding]);
        return;
    }
    vpOriginalHandleDirectTouch = method_setImplementation(handle, (IMP)vpInnerHandleDirectTouch);
    vpFoldDisplayLog([NSString stringWithFormat:@"inner display: digitizer turn installed (%s)", encoding]);
}

static void vpInstallInnerDigitizer(void) {
    Class processor = objc_getClass("BKHIDDirectTouchEventProcessor");
    Method uuid = class_getInstanceMethod(processor, sel_registerName("_queue_displayUUIDForDigitizerService:"));
    Method state = class_getInstanceMethod(processor, sel_registerName("_queue_digitizerStateForService:"));
    Method add = class_getInstanceMethod(processor, sel_registerName("_queue_addDigitizerStateForService:"));
    const char *encodings[] = {uuid ? method_getTypeEncoding(uuid) : "missing", state ? method_getTypeEncoding(state) : "missing",
        add ? method_getTypeEncoding(add) : "missing"};
    if (strcmp(encodings[0], "@24@0:8@16") != 0 || strcmp(encodings[1], "@24@0:8@16") != 0 || strcmp(encodings[2], "@24@0:8@16") != 0) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: digitizer ABI unavailable (%s, %s, %s)",
            encodings[0], encodings[1], encodings[2]]);
        return;
    }
    vpOriginalDigitizerDisplayUUID = method_setImplementation(uuid, (IMP)vpInnerDigitizerDisplayUUID);
    vpOriginalDigitizerState = method_setImplementation(state, (IMP)vpInnerDigitizerState);
    vpFoldDisplayLog(@"inner display: digitizer routing installed");
    vpInstallInnerDigitizerTurn(processor);
}

// MARK: - SpringBoard: one scanout for two panels

// SpringBoard powers each panel through its CADisplayStateControl (state 1
// on, 0 off): open, the cover (primary, display 1) goes off and the inner
// display on; closed, the reverse. On this guest the primary is the only
// scanout, and open it has to show the inner display, which SpringBoard
// composites onto it (vpShowInnerDisplay). So the primary is kept on while
// either panel wants it; a screen-off turns both off. Closing does not turn
// the inner display off, so the inner display is lit only while the cover is
// not: the cover wins the shared panel. The compositor and backboardd's touch
// routing follow the inner display's applied state.
static IMP vpOriginalTransitionDisplayState;
static __weak id vpPrimaryStateControl, vpInnerStateControl;
static long long vpPrimaryWantedState = 1, vpPrimaryAppliedState = 1, vpInnerWantedState, vpInnerAppliedState = -1;

static unsigned int vpStateControlDisplayId(id control) {
    Ivar ivar = class_getInstanceVariable(object_getClass(control), "_display_id");
    if (!ivar || strcmp(ivar_getTypeEncoding(ivar), "I") != 0) return 0;
    return *(unsigned int *)((uint8_t *)(__bridge void *)control + ivar_getOffset(ivar));
}

static void vpApplyPanelState(id control, long long state, long long *applied, id completion) {
    if (!control || (state == *applied && !completion)) return;
    *applied = state;
    ((void (*)(id, SEL, long long, id))vpOriginalTransitionDisplayState)(control,
        sel_registerName("transitionToDisplayState:withCompletion:"), state, completion);
}

static void vpApplyPanelStates(id primaryCompletion, id innerCompletion) {
    vpApplyPanelState(vpPrimaryStateControl, vpPrimaryWantedState || vpInnerWantedState ? 1 : 0,
        &vpPrimaryAppliedState, primaryCompletion);
    long long inner = vpInnerWantedState && !vpPrimaryWantedState ? 1 : 0;
    BOOL changed = inner != vpInnerAppliedState;
    vpApplyPanelState(vpInnerStateControl, inner, &vpInnerAppliedState, innerCompletion);
    if (changed && vpInnerStateControl) dispatch_async(dispatch_get_main_queue(), ^{ vpShowInnerDisplay(inner != 0); });
}

static void vpSharedScanoutTransition(id self, SEL selector, long long state, id completion) {
    unsigned int displayId = vpStateControlDisplayId(self);
    vpFoldDisplayLog([NSString stringWithFormat:@"inner display: display %u wants state %lld", displayId, state]);
    if (displayId == 1) {
        vpPrimaryStateControl = self;
        vpPrimaryWantedState = state;
        vpApplyPanelStates(completion, nil);
        return;
    }
    id innerDisplay = nil;
    for (id display in vpReadObject(objc_getClass("CADisplay"), "displays") ?: @[])
        if ([[display valueForKey:@"displayId"] unsignedIntValue] == displayId && vpIsInnerDisplay(display)) innerDisplay = display;
    if (!innerDisplay) {
        ((void (*)(id, SEL, long long, id))vpOriginalTransitionDisplayState)(self, selector, state, completion);
        return;
    }
    vpInnerStateControl = self;
    vpInnerWantedState = state;
    vpApplyPanelStates(nil, completion);
}

static void vpInstallSharedScanout(void) {
    Method transition = class_getInstanceMethod(objc_getClass("CADisplayStateControl"),
        sel_registerName("transitionToDisplayState:withCompletion:"));
    const char *encoding = transition ? method_getTypeEncoding(transition) : "missing";
    Ivar displayId = class_getInstanceVariable(objc_getClass("CADisplayStateControl"), "_display_id");
    if (strcmp(encoding, "v32@0:8q16@?24") != 0 || !displayId || strcmp(ivar_getTypeEncoding(displayId), "I") != 0) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: shared scanout ABI unavailable (%s)", encoding]);
        return;
    }
    vpOriginalTransitionDisplayState = method_setImplementation(transition, (IMP)vpSharedScanoutTransition);
    vpFoldDisplayLog(@"inner display: shared scanout installed");
}

// Each render display's power and blanking, as backboardd holds them.
void vpLogRenderDisplayState(void) {
    @try {
        id server = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("CAWindowServer"), sel_registerName("serverIfRunning"));
        for (id display in ((id (*)(id, SEL))objc_msgSend)(server, sel_registerName("displays"))) {
            if (![[display valueForKey:@"enabled"] boolValue] && ![[display valueForKey:@"deviceName"] isEqual:@"primary"] &&
                display != vpInnerRenderDisplay) continue;
            NSMutableString *state = [NSMutableString stringWithFormat:@"inner display: server %@", [display valueForKey:@"deviceName"]];
            for (NSString *key in @[@"enabled", @"isBlanked", @"disablesUpdates", @"brightness"])
                [state appendFormat:@" %@=%@", key, [display respondsToSelector:NSSelectorFromString(key)] ? [display valueForKey:key] : @"-"];
            vpFoldDisplayLog(state);
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: server state exception %@", exception.reason]);
    }
}

void vpInstallInnerRenderDisplay(void) {
    if (!vpInnerDisplayRequested()) return;
    vpInstallInnerDigitizer();
    vpInstallInnerBootDisplay();
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
static id vpInnerIdentity;

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
    if (vpIsInnerDisplay(display) && !vpInnerIdentity) vpInnerIdentity = vpReadObject(result, "identity");
    return result;
}

// Applications take the scene's display identity from SpringBoard. UIKit
// gives a screen the device idiom only when that identity is UIKit-main-like
// and leaves it unspecified (-1) otherwise; UIKit's Swift idiom switches
// (sheet presentation, scroll edge effects) trap on -1. The identity
// SpringBoard keeps stays as classified, so only Main claims the cloning
// source; the copy an application decodes says main-like.
static IMP vpOriginalIdentityEncode;

static void vpInnerIdentityEncode(id self, SEL selector, xpc_object_t dictionary) {
    ((void (*)(id, SEL, xpc_object_t))vpOriginalIdentityEncode)(self, selector, dictionary);
    if (dictionary && vpInnerIdentity && [self isEqual:vpInnerIdentity])
        xpc_dictionary_set_bool(dictionary, "mainLike", true);
}

static void vpInstallInnerIdentityEncode(void) {
    Method encode = class_getInstanceMethod(objc_getClass("FBSDisplayIdentity"), sel_registerName("encodeWithXPCDictionary:"));
    if (!encode || strcmp(method_getTypeEncoding(encode), "v24@0:8@16") != 0) {
        vpFoldDisplayLog(@"inner display: identity encoding ABI unavailable");
        return;
    }
    vpOriginalIdentityEncode = method_setImplementation(encode, (IMP)vpInnerIdentityEncode);
}

static NSUInteger vpInnerPointScale(id self, SEL selector) {
    return vpIsInnerDisplay(self) ? 3 : ((NSUInteger (*)(id, SEL))vpOriginalPointScale)(self, selector);
}

static BOOL vpInnerExternal(id self, SEL selector) {
    return vpIsInnerDisplay(self) ? NO : ((BOOL (*)(id, SEL))vpOriginalExternal)(self, selector);
}

// UIScreen takes the device idiom only for a UIKit-main-like screen and
// leaves every other non-car screen unspecified (-1); UIKit's Swift idiom
// switch (ScrollEdgeEffectView) traps on -1. The inner panel is a built-in
// phone panel, so its screen takes the device idiom too.
static IMP vpOriginalUpdateScreenIdiom;

static void vpInnerUpdateScreenIdiom(id self, SEL selector) {
    ((void (*)(id, SEL))vpOriginalUpdateScreenIdiom)(self, selector);
    id identity = vpReadObject(vpReadObject(self, "displayConfiguration"), "identity");
    if (!identity || [[identity description] isEqual:@"Main"]) return;
    if (((long long (*)(id, SEL))objc_msgSend)(self, sel_registerName("_userInterfaceIdiom")) != -1) return;
    long long idiom = ((long long (*)(id, SEL))objc_msgSend)(vpReadObject(objc_getClass("UIDevice"), "currentDevice"),
        sel_registerName("userInterfaceIdiom"));
    ((void (*)(id, SEL, long long))objc_msgSend)(self, sel_registerName("_setUserInterfaceIdiom:"), idiom);
}

static void vpInstallInnerScreenIdiom(void) {
    Class screen = objc_getClass("UIScreen");
    Method update = class_getInstanceMethod(screen, sel_registerName("_updateUserInterfaceIdiom"));
    Method set = class_getInstanceMethod(screen, sel_registerName("_setUserInterfaceIdiom:"));
    Method get = class_getInstanceMethod(screen, sel_registerName("_userInterfaceIdiom"));
    if (!update || !set || !get || strcmp(method_getTypeEncoding(update), "v16@0:8") != 0 ||
        strcmp(method_getTypeEncoding(set), "v24@0:8q16") != 0 || strcmp(method_getTypeEncoding(get), "q16@0:8") != 0) {
        vpFoldDisplayLog(@"inner display: screen idiom ABI unavailable");
        return;
    }
    vpOriginalUpdateScreenIdiom = method_setImplementation(update, (IMP)vpInnerUpdateScreenIdiom);
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
    vpInstallSharedScanout();
    vpInstallInnerScreenIdiom();
    vpInstallInnerIdentityEncode();
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
    vpWatchInnerDisplayResolution();
}

// MARK: - SpringBoard: the inner display's scenes

static BOOL vpSceneIsOnInnerDisplay(id scene) {
    id configuration = vpReadObject(vpReadObject(vpReadObject(scene, "_FBSScene"), "settings"), "displayConfiguration");
    id identity = vpReadObject(configuration, "identity");
    return identity && ![[identity description] isEqual:@"Main"];
}

// The SpringBoard window scene (not an aperture subclass) on the inner
// display, or on Main.
static id vpSpringBoardWindowScene(BOOL inner) {
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    for (id scene in [vpReadObject(app, "connectedScenes") allObjects] ?: @[])
        if ([scene class] == objc_getClass("SBWindowScene") && vpSceneIsOnInnerDisplay(scene) == inner) return scene;
    return nil;
}

// MARK: - SpringBoard: the panel shows the inner display

// The render server's own clone of a display (addClone:options:) never
// reaches this guest's paravirtual panel, so SpringBoard composites
// instead: a render context ordered onto the primary display above
// everything hosts every window of the inner display's scenes by render
// context (CALayerHost, as scene hosting does). It is not a window of
// SB-main, because open, SpringBoard gives the cover (Main) auxiliary
// content and takes its scene's windows off screen. Touches on the hosted
// windows reach their owners through backboardd's render-tree hit test.
//
// The render server redraws a display for commits to its own contexts only;
// a commit by an inner-display context (an application changing its pixels)
// leaves the hosting primary display on its last frame. So while shown, the
// container is touched once per primary frame: a near-1 opacity flip that
// damages all of it, without an implicit animation.
static id vpInnerHostContext, vpInnerHostContainer, vpInnerHostRefresh;
static dispatch_source_t vpInnerHostTimer;

@interface VPhoneInnerHostRefresh : NSObject
@end

@implementation VPhoneInnerHostRefresh
- (void)refresh:(id)link {
    Class transaction = objc_getClass("CATransaction");
    ((void (*)(id, SEL))objc_msgSend)(transaction, sel_registerName("begin"));
    ((void (*)(id, SEL, BOOL))objc_msgSend)(transaction, sel_registerName("setDisableActions:"), YES);
    float opacity = ((float (*)(id, SEL))objc_msgSend)(vpInnerHostContainer, sel_registerName("opacity"));
    ((void (*)(id, SEL, float))objc_msgSend)(vpInnerHostContainer, sel_registerName("setOpacity:"), opacity < 1 ? 1 : 0.999f);
    ((void (*)(id, SEL))objc_msgSend)(transaction, sel_registerName("commit"));
}
@end
static NSMutableDictionary<NSNumber *, id> *vpInnerHostLayers;
static CGSize vpInnerHostPanel;

static id vpPrimaryCADisplay(void) {
    for (id display in vpReadObject(objc_getClass("CADisplay"), "displays") ?: @[])
        if ([[display valueForKey:@"deviceName"] isEqual:@"primary"]) return display;
    return nil;
}

// A display-level context works in the panel's pixels: the root covers them,
// and the inner display's points are fitted onto the panel's points,
// turned a quarter (-90 degrees) if it reads landscape on the portrait
// panel, centered, shrunk only if it does not fit.
static void vpFitInnerHosts(CGRect inner) {
    id primary = vpPrimaryCADisplay();
    CGRect pixels = ((CGRect (*)(id, SEL))objc_msgSend)(primary, sel_registerName("bounds"));
    double pointScale = [[primary valueForKey:@"pointScale"] doubleValue] ?: 1;
    CGSize panel = CGSizeMake(pixels.size.width / pointScale, pixels.size.height / pointScale);
    if (CGSizeEqualToSize(panel, vpInnerHostPanel)) return;
    vpInnerHostPanel = panel;
    id root = vpReadObject(vpInnerHostContext, "layer");
    ((void (*)(id, SEL, CGRect))objc_msgSend)(root, sel_registerName("setFrame:"), (CGRect){CGPointZero, pixels.size});
    BOOL turned = inner.size.width > inner.size.height;
    CGSize upright = turned ? CGSizeMake(inner.size.height, inner.size.width) : inner.size;
    CGFloat scale = MIN(1, MIN(panel.width / upright.width, panel.height / upright.height));
    CGAffineTransform transform = CGAffineTransformMakeScale(scale * pointScale, scale * pointScale);
    if (turned) transform = CGAffineTransformRotate(transform, -M_PI_2);
    id container = vpInnerHostContainer;
    ((void (*)(id, SEL, CGRect))objc_msgSend)(container, sel_registerName("setBounds:"), (CGRect){CGPointZero, inner.size});
    ((void (*)(id, SEL, CGPoint))objc_msgSend)(container, sel_registerName("setPosition:"), CGPointMake(CGRectGetMidX(pixels), CGRectGetMidY(pixels)));
    ((void (*)(id, SEL, CGAffineTransform))objc_msgSend)(container, sel_registerName("setAffineTransform:"), transform);
    vpFoldDisplayLog([NSString stringWithFormat:@"inner display: fitted panel=%@ inner=%@ turned=%d scale=%.3f",
        vpSizeText(panel), vpSizeText(inner.size), turned, scale]);
}

static void vpSyncInnerHosts(void) {
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    id innerScene = vpSpringBoardWindowScene(YES);
    if (innerScene)
        vpFitInnerHosts(((CGRect (*)(id, SEL))objc_msgSend)(vpReadObject(innerScene, "coordinateSpace"), sel_registerName("bounds")));
    NSMutableArray *windows = [NSMutableArray array];
    for (id scene in [vpReadObject(app, "connectedScenes") allObjects] ?: @[])
        if ([scene isKindOfClass:objc_getClass("UIWindowScene")] && vpSceneIsOnInnerDisplay(scene))
            for (id window in vpReadObject(scene, "windows") ?: @[])
                if (![[window valueForKey:@"hidden"] boolValue]) [windows addObject:window];
    [windows sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a valueForKey:@"windowLevel"] compare:[b valueForKey:@"windowLevel"]];
    }];
    NSMutableSet *live = [NSMutableSet set];
    SEL contextIdSelector = sel_registerName("_contextId");
    for (NSUInteger index = 0; index < windows.count; index++) {
        id window = windows[index];
        if (![window respondsToSelector:contextIdSelector]) continue;
        unsigned int contextId = ((unsigned int (*)(id, SEL))objc_msgSend)(window, contextIdSelector);
        if (!contextId) continue;
        NSNumber *key = @(contextId);
        [live addObject:key];
        id host = vpInnerHostLayers[key];
        if (!host) {
            host = [objc_getClass("CALayerHost") new];
            ((void (*)(id, SEL, unsigned int))objc_msgSend)(host, sel_registerName("setContextId:"), contextId);
            ((void (*)(id, SEL, id))objc_msgSend)(vpInnerHostContainer, sel_registerName("addSublayer:"), host);
            vpInnerHostLayers[key] = host;
        }
        ((void (*)(id, SEL, CGRect))objc_msgSend)(host, sel_registerName("setFrame:"),
            ((CGRect (*)(id, SEL))objc_msgSend)(window, sel_registerName("frame")));
        ((void (*)(id, SEL, double))objc_msgSend)(host, sel_registerName("setZPosition:"), index);
    }
    for (NSNumber *key in vpInnerHostLayers.allKeys) {
        if ([live containsObject:key]) continue;
        ((void (*)(id, SEL))objc_msgSend)(vpInnerHostLayers[key], sel_registerName("removeFromSuperlayer"));
        [vpInnerHostLayers removeObjectForKey:key];
    }
}

void vpShowInnerDisplay(BOOL shown) {
    @try {
        if (!shown) {
            if (!vpInnerHostContext) return;
            dispatch_source_cancel(vpInnerHostTimer);
            vpInnerHostTimer = nil;
            ((void (*)(id, SEL))objc_msgSend)(vpInnerHostRefresh, sel_registerName("invalidate"));
            vpInnerHostRefresh = nil;
            ((void (*)(id, SEL))objc_msgSend)(vpInnerHostContext, sel_registerName("invalidate"));
            vpInnerHostContext = vpInnerHostContainer = nil;
            vpInnerHostLayers = nil;
            vpInnerHostPanel = CGSizeZero;
            vpFoldDisplayLog(@"inner display: shown=0");
            return;
        }
        if (vpInnerHostContext) return;
        id primary = vpPrimaryCADisplay();
        NSString *__unsafe_unretained *displayable = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, "kCAContextDisplayable");
        NSString *__unsafe_unretained *displayIdKey = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, "kCAContextDisplayId");
        Method hostContext = class_getInstanceMethod(objc_getClass("CALayerHost"), sel_registerName("setContextId:"));
        Method level = class_getInstanceMethod(objc_getClass("CAContext"), sel_registerName("setLevel:"));
        if (!primary || !displayable || !displayIdKey || !hostContext || !level ||
            strcmp(method_getTypeEncoding(hostContext), "v20@0:8I16") != 0 || strcmp(method_getTypeEncoding(level), "v20@0:8f16") != 0) {
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: show unavailable primary=%d keys=%d host=%s level=%s",
                primary != nil, displayable && displayIdKey, hostContext ? method_getTypeEncoding(hostContext) : "missing",
                level ? method_getTypeEncoding(level) : "missing"]);
            return;
        }
        id context = ((id (*)(id, SEL, id))objc_msgSend)(objc_getClass("CAContext"), sel_registerName("remoteContextWithOptions:"),
            @{*displayable: @YES, *displayIdKey: [primary valueForKey:@"displayId"]});
        id root = [objc_getClass("CALayer") new];
        ((void (*)(id, SEL, CGColorRef))objc_msgSend)(root, sel_registerName("setBackgroundColor:"),
            ((CGColorRef (*)(id, SEL))objc_msgSend)(vpReadObject(objc_getClass("UIColor"), "blackColor"), sel_registerName("CGColor")));
        id container = [objc_getClass("CALayer") new];
        ((void (*)(id, SEL, id))objc_msgSend)(root, sel_registerName("addSublayer:"), container);
        ((void (*)(id, SEL, id))objc_msgSend)(context, sel_registerName("setLayer:"), root);
        ((void (*)(id, SEL, float))objc_msgSend)(context, sel_registerName("setLevel:"), 1.0e9f);
        vpInnerHostContext = context;
        vpInnerHostContainer = container;
        vpInnerHostLayers = [NSMutableDictionary dictionary];
        vpInnerHostPanel = CGSizeZero;
        vpSyncInnerHosts();
        vpInnerHostTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(vpInnerHostTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), NSEC_PER_SEC / 4, NSEC_PER_SEC / 20);
        dispatch_source_set_event_handler(vpInnerHostTimer, ^{ vpSyncInnerHosts(); });
        dispatch_resume(vpInnerHostTimer);
        vpInnerHostRefresh = ((id (*)(id, SEL, id, SEL))objc_msgSend)(objc_getClass("CADisplayLink"),
            sel_registerName("displayLinkWithTarget:selector:"), [VPhoneInnerHostRefresh new], @selector(refresh:));
        ((void (*)(id, SEL, id, id))objc_msgSend)(vpInnerHostRefresh, sel_registerName("addToRunLoop:forMode:"),
            NSRunLoop.mainRunLoop, NSRunLoopCommonModes);
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: shown=1 context=%@ hosts=%lu",
            [context valueForKey:@"contextId"], (unsigned long)vpInnerHostLayers.count]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: show exception %@", exception.reason]);
    }
}

// MARK: - SpringBoard: content mode resolution

// SpringBoard's display content mode coordinator starts resolving a window
// scene's display when the scene connects to it; the inner display's scene
// is never handed over, so the hinge could not move content to it. Hands it
// over once the scene and the resolver both exist (the resolver keys its
// display proxies by hardware identifier, so this runs once per
// SpringBoard), and reports whether the inner display is resolved.
static BOOL vpHandOverInnerDisplay(void) {
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    id coordinator = vpReadObject(app, "displayContentModeCoordinator");
    id innerScene = vpSpringBoardWindowScene(YES);
    id resolver = vpLogicalRoleResolver;
    Method connect = class_getInstanceMethod(object_getClass(coordinator), sel_registerName("windowSceneDidConnect:"));
    if (!coordinator || !innerScene || !resolver || !connect || strcmp(method_getTypeEncoding(connect), "v24@0:8@16") != 0)
        return NO;
    id identifier = vpReadObject(vpReadObject(vpReadObject(vpReadObject(innerScene, "_FBSScene"), "settings"),
        "displayConfiguration"), "hardwareIdentifier");
    if ([[vpReadObjectIvar(resolver, "_displayProxies") allKeys] containsObject:identifier]) return YES;
    ((void (*)(id, SEL, id))objc_msgSend)(coordinator, sel_registerName("windowSceneDidConnect:"), innerScene);
    vpFoldDisplayLog([NSString stringWithFormat:@"inner display: handed %@ to the content mode resolver: %@",
        vpReadObject(vpReadObject(innerScene, "_FBSScene"), "identifier"), resolver]);
    return [[vpReadObjectIvar(resolver, "_displayProxies") allKeys] containsObject:identifier];
}

void vpResolveInnerDisplay(void) {
    @try {
        if (!vpHandOverInnerDisplay()) vpFoldDisplayLog(@"inner display: resolve not ready");
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: resolve exception %@", exception.reason]);
    }
}

// From SpringBoard's start, until the inner display is resolved.
static void vpWatchInnerDisplayResolution(void) {
    static dispatch_source_t timer;
    static unsigned int attempts;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(timer, ^{
        BOOL resolved = NO;
        @try { resolved = vpHandOverInnerDisplay(); } @catch (__unused NSException *exception) {}
        if (resolved || ++attempts >= 600) {
            dispatch_source_cancel(timer);
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: resolution watch done resolved=%d after %u s", resolved, attempts]);
        }
    });
    dispatch_resume(timer);
}

// MARK: - Stage 1 test pattern

// A window on the inner display's scene with a clock that changes every
// second, so a frame reaching the panel can be told from a stale one, and a
// tap count, so a touch reaching the inner display can be told too.
static id vpInnerPatternWindow;
static dispatch_source_t vpInnerPatternTimer;
static unsigned int vpInnerPatternTaps;

@interface VPhoneInnerPatternTapTarget : NSObject
@end

@implementation VPhoneInnerPatternTapTarget
- (void)tapped:(id)recognizer {
    vpInnerPatternTaps++;
    CGPoint point = ((CGPoint (*)(id, SEL, id))objc_msgSend)(recognizer, sel_registerName("locationInView:"), nil);
    vpFoldDisplayLog([NSString stringWithFormat:@"inner display: pattern tap %u at {%.1f, %.1f}", vpInnerPatternTaps, point.x, point.y]);
}
@end

static VPhoneInnerPatternTapTarget *vpInnerPatternTapTarget;

void vpToggleInnerPattern(void) {
    @try {
        if (vpInnerPatternWindow) {
            dispatch_source_cancel(vpInnerPatternTimer);
            vpInnerPatternTimer = nil;
            ((void (*)(id, SEL, BOOL))objc_msgSend)(vpInnerPatternWindow, sel_registerName("setHidden:"), YES);
            vpInnerPatternWindow = nil;
            vpFoldDisplayLog(@"inner display: pattern removed");
            return;
        }
        id innerScene = vpSpringBoardWindowScene(YES);
        if (!innerScene) { vpFoldDisplayLog(@"inner display: pattern has no inner window scene"); return; }
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(vpReadObject(innerScene, "coordinateSpace"), sel_registerName("bounds"));
        id window = ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("UIWindow") alloc],
            sel_registerName("initWithWindowScene:"), innerScene);
        ((void (*)(id, SEL, CGRect))objc_msgSend)(window, sel_registerName("setFrame:"), bounds);
        ((void (*)(id, SEL, double))objc_msgSend)(window, sel_registerName("setWindowLevel:"), 10000000.0);
        ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("setBackgroundColor:"),
            vpReadObject(objc_getClass("UIColor"), "systemTealColor"));
        id label = ((id (*)(id, SEL, CGRect))objc_msgSend)([objc_getClass("UILabel") alloc],
            sel_registerName("initWithFrame:"), CGRectInset(bounds, 40, 40));
        ((void (*)(id, SEL, long long))objc_msgSend)(label, sel_registerName("setNumberOfLines:"), 0);
        ((void (*)(id, SEL, long long))objc_msgSend)(label, sel_registerName("setTextAlignment:"), 1);
        ((void (*)(id, SEL, id))objc_msgSend)(label, sel_registerName("setFont:"),
            ((id (*)(id, SEL, double))objc_msgSend)(objc_getClass("UIFont"), sel_registerName("boldSystemFontOfSize:"), 64));
        ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("addSubview:"), label);
        vpInnerPatternTapTarget = vpInnerPatternTapTarget ?: [VPhoneInnerPatternTapTarget new];
        id tap = ((id (*)(id, SEL, id, SEL))objc_msgSend)([objc_getClass("UITapGestureRecognizer") alloc],
            sel_registerName("initWithTarget:action:"), vpInnerPatternTapTarget, @selector(tapped:));
        ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("addGestureRecognizer:"), tap);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setHidden:"), NO);
        vpInnerPatternWindow = window;
        NSString *size = [NSString stringWithFormat:@"%.0fx%.0f", bounds.size.width, bounds.size.height];
        vpInnerPatternTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(vpInnerPatternTimer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(vpInnerPatternTimer, ^{
            NSString *time = [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle
                                                            timeStyle:NSDateFormatterMediumStyle];
            ((void (*)(id, SEL, id))objc_msgSend)(label, sel_registerName("setText:"),
                [NSString stringWithFormat:@"INNER %@\n%@\ntaps %u", size, time, vpInnerPatternTaps]);
        });
        dispatch_resume(vpInnerPatternTimer);
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: pattern on %@ bounds=%@",
            vpReadObject(vpReadObject(innerScene, "_FBSScene"), "identifier"), size]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: pattern exception %@", exception.reason]);
    }
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
            // backboardd's traits for the panel. Its surfaceType comes from
            // DeviceSurfaceType in the display's extendedProperties, which
            // FoldDisplaySurfaceProbe.m supplies on this guest.
            id service = vpReadObject(objc_getClass("BKSDisplayService"), "sharedInstance");
            SEL traitsSelector = sel_registerName("traitsForDisplayUUID:");
            id uuid = vpReadObject(display, "uniqueId");
            if (uuid && [service respondsToSelector:traitsSelector])
                [line appendFormat:@" traits=%@", ((id (*)(id, SEL, id))objc_msgSend)(service, traitsSelector, uuid)];
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
        // PosterKit's class 1 is iPad; an iPhone (MG DeviceClassNumber 1)
        // is class 0, where only an auxiliary display rotates its poster.
        if (deviceClass && supports && lockRole && *lockRole)
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: PFCurrentDeviceClass=%ld embedded-as-class-1=%d",
                (long)deviceClass(), supports(*lockRole, @"DISPLAY_TYPE_EMBEDDED", 1)]);
        // Each scene's status bar windows (frame, provider, the status bar's
        // own frame) and its screen's inputs to the native provider lookup.
        for (id scene in [vpReadObject(app, "connectedScenes") allObjects] ?: @[]) {
            id screen = vpReadObject(scene, "screen");
            NSMutableString *line = [NSMutableString stringWithFormat:@"inner display: screen of %@",
                vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier")];
            for (NSString *key in @[@"_nativeDisplayBounds", @"_exclusionArea", @"_displayCornerRadius", @"_referenceBounds"]) {
                id value = nil;
                @try { value = [screen valueForKey:key]; } @catch (__unused NSException *exception) { value = @"-"; }
                [line appendFormat:@" %@=%@", key, value];
            }
            for (id window in vpReadObject(scene, "windows") ?: @[]) {
                if (![NSStringFromClass([window class]) containsString:@"StatusBar"]) continue;
                id statusBar = nil;
                NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
                while (pending.count && !statusBar) {
                    id view = pending.lastObject;
                    [pending removeLastObject];
                    if ([view isKindOfClass:objc_getClass("STUIStatusBar")]) statusBar = view;
                    else [pending addObjectsFromArray:[view valueForKey:@"subviews"] ?: @[]];
                }
                CGRect bounds = statusBar ? ((CGRect (*)(id, SEL))objc_msgSend)(statusBar, sel_registerName("bounds")) : CGRectZero;
                id hit = statusBar ? ((id (*)(id, SEL, CGPoint, id))objc_msgSend)(statusBar, sel_registerName("hitTest:withEvent:"),
                    CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds)), nil) : nil;
                [line appendFormat:@" | %@ frame=%@ STUIStatusBar=%@ provider=%@ middleHit=%@", NSStringFromClass([window class]),
                    [window valueForKey:@"frame"], statusBar ? [statusBar valueForKey:@"frame"] : @"-",
                    statusBar ? [statusBar valueForKey:@"_visualProviderClassName"] : @"-", NSStringFromClass([hit class])];
            }
            vpFoldDisplayLog(line);
        }
        for (id scene in [vpReadObject(app, "connectedScenes") allObjects] ?: @[]) {
            id configuration = nil;
            @try { configuration = vpReadObject(vpReadObject(scene, "_FBSScene"), "settings"); configuration = vpReadObject(configuration, "displayConfiguration"); }
            @catch (__unused NSException *exception) {}
            id type = configuration && displayType ? displayType(configuration) : nil;
            BOOL rotates = type && supports && deviceClass && lockRole && *lockRole ? supports(*lockRole, type, deviceClass()) : NO;
            NSMutableString *roles = [NSMutableString string];
            for (NSString *key in @[@"type", @"connectionType", @"isUIKitMainLike", @"isAlwaysConnected", @"hardwareIdentifier"]) {
                id value = nil;
                @try { value = [configuration valueForKey:key]; } @catch (__unused NSException *exception) { value = @"-"; }
                [roles appendFormat:@" %@=%@", key, value];
            }
            id surface = nil;
            @try { surface = [scene valueForKey:@"surfaceType"]; } @catch (__unused NSException *exception) {}
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: scene %@ %@ display=%@ bounds=%@ posterType=%@ dynamicRotation=%d surfaceType=%@ delegate=%@ idiom=%@ screenIdiom=%@%@",
                NSStringFromClass([scene class]), vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier"),
                vpReadObject(configuration, "identity"), [configuration valueForKey:@"bounds"], type, rotates, surface,
                NSStringFromClass([vpReadObject(scene, "delegate") class]),
                [vpReadObject(scene, "traitCollection") valueForKey:@"userInterfaceIdiom"],
                [vpReadObject(vpReadObject(scene, "screen"), "traitCollection") valueForKey:@"userInterfaceIdiom"], roles]);
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: inspect exception %@", exception.reason]);
    }
}
