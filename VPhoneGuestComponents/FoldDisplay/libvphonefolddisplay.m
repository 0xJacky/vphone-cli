// Experimental, manifest-gated Duo display diagnostics.
// The framebuffer already reports the requested inner dimensions, while the
// home grid retains the narrow family. Identity-count hooks below have not
// been called on the tested guest. Keep their outcome distinct from the
// confirmed mainConfiguration and screen-type observations; see
// Research/Guest/iphone_duo_bringup.md.

#import "FoldDisplayPrivate.h"

atomic_bool vpCoordinateRootSceneFrame;
IMP vpOriginalSceneGeometryCallback;
BOOL vpAutomaticMainStatus;

// MARK: - backboardd

// backboardd owns the render displays: the surface-type probe, the virtual
// display experiments and the orientation-event probes run there.
static void vpInstallBackboardProbes(void) {
    vpInstallInnerRenderDisplay();
    Method extended = class_getInstanceMethod(objc_getClass("CAWindowServerDisplay"), sel_registerName("extendedProperties"));
    if (extended && strcmp(method_getTypeEncoding(extended), "@16@0:8") == 0) {
        vpOriginalExtendedProperties = method_setImplementation(extended, (IMP)vpSurfaceExtendedProperties);
        vpFoldDisplayLog(@"surface probe: extendedProperties observer installed, inactive");
    }
    static int surfaceToken, surfacePairToken, surfaceCoverToken;
    notify_register_dispatch("com.vphone.display.surface.inner", &surfaceToken, dispatch_get_main_queue(),
        ^(int token) { vpBeginSurfaceProbe(2, NO); });
    notify_register_dispatch("com.vphone.display.surface.pair", &surfacePairToken, dispatch_get_main_queue(),
        ^(int token) { vpBeginSurfaceProbe(2, YES); });
    notify_register_dispatch("com.vphone.display.surface.cover", &surfaceCoverToken, dispatch_get_main_queue(),
        ^(int token) { vpBeginSurfaceProbe(1, NO); });
    static int createToken, removeToken, serverInspectToken, enableToken, tagToken;
    notify_register_dispatch("com.vphone.display.virtual.create", &createToken, dispatch_get_main_queue(),
        ^(int token) { vpVirtualDisplayExperiment(YES); });
    notify_register_dispatch("com.vphone.display.virtual.remove", &removeToken, dispatch_get_main_queue(),
        ^(int token) { vpVirtualDisplayExperiment(NO); });
    notify_register_dispatch("com.vphone.display.server.inspect", &serverInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectServerClass(); vpInspectRenderDisplays(); });
    static int orientationInspectToken, orientationEnableToken, orientationRestoreToken;
    notify_register_dispatch("com.vphone.display.server.orientation.inspect", &orientationInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpSnapshotBackboardOrientation(); });
    notify_register_dispatch("com.vphone.display.server.orientation.enable", &orientationEnableToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeBackboardOrientationEvents(); });
    notify_register_dispatch("com.vphone.display.server.orientation.restore", &orientationRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreBackboardOrientationEvents(); });
    notify_register_dispatch("com.vphone.display.virtual.enable", &enableToken, dispatch_get_main_queue(),
        ^(int token) { vpEnableVirtualDisplayProbe(); });
    notify_register_dispatch("com.vphone.display.virtual.tag-unknown", &tagToken, dispatch_get_main_queue(),
        ^(int token) { vpTagVirtualDisplayProbe(); });
    static int innerStateToken;
    notify_register_dispatch("com.vphone.display.inner.server-state", &innerStateToken, dispatch_get_main_queue(),
        ^(int token) { vpLogRenderDisplayState(); });
}

// MARK: - SpringBoard hooks

