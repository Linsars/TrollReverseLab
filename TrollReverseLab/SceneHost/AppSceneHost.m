//
//  AppSceneHost.m
//  TrollReverseLab
//
//  真后台 scene 托管实现。核心序列移植自 ImmortalizerTS (GPL v3, Serge Alagon)
//  的 ViewController.initializeNewSceneForBundleId —— 改动：
//  - 多场景 app 的 UIAlertController 改为静默自动 kill+重建（TRL 无该 UI 流）
//  - 托管完成自动开浮动窗（ITS 需点按/长按才显示）
//  - 生命周期收敛为单例引擎，供 Swift 侧 frida attach 联动
//

#import "AppSceneHost.h"
#import "ExternalAppSceneView.h"
#include <signal.h>
#include <sys/wait.h>
#include <dlfcn.h>

// 包内版本标记串（IPA 验证用，与 project.yml MARKETING_VERSION 对应）
static const char *kSceneHostVersion = "scene-host-6.4.7";

@implementation SceneHostApp
- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name {
    self = [super init];
    if (self) {
        _bundleId = [bundleId copy];
        _name = [name copy];
    }
    return self;
}
@end

@interface AppSceneHost () <ExternalAppSceneView>
@property (nonatomic, strong) NSMutableDictionary<NSString *, FBScene *> *scenesByBundleId;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIMutableApplicationSceneSettings *> *settingsByBundleId;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ExternalAppSceneView *> *windowsByBundleId;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *appNames;
@property (nonatomic, assign) BOOL hostInProgress;
@end

@implementation AppSceneHost

/* Xcode 16 的 iOS SDK 删了 PrivateFrameworks——链接走空壳 TBD stub + dynamic_lookup，
   运行时先把 4 个私有框架 dlopen 进来，_OBJC_CLASS_$_ 引用才能在首次使用时解析 */
static void loadPrivateFrameworks(void) {
    static const char *paths[] = {
        "/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard",
        "/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",
        "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        (void)dlopen(paths[i], RTLD_LAZY);   // 失败容忍（私有类引用处有 nil 检查）
    }
}

+ (instancetype)shared {
    static AppSceneHost *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[AppSceneHost alloc] init];
        loadPrivateFrameworks();
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _scenesByBundleId = [NSMutableDictionary dictionary];
        _settingsByBundleId = [NSMutableDictionary dictionary];
        _windowsByBundleId = [NSMutableDictionary dictionary];
        _appNames = [NSMutableDictionary dictionary];
        NSLog(@"[scene-host] %s ready", kSceneHostVersion);
    }
    return self;
}

#pragma mark - App list (LS 数据库，同 ImmortalizerTS 过滤规则)

