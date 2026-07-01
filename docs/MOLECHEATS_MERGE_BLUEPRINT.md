# Implementation Blueprint — MoleTweak → molecheats Full Parity

Target: MobileSubstrate/Logos tweak, single `Tweak.xm`, Objective-C, armv7, iOS 6.1.3.
Authority rule: **where the current tweak and molecheats disagree, molecheats wins.**

---

## 0. Global scaffolding (build once, reused by all pages)

### 0.1 Runtime helpers to add

```objc
// --- Class / singleton resolution ---
static Class MTClass(const char *n){ return objc_getClass(n); }

// Running cocos2d scene: [[CCDirector sharedDirector] runningScene]
static id MTRunningScene(void){
    Class dir = objc_getClass("CCDirector");
    if(!dir) return nil;
    id d = ((id(*)(id,SEL))objc_msgSend)(dir, @selector(sharedDirector));
    if(!d) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(d, @selector(runningScene));
}

// GameData singleton — prefer +sharedInstance, fall back to captured gGameDataRef
static id MTGameData(void){
    Class gd = objc_getClass("GameData");
    if(gd && [gd respondsToSelector:@selector(sharedInstance)])
        return ((id(*)(id,SEL))objc_msgSend)(gd, @selector(sharedInstance));
    return gGameDataRef;
}
static id MTUserInfoData(void){
    id gd = MTGameData();
    return gd ? ((id(*)(id,SEL))objc_msgSend)(gd, @selector(userInfoData)) : nil;
}

// Generic singleton via +sharedManager / +shareInstance / +sharedInstance
static id MTShared(const char *clsName){
    Class c = objc_getClass(clsName);
    if(!c) return nil;
    SEL cands[] = { @selector(sharedManager), @selector(shareInstance),
                    @selector(sharedInstance), @selector(sharedDirector) };
    for(int i=0;i<4;i++)
        if([c respondsToSelector:cands[i]])
            return ((id(*)(id,SEL))objc_msgSend)(c, cands[i]);
    return nil;
}

// Save currency/user data
static void MTSaveUserInfo(void){
    id gd = MTGameData();
    if(gd && [gd respondsToSelector:@selector(saveUserInfoData)])
        ((void(*)(id,SEL))objc_msgSend)(gd, @selector(saveUserInfoData));
}

// Summon a cocos2d layer at z; retain as LAST_SUMMONED for CloseSummoned.
static id LAST_SUMMONED = nil; // strong
static void MTSummon(const char *clsName, int z){
    Class c = objc_getClass(clsName);
    id scene = MTRunningScene();
    if(!c || !scene) return;
    id o = ((id(*)(id,SEL))objc_msgSend)(((id(*)(id,SEL))objc_msgSend)((id)c,@selector(alloc)), @selector(init));
    if(!o) return;
    ((void(*)(id,SEL,id,int))objc_msgSend)(scene, @selector(addChild:z:), o, z);
    if(LAST_SUMMONED){ [LAST_SUMMONED release]; }
    LAST_SUMMONED = [o retain];
    [o release]; // scene owns it; we hold LAST_SUMMONED retain
}
```

### 0.2 Ghost TestLayer (page 0 numbers)

molecheats routes every `经验/摩尔豆/贝壳/VIP值/食物/…` delta through a **cached, retained, off-scene `TestLayer`** whose `onButtonXxxPlus:/Minus:` methods it fires N times. The current tweak already does exactly this in its Dev Panel. Reuse it:

```objc
static id gGhostTestLayer = nil; // strong, lazy
static id MTGhostTL(void){
    if(gGhostTestLayer) return gGhostTestLayer;
    Class c = objc_getClass("TestLayer");
    if(!c) return nil;
    id t = ((id(*)(id,SEL))objc_msgSend)(((id(*)(id,SEL))objc_msgSend)((id)c,@selector(alloc)),@selector(init));
    gGhostTestLayer = [t retain];
    return gGhostTestLayer;
}
static void MTGhostFire(SEL sel, int repeat){
    id t = MTGhostTL();
    if(!t || ![t respondsToSelector:sel]) return;
    for(int i=0;i<repeat;i++)
        ((void(*)(id,SEL,id))objc_msgSend)(t, sel, nil);
    MTSaveUserInfo();
}
```
> Note: the ghost `TestLayer` is NOT added to the scene (no `addChild:`). This matches molecheats' "GhostTL" kind — a detached instance used purely as a method bag.

### 0.3 Toggle store

Keep the current hand-rolled plist store (`MTSettings()` + `MT_SET`/`MT_BOOL`/`MT_INT`/`MT_FLT`) — it works on iOS 6 and avoids `NSUserDefaults initWithSuiteName:`. All toggle keys become plist booleans/ints. The `mole_cheats::toggle("key")` calls in INPUT 2 map 1:1 to `MT_SET(@"key", @(!MT_BOOL(@"key")))`.

**Defaults (from INPUT 1):** `fix_divine=ON`, `enter_newislands=ON`, `fix_golden_island=ON`, `enable_newscene_island=ON`. All others OFF.

### 0.4 Multiplier / level cycle state

- `gold_x10` / `xp_x10`: store an int multiplier per key. molecheats uses fixed 10; keep the current 1–50 slider as a superset, but the **toggle button** sets it to 10/off. `is_on := mult>1`.
- `bump_level()`: cycles forced curLevel `0,10,…,100` (0 = off/passthrough).
- `bump_vip_level()`: cycles forced VIP level `1..=15`, auto-enables `force_vip`. (Intercept clamps to `VIP_LEVEL_MAX=4` for the `vipLevelWithNewType` string — see §2.)

---

## 1. TARGET MENU — 5-page tabbed rebuild

**Structural change [FIX]:** replace the current *single scrolling card + separate Dev Panel* with a **5-page tabbed menu** (tab bar across the top, one scroll body per page), pages in molecheats order below. Keep the iOS6 machinery that already works: the floating "修改" button attach (`UIWindow -makeKeyAndVisible`), the `MTApplyScrollViewFix:` (delaysContentTouches=NO / canCancelContentTouches=NO / exclusiveTouch=YES) for every scroll body, and the manual `CGAffineTransform` rotation handling. **Update the title string** from "摩尔庄园 修改器 v3" to the current version (v20) — the stale "v3" is a [FIX].

Each page = a `UIScrollView` of rows. Tab bar buttons switch the visible page. Sliders are read-only display rows that refresh from `%orig`-cached globals via the existing 0.5s `NSTimer`.

---

### PAGE 0 — 数值 (Numbers)

