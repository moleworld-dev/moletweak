# 摩尔庄园 5.5.0 iOS 逆向研究报告

> 二进制路径: `extracted_550/Payload/MoleWorld.app/MoleWorld`
> 架构: ARM v7 (32-bit), Mach-O thin
> 编译器: clang.1_0, SDK iphoneos7.0
> Bundle ID: `com.taomee.MoleWorld`
> 版本: 5.5.0
> 加密状态: cryptid 0(已脱壳)
> 配套数据 dump 在 `reverse/` 目录

本报告记录了对淘米《摩尔庄园》5.5.0 iOS 版二进制的逆向分析,重点是淘米程序员留下的**开发者隐藏菜单、调试入口、后门密码系统、反作弊机制**等。所有结论可在 `reverse/*.txt` 的原始 dump 中复核。

---

## 1. 程序员埋的 5 大后门系统

| 系统 | 关键类 | 状态 | 玩家原本如何触发 |
|------|--------|------|------------------|
| **A. TestLayer 调试菜单** | `TestLayer` | 现成可用 | 通过秘密按钮 → MagicNumber 验证 → 弹出 |
| **B. NewSceneTestLayer 新场景调试** | `NewSceneTestLayer` | 现成可用 | 同上,新场景版 |
| **C. MagicPassword 后门** | `GameData` + `MagicNumberView` + `NetworkManager` | **服务器停服后失效** | 服务器下发密码 → 玩家输入相同数字 → 通过 |
| **D. 秘密按钮显形** | `EasterEggMainLayer` | 默认隐藏 | `isControlOpenSecretButton_` 被某条件置 1 |
| **E. 反作弊检测** | `GameData` + `WrapperManager` | 默认运行 | 检测到 hack 数据时弹警告 |

---

## 2. MagicPassword 后门 —— 完整逆向

### 2.1 数据归属

```
GameData                      ← 持久化的游戏全局数据单例
  ├─ NSString *magicPassword_  (offset 0xa708, attr "T@\"NSString\",&,N,VmagicPassword_")
  ├─ - (NSString *)magicPassword
  └─ - (void)setMagicPassword:(NSString *)password

MagicNumberView : CCLayer/UIView ← 玩家输入数字的弹窗
  ├─ id <MagicNumberDelegate> magicNumberDelegate (ivar offset 236)
  ├─ - (id)init
  ├─ - (void)doClose
  ├─ - (void)flashScreen / callbackflash      ← 错误时屏幕闪烁
  ├─ - (void)takeScreenshot:(float)            ← 答错时截屏(取证?)
  ├─ - (void)onButtonYesSelected:(id)          ← 确定按钮 → 比对密码
  ├─ - (void)onButtonNoSelected:(id)           ← 取消按钮
  └─ - (void)onImageSavedToPhotosAlbum:didFinishSavingWithError:contextInfo:

NetworkManager                ← 网络层
  ├─ - (void)getMagicPasswordFromServer       ← 请求服务器下发
  └─ - (int)parseMagicPassword:pos:len:       ← 解析服务器响应
```

### 2.2 工作流程(原版)

```
玩家点击秘密按钮
   ↓
[NetworkManager getMagicPasswordFromServer]
   ↓ TCP 上行
服务器(已停服)生成密码字符串
   ↓ TCP 下行
[NetworkManager parseMagicPassword:pos:len:] 解析
   ↓
[GameData setMagicPassword:@"xxxx"]  ← 密码存入全局
   ↓
弹出 MagicNumberView 让玩家输入
   ↓
玩家输入 → onButtonYesSelected:
   ↓
内部比对 输入 == [GameData magicPassword]
   ↓ 成功
[delegate onMagicNumberFinished]  ← 触发后门激活
   ↓ 失败
flashScreen + takeScreenshot:  ← 屏幕闪 + 偷偷截屏
```

### 2.3 现状

**服务器停服后此后门源头永久失效**:
- `getMagicPasswordFromServer` 发出请求无响应
- `magicPassword_` 永远是 nil 或空串
- 即使玩家发现秘密按钮也无法获得正确密码

### 2.4 截屏取证机制(细节有意思)

`MagicNumberView.takeScreenshot:` 配合 `onImageSavedToPhotosAlbum:didFinishSavingWithError:contextInfo:` —— 这是 iOS 标准的"保存到相册"回调签名,说明**密码答错时,游戏会偷偷把屏幕保存到玩家相册**(可能是给客服查看?或者是 Easter Egg 无关字段)。

