#ifndef FOLD_DISPLAY_PRIVATE_H
#define FOLD_DISPLAY_PRIVATE_H

// Shared by every libvphonefolddisplay translation unit: the state and
// helpers one section owns and another reads, grouped by the file that
// defines them (FoldDisplay<Section>.m; the constructor's state lives in
// libvphonefolddisplay.m). State used by one file stays static there.
//
// Everything declared between the visibility pragmas is internal to the
// dylib: it links across files but stays out of the export table.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../MISFix/MISFixDetour.h"
#include <dlfcn.h>
#include <string.h>
#include <stdatomic.h>
#include <notify.h>
#include <xpc/xpc.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <stdio.h>

#pragma GCC visibility push(hidden)

// MARK: - typed selector declarations
@protocol VPhoneDisplayProjectionCopying
- (instancetype)copyWithOverrideBounds:(CGRect)bounds;
- (instancetype)copyWithOverrideMode:(id)mode;
@end
@protocol VPhoneDisplayModeCopying
- (instancetype)_copyWithOverrideSize:(CGSize)size scale:(CGFloat)scale;
@end

// MARK: - logging and object readers

void vpFoldDisplayLog(NSString *line);
BOOL vpConsumeDisplayExperimentFlag(const char *flag);
id vpReadObject(id object, const char *name);
id vpReadMultilineDescription(id object);
id vpReadObjectIvar(id object, const char *name);
id vpRootServerScenes(id app);
NSNumber *vpReadBoolValue(id object, const char *name);
NSValue *vpReadRectValue(id object, const char *name);
id vpSnapshotRect(id object, const char *name);
NSNumber *vpSnapshotScalarIvar(id object, const char *name);
NSString *vpDescribeLayerContents(id contents);
void vpDumpObjectIvars(id object, NSString *label, NSUInteger limit);
NSString *vpSizeText(CGSize size);

// MARK: - display configuration pipeline

extern atomic_bool vpLogicalProjectionEnabled;
extern __weak id vpLogicalRoleResolver;
extern IMP vpOriginalStartResolvingDisplay;
extern __weak id vpObservedConfigurationTransformer;
extern NSHashTable *vpObservedDisplayMonitors;
void vpRefreshMainTransform(void);
BOOL vpIsDuoInnerBounds(id configuration);
void vpResolveSingleInnerDisplay(id self, SEL cmd, id proxy);
void vpInstallDisplayPipelineObservation(void);

// MARK: - logical viewport

extern atomic_bool vpCoverViewportEnabled;
extern BOOL vpPersistentViewport;
extern IMP vpOriginalLogicalSurfaceType;
extern atomic_uint vpViewportRequestGeneration;
extern atomic_bool vpNativeGeometryRefreshEnabled;
extern atomic_bool vpSceneResizePropagationEnabled;
extern IMP vpOriginalSBWindowResizePolicy;
extern NSMutableDictionary<NSString *, NSNumber *> *vpResizedSceneGenerations;
void vpScheduleViewportAdoption(void);
void vpLogicalProjectionControl(NSInteger action);
void vpSyncLogicalRoleResolver(void);
BOOL vpAllowScopedMainWindowResize(id self, SEL cmd);
void vpObserveSceneGeometry(id self, SEL cmd, id windowScene, id previousSpace, NSInteger previousOrientation, id previousTraits);
void vpProcessViewportWorkspaceRequest(BOOL submit);
void vpSetCoverViewport(BOOL enabled);
NSInteger vpLogicalSurfaceType(id self, SEL selector);
void vpSetPersistentViewport(BOOL cover);

// MARK: - home-screen family

extern IMP vpOriginalSceneScreenType;
NSUInteger vpNativeInnerSceneFamily(id self, SEL selector);
void vpInstallSharedInnerFamily(void);
void vpInstallViewportFamilyLookup(void);

// MARK: - orientation map

void vpExportNativeOrientationMapping(void);
id vpSnapshotPoseDirections(id provider);

// MARK: - interface orientation

void vpProbeUnknownDisplayPolicy(BOOL restore);
void vpRestoreRootSceneOrientations(void);
void vpSyncRootSceneOrientation(void);
id vpMainInnerWindowScene(void);
id vpOrientationArbitrationScene(void);
void vpRestoreSceneGeometryRequest(void);
void vpProbeSceneGeometryRequest(void);
void vpRefreshNativeOrientationInputs(BOOL rereadPose);
void vpForceNativeOrientationResolution(void);
void vpSetCanonicalOrientationProbe(BOOL enabled);
void vpRefreshNativeOrientationActuation(void);
void vpRestoreEmbeddedOrientation(void);
void vpProbeEmbeddedOrientation(void);
void vpSnapshotBackboardOrientation(void);
void vpRestoreBackboardOrientationEvents(void);
void vpProbeBackboardOrientationEvents(void);

