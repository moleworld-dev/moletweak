# 摩尔庄园 5.5.0 — 隐藏功能补充报告 (Round 2)

> 接续 [REVERSE_ENGINEERING.md](REVERSE_ENGINEERING.md)。这一轮专挖**还没发现**的金矿:项目原代号、未上线联名活动、内网服务器、SDK 调试入口、隐藏菜单位置常量。

---

## 1. 项目代号: **iMoleVillage**(摩尔村庄)

**正式上线名是 MoleWorld,但开发期项目叫 iMoleVillage**。证据:

```
/TestProject/iMoleVillage/src/Networking/JSONKit.m
/TestProject/iMoleVillage/src/libs/ThirdParty/AdMediation/Atom/internal/AtomConfigStore.m
/TestProject/iMoleVillage/src/libs/ThirdParty/AdMediation/Atom/internal/AtomView.m
/TestProject/iMoleVillage/src/libs/ThirdParty/ShareKit/.../SHKSinaWeiboV2.m
iMoleVillageAppDelegate    ← 类名也证实
```

App 类入口实际叫 `iMoleVillageAppDelegate` 而非 `MoleWorldAppDelegate`。**全产品线没改类名,仅 .app 名改了**。

---

## 2. 主菜单上的 `hiddenMenuPosition` —— 隐藏菜单坐标硬编码 ⭐

```
MainMenuScene 类 -> hiddenMenuPosition (类常量/方法)
```

`MainMenuScene` 类持有 `hiddenMenuPosition` 这个名字(详见 `reverse/MainMenuScene.txt`)。结合 `MainMenu` 类有的 `testAnimation` 方法 —— **这强烈暗示:在主菜单某个固定坐标点击/长按,会触发隐藏调试入口**。

需要进一步反汇编 `hiddenMenuPosition` 的 getter 看具体坐标(目测是 CGPoint 或 NSValue 包装),以及 `MainMenu.testAnimation` 的实现,但很可能是:

```objc
- (void)ccTouchBegan:(touch) {
    if (CGRectContainsPoint(hiddenMenuRect, touch.location)) {
        tapCount++;
        if (tapCount >= N) [self showDebugMenu];
    }
}
```

**Tweak 利用方向**:hook `MainMenuScene` / `MainMenu` 的 `init` 后立即调用 `testAnimation` 或显示一个标记。

---

## 3. 13 个 Activity Responder —— 未上线/已下线的联名活动 ⭐⭐

完整清单(详见 `reverse/all_activities.txt`):

| Responder | 推测主题 | 关联 Layer 数 |
|-----------|---------|---------------|
| `AroundTheWorldActivityResponder` | 环游世界 | — |
| `AutumnActivityResponder` | 秋季活动 | — |
| `CaribbeanActivityResponder` | 加勒比海盗 | 多个 |
| `EasterEggActivityResponder` | 复活节(已知) | 完整 |
| `FlyKiteActivityResponder` | 春季放风筝 | — |
| `GreenRiceBallActivityResponder` | **清明节青团** | — |
| `GuessWorldCupActivityResponder` | **2014 世界杯竞猜** | — |
| `HalloweenActivityResponder` | 万圣节 | — |
| `IceActivityResponder` | 冰雪/冬季 | — |
| `NaramSpringActivityResponder` | Naram(角色?)春季 | — |
| `OpenTreasureChestActivityResponder` | 开宝箱 | — |
| `PopularItemsPKActivityResponder` | 热门物品 PK | — |
| `SeabedSeekingTreasureActivityResponder` | 海底寻宝 | — |
| `SpringPoemActivityResponder` | 春诗活动 | — |
| `XmasActivityResponder` | 圣诞 | 多个 |

### 完整联名 IP 活动 layer 集

| IP | Layer 数 | 含义 |
|----|---------|------|
| **Alice 爱丽丝** | 8 (Dice/Exchange/Main/Recycle/Rule/Strength/Treasure + BasePop) | 迪士尼《爱丽丝梦游仙境》联动 — 完整一个 mini-game |
| **FlameWars** | 7 (DailyDonate/DailyReward/Exchange/Levelup/Main/Rule/TopTen + BasePop) | "火焰战争",PK 玩法,顶 10 排行榜 |
| **IceCream** | 4 (DailyDonate/DailyReward/Exchange + BasePop) | 冰激凌活动 |
| **Shrek 史莱克** | 3 (DailyReward/Rule + BasePop) | 梦工厂《怪物史莱克》联动 |
| **Totoro 龙猫** | 3 (DailyDonate/DailyReward + BasePop) | **吉卜力《龙猫》联动**!这个挺神奇 |

**淘米当年的国民级身份**:能拿到爱丽丝、史莱克、龙猫这种 IP 授权,说明淘米《摩尔庄园》在 2013-2014 是国内非常顶尖的儿童手游之一。