### 2.5 Tweak 旁路方案

参考 `Tweak.xm` 中 `%hook MagicNumberView - onButtonYesSelected:`:
- 跳过原密码比对
- 直接调用 `[delegate onMagicNumberFinished]`
- 调用 `[self doClose]` 关闭面板

**这意味着只要弹出 `MagicNumberView` 输入随便几个数字按确定就能通过**——但前提是有触发 `MagicNumberView` 显现的入口(参见秘密按钮章节)。

---

## 3. TestLayer —— 完整调试菜单

`reverse/TestLayer.txt` 是完整 dump。下面是结构化整理。

### 3.1 类信息

| 项 | 值 |
|----|-----|
| 类名 | `TestLayer` |
| 父类 | 推测 cocos2d `CCLayer`(instanceSize 300,远超 NSObject) |
| 实例大小 | 300 字节 |
| 方法数 | 34 |
| ivar 数 | 16 |
| 入口方法 | `- (id)init`(无参数) |

### 3.2 ivar 内存布局

| Offset | Name | Type | 用途 |
|--------|------|------|------|
| 236 | `labelxp` | CCLabelTTF* | 经验显示 |
| 240 | `labelgold` | CCLabelTTF* | 摩尔豆显示 |
| 244 | `labelvipgold` | CCLabelTTF* | 贝壳(VIP金币)显示 |
| 252 | `labelquestid` | CCLabelTTF* | 普通任务 ID |
| 248 | `labeltime` | CCLabelTTF* | 时间值 |
| 256 | `labeltimequestid` | CCLabelTTF* | 限时任务 ID |
| 264 | `labelvipquestid` | CCLabelTTF* | VIP 任务 ID |
| 260 | `labelVipValue` | CCLabelTTF* | VIP 值 |
| 268 | `labelFoodPrints` | CCLabelTTF* | 食物分数 |
| 272 | `labelRewardTickets` | CCLabelTTF* | 奖励券 |
| 276 | `time_` | int | 当前时间值 |
| 280 | `questId_` | int | 当前选中任务 ID |
| 284 | `timequestId_` | int | 限时任务 ID |
| 288 | `vipquestId_` | int | VIP 任务 ID |
| 292 | `foodsNum_` | int | 食物数量 |
| 296 | `rewardTickets_` | int | 奖励券数量 |

### 3.3 方法分类

#### 生命周期 + UI
- `- (id)init` —— 构造,搭建 UI
- `- (void)dealloc`
- `- (void)updateUI` —— 刷新所有 label
- `- (void)updateTime` —— 更新时间显示
- `- (void)onRecieveMessage:(id)` —— 通知接收(注意拼写错误 Recieve)

#### Getter(用于读当前调整步长)
- `- (int)getXPChangeValue`
- `- (int)getGoldChangeValue`
- `- (int)getVipGoldChangeValue`
- `- (int)getVipValueChangeValue`
- `- (int)getTimeChangeValue`

#### 18 对加减按钮处理(完整)

| 资源 | + 按钮 | − 按钮 | 触摸事件 |
|------|--------|--------|----------|
| XP 经验 | `onButtonXPPlus:` | `onButtonXPMinus:` | — |
| Gold 摩尔豆 | `onButtonGoldPlus:` | `onButtonGoldMinus:` | — |
| VipGold 贝壳 | `onButtonVipGoldPlus:` | `onButtonVipGoldMinus:` | — |
| VipValue VIP值 | `onButtonVipValuePlus:` | `onButtonVipValueMinus:` | — |
| Time 时间 | `onButtonTimePlus:` | `onButtonTimeMinus:` | `onButtonTimeTouched:` |
| Quest 任务 | `onButtonQuestPlus:` | `onButtonQuestMinus:` | `onButtonQuestTouched:` |
| TimeQuest 限时任务 | `onButtonTimeQuestPlus:` | `onButtonTimeQuestMinus:` | `onButtonTimeQuestTouched:` |
| VipQuest VIP任务 | `onButtonVipQuestPlus:` | `onButtonVipQuestMinus:` | `onButtonVipQuestTouched:` |
| Food 食物 | `onButtonFoodPlus:` | `onButtonFoodMinus:` | — |
| Tickets 奖励券 | `onButtonTicketsPlus:` | `onButtonTicketsMinus:` | — |

