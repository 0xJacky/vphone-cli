// The UIKit display configuration and screen traits published to SpringBoard's
// scenes, with their restore paths.

#import "FoldDisplayPrivate.h"

__weak id vpUIConfigWindowScene;
static __weak id vpUIConfigServerScene, vpUIConfigClientScene;
static _Atomic(IMP) vpUIIdentityCopyOriginal;
static _Thread_local void *vpUIIdentityCopySource, *vpUIIdentityCopyReplacement;
id vpUIConfigPublished;
static id vpUIConfigOriginalHosted, vpUIConfigOriginalServerDisplay, vpUIConfigOriginalUI;
static atomic_uint vpUIConfigGeneration;
static id vpUIOldStatusComponent, vpUINewStatusComponent, vpUIStatusComponentKey;
static BOOL vpUIStatusDetachedBeforeRollback;
static __weak id vpUIOldStatusWindow;
static NSNumber *vpUIOldStatusWindowHidden;
static __weak id vpUITraitsScreen;
static NSNumber *vpUITraitsOriginalIdiom;
static NSInteger vpUITraitsPublishedIdiom;
static NSString *vpUITraitsIdentifier;

@protocol VPhoneDisplayProjectionBuilding
- (instancetype)initWithConfiguration:(id)configuration;
- (void)setUniqueIdentifier:(NSString *)identifier;
- (void)setDisplayType:(NSInteger)type;
- (void)setUIKitMainLike;
- (id)buildConfigurationWithError:(NSError **)error;
@end
@protocol VPhoneDisplayIdentityInitializing
- (instancetype)_initWithType:(NSInteger)type UIKitMainLike:(BOOL)mainLike displayID:(uint32_t)displayID
    connectionType:(NSInteger)connectionType connectionSeed:(uint32_t)connectionSeed pid:(int)pid
    external:(BOOL)external uniqueIdentifier:(id)identifier secure:(BOOL)secure
    alwaysConnected:(BOOL)alwaysConnected root:(id)root;
@end

// MARK: - configuration builders

static id vpCreateUIConfiguration(id configuration) {
    Class cls = objc_getClass("FBSDisplayConfigurationBuilder");
    Method type = class_getInstanceMethod(cls, sel_registerName("setDisplayType:"));
    Method mainLike = class_getInstanceMethod(cls, sel_registerName("setUIKitMainLike"));
    if (!type || strcmp(method_getTypeEncoding(type), "v24@0:8q16") != 0 ||
        !mainLike || strcmp(method_getTypeEncoding(mainLike), "v16@0:8") != 0) return nil;
    id<VPhoneDisplayProjectionBuilding> builder = [(id<VPhoneDisplayProjectionBuilding>)[cls alloc] initWithConfiguration:configuration];
    [builder setUniqueIdentifier:@"vphone-duo-ui-preview"];
    [builder setDisplayType:7];
    [builder setUIKitMainLike];
    NSError *error = nil;
    id result = [builder buildConfigurationWithError:&error];
    if (!result) vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration build failed: %@", error]);
    return result;
}

static id vpUIIdentityDuringUnpublishedCopy(id self, SEL selector) {
    if ((__bridge void *)self == vpUIIdentityCopySource) return (__bridge id)vpUIIdentityCopyReplacement;
    return ((id (*)(id, SEL))vpUIIdentityCopyOriginal)(self, selector);
}

