// Virtual display experiments and render display inspection.

#import "FoldDisplayPrivate.h"

// Disabling the broad server probe restored startup on the Duo guest. The
// surviving log identified BKDisplayCloneMirroringManager as an evaluator
// owner. Inspect only this class after startup; do not realize every class or
// replace methods until their signatures and purpose have been established.
void vpInspectServerClass(void) {
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

void vpInspectRenderDisplays(void) {
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

void vpEnableVirtualDisplayProbe(void) {
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

void vpTagVirtualDisplayProbe(void) {
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

void vpVirtualDisplayExperiment(BOOL create) {
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