### 3.4 显示能力(label 数量)

10 个 label 同屏显示:经验/摩尔豆/贝壳/任务ID/时间/限时任务ID/VIP任务ID/VIP值/食物/奖励券。

### 3.5 调用方式(Tweak 利用)

```objc
Class TLClass = NSClassFromString(@"TestLayer");
id testLayer = [[TLClass alloc] init];
id director = [NSClassFromString(@"CCDirector") performSelector:@selector(sharedDirector)];
id scene = [director performSelector:@selector(runningScene)];
[scene performSelector:@selector(addChild:) withObject:testLayer];
```

参考已实现版本: `Tweak.xm` 中 `MTOpenDebugMenu()` 函数。

---

## 4. NewSceneTestLayer —— 新场景调试面板

精简版 TestLayer,专为重构后的"新场景"系统(`NewSceneRestaurant`/`NewSceneShop` 等)用。

### 4.1 关键差异

- 14 方法(vs TestLayer 34)
- 4 个 label(`labelxp` / `labelbuild` / `labelvipgold` / `labelquestid` / `labelVipValue`)
- 新增 `getbuildValueChangeValue` / `onButtonbuildValuePlus:` —— **用来调整建筑值**(`buildValue`)
- 仍保留 XP / VipGold / Quest / VipValue 共 5 个调试维度

### 4.2 用途推测

游戏后期重构 `NewSceneRestaurant` 时,需要测试餐厅升级、建筑材料 buildValue 等新引入的玩法,程序员复制 TestLayer 改造而成。

---

## 5. EasterEggMainLayer —— 秘密按钮 + 彩蛋活动

### 5.1 ivar 关键字段

| Offset | Name | Type | 用途 |
|--------|------|------|------|
| 332 | `addTestLayerButton_` | CCMenuItemSpriteIndependent* | **进入 TestLayer 的按钮** |
| 380 | `activityTipSpr_` | CCSprite* | 活动提示 |
| 384 | `tipDateLabel_` | CCLabelTTF* | 日期文字 |
| 388 | `easterEggGetRewardLayer_` | EasterEggGetRewardLayer* | 彩蛋奖励层 |
| 392 | `middleBigEggSpr_` | CCSprite* | 中间大蛋图 |
| 396 | `rewardObject` | ObjectData* | 奖励物品 |
| 400 | `isControlOpenSecretButton_` | char (BOOL) | **控制秘密按钮显示** |

### 5.2 `lightOpenSecretButton` 方法

存在但默认不被自动调用 —— 需要某个外部条件(可能是服务器下发的"活动启用"标志)才会调用。**淘米的策略**:用此机制远程控制让特定玩家(内测/客服)能看到调试入口,而普通玩家不会发现。

### 5.3 完整方法链

```
EasterEggMainLayer init
  ↓
showLayerWithTarget:selector: ─── 由其他 controller 推入界面
  ↓
displayUI ─── 布置主彩蛋 UI
  ↓
[条件检查: isControlOpenSecretButton_]
  ↓
lightOpenSecretButton ─── 点亮 addTestLayerButton_
  ↓
[玩家点击 addTestLayerButton_]
  ↓
某个 onClick 处理 → 弹出 MagicNumberView 让玩家输密码
  ↓ 密码正确
弹出 TestLayer
```

### 5.4 其他业务方法(非后门相关)

`gotoGetRewardWithId:todayRewardId:` / `showNewFindEasterEgg` / `rewardStars[0/1/2]BlinkStart` / `eggsStar[0/1]BlinkStartWithIndex:` / `setRewardVisibleNo` / `onBuyButtonClick:` / `showGetRewardLayer` / `showActionLayerArrow:` / `onSureBuyEasterEgg` / `closeMainLayer` —— 这些是正常的彩蛋活动 UI 逻辑。

### 5.5 Tweak 利用

```objc
%hook EasterEggMainLayer
- (id)init {
    id r = %orig;
    if (开关 ON) {
        // 1. 强制 ivar = 1
        改 isControlOpenSecretButton_ ivar
        // 2. 主动调用游戏自己的点亮方法
        [r performSelector:@selector(lightOpenSecretButton)];
    }
    return r;
}
%end
```

参见 `Tweak.xm` 中 `%hook EasterEggMainLayer`。

