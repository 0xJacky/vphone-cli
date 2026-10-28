// backboardd: the inner display from the render server's first moment.
//
// QuartzCore's shared_server_init creates the CAWindowServer (_init), finds
// the hardware displays (_detectDisplays), configures them, and only then
// registers the render server's name (CA::Render::Server::register_name),
// which is when SpringBoard and every other client can connect and read the
// display inventory. Adding the inner display after the server runs (a
// main-queue retry on +[CAWindowServer serverIfRunning]) lands after that
// first read: FrontBoard's display monitor, BacklightServices' backlight
// hosts and SpringBoard's embedded-scene gate all missed it until
// SpringBoard restarted. Adding it from _detectDisplays puts it in the
// inventory before any client exists. The server-ready retry in
// FoldDisplayInnerDisplay.m stays as the fallback for a server that was
// already running when this library loaded.

#import "FoldDisplayPrivate.h"

static IMP vpOriginalDetectDisplays;

static void vpDetectDisplaysWithInner(id self, SEL selector) {
    ((void (*)(id, SEL))vpOriginalDetectDisplays)(self, selector);
    if (vpAddInnerRenderDisplayToServer(self))
        vpFoldDisplayLog(@"inner display: added during render server display detection");
}

void vpInstallInnerBootDisplay(void) {
    Method detect = class_getInstanceMethod(objc_getClass("CAWindowServer"), sel_registerName("_detectDisplays"));
    if (!detect || strcmp(method_getTypeEncoding(detect), "v16@0:8") != 0) {
        vpFoldDisplayLog(@"inner display: render server display detection ABI unavailable");
        return;
    }
    vpOriginalDetectDisplays = method_setImplementation(detect, (IMP)vpDetectDisplaysWithInner);
}
