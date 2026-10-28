// Spike: touches on the inner display reach its windows.
//
// backboardd routes the digitizer to the inner display while it is lit and
// its hit test names the inner window (FoldDisplayInnerDisplay.m). SpringBoard
// then sends the touch to a _UISystemGestureWindow first, and when that
// releases it, UIKit looks for the touch's window with
// -[UIWindow _targetWindowForPathIndex:atPoint:scenePointZ:forEvent:windowServerHitTestWindow:]:
// it hit-tests the point against the visible windows of the hit window's
// scene (+[UIWindow _hitTestToPoint:scenePointZ:forEvent:windowServerHitTestWindow:]).
// The answer was nil ("Unexpected nil window in latent system gesture client
// update", "to windows: 0"): the point is in the receiving window's space, a
// window of Main, and the inner scene's space is a different screen's.
//
// The compositor shows the inner scene's points one to one on the panel, so
// a point on Main's fixed coordinate space is the same point in the inner
// scene. When the native answer is nil for a hit window on the inner display,
// the point is taken through Main's fixed space and hit-tested again.

#import "FoldDisplayPrivate.h"

static IMP vpOriginalTargetWindow;
static unsigned int vpTouchLogCount;

static BOOL vpWindowIsOnInnerDisplay(id window) {
    id scene = vpReadObject(window, "windowScene");
    id configuration = vpReadObject(vpReadObject(vpReadObject(scene, "_FBSScene"), "settings"), "displayConfiguration");
    id identity = vpReadObject(configuration, "identity");
    return identity && ![[identity description] isEqual:@"Main"];
}

static id vpInnerTargetWindow(id self, SEL selector, NSInteger pathIndex, CGPoint point, double z, id event, id hitWindow) {
    id target = ((id (*)(id, SEL, NSInteger, CGPoint, double, id, id))vpOriginalTargetWindow)(self, selector, pathIndex, point, z, event, hitWindow);
    if (target || !hitWindow || !vpWindowIsOnInnerDisplay(hitWindow)) return target;
    @try {
        id fixed = vpReadObject(vpReadObject(self, "screen"), "fixedCoordinateSpace");
        CGPoint mapped = fixed ? ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(self,
            sel_registerName("convertPoint:toCoordinateSpace:"), point, fixed) : point;
        target = ((id (*)(id, SEL, CGPoint, double, id, id))objc_msgSend)(objc_getClass("UIWindow"),
            sel_registerName("_hitTestToPoint:scenePointZ:forEvent:windowServerHitTestWindow:"), mapped, z, event, hitWindow);
        if (vpTouchLogCount++ < 24)
            vpFoldDisplayLog([NSString stringWithFormat:@"inner touch: receiver %@ point {%.1f, %.1f} -> {%.1f, %.1f} hit %@ -> %@",
                NSStringFromClass([self class]), point.x, point.y, mapped.x, mapped.y,
                NSStringFromClass([hitWindow class]), target ? NSStringFromClass([target class]) : @"nil"]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner touch: exception %@", exception.reason]);
    }
    return target;
}

void vpInstallInnerTouch(void) {
    if (!vpInnerDisplayRequested()) return;
    Method target = class_getInstanceMethod(objc_getClass("UIWindow"),
        sel_registerName("_targetWindowForPathIndex:atPoint:scenePointZ:forEvent:windowServerHitTestWindow:"));
    Method hitTest = class_getClassMethod(objc_getClass("UIWindow"),
        sel_registerName("_hitTestToPoint:scenePointZ:forEvent:windowServerHitTestWindow:"));
    const char *targetEncoding = target ? method_getTypeEncoding(target) : "missing";
    const char *hitTestEncoding = hitTest ? method_getTypeEncoding(hitTest) : "missing";
    if (strcmp(targetEncoding, "@64@0:8q16{CGPoint=dd}24d40@48@56") != 0 ||
        strcmp(hitTestEncoding, "@56@0:8{CGPoint=dd}16d32@40@48") != 0) {
        vpFoldDisplayLog([NSString stringWithFormat:@"inner touch: target window ABI unavailable (%s, %s)",
            targetEncoding, hitTestEncoding]);
        return;
    }
    vpOriginalTargetWindow = method_setImplementation(target, (IMP)vpInnerTargetWindow);
    vpFoldDisplayLog(@"inner touch: target window adapter installed");
}