---

## 6. 反作弊机制 —— `isHackData` + `showCheatWarningMessage`

### 6.1 数据持有

```
GameData (全局单例)
  ├─ BOOL isHackData_      (offset 0xab30, attr "TB,R,N,VisHackData_")  ← 注意 R = readonly
  └─ - (BOOL)isHackData    (合成 getter,无 setter)

NewSceneUserInfoData (新场景用户数据)
  ├─ char isHackData_      (attr "Tc,N,VisHackData_")  ← 这个有 setter
  ├─ - (BOOL)isHackData
  └─ - (void)setIsHackData:(BOOL)
```

### 6.2 检测方式推测

游戏在以下场景**置 isHackData = YES**:
1. 加载本地存档时发现金币/等级超过合法上限
2. 服务器返回的玩家数据与本地不一致
3. MD5 校验失败(已知:`checkUserinfoMd5:` / `CheckUserInfoData:`)

### 6.3 警告显示

`WrapperManager.showCheatWarningMessage` —— 全局 UI 警告。
还有一个备用入口 `CommonChristmasFatherGiftLayer.showCheatWarningMessage`(圣诞活动里也内嵌检查)。

### 6.4 Tweak 旁路

```objc
%hook GameData
- (BOOL)isHackData { return NO; }      // 锁死 NO
%end

%hook NewSceneUserInfoData
- (BOOL)isHackData { return NO; }
- (void)setIsHackData:(BOOL)b { %orig(NO); }  // 永远拒绝置 YES
%end

%hook WrapperManager
- (void)showCheatWarningMessage { return; }   // 吞掉警告
%end
```

---

## 7. 其他后门 / 测试模式残留

### 7.1 `usingLoaclServerForTestOnly`

⚠️ 注意拼写错误 `Loacl` 而非 `Local`。这是一个 BOOL/方法,允许游戏切换到本地测试服务器。淘米程序员开发期用,正式版本默认 false。**已无意义**:他们的本地服务器肯定也下线了。

### 7.2 `atomTestMode`

腾讯/淘米的 Atom SDK(QQ 登录/社交模块)的测试模式开关。

### 7.3 `atomReceivedRequestForDeveloperToFufill:`

⚠️ 注意 `Fufill` 应为 `Fulfill`(错别字)。Atom 协议中 SDK 给开发者预留的"特殊请求"扩展点。开发期 NSLog 提示:`"Delegate does not implement atomReceivedRequestForDeveloperToFufill"`。

### 7.4 `Activity FreeGold` / `Enter Activity_FreeGold`

字符串残留,可能是某种"免费金币活动"的入口或调试 toast。

### 7.5 `IAP free cheating userId`

字符串残留,推测是淘米给内部开发者的特殊 userid,IAP 验证时遇到此 userId 直接放行(不实际收钱也算购买成功)。

### 7.6 `fishboatShake` + 重力感应彩蛋

这是**游戏内玩法的一部分**(渔船 mini-game 摇手机互动),不是后门。`shakeStep` / `shakeRepeat_boat` 用于步进计数。

### 7.7 编译期被抹掉但残留的 `showDebug_` ivar

属于 GAD 广告 SDK(`GADImpressionTicketGestureRecognizer.adDebugDialog` 邻居),不是游戏自己的调试。

---

## 8. 开发者私货 —— 路径泄露

### 8.1 淘米员工源码路径

| 路径前缀 | 推测人员/模块 |
|----------|---------------|
| `/Users/kevinwang/Documents/Projects/svn/TaomeeMobileLibrary/TaomeeIAPVerify/...` | **kevinwang**:淘米 iOS IAP 验证模块负责人 |
| `/Users/kevinwang/Documents/Projects/svn/TaomeeMobileLibrary/CrashLog/...` | kevinwang:崩溃日志模块 |
| `/Users/andychen/Documents/TaomeeMobileLibrary/TaomeeAccount/TaomeeLogin/...` | **andychen**:登录模块 |
| `/Users/delle/Documents/TaomeeMoreGame/TaomeeGameMore/...` | **delle**:推广小游戏模块 |
| `/Users/ck04-011/Desktop/Work/SDK/` | 工号 **ck04-011** 的开发机 |

### 8.2 第三方 SDK 路径

