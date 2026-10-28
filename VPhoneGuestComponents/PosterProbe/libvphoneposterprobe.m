#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

// Wallpaper/poster extension orientation follower for the Duo guest. The
// hosted scene in these extension processes never receives the host's
// rotation — measured on iPhone19,4, the scene stayed 669x951 portrait
// with interface 1 across a full landscape pass — so the extension renders
// portrait content that SpringBoard then misplaces in its rotated scene.
// The follower polls the per-second orientation map vphoned publishes and,
// when the host's interface differs from the scene's, asks UIKit for the
// geometry update through the public request API.

static NSString *const vpPosterMapPath = @"/var/mobile/Library/Caches/vphone-display-orientation-map.json";
static NSInteger vpPosterLastRequestedOrientation;
static NSInteger vpPosterRequestInFlight;
static CFTimeInterval vpPosterLastRequestUptime;
static int vpPosterOrientationBroadcastToken = -1;

static void vpPosterLog(NSString *line) {
    NSString *path = @"/var/mobile/Library/Logs/vphone-poster-inspect.log";
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:path]) [files createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:[[NSString stringWithFormat:@"%@\n", line] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static NSInteger vpPosterMapInterface(void) {
    NSData *data = [NSData dataWithContentsOfFile:vpPosterMapPath options:0 error:NULL];
    if (!data) return 0;
    NSDictionary *map = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSNumber *value = [map isKindOfClass:NSDictionary.class] ? map[@"interfaceOrientation"] : nil;
    return [value isKindOfClass:NSNumber.class] ? value.integerValue : 0;
}

static NSInteger vpPosterBroadcastInterface(void) {
    if (vpPosterOrientationBroadcastToken < 0) return 0;
    uint64_t state = 0;
    if (notify_get_state(vpPosterOrientationBroadcastToken, &state) != NOTIFY_STATUS_OK) return 0;
    return state >= 1 && state <= 4 ? (NSInteger)state : 0;
}

static NSInteger vpPosterSceneInterface(UIWindowScene **outScene) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes.allObjects ?: @[]) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            if (outScene) *outScene = (UIWindowScene *)scene;
            @try {
                id geometry = [scene valueForKey:@"effectiveGeometry"];
                NSNumber *orientation = [geometry valueForKey:@"interfaceOrientation"];
                if (orientation) return orientation.integerValue;
            } @catch (__unused NSException *exception) {
            }
            return 0;
        }
    }
    if (outScene) *outScene = nil;
    return 0;
}

// PosterBoard owns the Add New Wallpaper editor. Its loading transition keeps
// a portrait scene contract while SpringBoard may be landscape; repeatedly
// requesting a geometry change leaves that transition loading forever. The
// hosted photo providers still need to follow the host orientation.
static BOOL vpPosterIsRendererProcess(void) {
    NSString *name = NSProcessInfo.processInfo.processName.lowercaseString ?: @"";
    if ([name containsString:@"posterboard"]) return NO;
    return [name containsString:@"poster"];
}

static void vpPosterRequestOrientation(id scene, NSInteger orientation) {
    Class preferencesClass = objc_getClass("UIWindowSceneGeometryPreferencesIOS");
    SEL initializer = sel_registerName("initWithInterfaceOrientations:");
    SEL request = sel_registerName("requestGeometryUpdateWithPreferences:errorHandler:");
    Method initMethod = class_getInstanceMethod(preferencesClass, initializer);
    Method requestMethod = class_getInstanceMethod(object_getClass(scene), request);
    if (!initMethod || strcmp(method_getTypeEncoding(initMethod), "@24@0:8Q16") != 0 ||
        !requestMethod || strcmp(method_getTypeEncoding(requestMethod), "v32@0:8@16@?24") != 0) {
        vpPosterLog(@"follow: geometry request ABI unavailable");
        return;
    }
    id preferences = [(id)[preferencesClass alloc] initWithInterfaceOrientations:1UL << orientation];
    vpPosterRequestInFlight = orientation;
    vpPosterLastRequestedOrientation = orientation;
    vpPosterLastRequestUptime = NSProcessInfo.processInfo.systemUptime;
    ((void (*)(id, SEL, id, id))objc_msgSend)(scene, request, preferences, ^(NSError *error) {
        vpPosterRequestInFlight = 0;
        vpPosterLog([NSString stringWithFormat:@"follow: geometry request error %@", error.localizedDescription]);
    });
    vpPosterLog([NSString stringWithFormat:@"follow: requested orientation %ld", (long)orientation]);
}

static void vpPosterFollowTick(void) {
    @autoreleasepool {
        @try {
            NSInteger wanted = vpPosterBroadcastInterface();
            if (wanted == 0) wanted = vpPosterMapInterface();
            UIWindowScene *scene = nil;
            NSInteger current = vpPosterSceneInterface(&scene);
            if (wanted >= 1 && wanted <= 4 && scene && current >= 1 && current <= 4 && wanted != current) {
                BOOL requestExpired = NSProcessInfo.processInfo.systemUptime - vpPosterLastRequestUptime > 8;
                if (vpPosterIsRendererProcess() && vpPosterRequestInFlight == 0 &&
                    (vpPosterLastRequestedOrientation != wanted || requestExpired))
                    vpPosterRequestOrientation(scene, wanted);
                // Ask SpringBoard to re-center any floating hosted scene that
                // was created since the previous tick.
                notify_post("com.vphone.display.wallpaper.scenehost.sync");
            }
        } @catch (__unused NSException *exception) {
        }
    }
}

__attribute__((constructor)) static void vpPosterProbeInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        notify_register_check("com.vphone.display.orientation.broadcast", &vpPosterOrientationBroadcastToken);
        vpPosterLog([NSString stringWithFormat:@"load %.3f pid=%d process=%@",
            NSProcessInfo.processInfo.systemUptime, getpid(),
            NSProcessInfo.processInfo.processName ?: @""]);
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
            (uint64_t)(1.5 * NSEC_PER_SEC), (uint64_t)(0.1 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, ^{
            @autoreleasepool { vpPosterFollowTick(); }
        });
        dispatch_resume(timer);
        objc_setAssociatedObject([UIApplication class], "vpPosterProbeTimer", timer, OBJC_ASSOCIATION_RETAIN);
    });
}
