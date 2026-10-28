// Lock-screen quick action buttons: inspection and glyph scaling.

#import "FoldDisplayPrivate.h"

// MARK: - inspection

// Lock-screen quick-action diagnostics: locate live CSQuickAction* views,
// record their geometry, traits and raw ivar state, and dump the native
// class surfaces so the profile selection can be read from evidence.
void vpInspectQuickActions(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id device = vpReadObject(objc_getClass("UIDevice"), "currentDevice");
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action device: model=%@ name=%@ idiom=%ld orientation=%ld",
            [device valueForKey:@"model"], [device valueForKey:@"name"],
            (long)((NSInteger (*)(id, SEL))objc_msgSend)(device, sel_registerName("userInterfaceIdiom")),
            (long)((NSInteger (*)(id, SEL))objc_msgSend)(device, sel_registerName("orientation"))]);
        NSUInteger found = 0;
        for (id window in vpReadObject(app, "windows")) {
            NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count) {
                id view = pending.lastObject;
                [pending removeLastObject];
                NSString *className = NSStringFromClass([view class]);
                BOOL quickAction = [className containsString:@"QuickAction"];
                BOOL prominent = [className containsString:@"Prominent"];
                if ((quickAction || prominent) && found < 10) {
                    found++;
                    vpFoldDisplayLog([NSString stringWithFormat:@"quick action view: class=%@ frame=%@ alpha=%@ hidden=%@",
                        className, [view valueForKey:@"frame"], [view valueForKey:@"alpha"], [view valueForKey:@"hidden"]]);
                    vpDumpObjectIvars(view, @"quick action instance", 48);
                    if ([className isEqualToString:@"CSQuickActionsButton"]) {
                        // Read-only computed getters; they reveal which metric
                        // row the native layout resolved for this instance.
                        // These selectors belong to the button, not the glyph.
                        SEL sizeSelector = sel_registerName("iconImageSize");
                        SEL frameSelector = sel_registerName("iconImageFrame");
                        SEL diameterSelector = sel_registerName("buttonDiameter");
                        if ([view respondsToSelector:sizeSelector]) {
                            CGSize size = ((CGSize (*)(id, SEL))objc_msgSend)(view, sizeSelector);
                            vpFoldDisplayLog([NSString stringWithFormat:@"quick action computed: iconImageSize={%g, %g}", size.width, size.height]);
                        }
                        if ([view respondsToSelector:frameSelector]) {
                            CGRect rect = ((CGRect (*)(id, SEL))objc_msgSend)(view, frameSelector);
                            vpFoldDisplayLog([NSString stringWithFormat:@"quick action computed: iconImageFrame={{%g, %g}, {%g, %g}}",
                                rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]);
                        }
                        if ([view respondsToSelector:diameterSelector]) {
                            double diameter = ((double (*)(id, SEL))objc_msgSend)(view, diameterSelector);
                            vpFoldDisplayLog([NSString stringWithFormat:@"quick action computed: buttonDiameter=%.6g", diameter]);
                        }
                    }
                    if ([className isEqualToString:@"CSQuickActionsView"]) {
                        vpDumpObjectIvars(vpReadObjectIvar(view, "_quickActionsSettings"), @"quick action settings", 96);
                        vpDumpObjectIvars(vpReadObjectIvar(view, "_buttonContainerView"), @"quick action buttons container", 48);
                    }
                }
                for (id child in [view valueForKey:@"subviews"] ?: @[]) [pending addObject:child];
            }
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action inventory: views=%lu", (unsigned long)found]);
        // The layout controller, its adaptive time context, and the determined
        // configuration hang off the quick-action objects' ivar graph.
        if (vpStashedConfig) {
            vpDumpDeviceConfiguration(vpStashedConfig);
        } else {
            vpFoldDisplayLog(@"live device configuration: not constructed yet");
        }
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action exception: %@", exception.reason]);
    }
}

// MARK: - glyph scale

// The user-validated glyph factor, applied without any experiment opt-in:
// over a SpringBoard startup ladder, after every orientation actuation
// refresh, after viewport transitions, and once per clock tick, because
// lock-screen rebuilds create fresh glyph instances.  The glyph class's
// method list is never touched (round-12/13); a plain transform walk is
// the only safe lever.
// The glyph frames are the symbol metrics times one shared multiplier, so
// a tall symbol (flashlight.off.fill, 20x37pt) towers over a wide one
// (camera.fill, 24x18pt) under any uniform factor.  Keep the flashlight at
// the accepted 16pt long side, while restoring the camera to the 0.82 target
// factor selected by the real-device comparison.  Bounds are deliberately used
// below: unlike frame, they are in the glyph's own coordinate space and do
// not include the transform we set.  This makes every retry idempotent during
// rotation/fold pulses and prevents the camera from being scaled down again.
static double const vpQuickActionTallGlyphLongSide = 16.0;
static double const vpQuickActionCameraScale = 0.82;
static char vpQuickActionNativeBoundsKey;
static atomic_uint vpQuickActionScaleGeneration;