static id vpCreateNonEmbeddedUIConfiguration(id root) {
    // The native builder can set MainLike but has no clear operation. Copy
    // from a distinct, unpublished UI configuration whose identity getter is
    // substituted only on this thread for the duration of the native build.
    // The physical Main and its accessors are never substituted.
    id source = vpCreateUIConfiguration(root);
    id identity = vpReadObject(source, "identity");
    if (!source || source == root || [[identity valueForKey:@"isMainDisplay"] boolValue] ||
        ![vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")]) return nil;
    Class cls = objc_getClass("FBSDisplayIdentity");
    SEL initializer = sel_registerName("_initWithType:UIKitMainLike:displayID:connectionType:connectionSeed:pid:external:uniqueIdentifier:secure:alwaysConnected:root:");
    Method method = class_getInstanceMethod(cls, initializer);
    if (!method || strcmp(method_getTypeEncoding(method), "@76@0:8q16B24I28q32I40i44B48@52B60B64@68") != 0) return nil;
    id replacement = [(id<VPhoneDisplayIdentityInitializing>)[cls alloc]
        _initWithType:[[identity valueForKey:@"type"] integerValue] UIKitMainLike:NO
        displayID:[[identity valueForKey:@"displayID"] unsignedIntValue]
        connectionType:[[identity valueForKey:@"connectionType"] integerValue]
        connectionSeed:[[identity valueForKey:@"connectionSeed"] unsignedIntValue]
        pid:[[identity valueForKey:@"pid"] intValue] external:[[identity valueForKey:@"isExternal"] boolValue]
        uniqueIdentifier:vpReadObject(identity, "uniqueIdentifier")
        secure:[[identity valueForKey:@"expectsSecureRendering"] boolValue]
        alwaysConnected:[[identity valueForKey:@"isAlwaysConnected"] boolValue] root:vpReadObject(identity, "rootIdentity")];
    if (!replacement || [[replacement valueForKey:@"isUIKitMainLike"] boolValue]) return nil;
    id<VPhoneDisplayProjectionBuilding> builder = [(id<VPhoneDisplayProjectionBuilding>)[objc_getClass("FBSDisplayConfigurationBuilder") alloc]
        initWithConfiguration:source];
    [builder setUniqueIdentifier:@"vphone-duo-ui-unembedded-preview"];
    [builder setDisplayType:7];
    SEL getter = sel_registerName("identity");
    Method identityMethod = class_getInstanceMethod(object_getClass(source), getter);
    if (!identityMethod || strcmp(method_getTypeEncoding(identityMethod), "@16@0:8") != 0 || vpUIIdentityCopySource) return nil;
    vpUIIdentityCopyOriginal = method_getImplementation(identityMethod);
    vpUIIdentityCopySource = (__bridge void *)source;
    vpUIIdentityCopyReplacement = (__bridge void *)replacement;
    id result = nil;
    @try {
        method_setImplementation(identityMethod, (IMP)vpUIIdentityDuringUnpublishedCopy);
        NSError *error = nil;
        result = [builder buildConfigurationWithError:&error];
        if (!result) vpFoldDisplayLog([NSString stringWithFormat:@"nonembedded UI copy failed: %@", error]);
    } @finally {
        if (method_getImplementation(identityMethod) == (IMP)vpUIIdentityDuringUnpublishedCopy)
            method_setImplementation(identityMethod, vpUIIdentityCopyOriginal);
        vpUIIdentityCopySource = NULL; vpUIIdentityCopyReplacement = NULL;
    }
    if ([[vpReadObject(result, "identity") valueForKey:@"isUIKitMainLike"] boolValue] ||
        vpReadObject(result, "CADisplay") != vpReadObject(root, "CADisplay")) return nil;
    return result;
}

void vpPreviewNonEmbeddedUIConfiguration(void) {
    @try {
        id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id result = vpCreateNonEmbeddedUIConfiguration(root);
        id identity = vpReadObject(result, "identity");
        NSDictionary *fields = @{@"built": @(result != nil),
            @"mainLike": [identity valueForKey:@"isUIKitMainLike"] ?: NSNull.null,
            @"main": [identity valueForKey:@"isMainDisplay"] ?: NSNull.null,
            @"rootMatchesMain": @([vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")]),
            @"sameCADisplay": @(result && vpReadObject(result, "CADisplay") == vpReadObject(root, "CADisplay")),
            @"physicalMainLike": [vpReadObject(root, "identity") valueForKey:@"isUIKitMainLike"] ?: NSNull.null,
            @"bounds": vpSnapshotRect(result, "bounds"), @"previewOnly": @YES};
        NSData *data = [NSJSONSerialization dataWithJSONObject:fields options:0 error:NULL];
        if (data) vpFoldDisplayLog([@"nonembedded UI preview " stringByAppendingString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"nonembedded UI preview exception: %@", exception.reason]);
    }
}

static BOOL vpUIObjectsEqual(id a, id b) { return a == b || [a isEqual:b]; }

// MARK: - screen traits

static void vpPropagateUIScreenTraits(id screen) {
    SEL update = sel_registerName("_updateTraits");
    Method updateMethod = class_getInstanceMethod(object_getClass(screen), update);
    if (updateMethod && strcmp(method_getTypeEncoding(updateMethod), "v16@0:8") == 0)
        ((void (*)(id, SEL))objc_msgSend)(screen, update);
    SEL selector = sel_registerName("_notifyTraitsChangedAndPropagate");
    Method method = class_getInstanceMethod(object_getClass(screen), selector);
    if (method && strcmp(method_getTypeEncoding(method), "v16@0:8") == 0)
        ((void (*)(id, SEL))objc_msgSend)(screen, selector);
}

static BOOL vpRestoreUIScreenTraits(void) {
    id screen = vpUITraitsScreen;
    if (!vpUITraitsOriginalIdiom) return YES;
    id identity = vpReadObject(screen, "displayIdentity");
    if (screen && ![[identity valueForKey:@"isMainDisplay"] boolValue] &&
        [vpReadObject(identity, "uniqueIdentifier") isEqual:vpUITraitsIdentifier] &&
        [[screen valueForKey:@"_userInterfaceIdiom"] integerValue] == vpUITraitsPublishedIdiom) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(screen, sel_registerName("_setUserInterfaceIdiom:"), vpUITraitsOriginalIdiom.integerValue);
        vpPropagateUIScreenTraits(screen);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: restored idiom=%@ readback=%@",
            vpUITraitsOriginalIdiom, [screen valueForKey:@"_userInterfaceIdiom"]]);
        if (![[screen valueForKey:@"_userInterfaceIdiom"] isEqual:vpUITraitsOriginalIdiom]) return NO;
    } else vpFoldDisplayLog(@"UI screen traits: detached screen gone or newer identity/value preserved");
    vpUITraitsScreen = nil; vpUITraitsOriginalIdiom = nil; vpUITraitsIdentifier = nil;
    return YES;
}

void vpSyncUIScreenTraits(void) {
    @try {
        if (vpUITraitsOriginalIdiom || !vpUIConfigPublished) return;
        id scene = vpUIConfigWindowScene;
        id screen = vpReadObject(scene, "screen");
        id identity = vpReadObject(screen, "displayIdentity");
        id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id mainScreen = vpReadObject(vpReadObject(root, "identity"), "UIScreen");
        if (!scene || !screen || screen == mainScreen || !mainScreen ||
            [[identity valueForKey:@"isMainDisplay"] boolValue] ||
            ![identity isEqual:vpReadObject(vpUIConfigPublished, "identity")] ||
            ![vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")]) {
            vpFoldDisplayLog(@"UI screen traits: owned alias/Main screen binding unavailable"); return;
        }
        SEL selector = sel_registerName("_setUserInterfaceIdiom:");
        Method setter = class_getInstanceMethod(object_getClass(screen), selector);
        NSNumber *source = [mainScreen valueForKey:@"_userInterfaceIdiom"];
        NSNumber *original = [screen valueForKey:@"_userInterfaceIdiom"];
        if (!setter || strcmp(method_getTypeEncoding(setter), "v24@0:8q16") != 0 ||
            ![source isKindOfClass:NSNumber.class] || ![original isKindOfClass:NSNumber.class] || source.integerValue != 0) {
            vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: native setter/source unavailable source=%@ original=%@", source, original]); return;
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: source=%@ alias=%@ trait=%@",
            source, original, [vpReadObject(screen, "traitCollection") valueForKey:@"userInterfaceIdiom"]]);
        vpUITraitsScreen = screen; vpUITraitsOriginalIdiom = original;
        vpUITraitsPublishedIdiom = source.integerValue;
        vpUITraitsIdentifier = vpReadObject(identity, "uniqueIdentifier");
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(screen, selector, source.integerValue);
        vpPropagateUIScreenTraits(screen);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits: native phone inheritance idiom=%@ trait=%@ embedded=%@",
            [screen valueForKey:@"_userInterfaceIdiom"], [vpReadObject(screen, "traitCollection") valueForKey:@"userInterfaceIdiom"],
            vpReadBoolValue(screen, "_isEmbeddedScreen")]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI screen traits exception: %@", exception.reason]);
    }
}

