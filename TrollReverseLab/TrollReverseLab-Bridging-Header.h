//
//  TrollReverseLab-Bridging-Header.h
//  TrollReverseLab
//
//  Exposes the frida-core C bridge (and devkit headers) to Swift.
//  Configured via SWIFT_OBJC_BRIDGING_HEADER in project.yml.
//

#import "FridaCoreBridge.h"
#import "frida-core.h"

// Scene-host 真后台引擎（移植自 ImmortalizerTS, GPL v3, 见 SceneHost/NOTICE.txt）
#import "SceneHost/PrivateHeaders.h"
#import "SceneHost/AppSceneHost.h"