| Label | On-tap Objective-C | Scene/singleton needed |
|---|---|---|
| 等级 (slider, read-only, max 52) | `cur = (int)[MTUserInfoData() curLevel];` display only | UserInfoData |
| 摩尔豆 (slider RO, max 9999999) | `cur = [MTUserInfoData() gold];` | UserInfoData |
| 贝壳 (slider RO, max 2000000) | `cur = [MTUserInfoData() vipGold];` | UserInfoData |
| 工人 (slider RO, max 99) | `cur = [MTUserInfoData() totalWorkers];` | UserInfoData |
| 房间 (slider RO, max 99) | `cur = [MTUserInfoData() totalRooms];` | UserInfoData |
| 经验 +1 | `MTGhostFire(@selector(onButtonXPPlus:),1);` | Ghost TestLayer |
| 经验 +10 | `MTGhostFire(@selector(onButtonXPPlus:),10);` | Ghost TestLayer |
| 经验 +100 | `MTGhostFire(@selector(onButtonXPPlus:),100);` | Ghost TestLayer |
| 经验 -1 | `MTGhostFire(@selector(onButtonXPMinus:),1);` | Ghost TestLayer |
| 经验 -10 | `MTGhostFire(@selector(onButtonXPMinus:),10);` | Ghost TestLayer |
| 摩尔豆 +1 | `MTGhostFire(@selector(onButtonGoldPlus:),1);` | Ghost TestLayer |
| 摩尔豆 +10 | `MTGhostFire(@selector(onButtonGoldPlus:),10);` | Ghost TestLayer |
| 摩尔豆 +100 | `MTGhostFire(@selector(onButtonGoldPlus:),100);` | Ghost TestLayer |
| 摩尔豆 -1 | `MTGhostFire(@selector(onButtonGoldMinus:),1);` | Ghost TestLayer |
| 摩尔豆 -10 | `MTGhostFire(@selector(onButtonGoldMinus:),10);` | Ghost TestLayer |
| 贝壳 +1 | `MTGhostFire(@selector(onButtonVipGoldPlus:),1);` | Ghost TestLayer |
| 贝壳 +10 | `MTGhostFire(@selector(onButtonVipGoldPlus:),10);` | Ghost TestLayer |
| 贝壳 +1000 | `id gd=MTGameData(); ((void(*)(id,SEL,int,BOOL))objc_msgSend)(gd,@selector(addVipGoldForBuy:UIUpdate:),1000,YES);` | GameData (NOT ghost — direct call) |
| VIP值 +1 | `MTGhostFire(@selector(onButtonVipValuePlus:),1);` | Ghost TestLayer |
| 食物 +1 | `MTGhostFire(@selector(onButtonFoodPlus:),1);` | Ghost TestLayer |
| 奖励券 +1 | `MTGhostFire(@selector(onButtonTicketsPlus:),1);` | Ghost TestLayer |
| 时间 +1 | `MTGhostFire(@selector(onButtonTimePlus:),1);` | Ghost TestLayer |
| 任务进度 +1 | `MTGhostFire(@selector(onButtonQuestPlus:),1);` | Ghost TestLayer |
| 限时任务 +1 | `MTGhostFire(@selector(onButtonTimeQuestPlus:),1);` | Ghost TestLayer |
| VIP任务 +1 | `MTGhostFire(@selector(onButtonVipQuestPlus:),1);` | Ghost TestLayer |
| 工人数 = 20 | `id ui=MTUserInfoData(); ((void(*)(id,SEL,int))objc_msgSend)(ui,@selector(setTotalWorkers:),20); ((void(*)(id,SEL,int))objc_msgSend)(ui,@selector(setAvailableWorkers:),20); MTSaveUserInfo();` | UserInfoData |
| 房间数 = 20 | `((void(*)(id,SEL,int))objc_msgSend)(MTUserInfoData(),@selector(setTotalRooms:),20); MTSaveUserInfo();` | UserInfoData |

---

### PAGE 1 — 召唤 (Summon), z=88888

Every button = `MTSummon("<Class>", 88888);` (obtains running scene internally). List in molecheats order:

`SuperShellTree`, `ShowFreeShellsLayer`, `WaterTower`, `CrowPriest`, `ChrismasTreeView`, `VillageMenuLayer`, `NewStyleStoreMainLayer` (label 新版商店(勿点!易卡)), `PromoteSalesMainLayer`, `XmasMainLayer`, `EasterEggMainLayer`, `AnniversaryMainLayer`, `AutumnMainLayer`, `HalloweenMainLayer`, `NaramSpringMainLayer`, `Activity_Alice_MainLayer`, `Activity_Shrek_BasePopLayer`, `Activity_Totoro_BasePopLayer`, `Activity_IceCream_BasePopLayer`, `Activity_FlameWars_MainLayer`, `CaribbeanMainLayer`, `SeabedSeekingTreasureMainLayer`, `AroundTheWorldMainLayer`, `SpringPoemMainLayer`, `FlyKiteMainLayer`, `GreenRiceBallMainLayer`, `OpenTreasureChestMainLayer`, `GuessWorldCupMainLayer`, `IceSummerMainLayer`, `ShowAdwallBoardLayer`, `ShowMoreFriendsLayer`, `ShowActivityRuleLayer`.

> All go through the same guarded `MTSummon` (nil-checks class + scene). Faithful to molecheats' `SummonClass` z=88888. `CaribbeanMainLayer` here is a *plain* summon — distinct from the OpenCaribbean flow on page 4.

---

### PAGE 2 — Mini/任务/重置