// MARK: - status component

static void vpUIStatusLifecycle(id component, const char *name, id scene) {
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(component), selector);
    if (method && strcmp(method_getTypeEncoding(method), "v24@0:8@16") == 0)
        ((void (*)(id, SEL, id))objc_msgSend)(component, selector, scene);
}

static BOOL vpUIStatusRegistryAvailable(id scene) {
    Method reg = class_getInstanceMethod(object_getClass(scene), sel_registerName("_registerSceneComponent:forKey:"));
    Method unreg = class_getInstanceMethod(object_getClass(scene), sel_registerName("_unregisterSceneComponentForKey:"));
    return reg && unreg && strcmp(method_getTypeEncoding(reg), "v32@0:8@16@24") == 0 &&
        strcmp(method_getTypeEncoding(unreg), "v24@0:8@16") == 0;
}

static void vpDetachUIStatusComponent(void) {
    id scene = vpUIConfigWindowScene;
    if (!scene || !vpUINewStatusComponent || !vpUIStatusComponentKey) return;
    id current = vpReadObject(scene, "statusBarManager");
    if (current != vpUINewStatusComponent) return;
    id replacementWindow = vpReadObject(current, "statusBarWindow");
    if (replacementWindow && replacementWindow != vpUIOldStatusWindow)
        ((void (*)(id, SEL, BOOL))objc_msgSend)(replacementWindow, sel_registerName("setHidden:"), YES);
    vpUIStatusLifecycle(current, "windowSceneDidDisconnect:", scene);
    // Keep a registered component while UIKit processes the identity rollback;
    // replace it only after the original identity has been acknowledged.
    vpUIStatusDetachedBeforeRollback = YES;
    vpFoldDisplayLog(@"UI configuration: replacement native component detached before identity rollback");
}