**Tweak 利用方向**:这些活动 Responder 都通过服务器下发 `cmd` 触发。如果 hook `[XxxActivityResponder onStateChangedTo:]` / `[XxxActivityResponder onCommandReceived:]` 模拟服务器消息,**可以让停服游戏内**重现这些联名活动。

---

## 4. 服务器架构 — 完整内网/外网清单

### 4.1 淘米官方域名(`*.61.com`,因为 6/1 儿童节)

| 域名 | 用途 |
|------|------|
| `account-mapi.61.com/account_service.php` | 账号 API(HTTPS) |
| `mlogin.61.com/ipsvr.fcgi` | 动态登录 IP 分配 |
| `imole.61.com/m` | iMole 短链 |
| `imolelogin.61.com:8080/dynamic/online.imole` | 登录服务器(8080 端口) |
| `bbs.61.com` | 论坛 + 会话 |
| `wlad.61.com` / `wlad2.61.com` | 广告(wireless ad) |
| `wall.61.com` | 广告墙 |
| `wlstat.61.com` | 统计 |
| `dc.61.com` | 数据收集 |
| `mcdn.61.com` | CDN(`/ad/2012060701/` 时间戳显示这是 2012 年的资源) |
| `pic1-bus.61.com` | 图片 CDN |
| `ipush.61.com/push.fcgi` | 推送 |
| `m.61.com` | 移动入口 |
| `game.61.com/molecard` | 摩尔卡(实体卡兑换) |

### 4.2 内网开发服务器(明显是开发期残留没清理)

```
http://10.1.1.27/ammy_project/expeprogram/wireless/wireless_info.php
http://10.1.1.27/ammy_project/webaccount/account_service.php
http://10.1.1.163/wlstat/index.php
http://10.1.1.57
```

`ammy_project` 是淘米某个内部项目代号(**Ammy** 可能是项目缩写或开发组名)。**生产二进制留着开发服务器 IP,典型粗心**。

### 4.3 211.151 中国机房 IP

```
http://211.151.121.43
http://211.151.105.139/wareless/wareless/ser/dumpfile.php
```

**注意 `wareless/wareless/` 双重拼写错误**(应为 `wireless`)。这是崩溃 dump 上报地址,被双重重复路径段。

### 4.4 集成的第三方 SDK(13+ 个,2013 年代国产手游典型)

| SDK | 用途 | 调试入口 |
|-----|------|---------|
| **AdMob** (Google) | 横幅/插页广告 | `adDebugDialog_` (`GADObjectPrivate.adDebugDialog_`) |
| **Flurry** | 数据分析 | `data.flurry.com/aas.do` |
| **Inmobi** | 广告 | `i.w.inmobi.com/showad.asm` |
| **DianRu (点入)** | 广告墙 | `cmd=getadwalllst` / `cmd=addfeedback` (`api.wall.v3.dianru.com`) |
| **Tapjoy** | 激励视频 | `connect.tapjoy.com` |
| **Domob (多盟)** | 国内广告 | `r.ow.domob.cn` |
| **Immob** | 广告 | `api.immob.cn` |
| **Cocounion** | 联运 | `service.cocounion.com` |
| **YouMi (有米)** | 广告墙 | `au.youmi.net` / `ios.wall.youmi.net` |
| **Miidi (米米)** | 广告 SDK | `MiidiSdkProfile.secretUDID` |
| **TalkingData** | 数据分析 | `TDGA*` 类 |
| **Umeng (友盟)** | 数据分析 | `alog.umeng.com/app_logs` |
| **HockeyApp** | 崩溃报告 | `rink.hockeyapp.net` |
| **NewRelic** | 性能监控 | `+[NewRelicAgentInternal engageTestMode]` ⭐ |

### 4.5 社交分享 SDK

Sina 微博 / Twitter / Facebook / QQ / Renren / Douban / Tencent QQ — 6 个分享渠道全集成。

---

## 5. 重要的隐藏开关 ivar 清单(可 Tweak)

| 类 | ivar / 方法 | 类型 | 用途 |
|----|------------|------|------|
| `MainMenuScene` | `hiddenMenuPosition` | (常量/方法) | **隐藏菜单坐标** |
| `MainMenu` | `testAnimation` | 方法 | 主菜单测试动画 |
| `UserInfoLayer` | `addTestSprite_` | CCSprite* | 测试精灵图 |
| `UserInfoLayer` | `addTestLayerButton_` | CCMenuItemSpriteIndependent* | 进入 TestLayer 的按钮(已知) |
| `InAppPurchaseManager` | `debugTransactionInfo:` | 方法 | **IAP 内购调试信息** |
| `NewRelicAgentInternal` | `engageTestMode` | +类方法 | NewRelic 测试模式 |
| `NewRelicAgentInternal` | `setDeviceLocation:` | +类方法 | 强制设设备地理位置 |
| `GADObjectPrivate` | `adDebugDialog_` | NSString | AdMob 调试弹窗 |
| `MiidiSdkProfile` | `secretUDID` | NSString | Miidi 设备指纹脱敏 |
| 多个类 | `testMode` / `testing` / `isTesting_` / `_isTesting` / `isTest` | BOOL | **6 个不同的测试标志**(每个 SDK 各一) |