| Label | On-tap Objective-C |
|---|---|
| Mini: 切水果 | `id m=MTShared("MiniGameManager"); ((void(*)(id,SEL,int,int,id,SEL))objc_msgSend)(m,@selector(startMiniGame:playType:callbackTarget:select:),1,0,nil,(SEL)0);` |
| Mini: 拍虫子 | same, `gameId=2` |
| Mini: 挖矿石 | same, `gameId=3` |
| Mini: 敲木桩 | same, `gameId=4` |
| Mini: 钓鱼 | same, `gameId=5` |
| 丝尔特(春) | `id gd=MTGameData(); ((void(*)(id,SEL,id))objc_msgSend)(gd,@selector(loadMapdataFromResource:),@"xiaotulv_map"); ((void(*)(id,SEL,id))objc_msgSend)(gd,@selector(loadUserInfoFromResource:),@"xiaotulv_userinfo"); id ngm=MTShared("NewGameManager"); ((void(*)(id,SEL))objc_msgSend)(ngm,@selector(reloadMapFromNewSceneData));` |
| 丝尔特(冬) | same with `@"xiaotulv_winter_map"` / `@"xiaotulv_winter_userinfo"` |
| ⚠️拷贝丝尔特家园到自己 (2-tap confirm) | `[gd loadMapdataFromResource:@"xiaotulv_map"]; [gd saveMapData]; [ngm reloadMapFromNewSceneData];` |
| 给宝藏奖励 | `((void(*)(id,SEL))objc_msgSend)(MTShared("GameManager"),@selector(addTreasureReward));` |
| 给宝藏兔奖励 | `[MTShared("GameManager") addTreasureRabbitReward];` (via objc_msgSend) |
| 强开剧情任务 | `[MTShared("GameManager") activateStoryQuest];` |
| 重置每日任务 | `[MTGameData() resetUnfinishedDailyQuestDataInMap]; MTSaveUserInfo();` |
| 重置限时任务 | `[MTGameData() resetTimeQuestDataInMap]; MTSaveUserInfo();` |
| 重置VIP任务 | `[MTGameData() resetVipQuestDataInMap]; MTSaveUserInfo();` |
| 重置今日签到 | `[MTGameData() resetLastGetDailyRewardDay]; MTSaveUserInfo();` |
| 重置每日列表 | `[MTGameData() resetDailyQuestList]; MTSaveUserInfo();` |
| 重置宝箱数据 | `[MTGameData() resetTreasureChestData]; MTSaveUserInfo();` |
| 重置加勒比 | `[MTGameData() resetCaribbeanData]; MTSaveUserInfo();` |
| ⚠️整库重置 (2-tap confirm) | `[MTGameData() resetUserGameData]; MTSaveUserInfo();` |

> All GameManager/GameData calls guarded by `respondsToSelector:`. Use `MTShared("MiniGameManager")` (resolves `shareInstance`). `select:` arg is a `SEL` typed `NULL`/`(SEL)0`.

---

### PAGE 3 — 开关/解锁/成就

Toggles → §2 hook table. Each toggle row runs `MT_SET(@"key", @(!MT_BOOL(@"key")))` (the molecheats `toggle()` call); the effect is delivered by the %hooks, not by a direct send.

| Label | Action |
|---|---|
| 金币 x10 | toggle `gold_x10` (set mult 10/1) |
| 经验 x10 | toggle `xp_x10` |
| 关反作弊检测 | toggle `kill_anticheat` |
| 作物瞬熟 | toggle `instant_crop` |
| 永不枯萎 | toggle `no_wither` |
| 冷却归零 | toggle `no_cooldown` |
| 建筑瞬完成 | toggle `instant_build` |
| 工人房间补满 | toggle `max_facility` |
| 产出×10(收菜) | toggle `harvest_mult` |
| 任务秒完成免费 | toggle `free_quest` |
| 小游戏奖励满 | toggle `minigame_reward` |
| 海底寻宝必中稀有 | toggle `seabed_best` |
| 等级 (cycle) | `MTBumpLevel();` — cycle forced curLevel 0/10/…/100; label shows 等级=N |
| 全物品解锁 | toggle `all_unlock` |
| 全成就通过 | toggle `all_achieve` |
| 魔法密码任意过 | toggle `magic_bypass` |
| 头像 = 1 | `id ui=MTUserInfoData(); ((void(*)(id,SEL,int))objc_msgSend)(ui,@selector(setAvatarIcon:),1); ((void(*)(id,SEL,int))objc_msgSend)(ui,@selector(setIconIndex:),1); MTSaveUserInfo();` |
| 头像 = 10 | same, id=10 |
| 头像 = 30 | same, id=30 |
| 头像 = 61 | same, id=61 |
| 奖励券 = 100 | `((void(*)(id,SEL,int))objc_msgSend)(MTGameData(),@selector(setRewardTickets:),100); MTSaveUserInfo();` |
| 奖励券 = 500 | same, val=500 |
| 一键收获全部 | `id om=MTShared("ObjectManager"); id farms=((id(*)(id,SEL))objc_msgSend)(om,@selector(farms)); NSUInteger n=[farms count]; for(NSUInteger i=0;i<n;i++){ id f=[farms objectAtIndex:i]; if(f && [f respondsToSelector:@selector(cropMatureHandler)]) [f cropMatureHandler]; } MTSaveUserInfo();` |

> `MTBumpLevel` cycles an int in the plist; the `UserInfoData -curLevel` hook returns it when non-zero (0 = passthrough).

---

### PAGE 4 — 开发者 / 调试

| Label | Action |
|---|---|
| 去越狱检测 | toggle `kill_jailbreak` (crack patch, §2.C) |
| 修复占卜功能(默认开) | toggle `fix_divine` (crack patch, default ON) |
| 节日村进入 | toggle `enter_holiday` (crack patch) |
| 商城免VIP等级 | toggle `store_no_vip` (crack patch) |
| 进新岛门(默认开) | toggle `enter_newislands` (crack patch, default ON) |
| 跳对象数据校验 | toggle `skip_parse_check` (crack patch) |
| 强制VIP | toggle `force_vip` |
| VIP等级 (cycle) | `MTBumpVipLevel();` — cycle 1..=15, force `force_vip=ON`; label VIP等级=N |
| 购物免费 | toggle `free_shop` |
| ▶ 一键进入黄金岛 | `MT_SET(@"enable_newscene_island",@YES); /* island_arm_entry: set ISLAND_ENTER_WINDOW */ id wm=MTShared("WrapperManager"); id village=((id(*)(id,SEL))objc_msgSend)(wm,@selector(currentVillageLayer)); if(village && [village respondsToSelector:@selector(enterNewIslands)]) [village enterNewIslands];` |
| 可建筑黄金岛·热点开关 | toggle `enable_newscene_island` |
| 修复加勒比寻宝 | toggle `fix_golden_island` |
| 直达终点(弃用) | toggle `golden_win` (also sets CARIBBEAN_DIRTY, forces fix_golden_island ON) |
| 打开加勒比黄金岛(弃用) | OpenCaribbean flow — see §1.4a |
| ✖ 关闭召唤层 | `if(LAST_SUMMONED){ ((void(*)(id,SEL,BOOL))objc_msgSend)(LAST_SUMMONED,@selector(removeFromParentAndCleanup:),YES); [LAST_SUMMONED release]; LAST_SUMMONED=nil; }` |
| GM面板 TestLayer | `MTSummon("TestLayer",99999);` |
| 黄金岛GM面板 NewSceneTestLayer | `MTSummon("NewSceneTestLayer",99999);` |
| 切到夜晚 | `[MTShared("CommonEffectController") formDayToNight];` (via objc_msgSend) |
| 切回白天 | `[MTShared("CommonEffectController") fromNightToDaybreak];` |
| ⚠️ 删本地存档 (2-tap confirm) | `NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]; NSFileManager *fm=[NSFileManager defaultManager]; [fm removeItemAtPath:[dir stringByAppendingPathComponent:@"userinfo.dat"] error:nil]; [fm removeItemAtPath:[dir stringByAppendingPathComponent:@"map.dat"] error:nil];` |