static BOOL vpRestoreUIStatusComponent(void) {
    if (!vpUIOldStatusComponent) return YES;
    id scene = vpUIConfigWindowScene;
    if (!scene) {
        vpUIOldStatusComponent = nil; vpUINewStatusComponent = nil; vpUIStatusComponentKey = nil;
        vpUIOldStatusWindow = nil; vpUIOldStatusWindowHidden = nil;
        vpUIStatusDetachedBeforeRollback = NO; return YES;
    }
    id current = vpReadObject(scene, "statusBarManager");
    if (current && current != vpUIOldStatusComponent && current != vpUINewStatusComponent) return NO;
    if (current == vpUINewStatusComponent) {
        if (!vpUIStatusDetachedBeforeRollback) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(scene, sel_registerName("_unregisterSceneComponentForKey:"), vpUIStatusComponentKey);
        current = nil;
    }
    if (!current)
        ((void (*)(id, SEL, id, id))objc_msgSend)(scene, sel_registerName("_registerSceneComponent:forKey:"), vpUIOldStatusComponent, vpUIStatusComponentKey);
    id window = vpReadObject(vpUIOldStatusComponent, "statusBarWindow");
    if (!vpReadObject(window, "windowScene")) {
        Method setter = class_getInstanceMethod(object_getClass(window), sel_registerName("setWindowScene:"));
        if (setter && strcmp(method_getTypeEncoding(setter), "v24@0:8@16") == 0)
            ((void (*)(id, SEL, id))objc_msgSend)(window, sel_registerName("setWindowScene:"), scene);
    }
    vpUIStatusLifecycle(vpUIOldStatusComponent, "windowSceneDidConnect:", scene);
    BOOL verified = vpReadObject(scene, "statusBarManager") == vpUIOldStatusComponent;
    if (verified && vpUIOldStatusWindowHidden && vpUIOldStatusWindow) {
        if (window != vpUIOldStatusWindow) return NO;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sel_registerName("setHidden:"), vpUIOldStatusWindowHidden.boolValue);
        verified = [vpReadBoolValue(window, "isHidden") isEqual:vpUIOldStatusWindowHidden];
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: original window visibility restored=%d", verified]);
    }
    if (verified) {
        vpUIOldStatusComponent = nil; vpUINewStatusComponent = nil; vpUIStatusComponentKey = nil;
        vpUIOldStatusWindow = nil; vpUIOldStatusWindowHidden = nil;
        vpUIStatusDetachedBeforeRollback = NO;
    }
    vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: original component restore verified=%d", verified]);
    return verified;
}