void vpApplyQuickActionGlyphScale(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        if (!app) return;
        NSUInteger touched = 0, rescaled = 0;
        for (id window in vpReadObject(app, "windows")) {
            NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count) {
                id view = pending.lastObject;
                [pending removeLastObject];
                if ([view isKindOfClass:objc_getClass("CSQuickActionImageGlyphView")]) {
                    SEL transformSelector = sel_registerName("transform");
                    SEL boundsSelector = sel_registerName("bounds");
                    if (![view respondsToSelector:transformSelector] || ![view respondsToSelector:boundsSelector]) continue;
                    CGAffineTransform current = ((CGAffineTransform (*)(id, SEL))objc_msgSend)(view, transformSelector);
                    CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(view, boundsSelector);
                    touched++;
                    // UIKit's bounds should be transform-independent, but
                    // this private glyph view can be relaid out with a new
                    // bounds after a fold. Capture the first native value so
                    // later passes cannot turn a prior result into their new
                    // input, even if the view's layout code rewrites it.
                    NSValue *nativeBoundsValue = objc_getAssociatedObject(view, &vpQuickActionNativeBoundsKey);
                    CGRect nativeBounds = bounds;
                    if ([nativeBoundsValue isKindOfClass:[NSValue class]]) {
                        [nativeBoundsValue getValue:&nativeBounds size:sizeof(nativeBounds)];
                    } else {
                        // Do not freeze the pre-layout zero rect. The next
                        // scheduled pass must be allowed to capture the
                        // first real glyph bounds.
                        if (fmax(bounds.size.width, bounds.size.height) < 1) continue;
                        nativeBoundsValue = [NSValue value:&nativeBounds withObjCType:@encode(CGRect)];
                        objc_setAssociatedObject(view, &vpQuickActionNativeBoundsKey,
                            nativeBoundsValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                    double longSide = fmax(nativeBounds.size.width, nativeBounds.size.height);
                    if (longSide < 1) continue;
                    BOOL isWideGlyph = nativeBounds.size.width > nativeBounds.size.height * 1.15;
                    double scale = isWideGlyph
                        ? vpQuickActionCameraScale
                        : vpQuickActionTallGlyphLongSide / longSide;
                    if (scale > 1) scale = 1;
                    if (scale < 0.2) scale = 0.2;
                    if (fabs(current.a - scale) < 0.001 &&
                        fabs(current.d - scale) < 0.001) continue;
                    CGAffineTransform scaled = CGAffineTransformMakeScale(scale, scale);
                    NSValue *value = [NSValue value:&scaled withObjCType:@encode(CGAffineTransform)];
                    [view setValue:value forKey:@"transform"];
                    rescaled++;
                }
                for (id child in [view valueForKey:@"subviews"] ?: @[]) [pending addObject:child];
            }
        }
        if (rescaled)
            vpFoldDisplayLog([NSString stringWithFormat:@"quick action glyph scale: %lu of %lu views (camera %.2f, tall long side %.0fpt)",
                (unsigned long)rescaled, (unsigned long)touched, vpQuickActionCameraScale,
                vpQuickActionTallGlyphLongSide]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action glyph scale exception: %@", exception.reason]);
    }
}

// The native orientation callback starts a new CoverSheet layout; its glyph
// views can be rebuilt after the callback returns. Apply on the next main-queue
// turn and at two short settling points, while coalescing stale rotation
// schedules. Each pass is safe because it uses the cached native bounds above.
void vpScheduleQuickActionGlyphScale(void) {
    if (!vpAutomaticMainStatus) return;
    unsigned int generation = atomic_fetch_add_explicit(&vpQuickActionScaleGeneration, 1, memory_order_acq_rel) + 1;
    const double delays[] = {0.0, 0.12, 0.4};
    for (NSUInteger index = 0; index < sizeof(delays) / sizeof(delays[0]); ++index) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[index] * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (generation != atomic_load_explicit(&vpQuickActionScaleGeneration, memory_order_acquire)) return;
                vpApplyQuickActionGlyphScale();
            });
    }
}
