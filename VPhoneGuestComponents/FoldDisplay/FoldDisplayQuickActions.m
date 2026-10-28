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
                    if ([className isEqualToString:@"CSQuickActionImageGlyphView"]) {
                        // The glyph's geometry chain: the size the button's
                        // layout set, the symbol's own size, the container
                        // the scale lives on, and the size that reaches the
                        // window.
                        id superview = [view valueForKey:@"superview"];
                        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(view, sel_registerName("bounds"));
                        CGRect onScreen = ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(view,
                            sel_registerName("convertRect:toView:"), bounds, nil);
                        vpFoldDisplayLog([NSString stringWithFormat:@"quick action glyph: bounds=%@ transform=%@ image=%@ window={%.1f, %.1f} container=%@ %@ subviews=%lu sublayerTransform=%@",
                            vpSizeText(bounds.size), [view valueForKey:@"transform"],
                            [vpReadObjectIvar(view, "_image") valueForKey:@"size"],
                            onScreen.size.width, onScreen.size.height,
                            NSStringFromClass([superview class]), [superview valueForKey:@"bounds"],
                            (unsigned long)[[superview valueForKey:@"subviews"] count],
                            [[superview valueForKey:@"layer"] valueForKey:@"sublayerTransform"]]);
                    }
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

// The Duo cover sheet lays the glyphs out at 20x37pt (flashlight) and
// 35x26pt (camera) inside a 48pt icon; a real iPhone Duo's landscape lock
// screen draws them at about 15x27pt and 23x17pt in the same 48pt icon.
// Those are 0.75 and 0.66 of the layout sizes, one factor within the
// measurement, so both glyphs take vpQuickActionGlyphScale and keep the
// per-symbol proportions the native layout gives them (the user's earlier
// visual check had settled on 0.68).
//
// The lever is the glyph's transform, but the button lays the glyph out with
// setFrame:, which on a transformed view grows the bounds until the visual
// frame is the native size again. Whether a glyph looked scaled depended on
// whether a layout pass followed the walk. Each glyph therefore moves to a
// runtime subclass (as KVO does) whose setFrame: sets center and bounds from
// the layout rect, so the transform survives every later pass. The glyph
// class's own method list is never written: its image's method pages are
// read-only and method_setImplementation there faults (round-12/13).
static double const vpQuickActionGlyphScale = 0.70;
static atomic_uint vpQuickActionScaleGeneration;
static Class vpQuickActionGlyphSubclass;
static IMP vpQuickActionGlyphSetFrame;

static void vpQuickActionGlyphSetFrameReplacement(id self, SEL selector, CGRect frame) {
    CGAffineTransform transform = ((CGAffineTransform (*)(id, SEL))objc_msgSend)(self, sel_registerName("transform"));
    if (CGAffineTransformIsIdentity(transform)) {
        ((void (*)(id, SEL, CGRect))vpQuickActionGlyphSetFrame)(self, selector, frame);
        return;
    }
    CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(self, sel_registerName("bounds"));
    bounds.size = frame.size;
    ((void (*)(id, SEL, CGRect))objc_msgSend)(self, sel_registerName("setBounds:"), bounds);
    ((void (*)(id, SEL, CGPoint))objc_msgSend)(self, sel_registerName("setCenter:"),
        CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)));
}

static Class vpQuickActionGlyphReportedClass(id self, SEL selector) {
    return class_getSuperclass(object_getClass(self));
}

// Moves one glyph to the layout-preserving subclass. Refuses a glyph whose
// class is already someone else's subclass (a KVO observer, say).
static BOOL vpAdoptQuickActionGlyph(id view, Class glyphClass) {
    Class current = object_getClass(view);
    if (current == vpQuickActionGlyphSubclass && current) return YES;
    if (current != glyphClass) return NO;
    if (!vpQuickActionGlyphSubclass) {
        SEL setFrame = sel_registerName("setFrame:");
        Method method = class_getInstanceMethod(glyphClass, setFrame);
        if (!method) return NO;
        Class subclass = objc_allocateClassPair(glyphClass, "VPhoneQuickActionGlyphView", 0);
        if (!subclass) return NO;
        vpQuickActionGlyphSetFrame = method_getImplementation(method);
        class_addMethod(subclass, setFrame, (IMP)vpQuickActionGlyphSetFrameReplacement, method_getTypeEncoding(method));
        class_addMethod(subclass, sel_registerName("class"), (IMP)vpQuickActionGlyphReportedClass, "#16@0:8");
        objc_registerClassPair(subclass);
        vpQuickActionGlyphSubclass = subclass;
    }
    object_setClass(view, vpQuickActionGlyphSubclass);
    return YES;
}

void vpApplyQuickActionGlyphScale(void) {
    @try {
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        Class glyphClass = objc_getClass("CSQuickActionImageGlyphView");
        if (!app || !glyphClass) return;
        NSUInteger touched = 0, rescaled = 0, refused = 0;
        for (id window in vpReadObject(app, "windows")) {
            NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count) {
                id view = pending.lastObject;
                [pending removeLastObject];
                for (id child in [view valueForKey:@"subviews"] ?: @[]) [pending addObject:child];
                if (![view isKindOfClass:glyphClass]) continue;
                touched++;
                // The subclass keeps bounds equal to the layout size, so the
                // transform alone sets the drawn size.
                if (!vpAdoptQuickActionGlyph(view, glyphClass)) { refused++; continue; }
                CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(view, sel_registerName("bounds"));
                // Not laid out yet; a later pass catches it.
                if (bounds.size.width < 1 || bounds.size.height < 1) continue;
                double scale = vpQuickActionGlyphScale;
                CGAffineTransform current = ((CGAffineTransform (*)(id, SEL))objc_msgSend)(view, sel_registerName("transform"));
                if (fabs(current.a - scale) < 0.001 && fabs(current.d - scale) < 0.001 && current.b == 0 && current.c == 0) continue;
                ((void (*)(id, SEL, CGAffineTransform))objc_msgSend)(view, sel_registerName("setTransform:"),
                    CGAffineTransformMakeScale(scale, scale));
                rescaled++;
            }
        }
        if (rescaled || refused)
            vpFoldDisplayLog([NSString stringWithFormat:@"quick action glyph scale: %lu of %lu views rescaled, %lu refused",
                (unsigned long)rescaled, (unsigned long)touched, (unsigned long)refused]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"quick action glyph scale exception: %@", exception.reason]);
    }
}

// The native orientation callback starts a new CoverSheet layout; its glyph
// views can be rebuilt after the callback returns. Apply on the next main-queue
// turn and at two short settling points, while coalescing stale rotation
// schedules. Repeated passes are no-ops once a glyph carries its scale.
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