**§1.4a OpenCaribbean flow:**
```objc
MT_SET(@"fix_golden_island",@YES);              // enable_golden_island()
id data = MTBuildCaribbeanData();               // build_caribbean_data(), §2.D
id gd = MTGameData();
((void(*)(id,SEL,id))objc_msgSend)(gd,@selector(setCaribbeanData:),data);
Class cl = objc_getClass("CaribbeanMainLayer");
id layer = [[cl alloc] init];
[MTRunningScene() addChild:layer z:88888];      // via objc_msgSend addChild:z:
id nm = MTShared("NetworkManager");
if(nm && [nm respondsToSelector:@selector(setDelegateCaribbeanActivity:)])
    ((void(*)(id,SEL,id))objc_msgSend)(nm,@selector(setDelegateCaribbeanActivity:),layer);
if([layer respondsToSelector:@selector(showLayerWithTarget:selector:)])
    ((void(*)(id,SEL,id,SEL))objc_msgSend)(layer,@selector(showLayerWithTarget:selector:),nil,(SEL)0);
else if([layer respondsToSelector:@selector(displayUI)])
    [layer displayUI];
[layer release];
```

---

## 2. TOGGLE CHEATS → Logos %hook translation

### 2.A Register-override intercepts → forced return / arg mutation

For each, the emulator's "fill r0..r3=0 / r0=N / return true" becomes a Logos `%hook … { return <val>; }` (skip `%orig`), and "return false / arg-scale" becomes "mutate arg, then `return %orig(mutated)`". All gated on `MT_BOOL(@"tweak_enabled") && MT_BOOL(@"<key>")`.

| Key | Class | Selector | Hook behavior |
|---|---|---|---|
| free_shop | UserInfoData | `-addGold:` | if `(int)delta<0` → `return; // swallow (BOOL: return YES/skip)`. else fall to gold_x10 arm. |
| free_shop | UserInfoData | `-addVipGold:` | if `(int)delta<0` → swallow (return without %orig). No mult on gains. |
| gold_x10 | UserInfoData | `-addGold:` | if `mult>1 && (int)delta>0` → `%orig(sat_mul(delta,mult))`. Runs original. |
| xp_x10 | UserInfoData | `-addXp:` | if `mult>1 && (int)delta>0` → `%orig(sat_mul(delta,mult))`. |
| kill_anticheat | GameData | `-isHackData` | `return NO;` |
| kill_anticheat | NewSceneUserInfoData | `-isHackData` | `return NO;` |
| kill_anticheat | WrapperManager | `-showCheatWarningMessage` | `return;` (swallow) |
| kill_anticheat | iMoleVillageAppDelegate | `-showCheatWarningMessage` | `return;` (swallow) **[ADD — tweak lacks this class]** |
| kill_anticheat | NewSceneData | `-checkUserinfoMd5:` | `return YES;` (checksum passes) |
| kill_anticheat | NewSceneData | `-CheckUserInfoData:` | `return 0;` (0==OK) |
| kill_anticheat | SystemTimeCheck | `-check` | `return;` (swallow) **[ADD]** |
| kill_anticheat | SystemTimeCheck | `-start` | `return;` (swallow) **[ADD]** |
| force_vip | WrapperManager | `-checkIsVipUser` | `return YES;` |
| force_vip | UserInfoLayer | `-isShowVIPFunctionsButton:` | **setter, not getter** → `%orig(YES);` (force arg, call original). Do NOT skip. |
| force_vip | UserVIPInfoData | `-vipLevelWithNewType` | returns **NSString\*** → `return MTVipLevelString();` (persistent `@"1"`..`@"4"`, VIP_LEVEL clamped 1..4). Never a bare int. |
| force_vip | UserVIPInfoData | `-vipValue` | `return 999999;` |
| instant_crop | Farm | `-getMatureTime` | `return 0.0;` (double) |
| no_wither | Farm | `-getWitherTime` | `return 1.0e15;` (double) |
| no_wither | Farm | `-cropWitherHandler:` | `return;` (swallow) |
| no_cooldown | Building | `-getCurLevelCoolTime` | `return 0.0;` |
| no_cooldown | Building | `-getLastCooldownTime` | `return 0.0;` |
| no_cooldown | Building | `-getLastGameCoolTime` | `return 0.0;` |
| no_cooldown | NewSceneRestaurant | `-getOutCoolTime` | `return 0.0;` |
| no_cooldown | MCNpcActor | `-getCurLevelCooltime:` | `return 0.0;` (double, takes arg) |
| no_cooldown | YaliNpcActor | `-checkCooltimeOver` | `return YES;` (BOOL) |
| instant_build | Building | `-getBuildTime:` | `return 0.0;` (double, takes arg) |
| all_unlock | WrapperManager | `-isUnlockedItem:` | `return YES;` |
| all_unlock | MusicHallLayer | `-checkIsUnlockMusic:` | `return YES;` **[ADD]** |
| all_unlock | AvatarLayer | `-checkRequiredVipLevel:` | `return YES;` **[ADD]** |
| all_unlock | GameData | `-getLockType4Crop:` | `return 0;` **[ADD]** |
| all_unlock | GameData | `-getLockType4CropWithId:` | `return 0;` **[ADD]** |
| all_unlock | GameData | `-getLockType4Object:` | `return 0;` **[ADD]** |
| all_unlock | GameData | `-getLockType4Gift:` | `return 0;` **[ADD]** |
| all_unlock | NewSceneData | `-getLockType4Object:` | `return 0;` **[ADD]** |
| all_unlock | NewSceneData | `-getLockType4Crop:` | `return 0;` **[ADD]** |
| all_unlock | DecorateRoomLayer | `-getLockType4Decorate:` | `return 0;` **[ADD]** |
| all_unlock | MusicHallLayer | `-getLockType4Decorate:` | `return 0;` **[ADD]** |
| max_facility | UserInfoData | `-totalWorkers` | `return 99;` **[ADD]** |
| max_facility | UserInfoData | `-availableWorkers` | `return 99;` **[ADD]** |
| max_facility | UserInfoData | `-totalRooms` | `return 99;` **[ADD]** |
| harvest_mult | ObjectManager | `-getXPSpeedUpObjectMultiple` | `return 1000;` **[ADD]** |
| harvest_mult | ObjectManager | `-getGoldSpeedUpObjectMultiple` | `return 1000;` **[ADD]** |
| free_quest | Quest | `-shellsNeeded` | `return 0;` **[ADD]** |
| free_quest | TimeQuest | `-shellsNeeded` | `return 0;` **[ADD]** |
| seabed_best | SeabedSeekingTreasureMainLayer | `-generateRandomRewardId` | `return 31169;` **[ADD]** |
| minigame_reward | FishingGame | `-getRewardCoin:` | `return 99999;` **[ADD]** |
| minigame_reward | MinerGame | `-getRewardCoin:` | `return 99999;` **[ADD]** |
| minigame_reward | MinerGame | `-getRewardXp:` | `return 99999;` **[ADD]** |
| all_achieve | AchievementControl | `-checkInAlreadyUnlockList:` | `return YES;` **[ADD]** |
| all_achieve | NewSceneAchievement | `-checkInAlreadyUnlockList:` | `return YES;` **[ADD]** |
| all_achieve | AchievementItems | `-unlocked:` | `return YES;` **[ADD]** |