void vpRefreshUIStatusComponent(void) {
    @try {
        id scene = vpUIConfigWindowScene;
        id identity = vpReadObject(scene, "_fbsDisplayIdentity");
        if (!scene || !vpUIConfigPublished || vpUIOldStatusComponent ||
            ![vpReadObject(identity, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")] ||
            !vpUIStatusRegistryAvailable(scene)) return;
        id __unsafe_unretained *keyAddress = (id __unsafe_unretained *)dlsym(RTLD_DEFAULT, "_UIStatusBarManagerWindowSceneComponentKey");
        id key = keyAddress ? *keyAddress : nil;
        id old = vpReadObject(scene, "statusBarManager");
        Method init = class_getInstanceMethod(object_getClass(old), sel_registerName("initWithScene:"));
        if (!key || !old || !init || strcmp(method_getTypeEncoding(init), "@24@0:8@16") != 0) return;
        id registered = ((id (*)(id, SEL, id))objc_msgSend)(scene, sel_registerName("_sceneComponentForKey:"), key);
        if (registered != old) { vpFoldDisplayLog(@"UI configuration: native component key did not match"); return; }
        vpUIOldStatusComponent = old;
        vpUIOldStatusWindow = vpReadObject(old, "statusBarWindow");
        vpUIOldStatusWindowHidden = vpReadBoolValue(vpUIOldStatusWindow, "isHidden");
        vpUIStatusComponentKey = key;
        vpUIStatusDetachedBeforeRollback = NO;
        vpUIStatusLifecycle(old, "windowSceneDidDisconnect:", scene);
        ((void (*)(id, SEL, id))objc_msgSend)(scene, sel_registerName("_unregisterSceneComponentForKey:"), key);
        id replacement = nil;
        void *previousScope = vpStatusProfileConstructionScene;
        @try {
            if (vpStatusProfileLookupEnabled) vpStatusProfileConstructionScene = (__bridge void *)scene;
            replacement = ((id (*)(id, SEL, id))objc_msgSend)([object_getClass(old) alloc], sel_registerName("initWithScene:"), scene);
        } @finally { vpStatusProfileConstructionScene = previousScope; }
        vpUINewStatusComponent = replacement;
        if (!replacement) { vpFoldDisplayLog(@"UI configuration: native replacement unavailable; restore checkpoint retained"); return; }
        ((void (*)(id, SEL, id, id))objc_msgSend)(scene, sel_registerName("_registerSceneComponent:forKey:"), replacement, key);
        vpUIStatusLifecycle(replacement, "windowSceneDidConnect:", scene);
        if (vpStatusProfileLookupEnabled) vpResetManagedStatusProvider();
        id replacementWindow = vpReadObject(replacement, "statusBarWindow");
        if (vpUIOldStatusWindow && replacementWindow && vpUIOldStatusWindow != replacementWindow && vpUIOldStatusWindowHidden) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(vpUIOldStatusWindow, sel_registerName("setHidden:"), YES);
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: previous profile window deactivated hidden=%@",
                vpReadBoolValue(vpUIOldStatusWindow, "isHidden")]);
        }
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: native component recreated=%d embedded=%@",
            vpReadObject(scene, "statusBarManager") == replacement, vpReadBoolValue(replacement, "_isEmbeddedDisplay")]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration component exception: %@", exception.reason]);
    }
}

// MARK: - scene configuration lease

static BOOL vpUIConfigurationOwnedByLease(id configuration) {
    id identity = vpReadObject(configuration, "identity");
    return [vpReadObject(identity, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")];
}

static BOOL vpNotifyUIConfiguration(id scene, id configuration) {
    SEL selector = sel_registerName("_noteDisplayIdentityDidChangeWithConfiguration:");
    Method method = class_getInstanceMethod(object_getClass(scene), selector);
    if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@16") != 0) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(scene, selector, configuration);
    return YES;
}

static void vpSetUISceneConfigurations(id configuration, id displayConfiguration, id expected, id expectedDisplay, unsigned int generation) {
    id server = vpUIConfigServerScene;
    SEL update = sel_registerName("updateUISettingsWithBlock:");
    Method method = class_getInstanceMethod(object_getClass(server), update);
    if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@?16") != 0) {
        vpFoldDisplayLog(@"UI configuration: server settings-update ABI unavailable"); return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(server, update, ^(id settings) {
        if (generation != atomic_load_explicit(&vpUIConfigGeneration, memory_order_acquire) || server != vpUIConfigServerScene ||
            !vpUIObjectsEqual(vpReadObject(settings, "sb_hostedDisplayConfiguration"), expected) ||
            !vpUIObjectsEqual(vpReadObject(settings, "displayConfiguration"), expectedDisplay)) return;
        SEL setter = sel_registerName("sb_setHostedDisplayConfiguration:");
        Method method = class_getInstanceMethod(object_getClass(settings), setter);
        if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@16") != 0) return;
        SEL displaySetter = sel_registerName("setDisplayConfiguration:");
        NSMethodSignature *signature = [settings methodSignatureForSelector:displaySetter];
        // Generated settings accessors include @"FBSDisplayConfiguration"
        // in their encoding. Validate the semantic object ABI, not spelling.
        if (!signature || signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, "v") != 0 ||
            [signature getArgumentTypeAtIndex:2][0] != '@') return;
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(settings, displaySetter, displayConfiguration);
            ((void (*)(id, SEL, id))objc_msgSend)(settings, setter, configuration);
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: hosted/display transaction generation=%u actual=%@",
                generation, vpReadObject(vpReadObject(settings, "displayIdentity"), "uniqueIdentifier")]);
        } @catch (NSException *exception) {
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration transaction exception: %@", exception.reason]);
        }
    });
}

