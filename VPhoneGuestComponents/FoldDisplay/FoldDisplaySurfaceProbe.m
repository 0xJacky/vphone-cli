// backboardd: the CAWindowServerDisplay extendedProperties surface-type probe.

#import "FoldDisplayPrivate.h"

IMP vpOriginalExtendedProperties;
atomic_bool vpInnerSurfaceProbeEnabled;
atomic_uint vpPrimarySurfaceType = 2;
static unsigned int vpSurfaceProbeGeneration;
static atomic_bool vpCoverSurfaceProbeEnabled;
static atomic_uint vpSurfaceProbeLogCount;

// backboardd's native traits RPC reads DeviceSurfaceType from this dictionary.
// Keep the probe bounded and scoped to the real primary render display. It
// changes neither the framebuffer nor the number/identity of display sources.
id vpSurfaceExtendedProperties(id self, SEL cmd) {
    id properties = ((id (*)(id, SEL))vpOriginalExtendedProperties)(self, cmd);
    if (!atomic_load_explicit(&vpInnerSurfaceProbeEnabled, memory_order_acquire)) return properties;
    id name = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("deviceName"));
    BOOL primary = [name isEqual:@"primary"];
    BOOL cover = atomic_load_explicit(&vpCoverSurfaceProbeEnabled, memory_order_acquire) &&
        [name isEqual:@"VPhone Cover Probe"];
    if ((!primary && !cover) || (properties && ![properties isKindOfClass:NSDictionary.class])) return properties;
    NSMutableDictionary *derived = properties ? [properties mutableCopy] : [NSMutableDictionary dictionary];
    derived[@"DeviceSurfaceType"] = primary ? @(atomic_load_explicit(&vpPrimarySurfaceType, memory_order_acquire)) : @1;
    if (atomic_fetch_add_explicit(&vpSurfaceProbeLogCount, 1, memory_order_relaxed) < 8)
        vpFoldDisplayLog([NSString stringWithFormat:@"surface probe: %@ traits %@ -> %@", name, properties, derived]);
    return [derived copy];
}

void vpBeginSurfaceProbe(unsigned int surfaceType, BOOL pair) {
    if (!vpOriginalExtendedProperties) return;
    if (surfaceType != 1 && surfaceType != 2) return;
    unsigned int generation = ++vpSurfaceProbeGeneration;
    atomic_store_explicit(&vpPrimarySurfaceType, surfaceType, memory_order_release);
    atomic_store_explicit(&vpCoverSurfaceProbeEnabled, pair, memory_order_release);
    atomic_store_explicit(&vpInnerSurfaceProbeEnabled, true, memory_order_release);
    vpFoldDisplayLog([NSString stringWithFormat:@"surface probe: primary role=%u enabled for 30 seconds; pairedCover=%d", surfaceType, pair]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation != vpSurfaceProbeGeneration) return;
        atomic_store_explicit(&vpInnerSurfaceProbeEnabled, false, memory_order_release);
        atomic_store_explicit(&vpCoverSurfaceProbeEnabled, false, memory_order_release);
        vpFoldDisplayLog(@"surface probe: primary native role restored");
    });
}