> **Polarity is per-selector** (verbatim from molecheats): `isHackData/CheckUserInfoData:/showCheatWarning/getLockType4* → 0/NO`; `checkUserinfoMd5:/checkIsUnlockedItem/checkRequiredVipLevel:/checkInAlreadyUnlockList: → 1/YES`.
> **Do NOT hook the void `checkAchieve_*` methods** — wrong signature → EXC_BAD_ACCESS (molecheats explicitly warns; only the BOOL getters above).
> **Double returns** (`getMatureTime`, `getWitherTime`, cooldown getters, `getBuildTime:`, `getCurLevelCooltime:`): declare the hooked method returning `double` in Logos and `return 0.0;`/`return 1e15;` — the armv7 ABI handles d0/r0:r1 automatically; do not emulate the soft-float register split.

### 2.B magic_bypass (special — not in generic interceptor)

molecheats: a class-gated `MagicNumberView` hook reads `magic_bypass_on()`. Current tweak hooks `MagicNumberView -onButtonYesSelected:` and calls delegate `onMagicNumberFinished`.

**[FIX — unverified selector]** The delegate callback name `onMagicNumberFinished` is molecheats-unverified AND tweak-unverified. Keep the mechanism but **guard with `respondsToSelector:`** and probe candidate names; if none respond, fall through to `%orig` (never crash):
```objc
%hook MagicNumberView
- (void)onButtonYesSelected:(id)s {
    if(MT_BOOL(@"tweak_enabled") && MT_BOOL(@"magic_bypass")){
        id del = [self magicNumberDelegate];
        SEL cb[] = { @selector(onMagicNumberFinished), @selector(magicNumberFinished),
                     @selector(onMagicNumberCorrect) };
        for(int i=0;i<3;i++) if(del && [del respondsToSelector:cb[i]]){
            ((void(*)(id,SEL))objc_msgSend)(del,cb[i]); break; }
        if([self respondsToSelector:@selector(doClose)]) [self doClose];
        return;
    }
    %orig;
}
%end
```

### 2.C Crack-patch cheats (6 toggles) — real-device approach

molecheats writes bytes to guest `__TEXT` vaddrs and invalidates the JIT. On a jailbroken device there is **no JIT**; the two faithful options are:

1. **Runtime in-memory byte patch** of the app binary's mapped `__TEXT`. Compute `slide = _dyld_get_image_vmaddr_slide(0)` (or the main image), `patchAddr = vaddr + slide`, then `vm_protect(mach_task_self(), page, len, FALSE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY)`, `memcpy` the cracked bytes, restore protection, and flush the i-cache with `sys_icache_invalidate(patchAddr, len)`. Toggling off writes the vanilla bytes back. This reproduces molecheats 1:1 (same vaddrs, same byte arrays).
2. **Method %hook equivalent** (higher-level, preferred where a clean method exists).

