# 摩尔庄园 5.5.0 — 淘米开发者痕迹完整清单

> 通过逆向二进制(arm v7, 12 MB Mach-O)+ 资源文件分析,梳理出**淘米开发团队留在生产二进制里的所有痕迹**。包括:调试菜单 / 后门 / 私货代码 / 资源 / 服务器架构 / SDK / 拼写错误 / 团队泄露。
>
> 本文为汇总目录。详细分析见: [REVERSE_ENGINEERING.md](REVERSE_ENGINEERING.md) / [HIDDEN_FEATURES.md](HIDDEN_FEATURES.md) / [GOLDEN_ISLAND_FIX.md](GOLDEN_ISLAND_FIX.md) / `reverse/*.txt`

---

## 0. 项目元信息

| 项 | 值 | 备注 |
|---|---|---|
| 上线名 | MoleWorld (com.taomee.MoleWorld) | App 名 |
| **项目代号** | **iMoleVillage** | "摩尔村庄" — 类名/路径全是这个原代号 |
| AppDelegate 类 | `iMoleVillageAppDelegate` | 53 个方法 |
| 二进制大小 | 12,247,472 字节(11.7 MB) | armv7 |
| 编译 SDK | iPhoneOS 7.0 | DTSDKBuild 11B508 |
| Build | 5.5.0 | 2014 年代 |
| cryptid | 0 | 已脱壳 |

---

## 1. 调试菜单 / 测试面板(完整存在,可激活)

### 1.1 `TestLayer` ⭐⭐⭐⭐⭐ — 主调试面板

完整 cocos2d CCLayer,**34 个方法,18 对 ± 按钮**:

| 资源 | + 方法 | − 方法 |
|------|-------|-------|
| 经验 XP | `onButtonXPPlus:` | `onButtonXPMinus:` |
| 摩尔豆 Gold | `onButtonGoldPlus:` | `onButtonGoldMinus:` |
| 贝壳 VipGold | `onButtonVipGoldPlus:` | `onButtonVipGoldMinus:` |
| VIP 值 | `onButtonVipValuePlus:` | `onButtonVipValueMinus:` |
| 时间 Time | `onButtonTimePlus:` | `onButtonTimeMinus:` |
| 任务 Quest | `onButtonQuestPlus:` | `onButtonQuestMinus:` |
| 限时任务 | `onButtonTimeQuestPlus:` | `onButtonTimeQuestMinus:` |
| VIP 任务 | `onButtonVipQuestPlus:` | `onButtonVipQuestMinus:` |
| 食物 Food | `onButtonFoodPlus:` | `onButtonFoodMinus:` |
| 奖励券 Tickets | `onButtonTicketsPlus:` | `onButtonTicketsMinus:` |

入口:`[scene addChild:[[TestLayer alloc] init]]`

### 1.2 `NewSceneTestLayer` — 新场景版调试

精简版(13 方法),含 `onButtonbuildValuePlus:` 调建筑值。

### 1.3 `EasterEggMainLayer` + 秘密按钮系统

```
addTestLayerButton_     ← CCMenuItemSpriteIndependent(进 TestLayer 的入口)
isControlOpenSecretButton_ ← BOOL 控制秘密按钮显示
lightOpenSecretButton    ← 点亮秘密按钮的方法
```

正常玩家看不见这个按钮 — 受服务器控制是否启用。

### 1.4 `MagicNumberView` — 后门密码输入

需要服务器下发密码的客服后门。**服务器停服后无法获得正确密码**,但可 hook `onButtonYesSelected:` 让任意输入通过验证。

---

## 2. 程序员私货方法(明显的开发期遗留)

| 方法 | 类 | 类型 | 推测用途 |
|------|-----|-----|---------|
| **`myfuctiion`** ⭐ | MainMenu | void | typo (应 myfunction),程序员私人测试方法 |
| `testAnimation` | MainMenu | void | 0.5x 缩放动画测试(反汇编确认) |
| `shareInstance` | AchievementControl / MiniGameManager | + 类方法 | typo (应 sharedInstance) |
| `resetUserGameData` | GameData | void | **整库重置玩家数据**(危险) |
| `addTestSprite_` | UserInfoLayer | CCSprite* | 测试 sprite ivar |
| `onButtonHideTestLayerSelected:` | (UI 层) | | 隐藏 TestLayer 按钮 |
| `purgeShareInstance` | 多个类 | + 类方法 | 清理单例(测试用) |