- (NSArray<SceneHostApp *> *)installedApps {
    NSMutableArray<SceneHostApp *> *result = [NSMutableArray array];
    NSArray *allApps = [LSApplicationWorkspace.defaultWorkspace allInstalledApplications];
    NSString *selfBid = [[NSBundle mainBundle] bundleIdentifier];
    for (LSApplicationProxy *app in allApps) {
        BOOL isUser = [app.applicationType isEqualToString:@"User"];
        BOOL isSystemUsable = [app.applicationType isEqualToString:@"System"] &&
                              ![app.appTags containsObject:@"hidden"] &&
                              !app.launchProhibited && !app.placeholder && !app.removedSystemApp;
        if (!isUser && !isSystemUsable) continue;
        if ([app.bundleIdentifier isEqualToString:selfBid]) continue;   // 自己不能托管自己
        [result addObject:[[SceneHostApp alloc] initWithBundleId:app.bundleIdentifier
                                                            name:app.localizedName ?: app.bundleIdentifier]];
    }
    [result sortUsingComparator:^NSComparisonResult(SceneHostApp *a, SceneHostApp *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return result;
}

- (UIImage *)iconForBundleId:(NSString *)bundleId {
    return [UIImage _applicationIconImageForBundleIdentifier:bundleId format:0 scale:3];
}

- (LSApplicationProxy *)proxyForBundleId:(NSString *)bundleId {
    NSArray *allApps = [LSApplicationWorkspace.defaultWorkspace allInstalledApplications];
    for (LSApplicationProxy *app in allApps) {
        if ([app.bundleIdentifier isEqualToString:bundleId]) return app;
    }
    return nil;
}

#pragma mark - Host lifecycle

- (void)hostAppWithBundleId:(NSString *)bundleId
                    appName:(NSString *)appName
                      ready:(SceneHostReadyBlock)ready
                       fail:(SceneHostFailBlock)fail {
    FBScene *existing = self.scenesByBundleId[bundleId];
    if (existing) {
        [self showWindowForBundleId:bundleId];
        if (ready) ready(existing.clientProcess.pid, bundleId, self.appNames[bundleId] ?: appName);
        return;
    }
    if ([bundleId isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        if (fail) fail(@"不能托管 TRL 自身");
        return;
    }
    if (self.hostInProgress) {
        if (fail) fail(@"上一次托管还没完成");
        return;
    }
    LSApplicationProxy *proxy = [self proxyForBundleId:bundleId];
    if (!proxy) {
        if (fail) fail(@"应用不存在");
        return;
    }
    self.hostInProgress = YES;
    BOOL running = [self pidForBundleId:bundleId] > 0;
    NSLog(@"[scene-host] %s: hosting %@ (running=%d)", kSceneHostVersion, bundleId, running);
    [self initializeNewSceneForProxy:proxy
                             bundleId:bundleId
                             appName:appName
                           firstLaunch:!running
                               ready:ready
                                fail:fail
                         relaunchCount:0];
}

/* where magic happens —— 序列与 ImmortalizerTS 一致 */
- (void)initializeNewSceneForProxy:(LSApplicationProxy *)proxy
                           bundleId:(NSString *)bundleId
                           appName:(NSString *)appName
                         firstLaunch:(BOOL)firstLaunch
                               ready:(SceneHostReadyBlock)ready
                                fail:(SceneHostFailBlock)fail
                         relaunchCount:(int)relaunchCount {
    if (firstLaunch) {
        [UIApplication.sharedApplication launchApplicationWithIdentifier:bundleId suspended:NO];
    }

    RBSProcessIdentity *identity = [RBSProcessIdentity identityForEmbeddedApplicationIdentifier:bundleId];
    RBSProcessPredicate *predicate = [RBSProcessPredicate predicateMatchingIdentity:identity];
    FBProcessManager *manager = [FBProcessManager sharedInstance];

    FBApplicationProcessLaunchTransaction *transaction =
        [[FBApplicationProcessLaunchTransaction alloc] initWithProcessIdentity:identity
                                                        executionContextProvider:^id(void) {
            FBMutableProcessExecutionContext *context = [FBMutableProcessExecutionContext new];
            context.identity = identity;
            context.environment = @{};
            context.launchIntent = 4;   // 前台
            return [manager launchProcessWithContext:context];
        }];

    __weak typeof(self) weakSelf = self;
    [transaction setCompletionBlock:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        RBSProcessHandle *processHandle = [RBSProcessHandle handleForPredicate:predicate error:nil];
        if (processHandle) {
            [manager registerProcessForAuditToken:processHandle.auditToken];
        }

        FBSMutableSceneDefinition *definition = [FBSMutableSceneDefinition definition];
        definition.identity = [FBSSceneIdentity identityForIdentifier:[self sceneIdentifierForBundleId:bundleId]];
        definition.clientIdentity = [FBSSceneClientIdentity identityForProcessIdentity:identity];
        definition.specification = [UIApplicationSceneSpecification specification];

        UIMutableApplicationSceneSettings *settings = [UIMutableApplicationSceneSettings new];
        settings.canShowAlerts = YES;
        settings.displayConfiguration = [UIScreen mainScreen].displayConfiguration;
        settings.foreground = YES;
        settings.backgrounded = NO;
        settings.frame = [UIScreen mainScreen].bounds;

        UIEdgeInsets defaultInset = UIEdgeInsetsZero;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindow *window = scene.windows.firstObject;
                defaultInset = window.safeAreaInsets;
                break;
            }
        }
        settings.peripheryInsets = defaultInset;
        settings.safeAreaInsetsPortrait = defaultInset;
        settings.level = 1;
        settings.persistenceIdentifier = NSUUID.UUID.UUIDString;

        FBSMutableSceneParameters *parameters = [FBSMutableSceneParameters parametersForSpecification:definition.specification];
        parameters.settings = settings;

        UIMutableApplicationSceneClientSettings *clientSettings = [UIMutableApplicationSceneClientSettings new];
        clientSettings.interfaceOrientation = UIInterfaceOrientationPortrait;
        clientSettings.statusBarStyle = 0;
        parameters.clientSettings = clientSettings;

        self.scenesByBundleId[bundleId] =
            [[FBSceneManager sharedInstance] createSceneWithDefinition:definition initialParameters:parameters];
        self.settingsByBundleId[bundleId] = settings;
        self.appNames[bundleId] = appName;

        if (!firstLaunch) {
            /* 重建完成（多场景 app 的第二轮）：开窗 + 上报 pid */
            self.hostInProgress = NO;
            [self showWindowForBundleId:bundleId];
            int32_t pid = self.scenesByBundleId[bundleId].clientProcess.pid;
            NSLog(@"[scene-host] relaunch done: %@ pid=%d", bundleId, pid);
            if (ready) ready(pid, bundleId, appName);
            return;
        }

        /* 多场景检测（固定 1s 延迟取 scene layer，同原文） */
        FBSceneLayerManager *layermanager = self.scenesByBundleId[bundleId].layerManager;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            FBScene *scene = self.scenesByBundleId[bundleId];
            if (!scene) return;
            FBSceneLayer *scenelayer = (layermanager.layers.count > 0) ? [layermanager.layers objectAtIndex:0] : nil;
            if (scenelayer && scenelayer.level != 10) {
                /* 多场景 app：只保留 TRL 里创建的这一个 scene → 杀进程后重建 */
                NSLog(@"[scene-host] %@ multi-scene: auto kill+relaunch (count=%d)", bundleId, relaunchCount);
                if (relaunchCount >= 1) {
                    self.hostInProgress = NO;
                    [self releaseAppWithBundleId:bundleId];
                    if (fail) fail(@"多场景应用重建失败");
                    return;
                }
                int32_t oldPid = scene.clientProcess.pid;
                [[FBSceneManager sharedInstance] destroyScene:[self sceneIdentifierForBundleId:bundleId] withTransitionContext:nil];
                [self.scenesByBundleId removeObjectForKey:bundleId];
                [self killAppWithPid:oldPid completion:^{
                    [self initializeNewSceneForProxy:proxy
                                             bundleId:bundleId
                                             appName:appName
                                           firstLaunch:NO
                                               ready:ready
                                                fail:fail
                                         relaunchCount:relaunchCount + 1];
                }];
            } else {
                /* 单场景：直接完成 */
                self.hostInProgress = NO;
                [self showWindowForBundleId:bundleId];
                int32_t pid = scene.clientProcess.pid;
                NSLog(@"[scene-host] hosted: %@ pid=%d", bundleId, pid);
                if (ready) ready(pid, bundleId, appName);
            }
        });
    }];

    [transaction begin];
}