### `debugTransactionInfo:` 是个潜在金矿

`InAppPurchaseManager.debugTransactionInfo:` —— 这是**淘米 IAP 验证模块的内部调试方法**,可能输出当前充值订单详情。Hook 后强制每次都调用,能看到玩家曾经的所有充值记录(本地缓存)。

---

## 6. 开发者吐槽与拼写错误档案 📝

> 国产手游程序员的"人味"在 typo 和奇怪的命名里展现得最明显。

| 拼写错误 | 出现位置 | 应为 |
|---------|----------|------|
| `Loacl` | `usingLoaclServerForTestOnly` | Local |
| `Fufill` | `atomReceivedRequestForDeveloperToFufill:` | Fulfill |
| `Recieve` | `TestLayer.onRecieveMessage:` | Receive |
| `Projectes` | `/Projectes/TaomeeAdWall/...` | Projects |
| `wareless` | `211.151.105.139/wareless/wareless/ser/...` | wireless(并且重复) |
| `Onekey` | `Farm.harvestOnekey:` | OneKey 或 oneKey |
| `Charima` | `getGoldByFriendsCharimaValue` | Charisma(魅力值) |
| `Plaw` | `Farm.hireWorkerToPlawFarm:` | Plow(犁地) |

**这 8 处拼写错误集中说明**:
- 团队没有 code review 静态规范(eslint/typo-detector 类)
- 人员英语水平参差(且常见词都拼错)
- 编译期没有 grep 检查工具(发现 typo 但没人改)

### 残留开发标记

```
HACK_USERINFO_DATA_ERROR        ← 用户数据错误的"hack"解决方案
TODO_DOMAIN                     ← 域名 TODO
[TODO]                          ← 字面 TODO 标签
NOTE: MAC address is being collected   ← 隐私警告但仍然收集
live_crash_report.XXXXXX        ← 临时崩溃文件名模板
```

### 摇手机彩蛋

```
fishboatShake / shakeStep / shakeRepeat_boat
accelerometer:didAccelerate:
```

**渔船 mini-game 的摇晃序列**。`shakeRepeat_boat` 暗示需要按特定模式摇晃多次才能触发。

---

## 7. 下一步可挖的方向

未做但有潜力:

| 方向 | 怎么做 |
|-----|-------|
| 反汇编 `MainMenuScene.hiddenMenuPosition` | otool -tV 找它的 getter,看坐标具体值 |
| 强制激活 13 个 Activity Responder | hook `onCommandReceived:` 模拟服务器消息触发活动 |
| 复活 Alice/Shrek/Totoro 联名活动 | 同上,加 `Activity_Alice_MainLayer` 一类的实例化入口 |
| `engageTestMode` (NewRelic) | hook `+[NewRelicAgentInternal engageTestMode]` 强制启用,看效果 |
| `adDebugDialog_` (AdMob) | 设个调试 URL 字符串,看广告 SDK 调试 UI |
| `debugTransactionInfo:` (IAP) | hook 让它每次都被调,记录所有 IAP 状态 |
| 中文 NSLog 抓取 | 加调试 hook 把 NSLog 重定向到 file,看实际打印的中文 |

---

## 8. `reverse/` 目录新增的 dump

| 文件 | 内容 |
|------|------|
| `MainMenuScene.txt` | 33KB —— 主菜单场景全部方法/ivar |
| `MainMenu.txt` | 8KB |
| `UserInfoLayer.txt` | 22KB —— 含 `addTestLayerButton_` 完整环境 |
| `InAppPurchaseManager.txt` | 47KB —— IAP 模块全部 |
| `all_urls.txt` | 8.5KB —— 二进制中所有 URL |
| `all_activities.txt` | 1.8KB —— 所有 Activity 类清单 |

---

## 9. 一行总结

> 二进制里塞满了 13 个 SDK + 13 个未上线联名活动 + 一个程序员留的隐藏调试菜单坐标,而且**项目代号是 iMoleVillage 不是 MoleWorld**,内网服务器 IP `10.1.1.27` 直接写死。这是一份高度凝缩的 2013-2014 年代中国手游工业化产物。

---

*报告生成时间: 2026-05-06,接续 v3 tweak 部署后*