---

## 3. 隐藏 NPC(代码完整,UI 入口被锁/隐藏)

实现 `ActivityResponder` 协议但玩家看不见的:

| NPC 类 | 含义 | 关键方法 |
|--------|------|---------|
| `WaterTower` | 水塔(可能是限时活动 NPC) | `onCommandReceived:` |
| `CrowPriest` | 乌鸦祭司(神秘 NPC) | 同 |
| `SuperShellTree` | 超级贝壳树 | 同 + `getShellTreeHarvestTimes` |
| `ChrismasTreeView` ⚠️ typo | 圣诞树(应为 Christmas) | 同 |

**召唤方式**:`[scene addChild:[[ClassName alloc] init]]` 直接显形。

---

## 4. 未上线 / 已下线联名活动 (13 个 + 多个 IP layer)

### Activity Responder 全集

```
AroundTheWorldActivityResponder    环游世界
AutumnActivityResponder            秋季活动
CaribbeanActivityResponder         加勒比海盗(俗称黄金岛)
EasterEggActivityResponder         复活节彩蛋
FlyKiteActivityResponder           春季放风筝
GreenRiceBallActivityResponder     清明青团
GuessWorldCupActivityResponder     2014 世界杯竞猜
HalloweenActivityResponder         万圣节
IceActivityResponder               冰雪/冬季
NaramSpringActivityResponder       Naram 春季
OpenTreasureChestActivityResponder 开宝箱
PopularItemsPKActivityResponder    热门物品 PK
SeabedSeekingTreasureActivityResponder 海底寻宝
SpringPoemActivityResponder        春诗
XmasActivityResponder              圣诞
```

### 完整联名 IP layer(20 个 *MainLayer)

| IP / 主题 | Layer 数 | 含义 |
|-----------|---------|------|
| **Alice 爱丽丝梦游仙境** | 8 | Disney 联动,完整 mini-game |
| **Shrek 怪物史莱克** | 3 | DreamWorks 联动 |
| **Totoro 龙猫** | 3 | **吉卜力联动** ⭐ |
| **FlameWars 火焰战争** | 7 | PK 玩法 + Top 10 排行 |
| **IceCream 冰激凌** | 4 | |
| **Xmas 圣诞** | 5+ | 投票/规则/奖励 |
| **新版商店** | NewStyleStoreMainLayer | 可能解锁更多商品 |
| **促销主层** | PromoteSalesMainLayer | 折扣商品 |
| **周年纪念** | AnniversaryMainLayer | |

---

## 5. Demo 数据(丝尔特庄园)

完整可用的 demo 庄园资源:

| 文件 | 大小 | 内容 |
|------|------|------|
| `xiaotulv_map` | 72 KB | 春季 Demo 地图 |
| `xiaotulv_userinfo` | 3 KB | Demo 用户信息 |
| `xiaotulv_winter_map` | 128 KB | **冬季雪景 Demo 地图** |
| `xiaotulv_winter_userinfo` | 1.5 KB | 冬季用户信息 |

**真实名字**:`xiaotulv` = "小兔绿"(拼音),玩家社区俗称"丝尔特"。

**加载入口**:
- `WrapperManager.showXiaoTuLvVillage`(标志位 setter,不是 UI)
- `GameData.loadMapdataFromResource:@"xiaotulv_map"` ⭐ 真正加载
- `GameData.loadUserInfoFromResource:@"xiaotulv_userinfo"`

---

## 6. SDK 测试模式入口

13+ 个第三方 SDK 都有自己的 testMode 开关:

| SDK | 用途 | 测试入口 |
|-----|------|---------|
| **AdMob** (Google) | 广告 | `GADObjectPrivate.adDebugDialog_` |
| **Flurry** | 数据分析 | testMode |
| **Inmobi** | 广告 | `IMAdRequest.testMode` |
| **DianRu (点入)** | 广告墙 | `cmd=getadwalllst` |
| **Tapjoy** | 激励视频 | testing 标志 |
| **Domob** | 国内广告 | r.ow.domob.cn |
| **Immob** | 广告 | api.immob.cn |
| **Cocounion** | 联运 | service.cocounion.com |
| **YouMi (有米)** | 广告墙 | `YMDevConfiguration._isTesting` |
| **Miidi (米米)** | 广告 SDK | `MiidiSdkProfile.setAppTestMode:` ⭐ |
| **TalkingData** | 数据分析 | `TDGADeviceProfile` |
| **Umeng (友盟)** | 数据分析 | testMode |
| **HockeyApp** | 崩溃报告 | (BWQuincyManager) |
| **NewRelic** | 性能监控 | `+[NewRelicAgentInternal engageTestMode]` ⭐ |
| **Atom (腾讯)** | QQ 登录 SDK | `atomTestMode` |