static void vpFinishUIConfigurationRestore(unsigned int generation, unsigned int attempt) {
    if (generation != atomic_load_explicit(&vpUIConfigGeneration, memory_order_acquire) || !vpUIConfigPublished) return;
    @try {
        id server = vpUIConfigServerScene;
        if (!server) {
            if (!vpRestoreUIScreenTraits()) return;
            vpUIConfigPublished = nil; vpUIConfigOriginalHosted = nil; vpUIConfigOriginalServerDisplay = nil; vpUIConfigOriginalUI = nil;
            vpUIOldStatusComponent = nil; vpUINewStatusComponent = nil; vpUIStatusComponentKey = nil;
            vpUIOldStatusWindow = nil; vpUIOldStatusWindowHidden = nil;
            vpUIStatusDetachedBeforeRollback = NO;
            vpUIConfigWindowScene = nil; vpUIConfigClientScene = nil; return;
        }
        id current = vpReadObject(vpReadObject(server, "uiSettings"), "sb_hostedDisplayConfiguration");
        id currentDisplay = vpReadObject(vpReadObject(server, "uiSettings"), "displayConfiguration");
        if (!vpUIObjectsEqual(current, vpUIConfigOriginalHosted) || !vpUIObjectsEqual(currentDisplay, vpUIConfigOriginalServerDisplay)) {
            if ((!vpUIObjectsEqual(current, vpUIConfigPublished) && !vpUIObjectsEqual(current, vpUIConfigOriginalHosted)) ||
                (!vpUIObjectsEqual(currentDisplay, vpUIConfigPublished) && !vpUIObjectsEqual(currentDisplay, vpUIConfigOriginalServerDisplay))) {
                vpFoldDisplayLog(@"UI configuration: newer hosted value preserved; checkpoint retained"); return;
            }
            vpSetUISceneConfigurations(vpUIConfigOriginalHosted, vpUIConfigOriginalServerDisplay, current, currentDisplay, generation);
        } else {
            id scene = vpUIConfigWindowScene;
            id liveIdentityBeforeRestore = vpReadObject(scene, "_fbsDisplayIdentity");
            BOOL uiOwnedBeforeRestore = vpUIConfigurationOwnedByLease(vpReadObject(scene, "_sbDisplayConfiguration")) ||
                [vpReadObject(liveIdentityBeforeRestore, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")];
            if (scene && vpReadObject(scene, "_FBSScene") == vpUIConfigClientScene && uiOwnedBeforeRestore)
                vpNotifyUIConfiguration(scene, vpUIConfigOriginalUI);
            id liveIdentity = vpReadObject(scene, "_fbsDisplayIdentity");
            BOOL uiStillOwned = scene && (vpUIConfigurationOwnedByLease(vpReadObject(scene, "_sbDisplayConfiguration")) ||
                [vpReadObject(liveIdentity, "uniqueIdentifier") isEqual:vpReadObject(vpReadObject(vpUIConfigPublished, "identity"), "uniqueIdentifier")]);
            if (!uiStillOwned && vpRestoreUIStatusComponent() && vpRestoreUIScreenTraits()) {
                vpUIConfigPublished = nil; vpUIConfigOriginalHosted = nil; vpUIConfigOriginalServerDisplay = nil; vpUIConfigOriginalUI = nil;
                vpUIConfigWindowScene = nil; vpUIConfigServerScene = nil; vpUIConfigClientScene = nil;
                vpFoldDisplayLog(@"UI configuration: original hosted/UI configuration verified"); return;
            }
        }
        if (attempt < 5) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 5), dispatch_get_main_queue(), ^{
            vpFinishUIConfigurationRestore(generation, attempt + 1);
        });
        else vpFoldDisplayLog(@"UI configuration: restore pending; checkpoint retained");
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration restore exception: %@", exception.reason]);
    }
}

void vpRestoreUIConfiguration(void) {
    vpRestoreStatusProfileLookup();
    @try { vpDetachUIStatusComponent(); } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration component detach exception: %@", exception.reason]);
    }
    unsigned int generation = atomic_fetch_add_explicit(&vpUIConfigGeneration, 1, memory_order_acq_rel) + 1;
    vpFinishUIConfigurationRestore(generation, 0);
}