- (NSString *)sceneIdentifierForBundleId:(NSString *)bundleId {
    return [NSString stringWithFormat:@"sceneID:%@-%@", bundleId, @"default"];
}

#pragma mark - Window

- (void)showWindowForBundleId:(NSString *)bundleId {
    FBScene *scene = self.scenesByBundleId[bundleId];
    if (!scene || self.windowsByBundleId[bundleId]) return;
    ExternalAppSceneView *view =
        [[ExternalAppSceneView alloc] initExternalWindowWithScene:scene
                                                       withAppName:self.appNames[bundleId] ?: bundleId
                                                       withSettings:self.settingsByBundleId[bundleId]];
    view.delegate = self;
    self.windowsByBundleId[bundleId] = view;
}

- (void)hideWindowForBundleId:(NSString *)bundleId {
    ExternalAppSceneView *view = self.windowsByBundleId[bundleId];
    if (!view) return;
    [view closeWindow:nil];
}

- (void)removePresentedSceneByBundleId:(NSString *)bundleId {
    /* ExternalAppSceneView 浮动窗被关闭：场景继续托管，app 继续活 */
    self.windowsByBundleId[bundleId] = nil;
    NSLog(@"[scene-host] window closed, %@ stays alive", bundleId);
}

#pragma mark - Release

- (void)releaseAppWithBundleId:(NSString *)bundleId {
    int32_t pid = [self pidForBundleId:bundleId];
    FBScene *scene = self.scenesByBundleId[bundleId];

    /* 强制释放：不 walk closeWindow（其动画 completion 会 updateSettings 已销毁的场景）——
       直接丢引用，view→binder→UIRootSceneWindow 引用链整体释放 */
    [self.windowsByBundleId removeObjectForKey:bundleId];

    if (scene) {
        [[FBSceneManager sharedInstance] destroyScene:scene.identifier withTransitionContext:nil];
        [self.scenesByBundleId removeObjectForKey:bundleId];
        [self.settingsByBundleId removeObjectForKey:bundleId];
        [self.appNames removeObjectForKey:bundleId];
    }
    if (pid > 0) {
        [self killAppWithPid:pid completion:nil];
    }
    self.hostInProgress = NO;
    NSLog(@"[scene-host] released %@ (pid=%d)", bundleId, pid);
}

#pragma mark - Helpers

- (int32_t)pidForBundleId:(NSString *)bundleId {
    FBScene *scene = self.scenesByBundleId[bundleId];
    if (scene && scene.valid) return scene.clientProcess.pid;
    RBSProcessIdentity *identity = [RBSProcessIdentity identityForEmbeddedApplicationIdentifier:bundleId];
    RBSProcessPredicate *predicate = [RBSProcessPredicate predicateMatchingIdentity:identity];
    RBSProcessHandle *handle = [RBSProcessHandle handleForPredicate:predicate error:nil];
    return handle ? handle.pid : 0;
}

- (BOOL)isHosted:(NSString *)bundleId {
    return self.scenesByBundleId[bundleId] != nil;
}

- (NSString *)hostedAppName:(NSString *)bundleId {
    return self.appNames[bundleId];
}

/* 同 ImmortalizerTS：SIGTERM + 轮询 + 收尸 */
- (void)killAppWithPid:(int32_t)pid completion:(void (^)(void))completion {
    kill(pid, SIGTERM);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int status;
        BOOL isRunning = YES;
        int tries = 0;
        while (isRunning && tries < 30) {   // 最多等 3s，卡死也放行后续流程
            isRunning = (kill(pid, 0) == 0);
            if (isRunning) {
                usleep(100000);
                tries++;
            }
        }
        if (tries >= 30) {
            kill(pid, SIGKILL);
        }
        waitpid(pid, &status, 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion();
        });
    });
}

@end