---

## 7. 服务器架构

### 7.1 淘米官方公网域名(`*.61.com`,因为儿童节 6/1)

```
account-mapi.61.com/account_service.php  HTTPS 账号 API
mlogin.61.com/ipsvr.fcgi                 动态登录 IP
imole.61.com/m                            iMole 短链
imolelogin.61.com:8080/dynamic/online.imole  登录服务器(8080 端口)
bbs.61.com                                论坛 + 会话
wlad.61.com / wlad2.61.com                广告(wireless ad)
wall.61.com                               广告墙
wlstat.61.com                             统计
dc.61.com                                 数据收集
mcdn.61.com                               CDN(/ad/2012060701/ 显示是 2012 资源)
pic1-bus.61.com                           图片 CDN
ipush.61.com/push.fcgi                    推送
m.61.com                                  移动入口
game.61.com/molecard                      摩尔卡(实体卡)
```

### 7.2 ⚠️ 内网开发服务器 IP(写死在生产二进制!)

```
http://10.1.1.27/ammy_project/expeprogram/wireless/wireless_info.php
http://10.1.1.27/ammy_project/webaccount/account_service.php
http://10.1.1.163/wlstat/index.php
http://10.1.1.57
http://211.151.121.43
http://211.151.105.139/wareless/wareless/ser/dumpfile.php
                       ↑↑↑ 双重拼写错误 wareless → wireless,且重复
```

`ammy_project` 是淘米某个内部项目代号。

---

## 8. 开发者源码路径泄露(团队画像)

| 路径前缀 | 推测人员 / 模块 |
|----------|---------------|
| `/Users/kevinwang/Documents/Projects/svn/TaomeeMobileLibrary/TaomeeIAPVerify/...` | **kevinwang** — iOS IAP 验证模块 |
| `/Users/kevinwang/.../CrashLog/Reachability/...` | kevinwang — 崩溃日志模块 |
| `/Users/andychen/Documents/TaomeeMobileLibrary/TaomeeAccount/TaomeeLogin/...` | **andychen** — 登录模块 |
| `/Users/delle/Documents/TaomeeMoreGame/...` | **delle** — 推广小游戏 |
| `/Users/ck04-011/Desktop/Work/SDK/` | 工号 **ck04-011** 的开发机 |
| `/TestProject/iMoleVillage/...` | **项目原代号路径** |
| `iMoleVillageAppDelegate` | 类名也证实 |

第三方 SDK 集成开发者:
- `/Users/Akshay/Downloads/plcrashreporter-...` — PLCrashReporter
- `/Users/andreaslinde/Sourcecode/OpenSource/PLCrashReporterGit/...`
- `/Users/ENZO/Work/YouMiSDK/...` — 有米 SDK
- `/Users/bamboo/bamboo-agent/.../TalkingData/...` — Bamboo CI 构建

**淘米团队画像**:至少 4 名 iOS 开发者(kevinwang/andychen/delle + 工号 ck04-011)+ 多个 SDK 集成 + Bamboo 持续集成 = 典型 2013-2014 年代国产手游团队。

---

## 9. 拼写错误档案 (Typo Hall of Shame) 📝

国产手游开发现场的"人味"档案(累计 17+ 处):

| Typo | 应为 | 出现位置 |
|------|------|---------|
| `Loacl` | Local | `usingLoaclServerForTestOnly` |
| `Fufill` | Fulfill | `atomReceivedRequestForDeveloperToFufill:` |
| `Recieve` | Receive | `TestLayer.onRecieveMessage:` |
| `Projectes` | Projects | `/Projectes/TaomeeAdWall/` |
| `wareless` | wireless | `211.151.105.139/wareless/wareless/`(还重复) |
| `Onekey` | OneKey | `Farm.harvestOnekey:` |
| `Charima` | Charisma | `getGoldByFriendsCharimaValue` |
| `Plaw` | Plow | `Farm.hireWorkerToPlawFarm:` |
| **`myfuctiion`** | myfunction | `MainMenu.myfuctiion` ⭐ 私货 |
| `shareInstance` | sharedInstance | `AchievementControl.shareInstance` |
| `Nearst` | Nearest | `MCNpcActor.findNearstMoles:` |
| `Boart` | Boat | `WashRoomGame.initSailingBoartAnimations` |
| `Achivement` | Achievement | `MiniGameManager.enterAchivement:` |
| `totle` | total | `CaribbeanDiscoveringData.totleDistance` |
| **`Chrismas`** | Christmas | `ChrismasTreeView` (整个类名错!) |
| `ARRIVALED` | ARRIVED | `CARIBBEAN_DESTINATION_ARRIVALED` |
| `Spacial` | Special | `spacialOjectId_` |

