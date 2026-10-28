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

// The surface type backboardd reports for a render display, from the
// iPhone19,4 device tree: display0 (the primary, cover) 1, display1 (inner) 2.
NSNumber *vpInnerDisplaySurfaceType(id deviceName) {
    if (!vpInnerDisplayRequested()) return nil;
    if ([deviceName isEqual:@"primary"]) return @1;
    if ([deviceName isEqual:vpInnerDisplayName]) return @2;
    return nil;
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

// MARK: - Stage 1: the panel shows the inner display

// The render server's own clone of a display (addClone:options:) never
// reaches this guest's paravirtual panel, so SpringBoard composites
// instead: a window on Main hosts every window of the inner display's
// scenes by render context (CALayerHost, as scene hosting does), turned
// and scaled from the landscape panel onto the portrait framebuffer.
static id vpInnerHostWindow, vpInnerHostContainer;
static dispatch_source_t vpInnerHostTimer;
static NSMutableDictionary<NSNumber *, id> *vpInnerHostLayers;

static void vpSyncInnerHosts(void) {
    id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
    NSMutableArray *windows = [NSMutableArray array];
    for (id scene in [vpReadObject(app, "connectedScenes") allObjects] ?: @[])
        if ([scene isKindOfClass:objc_getClass("UIWindowScene")] && vpSceneIsOnInnerDisplay(scene))
            for (id window in vpReadObject(scene, "windows") ?: @[])
                if (![[window valueForKey:@"hidden"] boolValue]) [windows addObject:window];
    [windows sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a valueForKey:@"windowLevel"] compare:[b valueForKey:@"windowLevel"]];
    }];
    NSMutableSet *live = [NSMutableSet set];
    id container = vpReadObject(vpInnerHostContainer, "layer");
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
            ((void (*)(id, SEL, id))objc_msgSend)(container, sel_registerName("addSublayer:"), host);
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
            if (!vpInnerHostWindow) return;
            dispatch_source_cancel(vpInnerHostTimer);
            vpInnerHostTimer = nil;
            ((void (*)(id, SEL, BOOL))objc_msgSend)(vpInnerHostWindow, sel_registerName("setHidden:"), YES);
            vpInnerHostWindow = vpInnerHostContainer = nil;
            vpInnerHostLayers = nil;
            vpFoldDisplayLog(@"inner display: shown=0");
            return;
        }
        if (vpInnerHostWindow) return;
        id innerScene = vpSpringBoardWindowScene(YES), mainScene = vpSpringBoardWindowScene(NO);
        Method contextId = class_getInstanceMethod(objc_getClass("UIWindow"), sel_registerName("_contextId"));
        Method hostContext = class_getInstanceMethod(objc_getClass("CALayerHost"), sel_registerName("setContextId:"));
        if (!innerScene || !mainScene || !contextId || !hostContext ||
            strcmp(method_getTypeEncoding(contextId), "I16@0:8") != 0 ||
            strcmp(method_getTypeEncoding(hostContext), "v20@0:8I16") != 0) {
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: show unavailable inner=%d main=%d contextId=%s host=%s",
                innerScene != nil, mainScene != nil, contextId ? method_getTypeEncoding(contextId) : "missing",
                hostContext ? method_getTypeEncoding(hostContext) : "missing"]);
            return;
        }
        CGRect panel = ((CGRect (*)(id, SEL))objc_msgSend)(vpReadObject(mainScene, "coordinateSpace"), sel_registerName("bounds"));
        CGRect inner = ((CGRect (*)(id, SEL))objc_msgSend)(vpReadObject(innerScene, "coordinateSpace"), sel_registerName("bounds"));
        id window = ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("UIWindow") alloc],
            sel_registerName("initWithWindowScene:"), mainScene);
        ((void (*)(id, SEL, CGRect))objc_msgSend)(window, sel_registerName("setFrame:"), panel);
        ((void (*)(id, SEL, double))objc_msgSend)(window, sel_registerName("setWindowLevel:"), 9999999.0);
        ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("setBackgroundColor:"),
            vpReadObject(objc_getClass("UIColor"), "blackColor"));
        // The inner display in its own points, turned a quarter (the
        // interface-4 mount, -90 degrees) when it is landscape on the
        // portrait panel, scaled to fit and centered.
        id container = ((id (*)(id, SEL, CGRect))objc_msgSend)([objc_getClass("UIView") alloc],
            sel_registerName("initWithFrame:"), inner);
        BOOL turned = inner.size.width > inner.size.height;
        CGSize upright = turned ? CGSizeMake(inner.size.height, inner.size.width) : inner.size;
        CGFloat scale = MIN(panel.size.width / upright.width, panel.size.height / upright.height);
        CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
        if (turned) transform = CGAffineTransformRotate(transform, -M_PI_2);
        ((void (*)(id, SEL, CGPoint))objc_msgSend)(container, sel_registerName("setCenter:"),
            CGPointMake(CGRectGetMidX(panel), CGRectGetMidY(panel)));
        ((void (*)(id, SEL, CGAffineTransform))objc_msgSend)(container, sel_registerName("setTransform:"), transform);
        ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("addSubview:"), container);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setHidden:"), NO);
        vpInnerHostWindow = window;
        vpInnerHostContainer = container;
        vpInnerHostLayers = [NSMutableDictionary dictionary];
        vpSyncInnerHosts();
        vpInnerHostTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(vpInnerHostTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), NSEC_PER_SEC / 4, NSEC_PER_SEC / 20);
        dispatch_source_set_event_handler(vpInnerHostTimer, ^{ vpSyncInnerHosts(); });
        dispatch_resume(vpInnerHostTimer);
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: shown=1 panel=%@ inner=%@ turned=%d scale=%.3f hosts=%@",
            vpSizeText(panel.size), vpSizeText(inner.size), turned, scale, vpInnerHostLayers.allKeys]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: show exception %@", exception.reason]);
    }
}