static void vpInstallSpringBoardHooks(void) {
    vpInstallInnerDisplayAdapter();
    vpInstallInnerTouch();
    // The round-16 landscape wallpaper gate is now part of the Duo startup
    // path.  The one-shot marker remains accepted for older guests, but a
    // fresh boot must not silently fall back to the portrait wallpaper
    // admission path (which recreates the black bands).
    if (vpAutomaticMainStatus || vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-wallpaper-traits.once")) {
        vpInstallWallpaperTraitsExperiment();
        vpInstallLandscapeWallpaperGateDetour();
    }
    BOOL requestedFamily = vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-viewport-family.once");
    if (vpAutomaticMainStatus || requestedFamily)
        vpInstallViewportFamilyLookup();
    // Duo has one physical Main, but SpringBoard's native scene policy still
    // needs the inner role to participate in orientation and status-bar
    // arbitration.  The role adapter preserves the physical identity and is
    // now part of the normal Duo path; the old once marker remains accepted
    // for older guests but is no longer required.
    if (vpAutomaticMainStatus || vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-logical-role.once")) {
        Method surface = class_getInstanceMethod(objc_getClass("SBWindowScene"), sel_registerName("surfaceType"));
        if (surface && strcmp(method_getTypeEncoding(surface), "q16@0:8") == 0) {
            vpLogicalRoleExperiment = YES;
            Class clock = objc_getClass("SBFMachNextMinuteDateProvider");
            Method tick = class_getInstanceMethod(clock, sel_registerName("_onMachTimer"));
            Method observe = class_getInstanceMethod(clock, sel_registerName("observeMinuteUpdatesWithHandler:"));
            if (tick && observe && strcmp(method_getTypeEncoding(tick), "v16@0:8") == 0 &&
                strcmp(method_getTypeEncoding(observe), "@24@0:8@?16") == 0) {
                vpOriginalMachClockTick = method_setImplementation(tick, (IMP)vpMachClockTick);
                vpOriginalMachClockObserve = method_setImplementation(observe, (IMP)vpMachClockObserve);
                vpFoldDisplayLog(@"native clock reference: detached-view scheduling adapter installed");
            }
            Method timeUpdate = class_getInstanceMethod(objc_getClass("SBStatusBarStateAggregator"), sel_registerName("_updateTimeItemsWithDate:"));
            if (timeUpdate && strcmp(method_getTypeEncoding(timeUpdate), "v24@0:8@16") == 0)
                vpOriginalTimeItemUpdate = method_setImplementation(timeUpdate, (IMP)vpObserveNativeTimeUpdate);
            vpOriginalLogicalSurfaceType = method_setImplementation(surface, (IMP)vpLogicalSurfaceType);
            vpFoldDisplayLog(@"logical surface: native-size scoped SB-main role adapter installed");
        }
    }
    vpObservedDisplayMonitors = [NSHashTable weakObjectsHashTable];
    vpResizedSceneGenerations = [NSMutableDictionary dictionary];
    Method resizePolicy = class_getInstanceMethod(objc_getClass("SBWindow"), sel_registerName("_shouldResizeWithScene"));
    if (resizePolicy && strcmp(method_getTypeEncoding(resizePolicy), "B16@0:8") == 0)
        vpOriginalSBWindowResizePolicy = method_setImplementation(resizePolicy, (IMP)vpAllowScopedMainWindowResize);
    Method sceneGeometry = class_getInstanceMethod(objc_getClass("SBAbstractWindowSceneDelegate"),
        sel_registerName("windowScene:didUpdateCoordinateSpace:interfaceOrientation:traitCollection:"));
    if (sceneGeometry && strcmp(method_getTypeEncoding(sceneGeometry), "v48@0:8@16@24q32@40") == 0)
        vpOriginalSceneGeometryCallback = method_setImplementation(sceneGeometry, (IMP)vpObserveSceneGeometry);
    // Retired: promoting a software CADisplay to builtin asserted in cloning.
    // Consume stale markers without ever installing that type/scale override.
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-internal-panel.once"))
        vpFoldDisplayLog(@"panel adapter: retired builtin promotion marker discarded");
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-shared-family.once"))
        vpInstallSharedInnerFamily();
    // With the inner display published, Main is the cover and the inner panel
    // has scenes of its own: each screen's status bar provider is chosen for
    // its own panel (vpInstallDualStatusLookup). The single-display profile
    // lookup and scene status policy below would pin Main to the inner
    // panel's profile instead.
    BOOL nativeStatus = vpInnerDisplayRequested();
    BOOL requestedMainStatus = vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-main-status.once");
    if (nativeStatus) vpInstallDualStatusLookup();
    else if (vpAutomaticMainStatus || requestedMainStatus) vpInstallMainStatusLookup();
    if (vpAutomaticMainStatus) {
        if (!nativeStatus) {
            static int mainStatusStartupToken;
            notify_register_dispatch("com.apple.springboard.finishedstartup", &mainStatusStartupToken, dispatch_get_main_queue(),
                ^(int token) { vpPulseMainStatusProfile(); });
            // The library may load before scene construction or after the startup
            // notification. Bounded retries establish the existing Main renderer.
            for (unsigned int retry = 1; retry <= 12; ++retry)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, retry * NSEC_PER_SEC), dispatch_get_main_queue(),
                    ^{ vpPulseMainStatusProfile(); });
        }
        // The same ladder establishes the default quick-action glyph scale
        // on every lock-screen construction timing without any opt-in file.
        for (unsigned int retry = 1; retry <= 12; ++retry)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, retry * NSEC_PER_SEC), dispatch_get_main_queue(),
                ^{ vpApplyQuickActionGlyphScale(); });
    }
    BOOL requestedSceneStatus = vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-scene-status.once");
    if (!nativeStatus && (vpAutomaticMainStatus || requestedSceneStatus))
        vpInstallSceneStatusPolicy();
    if (nativeStatus) vpFoldDisplayLog(@"status bar: native per-screen providers, single-display status shims not installed");
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-root-scene-policy.once"))
        vpFoldDisplayLog(@"root scene policy: retired global Main conversion marker discarded");
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-inner-family.once")) {
        Method family = class_getInstanceMethod(objc_getClass("SBWindowScene"), sel_registerName("sbhScreenType"));
        if (family && strcmp(method_getTypeEncoding(family), "Q16@0:8") == 0) {
            vpOriginalSceneScreenType = method_setImplementation(family, (IMP)vpNativeInnerSceneFamily);
            vpFoldDisplayLog(@"shared scene family: one-instance classifier adapter installed");
        }
    }
    BOOL requestedSingleInner = vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-single-inner.once");
    if (vpLogicalRoleExperiment || requestedSingleInner) {
        Method resolve = class_getInstanceMethod(objc_getClass("SBFDisplayContentModeResolver"),
            sel_registerName("_startResolvingContentModeOfDisplay:"));
        if (resolve && strcmp(method_getTypeEncoding(resolve), "v24@0:8@16") == 0) {
            vpOriginalStartResolvingDisplay = method_setImplementation(resolve, (IMP)vpResolveSingleInnerDisplay);
            vpFoldDisplayLog(@"single inner readiness: one-instance adapter installed");
        } else vpFoldDisplayLog(@"single inner readiness: native callback ABI unavailable");
    }
    // SBFBSDisplayTransformer requires one result per source. The startup
    // two-result experiment asserted before monitor initialization; retain
    // native builder preview only, never arm that publication again.
    if (vpConsumeDisplayExperimentFlag("/var/mobile/Library/Caches/vphone-duo-logical-panel.once"))
        vpFoldDisplayLog(@"logical projection: unsupported startup marker discarded");
    // Installed before SpringBoard builds its cover sheet, so the first
    // SBSDeviceDeterminedConfiguration construction is captured.
    vpFoldDisplayLog(@"folddisplay build marker: bridge-diag-3");
    vpInstallConfigInitSwizzle();
    vpInstallLayoutClassSwizzle();
    // Keep a fresh SB-main orientation map from the first minute of boot:
    // vphoned's rotation and posture paths refuse to settle without it.
    for (unsigned int retry = 2; retry <= 12; retry += 2)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retry * NSEC_PER_SEC)), dispatch_get_main_queue(),
            ^{ vpExportNativeOrientationMapping(); });
}

