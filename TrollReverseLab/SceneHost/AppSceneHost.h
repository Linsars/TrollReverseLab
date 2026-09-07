//
//  AppSceneHost.h
//  TrollReverseLab
//
//  Scene-host 真后台引擎：用 FrontBoard 私有 API 把目标 app 的前台 scene
//  托管进 TRL 的 root 窗口 → 目标进程保持前台状态 → 不被 jetsam 回收。
//
//  核心机制移植自 ImmortalizerTS (Serge Alagon, GPL v3):
//  https://github.com/sergealagon/ImmortalizerTS
//  见 NOTICE.txt 的许可证与署名。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_SWIFT_NAME(SceneHostApp)
@interface SceneHostApp : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *name;
- (instancetype)initWithBundleId:(NSString *)bundleId name:(NSString *)name;
@end

typedef void (^SceneHostReadyBlock)(int32_t pid, NSString *bundleId, NSString *appName);
typedef void (^SceneHostFailBlock)(NSString *message);

NS_SWIFT_NAME(AppSceneHost)
@interface AppSceneHost : NSObject

+ (instancetype)shared;

/// 全部可托管应用（LS 数据库：商店+巨魔+自装，过滤隐藏/系统占位）
- (NSArray<SceneHostApp *> *)installedApps;
- (UIImage *)iconForBundleId:(NSString *)bundleId;

/// 真后台托管启动：FB 前台 launch + 场景托管 + 浮动窗自动显示。
/// ready 在目标 pid 可用时触发（主线程）。
- (void)hostAppWithBundleId:(NSString *)bundleId
                    appName:(NSString *)appName
                      ready:(SceneHostReadyBlock)ready
                       fail:(SceneHostFailBlock)fail;

/// 关闭浮动窗（目标进程继续活着）
- (void)hideWindowForBundleId:(NSString *)bundleId;
/// 重新显示浮动窗
- (void)showWindowForBundleId:(NSString *)bundleId;

/// 释放：销毁场景 + 杀目标进程（= 用户划掉语义）
- (void)releaseAppWithBundleId:(NSString *)bundleId;

- (int32_t)pidForBundleId:(NSString *)bundleId;
- (BOOL)isHosted:(NSString *)bundleId;
- (NSString *)hostedAppName:(NSString *)bundleId;

@end