// MARK: - SpringBoard: content mode resolution

// SpringBoard's display content mode coordinator starts resolving a window
// scene's display when the scene connects to it; the inner display's scene
// is never handed over. Hands it over and logs what the resolver makes of
// the two panels.
void vpResolveInnerDisplay(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id coordinator = vpReadObject(app, "displayContentModeCoordinator");
        id innerScene = vpSpringBoardWindowScene(YES);
        Method connect = class_getInstanceMethod(object_getClass(coordinator), sel_registerName("windowSceneDidConnect:"));
        if (!coordinator || !innerScene || !connect || strcmp(method_getTypeEncoding(connect), "v24@0:8@16") != 0) {
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: resolve unavailable coordinator=%@ scene=%@", coordinator, innerScene]);
            return;
        }
        if (![[vpReadObjectIvar(vpLogicalRoleResolver, "_displayProxies") allKeys] containsObject:
                vpReadObject(vpReadObject(vpReadObject(vpReadObject(innerScene, "_FBSScene"), "settings"), "displayConfiguration"), "hardwareIdentifier")])
            ((void (*)(id, SEL, id))objc_msgSend)(coordinator, sel_registerName("windowSceneDidConnect:"), innerScene);
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: resolve %@ -> %@",
            vpReadObject(vpReadObject(innerScene, "_FBSScene"), "identifier"), vpLogicalRoleResolver]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: resolve exception %@", exception.reason]);
    }
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
            vpFoldDisplayLog([NSString stringWithFormat:@"inner display: scene %@ %@ display=%@ bounds=%@ posterType=%@ dynamicRotation=%d surfaceType=%@ delegate=%@%@",
                NSStringFromClass([scene class]), vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier"),
                vpReadObject(configuration, "identity"), [configuration valueForKey:@"bounds"], type, rotates, surface,
                NSStringFromClass([vpReadObject(scene, "delegate") class]), roles]);
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner display: inspect exception %@", exception.reason]);
    }
}