// MARK: - notification registry

// Every com.vphone.display.* request SpringBoard answers. Registration only
// installs the handlers; none runs before the constructor returns.
static void vpRegisterSpringBoardNotifications(void) {
    static int innerDisplayInspectToken, innerPatternToken, innerShowToken, innerHideToken;
    notify_register_dispatch("com.vphone.display.inner.inspect", &innerDisplayInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectInnerDisplay(); });
    notify_register_dispatch("com.vphone.display.inner.pattern", &innerPatternToken, dispatch_get_main_queue(),
        ^(int token) { vpToggleInnerPattern(); });
    notify_register_dispatch("com.vphone.display.inner.show", &innerShowToken, dispatch_get_main_queue(),
        ^(int token) { vpShowInnerDisplay(YES); });
    notify_register_dispatch("com.vphone.display.inner.hide", &innerHideToken, dispatch_get_main_queue(),
        ^(int token) { vpShowInnerDisplay(NO); });
    static int innerResolveToken;
    notify_register_dispatch("com.vphone.display.inner.resolve", &innerResolveToken, dispatch_get_main_queue(),
        ^(int token) { vpResolveInnerDisplay(); });
    static int persistentCoverToken, persistentInnerToken;
    notify_register_dispatch("com.vphone.display.viewport.apply.cover", &persistentCoverToken, dispatch_get_main_queue(),
        ^(int token) { vpSetPersistentViewport(YES); });
    notify_register_dispatch("com.vphone.display.viewport.apply.inner", &persistentInnerToken, dispatch_get_main_queue(),
        ^(int token) { vpSetPersistentViewport(NO); });
    static int workspaceRefreshToken;
    notify_register_dispatch("com.vphone.display.workspace.refresh", &workspaceRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpProcessViewportWorkspaceRequest(YES); });
    static int workspacePreviewToken;
    notify_register_dispatch("com.vphone.display.workspace.preview", &workspacePreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpProcessViewportWorkspaceRequest(NO); });
    static int presentationWallpaperToken;
    notify_register_dispatch("com.vphone.display.presentation.wallpaper.pulse", &presentationWallpaperToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseNativeWallpaperOrientation(); });
    static int presentationClockToken;
    notify_register_dispatch("com.vphone.display.presentation.clock.refresh", &presentationClockToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeClockSource(); });
    static int presentationRegistrationToken;
    notify_register_dispatch("com.vphone.display.presentation.registration.refresh", &presentationRegistrationToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeStatusRegistration(); });
    static int presentationInspectToken;
    notify_register_dispatch("com.vphone.display.presentation.inspect", &presentationInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectNativePresentation(); });
    static int quickActionInspectToken;
    notify_register_dispatch("com.vphone.display.quickaction.inspect", &quickActionInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectQuickActions(); });
    static int windowsInspectToken;
    notify_register_dispatch("com.vphone.display.windows.inspect", &windowsInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectAllWindows(); });
    static int wallpaperSceneHostSyncToken;
    notify_register_dispatch("com.vphone.display.wallpaper.scenehost.sync", &wallpaperSceneHostSyncToken, dispatch_get_main_queue(),
        ^(int token) { vpSyncWallpaperSceneHosts(); });
    static int screenUndimToken;
    notify_register_dispatch("com.vphone.display.screen.undim", &screenUndimToken, dispatch_get_main_queue(),
        ^(int token) { vpUndimScreenOnly(); });
    static int displayStateToken;
    notify_register_dispatch("com.vphone.display.inspect", &displayStateToken, dispatch_get_main_queue(),
        ^(int token) { vpSnapshotMainScene(); });
    static int displayDetailsToken, homeFamilyToken;
    notify_register_dispatch("com.vphone.display.inspect.detail", &displayDetailsToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectDisplayState(); });
    notify_register_dispatch("com.vphone.display.families.inspect", &homeFamilyToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectHomeScreenType(); });
    static int uiContextPreviewToken;
    notify_register_dispatch("com.vphone.display.ui_context.preview", &uiContextPreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpPreviewUISceneConfiguration(); });
    static int duoSystemUIInspectToken;
    notify_register_dispatch("com.vphone.display.duo_system_ui.inspect", &duoSystemUIInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectDuoSystemUI(); });
    static int statusProviderInspectToken;
    notify_register_dispatch("com.vphone.display.status_provider.inspect", &statusProviderInspectToken, dispatch_get_main_queue(),
        ^(int token) { vpInspectStatusProvider(); });
    static int statusProfilePulseToken, statusProfileRestoreToken;
    notify_register_dispatch("com.vphone.display.status_profile.pulse", &statusProfilePulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseStatusProfileLookup(); });
    notify_register_dispatch("com.vphone.display.status_profile.restore", &statusProfileRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreStatusProfileLookup(); });
    static int inputTracePulseToken, inputTraceRestoreToken;
    notify_register_dispatch("com.vphone.display.input_trace.pulse", &inputTracePulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseInputTrace(); });
    notify_register_dispatch("com.vphone.display.input_trace.restore", &inputTraceRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreInputTrace(); });
    static int mainStatusPulseToken, mainStatusRestoreToken;
    notify_register_dispatch("com.vphone.display.main_status.pulse", &mainStatusPulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseMainStatusProfile(); });
    notify_register_dispatch("com.vphone.display.main_status.restore", &mainStatusRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreMainStatusProfile(); });
    static int orientationMappingToken;
    notify_register_dispatch("com.vphone.display.orientation.mapping.request", &orientationMappingToken, dispatch_get_main_queue(),
        ^(int token) { vpExportNativeOrientationMapping(); });
    static int uiContextPulseToken, uiContextActivateToken, uiContextRestoreToken;
    notify_register_dispatch("com.vphone.display.ui_context.pulse", &uiContextPulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseUIConfiguration(NO); });
    static int uiNonEmbeddedPreviewToken, uiNonEmbeddedPulseToken;
    notify_register_dispatch("com.vphone.display.ui_context.unembedded.preview", &uiNonEmbeddedPreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpPreviewNonEmbeddedUIConfiguration(); });
    notify_register_dispatch("com.vphone.display.ui_context.unembedded.pulse", &uiNonEmbeddedPulseToken, dispatch_get_main_queue(),
        ^(int token) { vpPulseUIConfiguration(YES); });
    static int uiScreenTraitsToken;
    notify_register_dispatch("com.vphone.display.ui_context.traits.sync", &uiScreenTraitsToken, dispatch_get_main_queue(),
        ^(int token) { vpSyncUIScreenTraits(); });
    notify_register_dispatch("com.vphone.display.ui_context.activate", &uiContextActivateToken, dispatch_get_main_queue(),
        ^(int token) { vpActivateUIConfiguration(); });
    notify_register_dispatch("com.vphone.display.ui_context.restore", &uiContextRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreUIConfiguration(); });
    static int uiContextComponentToken;
    notify_register_dispatch("com.vphone.display.ui_context.components.refresh", &uiContextComponentToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshUIStatusComponent(); });
    static int invalidationPulseToken;
    notify_register_dispatch("com.vphone.display.invalidation.pulse", &invalidationPulseToken, dispatch_get_main_queue(),
        ^(int token) {
            if (!atomic_load_explicit(&vpCoverViewportEnabled, memory_order_acquire)) vpRefreshMainTransform();
        });
    static int coverViewportToken, innerViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.cover", &coverViewportToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCoverViewport(YES); });
    notify_register_dispatch("com.vphone.display.viewport.inner", &innerViewportToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCoverViewport(NO); });
    static int orientationSyncToken, orientationRestoreToken;
    notify_register_dispatch("com.vphone.display.orientation.sync", &orientationSyncToken, dispatch_get_main_queue(),
        ^(int token) { vpSyncRootSceneOrientation(); });
    notify_register_dispatch("com.vphone.display.orientation.restore", &orientationRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreRootSceneOrientations(); });
    static int geometryRequestToken, geometryRestoreToken, poseRefreshToken, inputsRefreshToken;
    notify_register_dispatch("com.vphone.display.orientation.geometry", &geometryRequestToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeSceneGeometryRequest(); });
    notify_register_dispatch("com.vphone.display.orientation.geometry.restore", &geometryRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreSceneGeometryRequest(); });
    notify_register_dispatch("com.vphone.display.orientation.pose.refresh", &poseRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeOrientationInputs(YES); });
    notify_register_dispatch("com.vphone.display.orientation.inputs.refresh", &inputsRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpRefreshNativeOrientationInputs(NO); });
    static int arbitrationRefreshToken;
    notify_register_dispatch("com.vphone.display.orientation.arbitration.refresh", &arbitrationRefreshToken, dispatch_get_main_queue(),
        ^(int token) { vpForceNativeOrientationResolution(); });
    static int actuationRefreshToken;
    notify_register_dispatch("com.vphone.display.orientation.actuation.refresh", &actuationRefreshToken, dispatch_get_main_queue(),
        ^(int token) {
            vpRefreshNativeOrientationActuation();
        });
    static int embeddedOrientationToken, embeddedOrientationRestoreToken;
    notify_register_dispatch("com.vphone.display.orientation.embedded.sync", &embeddedOrientationToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeEmbeddedOrientation(); });
    notify_register_dispatch("com.vphone.display.orientation.embedded.restore", &embeddedOrientationRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpRestoreEmbeddedOrientation(); });
    static int canonicalOrientationToken, canonicalOrientationRestoreToken;
    notify_register_dispatch("com.vphone.display.orientation.canonical", &canonicalOrientationToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCanonicalOrientationProbe(YES); });
    notify_register_dispatch("com.vphone.display.orientation.canonical.restore", &canonicalOrientationRestoreToken, dispatch_get_main_queue(),
        ^(int token) { vpSetCanonicalOrientationProbe(NO); });
    static int sceneViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.scene.cover", &sceneViewportToken, dispatch_get_main_queue(),
        ^(int token) {
            atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
            vpSetCoverViewport(YES);
        });
    static int pipelineViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.pipeline.cover", &pipelineViewportToken, dispatch_get_main_queue(),
        ^(int token) {
            if (!vpOriginalSceneGeometryCallback) return;
            atomic_store_explicit(&vpNativeGeometryRefreshEnabled, true, memory_order_release);
            atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
            vpSetCoverViewport(YES);
        });
    static int resizeViewportToken;
    notify_register_dispatch("com.vphone.display.viewport.resize.cover", &resizeViewportToken, dispatch_get_main_queue(),
        ^(int token) {
            if (!vpOriginalSceneGeometryCallback || !vpOriginalSBWindowResizePolicy) return;
            atomic_store_explicit(&vpNativeGeometryRefreshEnabled, false, memory_order_release);
            atomic_store_explicit(&vpSceneResizePropagationEnabled, true, memory_order_release);
            atomic_store_explicit(&vpCoordinateRootSceneFrame, true, memory_order_release);
            vpSetCoverViewport(YES);
        });
    static int allowUnknownToken, restoreUnknownToken;
    notify_register_dispatch("com.vphone.display.unknown.allow", &allowUnknownToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeUnknownDisplayPolicy(NO); });
    notify_register_dispatch("com.vphone.display.unknown.restore", &restoreUnknownToken, dispatch_get_main_queue(),
        ^(int token) { vpProbeUnknownDisplayPolicy(YES); });
    static int projectionPreviewToken, projectionEnableToken, projectionDisableToken;
    notify_register_dispatch("com.vphone.display.logical.preview", &projectionPreviewToken, dispatch_get_main_queue(),
        ^(int token) { vpLogicalProjectionControl(0); });
    notify_register_dispatch("com.vphone.display.logical.enable", &projectionEnableToken, dispatch_get_main_queue(),
        ^(int token) { vpFoldDisplayLog(@"logical projection publication rejected: native transformer requires one result"); });
    notify_register_dispatch("com.vphone.display.logical.disable", &projectionDisableToken, dispatch_get_main_queue(),
        ^(int token) { vpLogicalProjectionControl(2); });
}

// MARK: - constructor

__attribute__((constructor)) static void vpInstallFoldDisplay(void) {
    if (strcmp(getprogname(), "backboardd") == 0) {
        vpInstallBackboardProbes();
        return;
    }
    if (strcmp(getprogname(), "SpringBoard") != 0)
        return;
    char product[128] = {0};
    size_t productLength = sizeof(product);
    vpAutomaticMainStatus = sysctlbyname("hw.machine", product, &productLength, NULL, 0) == 0 &&
        strcmp(product, "iPhone19,4") == 0;
    vpInstallSpringBoardHooks();
    vpRegisterSpringBoardNotifications();
    vpInstallDisplayPipelineObservation();
}
