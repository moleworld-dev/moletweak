# 黄金岛(加勒比寻宝)修复笔记

> 玩家俗称的"**黄金岛**" = 淘米《摩尔庄园》5.5.0 的「**加勒比海盗航海寻宝**」活动。本文档记录服务器停服后此活动失效的原因 + 我们的本地修复方案。

---

## 1. 命名考据 — 为什么叫"黄金岛"?

二进制中 **没有任何 `gold_island` / `goldenIsland` / `huangjin` 字符串**。但有大量加勒比相关字段:

```
CaribbeanMainLayer
CaribbeanDiscoveringData      ← 数据类
CaribbeanActivityResponder    ← 协议
CaribbeanObject

CARIBBEAN_TREASURE_HUNT_DEEP        (深海寻宝)
CARIBBEAN_TREASURE_HUNT_MODERATE    (中层)
CARIBBEAN_TREASURE_HUNT_SURFACE     (浅海)
CARIBBEAN_SEA_SOUL_AMOUNT           (海魂数量)
CARIBBEAN_SEA_SOUL_USED_FEEDBACK
CARIBBEAN_SITE_GIFT_1..5            (站点礼物 1~5)
CARIBBEAN_DESTINATION_ARRIVALED     (注意 typo: ARRIVED)
CARIBBEAN_NEXT_SITE_DISTANCE
CARIBBEAN_USE_VIP_GOLD_TO_HUNT      (用贝壳寻宝)
CARIBBEAN_TIME_COUNT_DOWN
```

**结论**:此活动主题是"加勒比海盗航海+寻宝",玩家用"海魂"或"贝壳"加速航行,经过 5 个站点(每站有礼物),沿途可在浅/中/深 3 种深度寻宝。**玩家社区俗称这个活动为"黄金岛"**(因为宝藏 + 岛屿主题)。

---

## 2. 数据流 — 服务器停服为什么坏?

### 2.1 类协作图

```
┌───────────────────┐         ┌────────────────────────────────┐
│  NetworkManager   │◀───────│  服务器 (淘米 imole.61.com:8080) │
│                   │         └────────────────────────────────┘
│  - getCaribbeanStateInfo:   ── 客户端发请求
│  - parseCaribbeanStateInfo:pos:len:  ── 收响应解析
│  - parseCaribbeanAdvanceTime:pos:len:
│  - delegateCaribbeanActivity ── 通知 UI
└─────────┬─────────┘
          │ 解析结果写入
          ▼
┌─────────────────────────────────────────────────┐
│  GameData (全局单例)                              │
│  - caribbeanData_  : CaribbeanDiscoveringData *  │
│  - loadCaribbeanData: / setCaribbeanData:        │
│  - resetCaribbeanData                            │
└─────────┬───────────────────────────────────────┘
          │ UI 读
          ▼
┌─────────────────────────────────────────────────┐
│  CaribbeanMainLayer  : CCLayer                   │
│  - displayUI / updateCountDown:                  │
│  - addTreasureHuntMenu:                          │
│  - onAllSpeedAdvance / onClickTreasureHunt:      │
│  - callbackUseVipGoldToAdvance                   │
│  - shipAdvanceSuccess                            │
│  - showNetWorkError ← 服务器无响应时弹这个       │
└─────────────────────────────────────────────────┘
```

### 2.2 `CaribbeanDiscoveringData` 的 5 个 int 字段

```c
@interface CaribbeanDiscoveringData : NSObject {
    int curIsland_;                   // 当前岛屿索引(玩家航行到了哪个站点)
    int distanceToNext_;              // 距下一个站点的距离
    int totleDistance_;               // 总航程 (typo: totle → total)
    int correctionSoulOfTheSea_;      // 海魂修正值(当前海魂数量)
    int leftDaysNum_;                 // 剩余天数
}
```

**就 5 个 int 字段** —— 极其简单的状态机。

### 2.3 服务器停服后失效路径

```
玩家点击「加勒比黄金岛」入口
    ↓
CaribbeanMainLayer init
    ↓
[NetworkManager getCaribbeanStateInfo:]   ← 发请求
    ↓
imole.61.com:8080 (停服) ← 永远不响应
    ↓
[GameData caribbeanData] = nil
    ↓
CaribbeanMainLayer.displayUI 拿不到数据
    ↓
[CaribbeanMainLayer showNetWorkError]   ← 弹"网络错误"
    ↓
玩家:🤬
```

---

## 3. 修复方案

### 3.1 核心思路

既然 `CaribbeanDiscoveringData` 是纯本地内存对象(没有什么服务器加密签名),我们**本地构造一个有效实例**塞给 GameData,UI 就能正常渲染。

### 3.2 三个 hook 协同