void vpActivateUIConfiguration(void) {
    @try {
        id scene = vpUIConfigWindowScene;
        id current = vpReadObject(vpReadObject(vpUIConfigServerScene, "uiSettings"), "sb_hostedDisplayConfiguration");
        if (!scene || vpReadObject(scene, "_FBSScene") != vpUIConfigClientScene ||
            !vpUIConfigPublished || !vpUIObjectsEqual(current, vpUIConfigPublished)) {
            vpFoldDisplayLog(@"UI configuration: activation refused without current hosted lease"); return;
        }
        BOOL submitted = vpNotifyUIConfiguration(scene, vpUIConfigPublished);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: native client activation submitted=%d", submitted]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration activation exception: %@", exception.reason]);
    }
}

void vpPulseUIConfiguration(BOOL nonEmbedded) {
    @try {
        if (vpUIConfigPublished) { vpFoldDisplayLog(@"UI configuration: prior lease must restore first"); return; }
        id scene = vpMainInnerWindowScene();
        id root = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id monitor = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        if (!scene || ![vpReadObject(vpReadObject(scene, "_FBSScene"), "identifier") isEqual:@"SB-main"] ||
            !vpIsDuoInnerBounds(root) ||
            [vpReadObject(monitor, "alwaysConnectedIdentities") count] != 1) return;
        id candidate = nonEmbedded ? vpCreateNonEmbeddedUIConfiguration(root) : vpCreateUIConfiguration(root);
        id render = vpReadObject(root, "CADisplay");
        id identity = vpReadObject(candidate, "identity");
        if (!candidate || !render || vpReadObject(candidate, "CADisplay") != render ||
            ![vpReadObject(identity, "rootIdentity") isEqual:vpReadObject(root, "identity")] ||
            [[identity valueForKey:@"isUIKitMainLike"] boolValue] == nonEmbedded || [[identity valueForKey:@"isExternal"] boolValue]) return;
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        id server = nil;
        for (id candidateServer in vpRootServerScenes(app))
            if ([vpReadObject(candidateServer, "identifier") isEqual:@"SB-main"]) { server = candidateServer; break; }
        Method update = class_getInstanceMethod(object_getClass(server), sel_registerName("updateUISettingsWithBlock:"));
        id client = vpReadObject(scene, "_FBSScene");
        if (!client || !update || strcmp(method_getTypeEncoding(update), "v24@0:8@?16") != 0) {
            vpFoldDisplayLog(@"UI configuration: writable SB-main server unavailable"); return;
        }
        id settingsCopy = [vpReadObject(server, "uiSettings") mutableCopy];
        for (NSString *name in @[@"setDisplayConfiguration:", @"_setDisplayConfiguration:", @"setDisplayIdentity:"]) {
            SEL selector = NSSelectorFromString(name);
            BOOL available = [settingsCopy respondsToSelector:selector];
            Method method = available ? class_getInstanceMethod(object_getClass(settingsCopy), selector) : NULL;
            vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: mutable %@ %s ABI=%s",
                NSStringFromClass(object_getClass(settingsCopy)), name.UTF8String, method ? method_getTypeEncoding(method) : "unavailable"]);
        }
        vpUIConfigWindowScene = scene;
        vpUIConfigServerScene = server;
        vpUIConfigClientScene = client;
        vpUIConfigOriginalHosted = vpReadObject(vpReadObject(vpUIConfigServerScene, "uiSettings"), "sb_hostedDisplayConfiguration");
        vpUIConfigOriginalServerDisplay = vpReadObject(vpReadObject(vpUIConfigServerScene, "uiSettings"), "displayConfiguration");
        vpUIConfigOriginalUI = vpReadObject(scene, "_sbDisplayConfiguration") ?: root;
        vpUIConfigPublished = candidate;
        unsigned int generation = atomic_fetch_add_explicit(&vpUIConfigGeneration, 1, memory_order_acq_rel) + 1;
        vpSetUISceneConfigurations(candidate, candidate, vpUIConfigOriginalHosted, vpUIConfigOriginalServerDisplay, generation);
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration: ten-second hosted lease generation=%u", generation]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation == atomic_load_explicit(&vpUIConfigGeneration, memory_order_acquire)) vpRestoreUIConfiguration();
        });
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI configuration pulse exception: %@", exception.reason]);
    }
}