**集中出现说明**:没 code review、没静态分析、英语水平参差。

---

## 10. 反作弊系统

| 机制 | 类.方法 | 作用 |
|------|--------|------|
| **数据被篡改标志** | `GameData.isHackData` (BOOL readonly) | 检测到 hack 时置 YES |
| **数据被篡改(新场景)** | `NewSceneUserInfoData.isHackData` (BOOL) | 同上 |
| **作弊警告 UI** | `WrapperManager.showCheatWarningMessage` | 弹警告 |
| **MD5 校验** | `NewSceneData.checkUserinfoMd5:` | 校验存档完整性 |
| **数据校验** | `NewSceneData.CheckUserInfoData:` | |
| **VIP/等级加密** | `UserInfoData.encryptVipGold` / `encryptCurLevel` | 反复加密做完整性校验 |
| **IAP 越狱检测** | `InAppPurchaseManager.checkRightInJailBroken:` | 越狱用户特殊处理 |
| **IAP 越狱超时** | `InAppPurchaseManager.onCheckIAPTimeoutForJailBrokenUser` | |
| **越狱检测** | `isJailBroken` / `deviceIsJailBroken` | 检查 `/Library/MobileSubstrate/DynamicLibraries/iap.dylib` 等路径 |

---

## 11. 一键 Reset / Clear / Award 方法集

### Reset 方法(GameData)

```
resetUserGameData                    ⚠️ 整库重置
resetUnfinishedDailyQuestDataInMap   重置每日任务
resetTimeQuestDataInMap              重置限时任务
resetVipQuestDataInMap               重置 VIP 任务
resetLastGetDailyRewardDay           重置签到记录
resetDailyQuestList                  重置每日任务列表
resetDailySignExchangeData           重置签到兑换
resetTreasureChestData               重置宝箱数据
resetCaribbeanData                   重置加勒比(黄金岛)
resetVipRewardData                   重置 VIP 奖励
resetTaomeeUserInfoData              重置淘米用户信息
```

### Add Reward 方法(GameManager)

```
addTreasureReward                    给宝藏奖励(队列空则不发)
addTreasureRabbitReward              给宝藏兔奖励
addAliceActivityRewardToMap:num:     爱丽丝活动奖励
addIceCreamActivityRewardToMap:num:  冰激凌活动奖励
addXmasActivityRewardToMap:...       圣诞奖励
```

### Set 方法(直接覆盖资源)

```
GameData.setRewardTickets:(int)      设奖励券
UserInfoData.setGold:(int)           摩尔豆
UserInfoData.setVipGold:(int)        贝壳
UserInfoData.setXp:(int)             经验
UserInfoData.setCurLevel:(int)       等级
UserInfoData.setTotalRooms:(int)     房间数
UserInfoData.setTotalWorkers:(int)   工人数
UserInfoData.setAvatarIcon:(int)     头像 ID
UserInfoData.setName:(NSString*)     昵称
UserVIPInfoData.setVipLevel:(uint)   VIP 等级
```

### Unlock 方法

```
WrapperManager.unlockItem:(int)      解锁物品 ID
WrapperManager.isUnlockedItem:(int)  查询是否解锁
GameData.unlockObjects               已解锁字典
```

---

## 12. Mini 游戏(6 个)

```
BugGame          抓虫
DivineGame       占卜(每日运势)
FishingGame      钓鱼
MinerGame        挖矿
PaintingGame     涂鸦/绘画
WashRoomGame     洗澡 ⭐(类内有 initSailingBoartAnimations,典型组合彩蛋)
```

启动:`[MiniGameManager.shareInstance startMiniGame:gameId playType:0 callbackTarget:nil select:NULL]`

---

## 13. 服务器关闭功能修复路径(本地复活的)