```objc
// (a) GameData.caribbeanData getter:返回时如果 nil 就本地造一个
%hook GameData
- (id)caribbeanData {
    id orig = %orig;
    if (orig) return orig;
    if (!MT_BOOL(kKeyFixGoldenIsland, NO)) return orig;

    Class C = NSClassFromString(@"CaribbeanDiscoveringData");
    id data = [[C alloc] init];
    [data setCurIsland:1];                    // 站点 1
    [data setDistanceToNext:100];             // 距下一站 100 单位
    [data setTotleDistance:500];              // 总航程 500
    [data setCorrectionSoulOfTheSea:9999];    // 给 9999 海魂(够用)
    [data setLeftDaysNum:99];                 // 99 天活动期
    [self setCaribbeanData:data];             // 写回 GameData
    return data;
}
%end

// (b) CaribbeanMainLayer 不再弹"网络错误"
%hook CaribbeanMainLayer
- (void)showNetWorkError {
    if (MT_BOOL(kKeyFixGoldenIsland, NO)) return;  // 吞
    %orig;
}
%end

// (c) NetworkManager 不真发请求(避免长时间等待)
%hook NetworkManager
- (int)getCaribbeanStateInfo:(id)arg {
    if (MT_BOOL(kKeyFixGoldenIsland, NO)) return 0;  // 直接返成功
    return %orig;
}
%end
```

### 3.3 默认值的取舍

| 字段 | 我设的值 | 理由 |
|------|---------|------|
| `curIsland_` | 1 | 站点 1(开始位置),避免 0 可能被判"未激活" |
| `distanceToNext_` | 100 | 距下一站 100 单位,玩家立刻能加速 |
| `totleDistance_` | 500 | 总航程,5 站 × 100 |
| `correctionSoulOfTheSea_` | 9999 | 海魂富裕,玩家可随便加速 |
| `leftDaysNum_` | 99 | 99 天活动期(不到期) |

---

## 4. 已知风险 / 待验证

### 4.1 可能不工作的场景

- **如果 UI 还依赖其他服务器消息**(比如 `parseCaribbeanAdvanceTime:` 决定动画路径),只 fix `caribbeanData` 不够,玩家可能能进入但无法操作
- **`onAllSpeedAdvance` / `onClickTreasureHunt:` 可能内部还会请求服务器**,需要进一步 hook 拦截
- **奖励发放可能依赖服务器**(`CARIBBEAN_SITE_GIFT_*`),即使能玩,可能拿不到奖励

### 4.2 可能的扩展

如果 4.1 的问题出现,后续 hook:
- `[NetworkManager getCaribbeanStateInfo:]` 完整改成本地"拟答"
- hook `CaribbeanMainLayer.onAllSpeedAdvance`,直接调 `shipAdvanceSuccess`
- hook `[CaribbeanMainLayer onClickTreasureHunt:]`,直接给玩家发 SITE_GIFT_X

### 4.3 测试方法

1. 进游戏 → 浮动菜单 → 开「修复黄金岛(加勒比)」开关
2. 进入加勒比活动入口(主菜单 / 活动中心)
3. 看是否还是「网络错误」弹窗;如果直接进了 UI,说明数据修复成功
4. 试试 `寻宝` / `加速` 按钮,看会不会再卡

---

## 5. 跟黄金岛**类似的还能修复**(同模式)

二进制里还有大量服务器停服后失效的活动,**结构差不多**(都是 `xxxData` + `xxxMainLayer` + `xxxResponder` 三件套):

| 活动 | 数据类 | 主 UI Layer | 修复难度 |
|------|--------|-------------|----------|
| 加勒比黄金岛 | `CaribbeanDiscoveringData` | `CaribbeanMainLayer` | ✅ 已修(5 int) |
| 海底寻宝 | `SeabedSeekingTreasureData`? | `SeabedSeekingTreasureMainLayer` | 中(需查) |
| 环游世界 | (待查) | `AroundTheWorldMainLayer` | 中 |
| 春天的诗 | (待查) | `SpringPoemMainLayer` | 中 |
| 放风筝 | `FlyKiteActivityRewardData` | `FlyKiteMainLayer` | 中 |
| 清明青团 | `GreenRiceBallActivityInfoData` | `GreenRiceBallMainLayer` | 中 |
| 开宝箱 | (待查) | `OpenTreasureChestMainLayer` | 中 |
| 世界杯竞猜 | (待查) | `GuessWorldCupMainLayer` | 高(需联网) |
| 复活节彩蛋 | `EasterEggActivityInfoData` | `EasterEggMainLayer` | 中(已部分 hook) |
| 爱丽丝 | `AliceActivityData` + `AliceTreasureData` 等 | `Activity_Alice_MainLayer` | **高**(联名 IP,逻辑复杂) |

**统一模式**:每个活动都是 GameData 持有 `xxxData` ivar,UI 读这个 ivar 渲染。修复套路相同。

---

## 6. 直接召唤(绕过黄金岛入口)

我们 v6 在「开发面板」里加了 14 个**直接 alloc 联名活动 layer 的按钮**:

```
[爱丽丝梦游] [史莱克]   [龙猫]      [冰激凌]
[火焰战争]   [加勒比黄金岛] [海底寻宝]  [环游世界]
[春天的诗]   [放风筝]    [清明青团]  [开宝箱]
[世界杯竞猜] [冰夏]
```

点这些按钮直接 `alloc init` 对应 layer 加到 `runningScene`。如果该活动数据也修复了(像黄金岛),活动 UI 应该能正常显示。

---

## 7. 一句话总结

> 黄金岛 = 加勒比寻宝,数据简单(5 个 int),修复办法是 hook `GameData.caribbeanData` 返回本地造的 `CaribbeanDiscoveringData` 实例 + 吞掉 `showNetWorkError`。如果只是 UI 进不去,这套修复就够;如果游玩流程还有别的服务器依赖,继续追加 hook 即可。

---

*报告生成时间: 2026-05-06,v6 tweak 部署后*