- `/Users/Akshay/Downloads/plcrashreporter-1.2-beta2/...` —— PLCrashReporter 库
- `/Users/andreaslinde/Sourcecode/OpenSource/PLCrashReporterGit/...` —— 同上的 fork
- `/Users/ENZO/Work/YouMiSDK/released_codes/YouMiSDK-5.00/...` —— 有米广告 SDK
- `/Users/bamboo/bamboo-agent/.../TalkingData/...` —— TalkingData 数据 SDK(Bamboo CI 构建)

### 8.3 内部协议/路径

- `/Projectes/TaomeeAdWall/...` —— 注意是 `Projectes`(原文如此),淘米广告墙模块
- `taomee_reward.xml` —— 奖励数据
- `/TaomeeMore.bundle/admask_iphone.png` —— 广告蒙层

### 8.4 推断:淘米 iOS 团队规模

通过路径中提到的人名,可以看到至少 4 名开发者(kevinwang/andychen/delle + ck04-011 工号),加上多个第三方 SDK 集成。这是个**典型 2013-2014 年代的国产手游团队结构**。

---

## 9. 完整 Tweak 激活映射

下表把每个后门和我们已实现的 hook 对应起来:

| 后门 | 类.方法 | Tweak 配置 key | 实现位置 |
|------|---------|----------------|----------|
| 显示秘密按钮 | `EasterEggMainLayer.init` 后改 ivar + 调 `lightOpenSecretButton` | `kKeySecretBtn` | %hook EasterEggMainLayer |
| 魔法密码任意通过 | `MagicNumberView.onButtonYesSelected:` 跳验证 | `kKeyMagicBypass` | %hook MagicNumberView |
| 一键弹 TestLayer | `[CCDirector sharedDirector].runningScene addChild:[TestLayer alloc] init]` | (按钮触发) | `MTOpenDebugMenu()` |
| 激活彩蛋活动 | `GameData.easterEggsFlag` 强返 1 | `kKeyEasterEgg` | %hook GameData |
| 关反作弊 | `GameData.isHackData` / `NewSceneUserInfoData.isHackData` 锁 NO + `WrapperManager.showCheatWarningMessage` 吞 | `kKeyAntiCheat` | 3 个 %hook |

---

## 10. 拓展玩法(未实现,但二进制中可挖)

这些后门发现但**未做进 tweak**,留给未来扩展:

1. **NewSceneTestLayer** —— 新场景调试面板,可以用同样方式 alloc 弹出,提供 buildValue 调整(我们的 `MTOpenDebugMenu()` 已经 fallback 到它如果 TestLayer 不可用)
2. **`Activity_FreeGold` 入口** —— 如果能找到字符串触发点(如某种 NSNotification 名),可以 post 通知激活
3. **`atomTestMode = YES`** —— 把腾讯 SDK 切到测试模式,可能解锁登录功能(但服务器停服)
4. **Easter Egg Reward 自动领取** —— `easterEggGetRewardLayer_` + `getEasterEggActivityReward` + `gotoGetRewardWithId:todayRewardId:` 一组方法,可以脚本化调用领取所有彩蛋奖励

---

## 11. 数据原始 dump 索引

`reverse/` 目录下:

| 文件 | 内容 |
|------|------|
| `TestLayer.txt` | TestLayer 完整 ObjC 元数据(457 行) |
| `NewSceneTestLayer.txt` | NewSceneTestLayer 完整 |
| `MagicNumberView.txt` | MagicNumberView 完整 |
| `EasterEggMainLayer.txt` | 包含 `lightOpenSecretButton` 等所有方法 |
| `GameData_secrets.txt` | GameData 中所有 magic/easter/hack 字段过滤 |
| `WrapperManager.txt` | showCheatWarningMessage 等 |
| `dev_traces.txt` | 所有开发路径 + 测试模式相关字符串 |

---

## 12. 法律 / 道德边界(非小事)

本报告仅记录已存在二进制中的程序员痕迹,**用于学习逆向工程和理解游戏架构**。注意:

- **服务器已停服**(2018 年左右),所有数据都是单机,改动只影响本地游戏体验
- **不要把改造后的客户端连未关闭的服务器**(如有山寨/私服)恶意刷数据,违反计算机安全法
- **不要发布破解版牟利**,涉及著作权和不正当竞争

---

*报告生成时间: 2026-05-06*
*作者: 二进制本身的程序员留下的痕迹 + 我们的整理*