| 功能 | 修复方法 |
|------|---------|
| **黄金岛(加勒比)** | hook `GameData.caribbeanData` 返回本地构造的 `CaribbeanDiscoveringData` |
| **爱丽丝/史莱克/龙猫** 等联名 | 直接 `[scene addChild:[[Activity_X_MainLayer alloc] init]]` |
| **丝尔特 demo** | `loadMapdataFromResource:` + `loadUserInfoFromResource:` |
| **VIP 检查** | hook `WrapperManager.checkIsVipUser` + `GameData.getVipInfoDataOfCurrentUser` |
| **内购成功** | hook `SKPaymentTransaction.transactionState` → 1 (Purchased) |
| **彩蛋秘密按钮** | 改 `EasterEggMainLayer.isControlOpenSecretButton_` ivar = 1 |

---

## 14. 资源文件分布

```
.app/
├── MoleWorld                     12 MB 二进制
├── Info.plist                    Bundle Info
├── 70+ 个 *.dat                  关卡 / 物品数据
├── AvatarIcons.plist             61 个头像 ID 表
├── Background.plist              背景配置
├── ObjectColor.plist             物品色彩
├── BugiPad.plist                 抓虫 mini 游戏数据
├── BGM_001~015.mp3              背景音乐(12 首)
├── EFFECT_001~107.mp3           音效(数十)
├── FX_006.mp3                    巨型音效(1 MB)
├── xiaotulv_map / userinfo       春季 Demo 庄园 ⭐
├── xiaotulv_winter_map / userinfo 冬季 Demo 庄园 ⭐
├── christmas_star_*              圣诞节资源
├── farmquest.dat / farmquestHV.dat  农场任务
├── DailyQuest.dat / DailyQuestHV.dat  每日任务
├── levelupHV.dat                 升级数据
└── 数千个 .png 图片资源
```

---

## 15. 已实施 Tweak 功能映射(到 v19)

把上述发现转化为 60+ 个可玩功能,完整列表见 `Tweak.xm` 头部 v1-v19 注释。最大类别:

| Section | 功能数 |
|---------|--------|
| 玩家数值修改(摩尔豆/贝壳/经验/等级 + slider 倍率) | 9 |
| 作物 / 建筑 / 冷却 时间加速 | 6 |
| VIP 强制激活 + 8 个 hook 协同 | 5 |
| IAP 假交易 (8 个 hook) | 8 |
| 反作弊关闭 / 隐藏点位 / NSLog 重定向 | 3 |
| TestLayer 18 对 ± 直调 | 36 按钮 |
| 18 个隐藏 NPC / Layer 召唤 | 18 |
| 14 个联名活动召唤 | 14 |
| 一键任务/签到重置(8 个) | 8 |
| 时间魔法节日触发(4 节日 + 自定义) | 5 |
| 丝尔特 Demo 庄园(春/冬 + 克隆) | 3 |
| 6 mini 游戏直接启动器 | 6 |
| 程序员私货 (myfuctiion / testAnimation) | 2 |
| 全部物品 / 成就解锁 | 2 |

---

## 16. 项目年表(从二进制推断)

| 时间 | 证据 |
|------|------|
| 2012 | `mcdn.61.com/ad/2012060701/` 资源时间戳 |
| 2013 | iOS 7 SDK 编译,主开发期 |
| 2014 | `GuessWorldCupActivityResponder` 暗示巴西世界杯 |
| 2014-上半 | `xiaotulv_winter` 冬季资源 |
| 服务器停服 | 推测 2018 年左右 — 所有 *.61.com 已无响应 |

---

## 一句话总结

**淘米《摩尔庄园》5.5.0 是一份高度凝缩的 2013-2014 年代中国手游工业化产物**:13+ 个广告/统计 SDK 堆叠、20+ 个未上线联名活动代码、至少 17 处拼写错误、4 名程序员私货遗留、内网 IP 写死生产二进制、完整测试调试面板可被本地激活、客服后门密码系统服务器停服后失效但可旁路、反作弊机制全套但都可被 hook。

整个游戏代码就像一份**未删减的工程师档案**,把整个开发组的水平、习惯、IP 资源、SDK 选型策略、bug 修补痕迹完整保留下来。

---

*报告版本: v19 同期(2026-05-07)*
*配套文档: REVERSE_ENGINEERING.md / HIDDEN_FEATURES.md / GOLDEN_ISLAND_FIX.md*