// MARK: - status bar

extern BOOL vpLogicalRoleExperiment;
extern IMP vpOriginalTimeItemUpdate;
extern IMP vpOriginalMachClockTick, vpOriginalMachClockObserve;
extern atomic_bool vpStatusProfileLookupEnabled;
extern _Thread_local void *vpStatusProfileConstructionScene;
void vpRefreshNativeStatusRegistration(void);
void vpMachClockTick(id self, SEL selector);
id vpMachClockObserve(id self, SEL selector, id handler);
void vpObserveNativeTimeUpdate(id self, SEL selector, id date);
void vpRefreshNativeClockSource(void);
BOOL vpIsSingleMainStatusScene(id scene, BOOL constructing);
void vpInstallSceneStatusPolicy(void);
void vpInstallMainStatusLookup(void);
void vpInstallDualStatusLookup(void);
void vpRefreshMainStatusRenderer(void);
void vpRestoreMainStatusProfile(void);
void vpPulseMainStatusProfile(void);
void vpResetManagedStatusProvider(void);
void vpRestoreStatusProfileLookup(void);
void vpPulseStatusProfileLookup(void);

// MARK: - UIKit configuration and traits

extern __weak id vpUIConfigWindowScene;
extern id vpUIConfigPublished;
void vpPreviewNonEmbeddedUIConfiguration(void);
void vpSyncUIScreenTraits(void);
void vpRefreshUIStatusComponent(void);
void vpRestoreUIConfiguration(void);
void vpActivateUIConfiguration(void);
void vpPulseUIConfiguration(BOOL nonEmbedded);
void vpPreviewUISceneConfiguration(void);

// MARK: - wallpaper

void vpPulseNativeWallpaperOrientation(void);
void vpDumpWallpaperTree(id view, NSUInteger depth);
void vpSyncWallpaperSceneHosts(void);
BOOL vpInstallWallpaperOrientationBridge(void);
void vpInstallWallpaperTraitsExperiment(void);
void vpInstallLandscapeWallpaperGateDetour(void);

// MARK: - quick actions

void vpInspectQuickActions(void);
void vpApplyQuickActionGlyphScale(void);
void vpScheduleQuickActionGlyphScale(void);

// MARK: - backboardd surface probe

extern IMP vpOriginalExtendedProperties;
extern atomic_bool vpInnerSurfaceProbeEnabled;
extern atomic_uint vpPrimarySurfaceType;
id vpSurfaceExtendedProperties(id self, SEL cmd);
void vpBeginSurfaceProbe(unsigned int surfaceType, BOOL pair);

// MARK: - virtual display

void vpInspectServerClass(void);
void vpInspectRenderDisplays(void);
void vpEnableVirtualDisplayProbe(void);
BOOL vpTagUnknownDisplay(id display);
void vpTagVirtualDisplayProbe(void);
void vpVirtualDisplayExperiment(BOOL create);

// MARK: - inner display spike

BOOL vpInnerDisplayRequested(void);
NSNumber *vpInnerDisplaySurfaceType(id deviceName);
void vpInstallInnerRenderDisplay(void);
BOOL vpAddInnerRenderDisplayToServer(id server);
void vpInstallInnerBootDisplay(void);
void vpLogRenderDisplayState(void);
void vpShowInnerDisplay(BOOL shown);
void vpToggleInnerPattern(void);
void vpResolveInnerDisplay(void);
void vpInstallInnerDisplayAdapter(void);
void vpInstallInnerTouch(void);
void vpInspectInnerDisplay(void);

// MARK: - diagnostics

extern id vpStashedConfig;
void vpInspectDuoSystemUI(void);
void vpInspectStatusProvider(void);
void vpPulseInputTrace(void);
void vpRestoreInputTrace(void);
void vpInspectHomeScreenType(void);
void vpSnapshotMainScene(void);
void vpDumpDeviceConfiguration(id config);
void vpInstallConfigInitSwizzle(void);
void vpInstallLayoutClassSwizzle(void);
void vpInspectAllWindows(void);
void vpUndimScreenOnly(void);
void vpInspectNativePresentation(void);
void vpInspectDisplayState(void);

// MARK: - constructor state (libvphonefolddisplay.m)

extern atomic_bool vpCoordinateRootSceneFrame;
extern IMP vpOriginalSceneGeometryCallback;
extern BOOL vpAutomaticMainStatus;

#pragma GCC visibility pop

#endif