void vpPreviewUISceneConfiguration(void) {
    @try {
        id configuration = vpReadObject(objc_getClass("FBDisplayManager"), "mainConfiguration");
        id rootIdentity = vpReadObject(configuration, "identity");
        if (![[rootIdentity valueForKey:@"isMainRootDisplay"] boolValue]) return;
        NSArray *physicalBefore = vpReadObject(objc_getClass("CADisplay"), "displays");
        NSUInteger physicalCountBefore = physicalBefore.count;
        id monitor = vpReadObject(objc_getClass("FBDisplayManager"), "sharedInstance");
        id identitiesBefore = vpReadObject(monitor, "alwaysConnectedIdentities");
        NSUInteger connectedCountBefore = [identitiesBefore count];
        Class builderClass = objc_getClass("FBSDisplayConfigurationBuilder");
        Method setType = class_getInstanceMethod(builderClass, sel_registerName("setDisplayType:"));
        Method mainLike = class_getInstanceMethod(builderClass, sel_registerName("setUIKitMainLike"));
        if (!setType || strcmp(method_getTypeEncoding(setType), "v24@0:8q16") != 0 ||
            !mainLike || strcmp(method_getTypeEncoding(mainLike), "v16@0:8") != 0) return;
        id<VPhoneDisplayProjectionBuilding> builder = [(id<VPhoneDisplayProjectionBuilding>)[builderClass alloc] initWithConfiguration:configuration];
        [builder setUniqueIdentifier:@"vphone-duo-ui-preview"];
        // Unknown (7) is native-valid (type 2 is reserved/invalid). Retain
        // the integrated, nonexternal Main backing and mark the UI view main-like.
        [builder setDisplayType:7];
        [builder setUIKitMainLike];
        NSError *error = nil;
        id preview = [builder buildConfigurationWithError:&error];
        if (!preview) { vpFoldDisplayLog([NSString stringWithFormat:@"UI context preview build failed: %@", error]); return; }
        id identity = vpReadObject(preview, "identity");
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"isMainDisplay", @"isMainRootDisplay", @"isRootIdentity", @"isUIKitMainLike",
                                 @"isAlwaysConnected", @"isExternal", @"connectionType", @"type", @"displayID", @"uniqueIdentifier"])
            result[key] = [identity valueForKey:key] ?: NSNull.null;
        result[@"rootIdentity"] = vpReadObject(vpReadObject(identity, "rootIdentity"), "uniqueIdentifier") ?: NSNull.null;
        result[@"rootMatchesOriginal"] = @([vpReadObject(identity, "rootIdentity") isEqual:rootIdentity]);
        result[@"bounds"] = vpSnapshotRect(preview, "bounds");
        id originalRender = vpReadObject(configuration, "CADisplay");
        id previewRender = vpReadObject(preview, "CADisplay");
        result[@"renderAccessorAvailable"] = @(originalRender != nil && previewRender != nil);
        result[@"sameRenderDisplay"] = originalRender && previewRender ? @(originalRender == previewRender) : NSNull.null;
        result[@"caDisplayObjectCountBefore"] = @(physicalCountBefore);
        result[@"caDisplayObjectCountAfter"] = @([vpReadObject(objc_getClass("CADisplay"), "displays") count]);
        result[@"connectedCountBefore"] = @(connectedCountBefore);
        result[@"connectedCountAfter"] = @([vpReadObject(monitor, "alwaysConnectedIdentities") count]);
        id app = vpReadObject(objc_getClass("UIApplication"), "sharedApplication");
        for (id serverScene in vpRootServerScenes(app)) {
            if (![vpReadObject(serverScene, "identifier") isEqual:@"SB-main"]) continue;
            id original = vpReadObject(serverScene, "uiSettings");
            id copy = [original mutableCopy];
            Method setter = class_getInstanceMethod(object_getClass(copy), sel_registerName("sb_setHostedDisplayConfiguration:"));
            if (!copy || copy == original || !setter || strcmp(method_getTypeEncoding(setter), "v24@0:8@16") != 0) continue;
            ((void (*)(id, SEL, id))objc_msgSend)(copy, sel_registerName("sb_setHostedDisplayConfiguration:"), preview);
            result[@"originalHostedIdentity"] = vpReadObject(vpReadObject(vpReadObject(original, "sb_hostedDisplayConfiguration"), "identity"), "uniqueIdentifier") ?: NSNull.null;
            result[@"copiedHostedIdentity"] = vpReadObject(vpReadObject(vpReadObject(copy, "sb_hostedDisplayConfiguration"), "identity"), "uniqueIdentifier") ?: NSNull.null;
            result[@"originalFrame"] = vpSnapshotRect(original, "frame");
            result[@"copiedFrame"] = vpSnapshotRect(copy, "frame");
        }
        result[@"published"] = @NO;
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        if (data) vpFoldDisplayLog([@"UI context preview " stringByAppendingString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    } @catch (NSException *exception) {
        vpFoldDisplayLog([NSString stringWithFormat:@"UI context preview exception: %@", exception.reason]);
    }
}