| Key | vaddrs (from INPUT 1) | Real-device recommendation |
|---|---|---|
| kill_jailbreak | 0x2fb9ec, 0x4850ca, 0x4f6d00(16B), 0x562c16, 0x5757d8, 0x606bb0(4B ARM), 0x6b60d6, 0x74c984, 0x7c8de6, 0x7c8e1c, 0x85aaa0(13B) | **Byte patch** all 11 (or `%hook` each SDK `-isJailbroken`/`-isDeviceCracked` → `return NO`). molecheats notes these are mostly redundant under touchHLE; on a real JB device the byte patch is the faithful path. |
| fix_divine (default ON) | 0x21638e(8B), 0x21718e(8B), 0xf4102(90B control-flow rewrite) | **Byte patch** the two small ones. For 0xf4102, byte patch is faithful; method alt = `%hook MiniGameManager -enterMiniGame:stage:` (skip gate) + `%hook DivineGame -firstCostPlay`/`-costGoldToDivine` (charge 0). Prefer byte patch to match exactly. |
| enter_holiday | 0x2393ec, 0x23940a, 0x239429 | **Byte patch** (BEQ→NOP ×2, BNE→uncond B) or `%hook HolidayVillageLayer -onEnter` skip checks. |
| store_no_vip | 0x3b22c0 (BNE→NOP) | **Byte patch** or `%hook NewStyleStoreMainLayer -purchaseCallback` skip VIP check. |
| enter_newislands (default ON) | 0x37650 (BEQ→NOP) | **Byte patch** or `%hook VillageLayer -enterNewIslands` skip gate. Prerequisite for enable_newscene_island. |
| skip_parse_check | 0x6f1ea (→ mov r0,#0) | **Byte patch** or `%hook GameData -parseObjectData:` force intermediate check to pass. |

> **Cannot be reproduced 1:1 as a pure Logos %hook:** the 0xf4102 90-byte and 0x6f1ea intra-function rewrites are *control-flow edits inside a method body*, not method entry/exit — a `%hook` can only approximate them (skip whole method / force a return). Faithful reproduction requires the runtime byte-patch path (option 1). Recommend building an `MTApplyCrackPatch(vaddr, vanilla[], cracked[], len, on)` helper driven by the same auto-generated diff table.
> The **7th CrackGroup (MapSync, 0x768fa)** is NOT a toggle — set programmatically only in online mode. Exclude from the menu (matches molecheats).

### 2.D enable_newscene_island + Caribbean runtime hooks (offline island)

This is the largest block. Reproduce as a set of `%hook`s all gated on `MT_BOOL(@"enable_newscene_island")` plus the frame-window/on-island flags. **Key real-device deviations from the emulator:**

- **LR (r14) call-site gating is impossible in Logos** (can't read the caller return address). molecheats forces `NewGameManager -gameMode` / `WrapperManager -currentGameMode` to 1 *only* at specific LRs (0x2497a9 / 0x32643b / 0x24bec3). **[FIX-mechanism]** Instead hook the **specific call-site methods** and bypass their `gameMode==1` gate directly: `RestaurantView`/`ApartmentView`/`ShopItemsLayer` `-showWithTarget:selector:` (Barbara's/Restaurant/ingredient-store) — do NOT globally force `gameMode=1` (that pauses cocos2d and freezes the island).
- **State flags** in the tweak: `ISLAND_ENTER_WINDOW` (int frame countdown), `ON_ISLAND` (BOOL), `ISLAND_INJECTED`, `CARIBBEAN_DIRTY`, `GOLDEN_WIN` — static globals in Tweak.xm.
- **Frame driver:** hook a per-frame method (`-drawScene`/`-mainLoop`) to decrement `ISLAND_ENTER_WINDOW` and advance a watchdog. (Current tweak has no such frame hook — **[ADD]**.)

Hooks (all `%orig` unless "swallow"):

| Class | Selector | Behavior (gated) |
|---|---|---|
| HolidayVillageLayer | `-showNoNetConnectErrorMessage` | swallow (`return`) |
| HolidayVillageLayer | `-showNetConnectErrorMessageWithRetryButton` | swallow |
| HolidayVillageLayer | `-showMultiLoginErrorMessageInNewScene` | swallow |
| (any) | `-showWithTarget:selector:` | ON_ISLAND && `(uintptr_t)target < 0x1000` → swallow (guards garbage-ptr `isKindOfClass:` crash); valid target → `%orig`. |
| NewSceneApartment | `-setCurrentProduceMoleNums:` | ON_ISLAND: read old via `currentProduceMoleNums`; if new>old, `[[NewSceneData sharedInstance].userInfoDataInNewScene addWorker:(new-old)]`, set arg=old, `%orig(old)`. |
| LoadingHoliday | `-updateLoading:` | WINDOW>0: read `curStep_` at self+0x10 (i32); if>=2 write `updatePause_` at self+0xC (u8)=0; `%orig`. |
| NetworkManager | `-isConnected` | WINDOW>0 \|\| ON_ISLAND → `return YES`. |
| NetworkManager | `-state` | in-window/on-island → `return 6`. |
| SceneMannager | `-curSceneId` | in-window/on-island && ON_ISLAND: read real `curSceneId_` at self+12; if real≠10 && real≠1 → `return 10`. |
| NewSceneData | `-moleUpperLimit` | in-window/on-island && ON_ISLAND: read self+180 (u32); if<16 → `return 16`; else `%orig`. |
| (any) | `-isReachable` | in-window/on-island → `return YES` (bare selector, ANY class). |
| NetworkManager | `-setModObjectToServer:` | in-window/on-island: `writeback_island_object(arg)` then swallow (`return YES`). |
| (any) | `-sendPacket:commandId:` | in-window/on-island → swallow. |
| (any) | `-sendAllBufferDatas` | in-window/on-island → swallow. |
| (any) | `-sendAllBuffDataInNewSceneLoading` | in-window/on-island → swallow. |
| NewGameManager | `-gameMode` | **[FIX]** do NOT LR-gate; leave `%orig`. Bypass gates via the showWithTarget: hooks above. |
| WrapperManager | `-currentGameMode` | **[FIX]** same — leave `%orig`; bypass at ShopItemsLayer. |
| NewSceneData | `-getLockType4ShopItem:shop:` | in-window/on-island → `return 0`. |
| NewScenePorter | `-inRectOfAquaticAreaOrNot:` | in-window/on-island → `return 0`. |
| NewScenePorter | `-checkBeyoundLeftCircleBeach:` | in-window/on-island → `return 0`. |
| (frame) | `-drawScene`/`-mainLoop` | ENABLE: watchdog++; if WINDOW>0 WINDOW--. |
| (various) | `-loadNewScene:` | WINDOW>0: `ON_ISLAND=YES`. |
| (various) | `-gobackMainVillage` | **pre-method**: save island userinfo, merge objects into mapdata, save map/fragments, `ON_ISLAND=NO`; then `%orig`. |
| VillageLayer | `-enterNewIslands` | `ISLAND_INJECTED=NO`; if WINDOW<=0 WINDOW=1200; `%orig`. |
| GameManager | `-updateGameDateForEnterNewSceneWithTarget:andCallback:` | target=arg; `ISLAND_INJECTED=NO`; WINDOW=1200; if target `[target performSelector:@selector(onGameDataInMainVillageUpdateSUCC) withObject:nil afterDelay:0]`; swallow packet (`return YES`). |
| (various) | `-getAllObjectsListFromServerWithStartId:` | WINDOW>0 && !injected: `ISLAND_INJECTED=YES`, `build_default_island_mapdata()`, swallow. |

**Ivar reads** use `class_getInstanceVariable`+`ivar_getOffset` where possible; only fall back to fixed offsets (curSceneId_ +12, moleUpperLimit +180, curStep_ +0x10, updatePause_ +0xC) if the ivar name isn't in the dump.

**fix_golden_island / golden_win / MTBuildCaribbeanData:**
```objc
static id MTBuildCaribbeanData(void){
    Class cl = objc_getClass("CaribbeanDiscoveringData");
    id d = [[cl alloc] init];
    BOOL win = MT_BOOL(@"golden_win");
    ((void(*)(id,SEL,int))objc_msgSend)(d,@selector(setCurIsland:), win?5:1);
    ((void(*)(id,SEL,int))objc_msgSend)(d,@selector(setDistanceToNext:), win?0:100);
    ((void(*)(id,SEL,int))objc_msgSend)(d,@selector(setTotleDistance:),500);
    ((void(*)(id,SEL,int))objc_msgSend)(d,@selector(setCorrectionSoulOfTheSea:),9999);
    ((void(*)(id,SEL,int))objc_msgSend)(d,@selector(setLeftDaysNum:),99);
    return [d autorelease];
}
```
Gate the `GameData -caribbeanData` hook to return this when server data is nil, and swallow `CaribbeanMainLayer -showNetWorkError` + `NetworkManager -getCaribbeanStateInfo:` (return 0) — the current tweak already does these two ([KEEP]).

---

## 3. DIFF TABLE — every feature tagged

### Toggle keys

| Feature | Tag | Old → New |
|---|---|---|
| free_shop (addGold:/addVipGold: negative swallow) | **[FIX]** | Currently gated on `kKeyEnabled` only → **gate on `free_shop`**. Keep addGold: swallow, add addVipGold: swallow. |
| gold_x10 (addGold: positive scale) | **[KEEP]** | already `%orig(delta*mult)`; ensure `mult>1` on-check. |
| xp_x10 (addXp:) | **[KEEP]** | already applies xp_multiplier. |
| kill_anticheat: GameData/NewSceneUserInfoData isHackData | **[FIX]** | `checkUserinfoMd5:`/`CheckUserInfoData:` currently gated on `kKeyEnabled` → **gate on `kill_anticheat`**. |
| kill_anticheat: WrapperManager showCheatWarningMessage | **[KEEP]** | present. |
| kill_anticheat: iMoleVillageAppDelegate showCheatWarningMessage | **[ADD]** | new class. |
| kill_anticheat: SystemTimeCheck -check / -start | **[ADD]** | new class, both swallow. |
| force_vip: WrapperManager checkIsVipUser | **[KEEP]** | (verify selector — see §note). |
| force_vip: UserInfoLayer isShowVIPFunctionsButton: | **[KEEP]** | already `%orig(YES)` setter form. |
| force_vip: UserVIPInfoData vipLevelWithNewType | **[ADD/FIX]** | tweak overrides `vipLevel` ivar/getter; molecheats also needs **`vipLevelWithNewType` → NSString `@"1".."4"`** (clamp 1..4). Add it; callers do `[result intValue]`. |
| force_vip: UserVIPInfoData vipValue | **[KEEP]** | →999999. |
| instant_crop: Farm getMatureTime | **[KEEP]** | →0.0. (Keep ivar write too — harmless belt-and-suspenders.) |
| no_wither: Farm getWitherTime / cropWitherHandler: | **[KEEP]** | →1e15 / swallow. |
| no_cooldown: Building 3 getters + NewSceneRestaurant getOutCoolTime + MCNpcActor getCurLevelCooltime: + YaliNpcActor checkCooltimeOver | **[KEEP]** | all present. |
| instant_build: Building getBuildTime: | **[KEEP]** | →0.0. |
| all_unlock: WrapperManager isUnlockedItem: | **[KEEP]** | →YES. |
| all_unlock: MusicHallLayer checkIsUnlockMusic:, AvatarLayer checkRequiredVipLevel:, 8× getLockType4* | **[ADD]** | none present; add all 10, polarity per §2.A. |
| max_facility: UserInfoData totalWorkers/availableWorkers/totalRooms | **[ADD]** | new toggle. |
| harvest_mult: ObjectManager getXP/GoldSpeedUpObjectMultiple | **[ADD]** | →1000. |
| free_quest: Quest/TimeQuest shellsNeeded | **[ADD]** | →0. |
| seabed_best: generateRandomRewardId | **[ADD]** | →31169. |
| minigame_reward: FishingGame getRewardCoin:, MinerGame getRewardCoin:/getRewardXp: | **[ADD]** | →99999. |
| all_achieve: AchievementControl/NewSceneAchievement checkInAlreadyUnlockList:, AchievementItems unlocked: | **[FIX]** | current "all_achievements" button calls `resetAllAchievementData` on `AchievementControl 'shareInstance'` (typo). Replace with the 3 BOOL-getter hooks; never hook void `checkAchieve_*`. |
| magic_bypass: MagicNumberView onButtonYesSelected: | **[FIX]** | delegate selector `onMagicNumberFinished` unverified → guard + probe candidates (§2.B). |
| kill_jailbreak | **[ADD]** | crack-patch cheat (§2.C); tweak has no jailbreak toggle. |
| fix_divine (default ON) | **[ADD]** | crack-patch; tweak lacks. |
| enter_holiday | **[ADD]** | crack-patch. |
| store_no_vip | **[ADD]** | crack-patch. |
| enter_newislands (default ON) | **[ADD]** | crack-patch. |
| skip_parse_check | **[ADD]** | crack-patch. |
| enable_newscene_island (default ON) + full island block | **[ADD/FIX]** | tweak has none of the offline buildable-island machinery. Add per §2.D; **FIX** the LR-gated gameMode forcing → call-site method hooks. |
| fix_golden_island (default ON) | **[FIX]** | present (GameData caribbeanData synth) — verify setter names (§5); keep, set default ON. |
| golden_win | **[KEEP]** | present as `golden_island_win`; **rename key to `golden_win`** and set CARIBBEAN_DIRTY + force fix_golden_island ON on toggle. |

### Menu-action / button selectors

| Item | Tag | Old → New |
|---|---|---|
| AchievementControl singleton | **[FIX]** | `'shareInstance'` (deliberate typo) → verify true selector; use `MTShared` probe (sharedManager/shareInstance/sharedInstance). |
| MiniGameManager start | **[FIX]** | current gameId map Bug/Fish/Divine/Miner/Paint/Wash is a guess → **use molecheats map**: 1=切水果,2=拍虫子,3=挖矿石,4=敲木桩,5=钓鱼. |
| addVipGold +1000 | **[FIX]** | current uses `addVipGold:` → molecheats uses **`addVipGoldForBuy:UIUpdate:`** (proper UI-updating path). |
| 头像 set | **[KEEP]** | `setAvatarIcon:`+`setIconIndex:` matches molecheats. |
| Currency ± | **[FIX]** | move from Dev-Panel-only into page 0 GhostTL grid in molecheats order/labels. |
| StoreKit instant_purchase | **[TWEAK-ONLY]** | see §4. |
| time_magic / fake_timestamp | **[TWEAK-ONLY]** | see §4. |
| show_hidden / secret_button / easter_egg | **[TWEAK-ONLY]** | see §4. |

---

## 4. TWEAK-ONLY FEATURES (molecheats lacks)

| Feature | Recommendation | Reasoning |
|---|---|---|
| `instant_purchase` — full InAppPurchaseManager StoreKit passthrough (purchase:, canPurchase:, validateReceipt:, SKPaymentTransaction state=Purchased, ivar writes result_/isInPurchase_) | **KEEP** (own row on page 4, off by default) | INPUT 3 marks this flow VERIFIED-CORRECT against dumps. molecheats runs in an offline emulator with no StoreKit, so it never needed it; on a real device it's genuinely useful. The only weak spot is the "amount from trailing digits of productId" heuristic — keep but label as best-effort. |
| `free_shop` IAP-eligibility hooks (canPurchase:/hasAlreadyPurchased:/validateReceipt:/checkRightInJailBroken:/checkIsCurrentUserId → YES) | **KEEP** under free_shop | Complements molecheats free_shop (which only swallows addGold:/addVipGold:); harmless superset on device. |
| `time_magic` + `fake_timestamp` (NewSceneTimer getCurrentServerTime override) | **KEEP** (page 4 dev section) | Enables festival triggers offline; molecheats handles festivals differently but this is a strict addition. Verify `getCurrentServerTime` return type (§5). |
| `show_hidden` (MainMenuScene hidden-menu halo overlay) | **DROP** | Cosmetic dev-only; `hiddenMenuPosition` return type unverified; not in molecheats. Low value, crash risk. |
| `secret_button` / `easter_egg` (EasterEggMainLayer ivar writes, GameData easterEggsFlag) | **KEEP but demote** | molecheats summons `EasterEggMainLayer` directly (page 1). Keep the summon; the ivar-forcing toggles are optional — retain as page-4 dev switches, low priority. Verify ivar names before shipping. |
| `log_to_file` (NSLog to file) | **KEEP** | dev convenience, no game impact. |
| `all_items_unlocked` "真解锁写存档" (unlockItem: loop writing save) | **DROP or gate hard** | `unlockItem:` selector unverified and **destructive** (writes save). molecheats achieves unlock non-destructively via `all_unlock` getters. Prefer the getter approach; drop the save-writing loop. |
| Direct ivar writes for Farm/Building/Restaurant/Shop times | **KEEP as backup** | molecheats uses getter overrides only; the ivar writes are redundant but harmless *if names are verified* (§5). Keep the getter hooks as primary; treat ivar writes as optional. |

---

## 5. VERIFICATION TODO (before shipping — unverified selectors/ivars)

Resolve against class dumps; all should be `respondsToSelector:`-guarded regardless:

1. **MagicNumberView** delegate callback (`onMagicNumberFinished`?) — single most-likely-wrong selector.
2. **WrapperManager**: `checkIsVipUser`, `isUnlockedItem:`, `showCheatWarningMessage`, `currentVillageLayer`, `currentGameMode` (dump truncated).
3. **New molecheats classes/selectors** not yet in tweak: `iMoleVillageAppDelegate`, `SystemTimeCheck check/start`, `MusicHallLayer`, `AvatarLayer checkRequiredVipLevel:`, all `getLockType4*`, `ObjectManager getXP/GoldSpeedUpObjectMultiple` + `farms`, `Quest/TimeQuest shellsNeeded`, `SeabedSeekingTreasureMainLayer generateRandomRewardId`, `FishingGame/MinerGame getReward*`, `AchievementControl/NewSceneAchievement/AchievementItems`, `NewSceneApartment setCurrentProduceMoleNums:`, `LoadingHoliday`, `NewScenePorter`, `SceneMannager curSceneId`, `NewSceneData moleUpperLimit/getLockType4ShopItem:shop:`.
4. **GameData**: `addVipGoldForBuy:UIUpdate:`, `resetUnfinishedDailyQuestDataInMap/resetTimeQuestDataInMap/resetVipQuestDataInMap/resetLastGetDailyRewardDay/resetDailyQuestList/resetTreasureChestData/resetCaribbeanData/resetUserGameData`, `loadMapdataFromResource:/loadUserInfoFromResource:/saveMapData/saveUserInfoData`, `setCaribbeanData:/caribbeanData`, `setRewardTickets:`.
5. **GameManager**: `addTreasureReward/addTreasureRabbitReward/activateStoryQuest`.
6. **CaribbeanDiscoveringData** setters (`setCurIsland:/setDistanceToNext:/setTotleDistance:[sic]/setCorrectionSoulOfTheSea:/setLeftDaysNum:`) — win-state constants are fabricated (curIsland=5/dist=0/total=500/soul=9999/left=99); molecheats uses the same, so keep.
7. **Ivar offsets** (fixed-offset fallbacks): curSceneId_ +12, moleUpperLimit_ +180, LoadingHoliday curStep_ +0x10 / updatePause_ +0xC, plus any legacy Building/Farm/VIP ivars kept as backups.
8. **Type signatures** on hooked getters (must match binary ABI): `curLevel` (unsigned char), `NewSceneData get*` (unsigned long), `getCurrentServerTime` (unsigned long), all double-returning cooldown/time getters.
9. Crack-patch byte arrays + vaddrs (INPUT 1 lists them literally; do not hand-edit — drive from the auto-generated diff).

---

## 6. COMPLETENESS CHECK

**Every toggle key in INPUT 1 (28) is accounted for:**
free_shop ✓, kill_anticheat ✓, force_vip ✓, gold_x10 ✓, xp_x10 ✓, instant_crop ✓, no_wither ✓, no_cooldown ✓, instant_build ✓, all_unlock ✓, max_facility ✓, harvest_mult ✓, free_quest ✓, seabed_best ✓, minigame_reward ✓, all_achieve ✓, magic_bypass ✓, fix_golden_island ✓, golden_win ✓, enable_newscene_island ✓, kill_jailbreak ✓, fix_divine ✓, enter_holiday ✓, store_no_vip ✓, enter_newislands ✓, skip_parse_check ✓. (MapSync 7th CrackGroup correctly excluded — not a toggle.)

**Every button in INPUT 2 (all 5 pages) is accounted for:** page 0 (27 rows) ✓, page 1 (31 summons) ✓, page 2 (19) ✓, page 3 (24) ✓, page 4 (22) ✓ — all mapped to concrete on-device ObjC in §1.

**Items that CANNOT be reproduced 1:1 on device (approximation required):**

1. **LR/return-address call-site gating** (`gameMode`/`currentGameMode` at LRs 0x2497a9/0x32643b/0x24bec3) — Logos cannot read r14 of the caller. **Approximation:** hook the specific call-site methods (RestaurantView/ApartmentView/ShopItemsLayer `-showWithTarget:selector:`) to bypass their `gameMode==1` gate instead of forcing the getter. Behaviorally equivalent, mechanically different.
2. **Intra-function control-flow byte rewrites** — `fix_divine` 0xf4102 (90B) and `skip_parse_check` 0x6f1ea. A pure `%hook` cannot patch mid-method logic; **faithful reproduction needs the runtime in-memory byte-patch path** (§2.C option 1), which IS achievable on a JB device via `vm_protect`+`memcpy`+`sys_icache_invalidate` at `vaddr+slide`. The method-%hook alternative only approximates.
3. **Guest-memory byte patches generally** (all 6 crack cheats) — reproducible on device via the byte-patch helper, but require the app image slide and writable `__TEXT`; if any target device hardens `__TEXT` this falls back to method %hooks (kill_jailbreak, enter_holiday, store_no_vip, enter_newislands each have clean method-hook fallbacks; fix_divine/skip_parse_check do not fully).

Everything else maps to a concrete `%hook` or `objc_msgSend` call as specified above.
