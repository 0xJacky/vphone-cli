#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static void vpPosterProbe(void) {
    @autoreleasepool {
        @try {
            UIApplication *app = [UIApplication sharedApplication];
            NSMutableArray *rows = [NSMutableArray array];
            for (UIScene *scene in app.connectedScenes.allObjects ?: @[]) {
                UIScreen *screen = nil;
                @try { screen = [scene valueForKey:@"screen"]; } @catch (__unused NSException *e) {}
                if (!screen) screen = UIScreen.mainScreen;
                NSMutableDictionary *row = [@{
                    @"class": NSStringFromClass(scene.class) ?: @"",
                    @"activation": @(scene.activationState),
                    @"bounds": NSStringFromCGRect(screen.bounds),
                    @"scale": @(screen.scale),
                } mutableCopy];
                @try { id settings = [scene valueForKey:@"settings"]; if (settings) row[@"settings"] = [settings description] ?: @""; } @catch (__unused NSException *e) {}
                @try { id mode = [screen valueForKey:@"_displayMode"]; if (mode) row[@"display_mode"] = [mode description] ?: @""; } @catch (__unused NSException *e) {}
                [rows addObject:row];
            }
            NSDictionary *payload = @{@"pid": @(getpid()), @"process": NSProcessInfo.processInfo.processName ?: @"", @"scenes": rows, @"uptime": @(NSProcessInfo.processInfo.systemUptime)};
            NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
            if (data.length > 65536) return;
            NSString *path = @"/var/mobile/Library/Logs/vphone-poster-inspect.log";
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            [handle seekToEndOfFile]; [handle writeData:[[NSString stringWithFormat:@"%@\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]] dataUsingEncoding:NSUTF8StringEncoding]]; [handle closeFile];
        } @catch (__unused NSException *exception) {}
    }
}

__attribute__((constructor)) static void vpPosterProbeInit(void) { dispatch_async(dispatch_get_main_queue(), ^{ vpPosterProbe(); }); }
