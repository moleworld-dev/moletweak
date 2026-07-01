// ============================================================================
//  MoleTweak - 摩尔庄园 5.5.0 修改器
//  功能: 1) 修改摩尔豆(gold)和贝壳(vipGold)
//        2) 修改等级(curLevel)和经验(xp)
//        3) 作物瞬间成熟 / 关闭枯萎
//        4) VIP金币/经验加成倍率
// ============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// SDK 9.3 TBD 不导出 memset,自己实现一个,使用 __asm__ 重命名,避免 clang 优化为 builtin
__attribute__((visibility("hidden"), used))
void *memset(void *b, int c, size_t len) {
    unsigned char *p = (unsigned char *)b;
    while (len-- > 0) *p++ = (unsigned char)c;
    return b;
}

__attribute__((visibility("hidden"), used))
void *memcpy(void *dst, const void *src, size_t len) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (len-- > 0) *d++ = *s++;
    return dst;
}

// =============== 修改器全局开关 (NSUserDefaults 持久化) ===============
static NSString * const kSuiteName  = @"com.xiaochoumao.moletweak";
static NSString * const kKeyEnabled = @"tweak_enabled";
static NSString * const kKeyGold    = @"override_gold";        // 0 = 不改
static NSString * const kKeyVipGold = @"override_vipgold";     // 0 = 不改
static NSString * const kKeyXp      = @"override_xp";          // 0 = 不改
static NSString * const kKeyLevel   = @"override_level";       // 0 = 不改
static NSString * const kKeyInstant = @"instant_crop";         // BOOL
static NSString * const kKeyNoWither= @"no_wither";            // BOOL
static NSString * const kKeyXpMul   = @"xp_multiplier";        // float
static NSString * const kKeyGoldMul = @"gold_multiplier";      // float
// v2 新增
static NSString * const kKeyInstantBuild = @"instant_build";   // BOOL  建筑瞬完成
static NSString * const kKeyFreeShop     = @"free_shop";       // BOOL  购物不扣钱
static NSString * const kKeyForceVip     = @"force_vip";       // BOOL  VIP 强制激活
static NSString * const kKeyVipLevel     = @"vip_level";       // int   VIP 等级 (1-10)
static NSString * const kKeyNoCD         = @"no_cooldown";     // BOOL  全局冷却归零
// v3 程序员后门 (默认全 OFF,避免与游戏正常逻辑冲突)
static NSString * const kKeyAntiCheat    = @"kill_anticheat";  // BOOL  关掉反作弊检测
static NSString * const kKeyMagicBypass  = @"magic_bypass";    // BOOL  魔法密码任意通过
static NSString * const kKeySecretBtn    = @"secret_button";   // BOOL  秘密按钮显形
static NSString * const kKeyEasterEgg    = @"easter_egg";      // BOOL  彩蛋激活
// v5 隐藏入口/日志重定向
static NSString * const kKeyShowHidden   = @"show_hidden";     // BOOL  显示主菜单 hiddenMenuPosition
static NSString * const kKeyLogToFile    = @"log_to_file";     // BOOL  NSLog 重定向到文件
// v6 服务器停服功能修复
static NSString * const kKeyFixGoldenIsland = @"fix_golden_island"; // BOOL 修复黄金岛(加勒比寻宝活动)
// v11 新发现
static NSString * const kKeyAllAchieve = @"all_achievements"; // BOOL 全部成就检查通过
// v12 物品/小游戏
static NSString * const kKeyAllUnlock  = @"all_items_unlocked"; // BOOL 所有物品视为已解锁
// v13 玩家自定义/任务重置/时间魔法/隐藏 NPC
static NSString * const kKeyAvatarIcon  = @"avatar_icon_id";    // int 头像 ID (1-61)
static NSString * const kKeyTotalRooms  = @"total_rooms";       // int 总房间数
static NSString * const kKeyTotalWorkers= @"total_workers";     // int 工人数
static NSString * const kKeyTimeMagic   = @"time_magic";        // BOOL 启用时间欺骗
static NSString * const kKeyFakeTime    = @"fake_timestamp";    // NSString unix epoch 秒
// v14 一键奖励/重置/Layer 召唤
static NSString * const kKeyTickets     = @"reward_tickets";    // int 奖励券数
// v15 黄金岛航行进度
static NSString * const kKeyGoldenWin   = @"golden_island_win"; // BOOL 直接设到终点(curIsland=5)
// v20 商店购买直通
static NSString * const kKeyInstantPurchase = @"instant_purchase"; // BOOL 点购买就成功(跳 StoreKit)
// v21 molecheats 对齐 —— 新增开关 (来自 mole_cheats.rs 已验证选择器)
static NSString * const kKeyMaxFacility     = @"max_facility";      // BOOL 工人/空闲工人/房间 getter 恒 99
static NSString * const kKeyHarvestMult     = @"harvest_mult";      // BOOL 收菜结算加成 getter 恒 1000 (=10x)
static NSString * const kKeyFreeQuest       = @"free_quest";        // BOOL 任务/催熟所需贝壳 → 0
static NSString * const kKeySeabedBest      = @"seabed_best";       // BOOL 海底寻宝 generateRandomRewardId 必中稀有
static NSString * const kKeyMinigameReward  = @"minigame_reward";   // BOOL 钓鱼/挖矿 getReward* 恒大值

// ivar 直写宏 - 用 object_getClass(runtime 函数,无类型推断问题)而非 [obj class]
#define MT_IVAR_F(o, name, val) do { \
    Ivar __v = class_getInstanceVariable(object_getClass(o), name); \
    if (__v) { *(float *)((char *)(__bridge void *)o + ivar_getOffset(__v)) = (val); } \
} while (0)

#define MT_IVAR_D(o, name, val) do { \
    Ivar __v = class_getInstanceVariable(object_getClass(o), name); \
    if (__v) { *(double *)((char *)(__bridge void *)o + ivar_getOffset(__v)) = (val); } \
} while (0)

#define MT_IVAR_I(o, name, val) do { \
    Ivar __v = class_getInstanceVariable(object_getClass(o), name); \
    if (__v) { *(int *)((char *)(__bridge void *)o + ivar_getOffset(__v)) = (val); } \
} while (0)

#define MT_IVAR_UL(o, name, val) do { \
    Ivar __v = class_getInstanceVariable(object_getClass(o), name); \
    if (__v) { *(unsigned long *)((char *)(__bridge void *)o + ivar_getOffset(__v)) = (val); } \
} while (0)

// iOS 6 兼容: 用 plist 文件直接持久化(不用 initWithSuiteName,iOS 7+ 才有)
static NSString *MTPlistPath() {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        NSString *dir = [[paths firstObject] stringByAppendingPathComponent:@"Preferences"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        path = [[dir stringByAppendingPathComponent:@"com.xiaochoumao.moletweak.plist"] copy];
    });
    return path;
}
static NSMutableDictionary *MTSettings() {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:MTPlistPath()];
        cache = d ? [d mutableCopy] : [NSMutableDictionary dictionary];
    });
    return cache;
}
static BOOL  MT_BOOL(NSString *k, BOOL  def){ id v=[MTSettings() objectForKey:k]; return v?[v boolValue]:def; }
static int   MT_INT (NSString *k, int   def){ id v=[MTSettings() objectForKey:k]; return v?[v intValue]:def; }
static float MT_FLT (NSString *k, float def){ id v=[MTSettings() objectForKey:k]; return v?[v floatValue]:def; }
static void  MT_SET (NSString *k, id v){
    [MTSettings() setObject:v forKey:k];
    [MTSettings() writeToFile:MTPlistPath() atomically:YES];
}

// =============== 单例实例引用(由 init hook 抓取) ===============
static __weak id gGameDataRef = nil;
static __weak id gWrapperManagerRef = nil;
static __weak id gNewGameManagerRef = nil;
static __weak id gGameManagerRef = nil;

// =============== 实时 raw 值缓存(由 getter hook 更新) ===============
// 这些是游戏内部真实的当前数值,菜单 UI 用它显示"当前"绿色字。
static volatile int   gRawGold     = 0;
static volatile int   gRawVipGold  = 0;
static volatile int   gRawXp       = 0;
static volatile int   gRawLevel    = 0;
static volatile unsigned int gRawVipLevel = 0;
static volatile float gRawGoldMul  = 1.0f;
static volatile float gRawXpMul    = 1.0f;

// =============== 前向声明(供早期 %hook 块调用,真实实现在文件下方) ===============
static id MTGameData(void);
static id MTUserInfoData(void);
static id MTNewGameManager(void);
static id MTGameManager(void);
static id MTWrapperManager(void);


// ============================================================================
//                          1) 玩家数据 hook (UserInfoData)
// ============================================================================
%hook UserInfoData

// --- 摩尔豆 (gold) ---
- (int)gold {
    int orig = %orig;
    gRawGold = orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    int over = MT_INT(kKeyGold, 0);
    return over > 0 ? over : orig;
}

- (void)setGold:(int)g {
    if (!MT_BOOL(kKeyEnabled, YES)) { %orig; return; }
    int over = MT_INT(kKeyGold, 0);
    %orig(over > 0 ? over : g);
}

- (void)addGold:(int)delta {
    if (!MT_BOOL(kKeyEnabled, YES)) { %orig; return; }
    // 免费购物: 减少 (扣钱) 时直接吞掉
    if (MT_BOOL(kKeyFreeShop, NO) && delta < 0) return;
    // 加成倍率
    float mul = MT_FLT(kKeyGoldMul, 1.0f);
    if (mul > 1.0f && delta > 0) delta = (int)(delta * mul);
    %orig(delta);
}

// --- 贝壳 (vipGold) ---
- (int)vipGold {
    int orig = %orig;
    gRawVipGold = orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    int over = MT_INT(kKeyVipGold, 0);
    return over > 0 ? over : orig;
}

- (void)setVipGold:(int)v {
    if (!MT_BOOL(kKeyEnabled, YES)) { %orig; return; }
    int over = MT_INT(kKeyVipGold, 0);
    %orig(over > 0 ? over : v);
}

- (void)addVipGold:(int)delta {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO) && delta < 0) return;
    %orig;
}

// --- 等级 (curLevel) ---
- (unsigned char)curLevel {
    unsigned char orig = %orig;
    gRawLevel = orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    int over = MT_INT(kKeyLevel, 0);
    if (over > 0 && over <= 255) return (unsigned char)over;
    return orig;
}

- (void)setCurLevel:(int)lv {
    if (!MT_BOOL(kKeyEnabled, YES)) { %orig; return; }
    int over = MT_INT(kKeyLevel, 0);
    %orig(over > 0 ? over : lv);
}

// --- 经验 (xp) ---
- (int)xp {
    int orig = %orig;
    gRawXp = orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    int over = MT_INT(kKeyXp, 0);
    return over > 0 ? over : orig;
}

- (void)setXp:(int)x {
    if (!MT_BOOL(kKeyEnabled, YES)) { %orig; return; }
    int over = MT_INT(kKeyXp, 0);
    %orig(over > 0 ? over : x);
}

- (void)addXp:(int)delta {
    if (!MT_BOOL(kKeyEnabled, YES)) { %orig; return; }
    float mul = MT_FLT(kKeyXpMul, 1.0f);
    if (mul > 1.0f && delta > 0) delta = (int)(delta * mul);
    %orig(delta);
}

// --- 加密校验 (绕过) ---
- (int)encryptVipGold {
    if (MT_BOOL(kKeyEnabled, YES) && MT_INT(kKeyVipGold, 0) > 0)
        return MT_INT(kKeyVipGold, 0);
    return %orig;
}

- (int)encryptCurLevel {
    if (MT_BOOL(kKeyEnabled, YES) && MT_INT(kKeyLevel, 0) > 0)
        return MT_INT(kKeyLevel, 0);
    return %orig;
}

%end


// ============================================================================
//                       2) 场景级数据 (NewSceneData)
// ============================================================================
%hook NewSceneData

- (unsigned long)getGold {
    unsigned long orig = %orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    int over = MT_INT(kKeyGold, 0);
    return over > 0 ? (unsigned long)over : orig;
}

- (unsigned long)getXp {
    unsigned long orig = %orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    int over = MT_INT(kKeyXp, 0);
    return over > 0 ? (unsigned long)over : orig;
}

- (unsigned long)getLevel {
    unsigned long orig = %orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    int over = MT_INT(kKeyLevel, 0);
    return over > 0 ? (unsigned long)over : orig;
}

// 服务器同步 / MD5 校验绕过
- (BOOL)checkUserinfoMd5:(id)arg {
    // molecheats 对齐: 归入 kill_anticheat 开关(不再默认恒开)
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return YES;
    return %orig;
}

- (int)CheckUserInfoData:(id)arg {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return 0;
    return %orig;
}

%end


// ============================================================================
//                       3) VIP 加成 (VipInfoData)
// ============================================================================
%hook VipInfoData

- (float)gold_add {
    float orig = %orig;
    gRawGoldMul = orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    float mul = MT_FLT(kKeyGoldMul, 1.0f);
    return mul > 1.0f ? mul : orig;
}

- (float)exp_add {
    float orig = %orig;
    gRawXpMul = orig;
    if (!MT_BOOL(kKeyEnabled, YES)) return orig;
    float mul = MT_FLT(kKeyXpMul, 1.0f);
    return mul > 1.0f ? mul : orig;
}

%end


// ============================================================================
//                       4) 作物瞬熟 (Farm) - 关键 hook 是 innerupdate:
// ============================================================================
// 弱引用集合,跟踪所有 Farm 实例,用于菜单按钮"立即成熟全部作物"
static NSHashTable *gFarmTable = nil;
static NSLock *gFarmLock = nil;

static void MTFarmTableEnsure(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gFarmTable = [NSHashTable hashTableWithOptions:NSHashTableWeakMemory];
        gFarmLock = [[NSLock alloc] init];
    });
}

// 把 farm 实例的 matureTime ivar 强制改为接近 0,让游戏内部成熟逻辑立即触发
static void MTForceMature(id farm) {
    if (!farm) return;
    Ivar mt = class_getInstanceVariable([farm class], "matureTime");
    if (mt) {
        char *base = (char *)(__bridge void *)farm;
        float *p = (float *)(base + ivar_getOffset(mt));
        if (*p > 0.01f) *p = 0.001f;
    }
    Ivar wt = class_getInstanceVariable([farm class], "witherTime");
    if (wt && MT_BOOL(kKeyNoWither, NO)) {
        char *base = (char *)(__bridge void *)farm;
        float *p = (float *)(base + ivar_getOffset(wt));
        *p = 9999999.0f;
    }
}

%hook Farm

// 周期性 update - 每帧调用,这是真正驱动作物状态的方法
- (void)innerupdate:(float)dt {
    // 维护实例集合
    MTFarmTableEnsure();
    [gFarmLock lock]; [gFarmTable addObject:self]; [gFarmLock unlock];

    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstant, NO)) {
        MTForceMature(self);
    }
    %orig;
}

// 成熟所需时间 (秒) - 返回 0 即"已成熟"
- (double)getMatureTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstant, NO)) return 0.0;
    return %orig;
}

// 枯萎时间 - 返回非常大,即"永不枯萎"
- (double)getWitherTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoWither, NO))
        return 999999999.0;
    return %orig;
}

// 防止枯萎处理被触发
- (void)cropWitherHandler:(BOOL)b {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoWither, NO)) return;
    %orig;
}

- (void)dealloc {
    if (gFarmLock) {
        [gFarmLock lock]; [gFarmTable removeObject:self]; [gFarmLock unlock];
    }
    %orig;
}

%end

// 立即遍历所有 Farm 实例,触发 cropMatureHandler 强制收割可成熟的作物
static void MTHarvestAllNow(void) {
    if (!gFarmTable) return;
    NSArray *farms = nil;
    [gFarmLock lock]; farms = [gFarmTable allObjects]; [gFarmLock unlock];
    SEL handler = NSSelectorFromString(@"cropMatureHandler");
    for (id farm in farms) {
        MTForceMature(farm);
        if ([farm respondsToSelector:handler]) {
            ((void(*)(id, SEL))objc_msgSend)(farm, handler);
        }
    }
}


// ============================================================================
//                       5) 通知时间 (NotificationTimes)
// ============================================================================
%hook NotificationTimes

- (double)cropMatureTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstant, NO))
        return [[NSDate date] timeIntervalSince1970];  // 当前时间 = 已成熟
    return %orig;
}

- (double)cropWitherTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoWither, NO))
        return [[NSDate date] timeIntervalSince1970] + 365.0*24.0*3600.0;
    return %orig;
}

- (double)buildingFinishTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstantBuild, NO))
        return [[NSDate date] timeIntervalSince1970];
    return %orig;
}

%end


// ============================================================================
//                  v2-A) 建筑/装修瞬完成 (Building / NewSceneRestaurant / NewSceneShop)
// ============================================================================
%hook Building

- (void)innerupdate:(float)dt {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstantBuild, NO)) {
        MT_IVAR_F(self, "buildTime_", 0.001f);
        MT_IVAR_D(self, "lastCoolDownTime_", 0.001);
    }
    %orig;
}

- (double)getBuildTime:(id)a {
    // v21 审查修复: 真机方法返回 double, 原 int 声明会漏写 d0/r1 → instant_build 读到垃圾值不生效
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstantBuild, NO)) return 0.0;
    return %orig;
}

// 全局冷却归零 (Building 类共享)
- (double)getCurLevelCoolTime {
    // v21 审查修复: 冷却 getter 真机返回 double(兄弟 getLastCooldownTime/getLastGameCoolTime 本就是 double)
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoCD, NO)) return 0.0;
    return %orig;
}

- (double)getLastCooldownTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoCD, NO)) return 0.0;
    return %orig;
}

- (double)getLastGameCoolTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoCD, NO)) return 0.0;
    return %orig;
}

%end


%hook NewSceneRestaurant

- (void)innerupdate:(float)dt {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstantBuild, NO)) {
        MT_IVAR_UL(self, "beginUpgradeTime_", 1);  // 1 而非 0,避免 (now-0) 异常
    }
    %orig;
}

- (double)getOutCoolTime {
    // v21 审查修复: 真机方法返回 double, 原 unsigned int 声明失效
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoCD, NO)) return 0.0;
    return %orig;
}

%end


%hook NewSceneShop

- (void)innerupdate:(float)dt {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstantBuild, NO)) {
        MT_IVAR_I(self, "buildTime_", 0);
        MT_IVAR_I(self, "saleTime_",  0);
    }
    %orig;
}

%end


// ============================================================================
//                  v2-B) 免费购物 (InAppPurchaseManager)
// ============================================================================
%hook InAppPurchaseManager

// v20: 点购买直接成功 — 跳过 SKPaymentQueue,自己给玩家加贝壳
// purchase: types = v12@0:4@8 (void)(NSString* productId)
- (void)purchase:(id)productIdentifier {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyInstantPurchase, NO)) {
        // 1. 解析 productId 尾部数字作为贝壳数(默认 100)
        int amount = 100;
        if ([productIdentifier isKindOfClass:[NSString class]]) {
            NSString *pid = (NSString *)productIdentifier;
            // 提取最后一组连续数字
            NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
            NSString *lastNum = nil;
            NSScanner *sc = [NSScanner scannerWithString:pid];
            while (![sc isAtEnd]) {
                [sc scanUpToCharactersFromSet:digits intoString:nil];
                NSString *s = nil;
                if ([sc scanCharactersFromSet:digits intoString:&s]) lastNum = s;
            }
            if (lastNum) {
                int n = [lastNum intValue];
                if (n > 0 && n < 100000) amount = n;
            }
        }

        // 2. 直接 [UserInfoData addVipGold:n] 给玩家加贝壳
        id ui = MTUserInfoData();
        if (ui) {
            SEL addVip = NSSelectorFromString(@"addVipGold:");
            if ([ui respondsToSelector:addVip]) {
                ((void (*)(id, SEL, int))objc_msgSend)(ui, addVip, amount);
            }
        }

        // 3. 持久化
        id gd = MTGameData();
        SEL save = NSSelectorFromString(@"saveUserInfoData");
        if (gd && [gd respondsToSelector:save]) {
            ((void (*)(id, SEL))objc_msgSend)(gd, save);
        }

        // 4. 调游戏自己的 onPurchaseSuccessful 弹"购买成功"
        SEL succ = NSSelectorFromString(@"onPurchaseSuccessful");
        id me = self;
        if ([me respondsToSelector:succ]) {
            ((void (*)(id, SEL))objc_msgSend)(me, succ);
        }

        // 5. 调 productPurchased 让游戏更新 UI
        SEL prod = NSSelectorFromString(@"productPurchased");
        if ([me respondsToSelector:prod]) {
            ((void (*)(id, SEL))objc_msgSend)(me, prod);
        }

        // v20.1: 关键 — 商店是通过 purchaseWithCallback:selector:productId: 进来的
        // 它把回调 target/sel 存到了 self->targetCallback_ / self->selector_ ivar
        // 同时设 self->isInPurchase_ = YES,商店 UI 会一直转圈等回调
        // 我们必须:① 清 isInPurchase_ 标志 ② 主动调回调让 UI 关掉加载圈
        Ivar ivCb  = class_getInstanceVariable([me class], "targetCallback_");
        Ivar ivSel = class_getInstanceVariable([me class], "selector_");
        Ivar ivIn  = class_getInstanceVariable([me class], "isInPurchase_");
        Ivar ivRes = class_getInstanceVariable([me class], "result_");
        if (ivIn) {
            *(char *)((char *)(__bridge void *)me + ivar_getOffset(ivIn)) = 0;  // isInPurchase_ = NO
        }
        if (ivRes) {
            *(char *)((char *)(__bridge void *)me + ivar_getOffset(ivRes)) = 1;  // result_ = YES
        }
        id cbTarget = nil;
        SEL cbSel   = NULL;
        if (ivCb)  cbTarget = object_getIvar(me, ivCb);
        if (ivSel) cbSel    = *(SEL *)((char *)(__bridge void *)me + ivar_getOffset(ivSel));
        if (cbTarget && cbSel && [cbTarget respondsToSelector:cbSel]) {
            // 商店的 purchaseCallback 不带参,直接调
            ((void (*)(id, SEL))objc_msgSend)(cbTarget, cbSel);
        }

        // 6. 隐藏可能存在的加载指示器
        SEL hideInd = NSSelectorFromString(@"hideIndicator");
        if ([me respondsToSelector:hideInd]) {
            ((void (*)(id, SEL))objc_msgSend)(me, hideInd);
        }
        SEL hideIndU = NSSelectorFromString(@"HideIndicator");
        if ([me respondsToSelector:hideIndU]) {
            ((void (*)(id, SEL))objc_msgSend)(me, hideIndU);
        }

        NSLog(@"[MoleTweak] InstantPurchase: pid=%@ amount=%d cb=%@ sel=%s",
              productIdentifier, amount, cbTarget, cbSel ? sel_getName(cbSel) : "(nil)");
        return;  // 不调 %orig,跳过 StoreKit
    }
    %orig;
}

// v20.1: 商店 UI 入口直接走这个,先存回调再调 purchase:
// types = v20@0:4@8:12@16 = (void)(id target, SEL sel, id productId)
// 我们让原方法存好回调,然后我们的 purchase: hook 触发回调
// — 不需要 hook 这个方法,默认行为已经会调到 purchase: 即可

- (BOOL)canPurchase:(id)pid {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) return YES;
    return %orig;
}

- (BOOL)hasAlreadyPurchased:(id)pid {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) return YES;
    return %orig;
}

// 配合 LocalIAPStore.dylib 使用:伪 transaction 收据校验时强制返 YES,游戏自己走奖励发放路径
- (BOOL)validateReceipt:(id)receipt {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) return YES;
    return %orig;
}

// 越狱用户的 IAP 权限检查 — 总返 YES
- (BOOL)checkRightInJailBroken:(id)arg {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) return YES;
    return %orig;
}

// 当前玩家 ID 校验 — 总返 YES
- (BOOL)checkIsCurrentUserId {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) return YES;
    return %orig;
}

// 越狱 IAP 超时/失败处理也吞掉,避免卡进度
- (void)onCheckIAPTimeoutForJailBrokenUser {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) {
        // 强制走"成功"路径,而不是超时
        SEL succ = NSSelectorFromString(@"onPurchaseSuccessful");
        id me = self;
        if ([me respondsToSelector:succ]) ((void(*)(id,SEL))objc_msgSend)(me, succ);
        return;
    }
    %orig;
}

- (void)onCheckIAPFailedForJailBrokenUser {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) {
        SEL succ = NSSelectorFromString(@"onPurchaseSuccessful");
        id me = self;
        if ([me respondsToSelector:succ]) ((void(*)(id,SEL))objc_msgSend)(me, succ);
        return;
    }
    %orig;
}

%end


// ============================================================================
//                  v2-C) VIP 强制激活 + 最高级
// ============================================================================
%hook WrapperManager

- (id)init {
    id r = %orig;
    if (r) gWrapperManagerRef = r;
    return r;
}

- (BOOL)checkIsVipUser {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) return YES;
    return %orig;
}

// 全物品解锁:任何物品都视为已解锁
- (BOOL)isUnlockedItem:(int)itemId {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return YES;
    return %orig;
}

%end


// 记录 NewGameManager / GameManager 实例
%hook NewGameManager
- (id)init { id r = %orig; if (r) gNewGameManagerRef = r; return r; }
%end

%hook GameManager
- (id)init { id r = %orig; if (r) gGameManagerRef = r; return r; }
%end


%hook UserVIPInfoData

// init 后立即改 ivar — 因服务器停服 setVipLevel: 永远不被调
- (id)init {
    id r = %orig;
    if (r && MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) {
        int over = MT_INT(kKeyVipLevel, 10);
        if (over <= 0 || over > 10) over = 10;
        Ivar v = class_getInstanceVariable(object_getClass(r), "vipLevel_");
        if (v) *(unsigned int *)((char *)(__bridge void *)r + ivar_getOffset(v)) = (unsigned int)over;
        Ivar vv = class_getInstanceVariable(object_getClass(r), "vipValue_");
        if (vv) *(unsigned int *)((char *)(__bridge void *)r + ivar_getOffset(vv)) = 999999;
    }
    return r;
}

- (void)setVipLevel:(unsigned int)lv {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) {
        int over = MT_INT(kKeyVipLevel, 10);
        if (over > 0 && over <= 10) lv = (unsigned int)over;
    }
    %orig(lv);
}

- (unsigned int)vipLevel {
    Ivar v = class_getInstanceVariable(object_getClass(self), "vipLevel_");
    unsigned int orig = v ? *(unsigned int *)((char *)(__bridge void *)self + ivar_getOffset(v)) : 0;
    gRawVipLevel = orig;
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) {
        int over = MT_INT(kKeyVipLevel, 10);
        if (over > 0) return (unsigned int)over;
    }
    return orig;
}

- (unsigned int)vipValue {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) return 999999;
    return %orig;
}

%end


// === VIP 修复关键点: GameData.getVipInfoDataOfCurrentUser ===
// 大多数 VIP 检查最终走这个方法拿到当前玩家的 VipInfoData (返 nil 表示非 VIP)
%hook GameData

// 记录 GameData 实例引用(单例没有显式 +类方法,只能 hook init 抓)
- (id)init {
    id r = %orig;
    if (r) gGameDataRef = r;
    return r;
}

- (id)getVipInfoDataOfCurrentUser {
    id orig = %orig;
    if (orig) return orig;
    if (!MT_BOOL(kKeyEnabled, YES) || !MT_BOOL(kKeyForceVip, NO)) return orig;
    // 用 getVipInfoDataWithLevel: 拿到最高级 VIP 配置
    SEL sel = NSSelectorFromString(@"getVipInfoDataWithLevel:");
    id me = self;
    if ([me respondsToSelector:sel]) {
        int lv = MT_INT(kKeyVipLevel, 10);
        if (lv <= 0 || lv > 10) lv = 10;
        id v = ((id (*)(id, SEL, int))objc_msgSend)(me, sel, lv);
        if (v) return v;
    }
    return orig;
}

%end


// === GoldSprite.isVip 也是 VIP 状态判断点 ===
%hook GoldSprite

- (BOOL)isVip {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) return YES;
    return %orig;
}

%end


// === UserInfoLayer:UI 层 VIP 显示状态 ===
// isInitVip_ (BOOL ivar at offset 396) = NO 时游戏不会渲染 VIP UI
// 我们 hook init / onEnter / updateUI4VIP 强制设它为 YES
%hook UserInfoLayer

- (id)init {
    id r = %orig;
    if (r && MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) {
        Ivar v = class_getInstanceVariable(object_getClass(r), "isInitVip_");
        if (v) *(char *)((char *)(__bridge void *)r + ivar_getOffset(v)) = 1;
    }
    return r;
}

- (void)updateUI4VIP {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) {
        Ivar v = class_getInstanceVariable(object_getClass(self), "isInitVip_");
        if (v) *(char *)((char *)(__bridge void *)self + ivar_getOffset(v)) = 1;
    }
    %orig;
}

- (void)isShowVIPFunctionsButton:(BOOL)show {
    // 强制总是显示 VIP 功能按钮
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) {
        %orig(YES);
        return;
    }
    %orig;
}

%end


// ============================================================================
//                  v7-IAP) SKPaymentTransaction 状态强制 Purchased
//   不依赖 LocalIAPStore.dylib —— 即使它没注入也能让所有内购看起来成功
// ============================================================================
%hook SKPaymentTransaction

- (int)transactionState {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeShop, NO)) {
        // SKPaymentTransactionStatePurchasing=0, Purchased=1, Failed=2, Restored=3, Deferred=4
        return 1;  // 强制 Purchased
    }
    return %orig;
}

%end


// ============================================================================
//                  v2-D) NPC 冷却归零
// ============================================================================
%hook YaliNpcActor

- (BOOL)checkCooltimeOver {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoCD, NO)) return YES;
    return %orig;
}

%end


%hook MCNpcActor

- (double)getCurLevelCooltime:(id)a {
    // v21 审查修复: 真机方法返回 double(带参), 原 int 声明失效
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyNoCD, NO)) return 0.0;
    return %orig;
}

%end


// ============================================================================
//                  v5-A) hiddenMenuPosition 高亮 (MainMenuScene)
// ============================================================================
%hook MainMenuScene

- (void)onEnter {
    %orig;
    if (!MT_BOOL(kKeyEnabled, YES) || !MT_BOOL(kKeyShowHidden, NO)) return;
    // 异步:等场景完全 onEnter 完
    id me = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SEL hmpSel = NSSelectorFromString(@"hiddenMenuPosition");
        if (![me respondsToSelector:hmpSel]) return;
        // 用 NSInvocation 安全地调用返回 CGPoint 的方法
        NSMethodSignature *sig = [me methodSignatureForSelector:hmpSel];
        if (!sig) return;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.selector = hmpSel;
        inv.target = me;
        [inv invoke];
        CGPoint pos;
        [inv getReturnValue:&pos];

        // pos 是 cocos2d 坐标(原点左下),转 UIKit 坐标(原点左上)
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        UIView *host = win.rootViewController.view ?: (UIView *)win;
        if (!host) return;
        CGSize scr = host.bounds.size;
        CGFloat uiX = pos.x;
        CGFloat uiY = scr.height - pos.y;

        UIView *halo = [[UIView alloc] initWithFrame:CGRectMake(uiX - 35, uiY - 35, 70, 70)];
        halo.layer.borderColor = [UIColor redColor].CGColor;
        halo.layer.borderWidth = 4;
        halo.layer.cornerRadius = 35;
        halo.userInteractionEnabled = NO;
        halo.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.18];
        [host addSubview:halo];

        // 文字标注坐标
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(uiX + 40, uiY - 14, 200, 28)];
        lbl.text = [NSString stringWithFormat:@"hiddenMenu (%.0f, %.0f)", pos.x, pos.y];
        lbl.font = [UIFont boldSystemFontOfSize:11];
        lbl.textColor = [UIColor redColor];
        lbl.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
        lbl.layer.cornerRadius = 4;
        lbl.clipsToBounds = YES;
        [host addSubview:lbl];

        // 闪烁动画(通过反复改 alpha)
        [UIView animateWithDuration:0.5 delay:0
                            options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                         animations:^{ halo.alpha = 0.3; }
                         completion:nil];

        // 8 秒后移除
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [halo removeFromSuperview];
            [lbl removeFromSuperview];
        });
    });
}

%end


// ============================================================================
//                  v6-A) 黄金岛修复 (Caribbean 加勒比寻宝活动)
// ============================================================================
// 服务器停服后 GameData.caribbeanData 永远 nil → CaribbeanMainLayer 拿不到数据 → 黑屏/卡住
// 修复策略:本地构造一个有效的 CaribbeanDiscoveringData 让 UI 能渲染
// (GameData.caribbeanData getter 的 hook 合并到下面 v3-A 的 GameData 块)

// 让加勒比 UI 不再因网络失败弹错误
%hook CaribbeanMainLayer

- (void)showNetWorkError {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFixGoldenIsland, NO)) return;  // 吞错误
    %orig;
}

%end

// 让 NetworkManager 收到 nil/空数据时不报错
%hook NetworkManager

- (int)getCaribbeanStateInfo:(id)arg {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFixGoldenIsland, NO)) {
        // 不发请求(避免长时间等待),直接走"成功"路径
        return 0;
    }
    return %orig;
}

%end


// ============================================================================
//                  v9-XiaoTuLv) 一键加载丝尔特 demo 庄园 (重写,稳定版)
//   资源文件: xiaotulv_map (72KB) + xiaotulv_userinfo (3KB) 在 .app 目录
//   核心: hook init 记录 GameData / NewGameManager 实例,绕开单例查找
//   全局 ref 在文件顶部声明
// ============================================================================
static id MTGameData(void) {
    if (gGameDataRef) return gGameDataRef;
    // fallback: 试单例方法
    Class GD = NSClassFromString(@"GameData");
    if (!GD) return nil;
    NSArray *names = @[ @"sharedGameData", @"shared", @"sharedInstance", @"instance" ];
    for (NSString *n in names) {
        SEL s = NSSelectorFromString(n);
        if ([GD respondsToSelector:s]) {
            id g = ((id (*)(id, SEL))objc_msgSend)(GD, s);
            if (g) { gGameDataRef = g; return g; }
        }
    }
    return nil;
}

static id MTNewGameManager(void) {
    if (gNewGameManagerRef) return gNewGameManagerRef;
    Class C = NSClassFromString(@"NewGameManager");
    if (!C) return nil;
    SEL s = @selector(sharedManager);
    if ([C respondsToSelector:s]) {
        id m = ((id (*)(id, SEL))objc_msgSend)(C, s);
        if (m) { gNewGameManagerRef = m; return m; }
    }
    return nil;
}

static id MTGameManager(void) {
    if (gGameManagerRef) return gGameManagerRef;
    Class C = NSClassFromString(@"GameManager");
    if (!C) return nil;
    SEL s = @selector(sharedManager);
    if ([C respondsToSelector:s]) {
        id m = ((id (*)(id, SEL))objc_msgSend)(C, s);
        if (m) { gGameManagerRef = m; return m; }
    }
    return nil;
}

// 加载 demo 数据到内存(不持久化)
static BOOL MTLoadXiaoTuLvIntoMemory(void) {
    id gd = MTGameData();
    if (!gd) return NO;
    SEL loadMap = NSSelectorFromString(@"loadMapdataFromResource:");
    SEL loadUI  = NSSelectorFromString(@"loadUserInfoFromResource:");
    BOOL didLoad = NO;
    if ([gd respondsToSelector:loadMap]) {
        ((void (*)(id, SEL, id))objc_msgSend)(gd, loadMap, @"xiaotulv_map");
        didLoad = YES;
    }
    if ([gd respondsToSelector:loadUI]) {
        ((void (*)(id, SEL, id))objc_msgSend)(gd, loadUI, @"xiaotulv_userinfo");
    }
    return didLoad;
}

// 触发场景重新渲染当前 mapdata(不重启游戏就能看到新地图)
static BOOL MTReloadCurrentMap(void) {
    BOOL ok = NO;
    id ngm = MTNewGameManager();
    if (ngm) {
        SEL s = NSSelectorFromString(@"reloadMapFromNewSceneData");
        if ([ngm respondsToSelector:s]) {
            ((void (*)(id, SEL))objc_msgSend)(ngm, s);
            ok = YES;
        }
    }
    if (!ok) {
        id gm = MTGameManager();
        if (gm) {
            // 旧版 fallback:loadMapByStep / endLoadMap
            SEL s = NSSelectorFromString(@"loadMapByStep");
            if ([gm respondsToSelector:s]) {
                ((void (*)(id, SEL))objc_msgSend)(gm, s);
                ok = YES;
            }
        }
    }
    return ok;
}

// 进入丝尔特 demo 庄园 (临时浏览):加载资源 + 触发场景刷新,不保存
static BOOL MTEnterXiaoTuLvVillage(void) {
    return MTLoadXiaoTuLvIntoMemory() && MTReloadCurrentMap();
}

// 强制覆盖玩家存档为丝尔特庄园:加载 + 持久化 + 刷新
static BOOL MTOverwriteSaveWithXiaoTuLv(void) {
    if (!MTLoadXiaoTuLvIntoMemory()) return NO;
    id gd = MTGameData();
    SEL saveAll = NSSelectorFromString(@"saveMapDataAndUserInfoToLocal");
    if ([gd respondsToSelector:saveAll]) {
        ((void (*)(id, SEL))objc_msgSend)(gd, saveAll);
    }
    MTReloadCurrentMap();
    return YES;
}


// ============================================================================
//                  v11-A) 全部成就强制通过 — 已移除错误签名 hook
//   原 11 个 checkAchieve_X 实际签名是 void,不是 BOOL!
//   我们之前用 (BOOL) hook + (id) 参数 → 签名不匹配 → EXC_BAD_ACCESS
//   现在改用 hook getAchieveDataByID: 返回 "已解锁" 状态(后续可加,先稳定)
// ============================================================================

// 取 AchievementControl 单例(注意拼写错误 shareInstance)
static id MTAchievementControl(void) {
    Class C = NSClassFromString(@"AchievementControl");
    if (!C) return nil;
    SEL s = NSSelectorFromString(@"shareInstance");  // typo, 真实方法名
    if ([C respondsToSelector:s]) {
        return ((id(*)(id,SEL))objc_msgSend)(C, s);
    }
    return nil;
}


// ============================================================================
//                  v11-B) 加载冬季丝尔特 / 调用 myfuctiion
// ============================================================================
// 加载冬季版丝尔特庄园(资源:xiaotulv_winter_map / xiaotulv_winter_userinfo)
static BOOL MTLoadXiaoTuLvWinterIntoMemory(void) {
    id gd = MTGameData();
    if (!gd) return NO;
    SEL loadMap = NSSelectorFromString(@"loadMapdataFromResource:");
    SEL loadUI  = NSSelectorFromString(@"loadUserInfoFromResource:");
    BOOL didLoad = NO;
    if ([gd respondsToSelector:loadMap]) {
        ((void(*)(id,SEL,id))objc_msgSend)(gd, loadMap, @"xiaotulv_winter_map");
        didLoad = YES;
    }
    if ([gd respondsToSelector:loadUI]) {
        ((void(*)(id,SEL,id))objc_msgSend)(gd, loadUI, @"xiaotulv_winter_userinfo");
    }
    return didLoad;
}

// 调用 MainMenu 上任意私货方法(myfuctiion / testAnimation)
static BOOL MTCallMainMenuMethod(NSString *selName) {
    Class CCDirector = NSClassFromString(@"CCDirector");
    if (!CCDirector) return NO;
    id director = ((id(*)(id,SEL))objc_msgSend)(CCDirector, @selector(sharedDirector));
    if (!director) return NO;
    SEL rs = NSSelectorFromString(@"runningScene");
    if (![director respondsToSelector:rs]) return NO;
    id scene = ((id(*)(id,SEL))objc_msgSend)(director, rs);
    if (!scene) return NO;

    Class MainMenuC = NSClassFromString(@"MainMenu");
    if (!MainMenuC) return NO;
    SEL targetSel = NSSelectorFromString(selName);
    SEL chs = NSSelectorFromString(@"children");

    NSMutableArray *stack = [NSMutableArray arrayWithObject:scene];
    int budget = 200;
    while (stack.count > 0 && budget-- > 0) {
        id node = [stack lastObject];
        [stack removeLastObject];
        if ([node isKindOfClass:MainMenuC] && [node respondsToSelector:targetSel]) {
            ((void(*)(id, SEL))objc_msgSend)(node, targetSel);
            return YES;
        }
        if ([node respondsToSelector:chs]) {
            id arr = ((id(*)(id, SEL))objc_msgSend)(node, chs);
            if ([arr respondsToSelector:@selector(count)]) {
                for (id ch in arr) [stack addObject:ch];
            }
        }
    }
    // fallback: 临时 alloc 一个 MainMenu 调
    id mm = ((id(*)(id, SEL))objc_msgSend)([MainMenuC alloc], @selector(init));
    if (mm && [mm respondsToSelector:targetSel]) {
        ((void(*)(id, SEL))objc_msgSend)(mm, targetSel);
        return YES;
    }
    return NO;
}

// 调用程序员私货 MainMenu.myfuctiion (拼写错误,应该是 myfunction)
// 找当前 MainMenu 实例,调它的方法
static BOOL MTCallMyFuctiion(void) {
    Class CCDirector = NSClassFromString(@"CCDirector");
    if (!CCDirector) return NO;
    id director = ((id(*)(id,SEL))objc_msgSend)(CCDirector, @selector(sharedDirector));
    if (!director) return NO;
    SEL rs = NSSelectorFromString(@"runningScene");
    if (![director respondsToSelector:rs]) return NO;
    id scene = ((id(*)(id,SEL))objc_msgSend)(director, rs);
    if (!scene) return NO;

    // 找 MainMenu 子节点(深度优先)
    Class MainMenuC = NSClassFromString(@"MainMenu");
    if (!MainMenuC) return NO;
    SEL myF = NSSelectorFromString(@"myfuctiion");
    SEL chs = NSSelectorFromString(@"children");

    NSMutableArray *stack = [NSMutableArray arrayWithObject:scene];
    int budget = 200;
    while (stack.count > 0 && budget-- > 0) {
        id node = [stack lastObject];
        [stack removeLastObject];
        if ([node isKindOfClass:MainMenuC]) {
            if ([node respondsToSelector:myF]) {
                ((void(*)(id,SEL))objc_msgSend)(node, myF);
                return YES;
            }
        }
        if ([node respondsToSelector:chs]) {
            id arr = ((id(*)(id,SEL))objc_msgSend)(node, chs);
            if ([arr respondsToSelector:@selector(count)]) {
                for (id ch in arr) [stack addObject:ch];
            }
        }
    }
    // 备用:用 alloc init 一个 MainMenu 实例临时调
    id mm = ((id(*)(id,SEL))objc_msgSend)([MainMenuC alloc], @selector(init));
    if (mm && [mm respondsToSelector:myF]) {
        ((void(*)(id,SEL))objc_msgSend)(mm, myF);
        return YES;
    }
    return NO;
}


// ============================================================================
//                  v12-A) 一键解锁所有物品(真写入 unlockedItemList_)
//   遍历 GameData.shopItems 字典所有 key,逐个调 [WrapperManager unlockItem:]
// ============================================================================
#if 0  // v21 审查停用: unlockItem: 选择器未验证 + 破坏性写存档, 已由 all_unlock getter hook 取代
static int MTUnlockAllItems(void) {
    id gd = MTGameData();
    if (!gd) gd = gGameDataRef;
    id wm = gWrapperManagerRef;
    if (!wm) {
        Class WMC = NSClassFromString(@"WrapperManager");
        if (WMC && [WMC respondsToSelector:@selector(sharedManager)])
            wm = ((id(*)(id,SEL))objc_msgSend)(WMC, @selector(sharedManager));
    }
    if (!gd || !wm) return -1;

    SEL siSel = NSSelectorFromString(@"shopItems");
    if (![gd respondsToSelector:siSel]) return -2;
    id items = ((id(*)(id,SEL))objc_msgSend)(gd, siSel);
    if (!items) return -3;

    SEL unSel = NSSelectorFromString(@"unlockItem:");
    if (![wm respondsToSelector:unSel]) return -4;

    int count = 0;
    if ([items respondsToSelector:@selector(allKeys)]) {
        NSArray *keys = [items allKeys];
        for (id k in keys) {
            int itemId = [k intValue];
            if (itemId > 0) {
                ((void(*)(id,SEL,int))objc_msgSend)(wm, unSel, itemId);
                count++;
            }
        }
    }
    // 持久化
    SEL save = NSSelectorFromString(@"saveUserInfoData");
    if ([gd respondsToSelector:save]) ((void(*)(id,SEL))objc_msgSend)(gd, save);
    return count;
}
#endif  // MTUnlockAllItems 停用


// ============================================================================
//                  v12-B) 启动 6 个 mini 游戏 (BugGame/Fishing/Divine/...)
//   通过 [MiniGameManager.shareInstance startMiniGame:playType:callbackTarget:select:]
// ============================================================================
static BOOL MTStartMiniGame(int gameId) {
    Class C = NSClassFromString(@"MiniGameManager");
    if (!C) return NO;
    SEL sis = NSSelectorFromString(@"shareInstance");  // 注意 typo
    if (![C respondsToSelector:sis]) return NO;
    id mgr = ((id(*)(id,SEL))objc_msgSend)(C, sis);
    if (!mgr) return NO;
    SEL start = NSSelectorFromString(@"startMiniGame:playType:callbackTarget:select:");
    if (![mgr respondsToSelector:start]) return NO;
    // (void)startMiniGame:(int)gameId playType:(int)pt callbackTarget:(id)t select:(SEL)s
    ((void (*)(id, SEL, int, int, id, SEL))objc_msgSend)(mgr, start, gameId, 0, nil, NULL);
    return YES;
}


// ============================================================================
//                  v13) 玩家数据修改 + 任务重置 + 时间魔法 + 隐藏 NPC
// ============================================================================
// 拿当前 UserInfoData 实例(从 GameData.userInfoData)
static id MTUserInfoData(void) {
    id gd = MTGameData();
    if (!gd) return nil;
    SEL s = NSSelectorFromString(@"userInfoData");
    if (![gd respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(gd, s);
}

// 把覆盖值依次写到 UserInfoData(头像/房间数/工人数)
static int MTApplyUserInfoOverrides(void) {
    id ui = MTUserInfoData();
    if (!ui) return -1;
    int applied = 0;

    int avatar = MT_INT(kKeyAvatarIcon, 0);
    if (avatar > 0) {
        SEL a1 = NSSelectorFromString(@"setAvatarIcon:");
        if ([ui respondsToSelector:a1]) {
            ((void (*)(id, SEL, int))objc_msgSend)(ui, a1, avatar);
            applied++;
        }
        SEL a2 = NSSelectorFromString(@"setIconIndex:");
        if ([ui respondsToSelector:a2]) {
            ((void (*)(id, SEL, int))objc_msgSend)(ui, a2, avatar);
        }
    }
    int rooms = MT_INT(kKeyTotalRooms, 0);
    if (rooms > 0) {
        SEL s = NSSelectorFromString(@"setTotalRooms:");
        if ([ui respondsToSelector:s]) {
            ((void (*)(id, SEL, int))objc_msgSend)(ui, s, rooms);
            applied++;
        }
    }
    int workers = MT_INT(kKeyTotalWorkers, 0);
    if (workers > 0) {
        SEL s1 = NSSelectorFromString(@"setTotalWorkers:");
        if ([ui respondsToSelector:s1]) {
            ((void (*)(id, SEL, int))objc_msgSend)(ui, s1, workers);
            applied++;
        }
        SEL s2 = NSSelectorFromString(@"setAvailableWorkers:");
        if ([ui respondsToSelector:s2]) {
            ((void (*)(id, SEL, int))objc_msgSend)(ui, s2, workers);
        }
    }

    // 持久化
    id gd = MTGameData();
    SEL save = NSSelectorFromString(@"saveUserInfoData");
    if (gd && [gd respondsToSelector:save]) {
        ((void (*)(id, SEL))objc_msgSend)(gd, save);
    }
    return applied;
}

// 一键重置任务/签到 — 各方法都在 GameData
static int MTResetByName(NSString *selName) {
    id gd = MTGameData();
    if (!gd) return -1;
    SEL s = NSSelectorFromString(selName);
    if (![gd respondsToSelector:s]) return -2;
    ((void (*)(id, SEL))objc_msgSend)(gd, s);
    SEL save = NSSelectorFromString(@"saveUserInfoData");
    if ([gd respondsToSelector:save]) ((void (*)(id, SEL))objc_msgSend)(gd, save);
    return 0;
}


// v14 helpers — 在 GameManager / GameData 上调 void 方法
static int MTGameManagerCallVoid(NSString *selName) {
    id gm = MTGameManager();
    if (!gm) return -1;
    SEL s = NSSelectorFromString(selName);
    if (![gm respondsToSelector:s]) return -2;
    ((void (*)(id, SEL))objc_msgSend)(gm, s);
    return 0;
}

static int MTSetRewardTickets(int n) {
    id gd = MTGameData();
    if (!gd) return -1;
    SEL s = NSSelectorFromString(@"setRewardTickets:");
    if (![gd respondsToSelector:s]) return -2;
    ((void (*)(id, SEL, int))objc_msgSend)(gd, s, n);
    SEL save = NSSelectorFromString(@"saveUserInfoData");
    if ([gd respondsToSelector:save]) ((void (*)(id, SEL))objc_msgSend)(gd, save);
    return 0;
}


// 服务器时间魔法 hook (NewSceneTimer.getCurrentServerTime, types L8@0:4 = unsigned long)
%hook NewSceneTimer
- (unsigned long)getCurrentServerTime {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyTimeMagic, NO)) {
        NSString *ts = [MTSettings() objectForKey:kKeyFakeTime];
        if (ts.length > 0) {
            unsigned long fake = (unsigned long)strtoul([ts UTF8String], NULL, 10);
            if (fake > 0) return fake;
        }
    }
    return %orig;
}
%end


// ============================================================================
//                  v6-B) 召唤未上线联名活动 (Alice / Shrek / Totoro / IceCream / FlameWars)
// ============================================================================
static void MTSummonActivityLayer(NSString *className) {
    Class CCDirector = NSClassFromString(@"CCDirector");
    if (!CCDirector) return;
    id director = ((id (*)(id, SEL))objc_msgSend)(CCDirector, @selector(sharedDirector));
    if (!director) return;
    SEL rs = NSSelectorFromString(@"runningScene");
    if (![director respondsToSelector:rs]) return;
    id scene = ((id (*)(id, SEL))objc_msgSend)(director, rs);
    if (!scene) return;
    Class C = NSClassFromString(className);
    if (!C) return;
    id layer = ((id (*)(id, SEL))objc_msgSend)([C alloc], @selector(init));
    if (!layer) return;
    SEL addSel = NSSelectorFromString(@"addChild:z:");
    if ([scene respondsToSelector:addSel]) {
        ((void (*)(id, SEL, id, int))objc_msgSend)(scene, addSel, layer, 88888);
    } else {
        SEL add2 = NSSelectorFromString(@"addChild:");
        if ([scene respondsToSelector:add2]) {
            ((void (*)(id, SEL, id))objc_msgSend)(scene, add2, layer);
        }
    }
}


// ============================================================================
//                  v3-A) 关闭反作弊检测 (GameData / NewSceneUserInfoData / WrapperManager)
// ============================================================================
// GameData.isHackData 是 readonly 属性(无 setter),只 hook getter
%hook GameData

- (BOOL)isHackData {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return NO;
    return %orig;
}

// 彩蛋激活 (easterEggsFlag_ 是 unsigned long)
- (unsigned long)easterEggsFlag {
    unsigned long o = %orig;
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyEasterEgg, NO) && o == 0) return 1;
    return o;
}

// 黄金岛(加勒比)修复 - 服务器停服后 caribbeanData 为 nil,本地造一个
- (id)caribbeanData {
    id orig = %orig;
    if (orig) return orig;
    if (!MT_BOOL(kKeyEnabled, YES) || !MT_BOOL(kKeyFixGoldenIsland, NO)) return orig;

    Class C = NSClassFromString(@"CaribbeanDiscoveringData");
    if (!C) return orig;
    id data = ((id (*)(id, SEL))objc_msgSend)([C alloc], @selector(init));
    if (!data) return orig;

    void (*sendInt)(id, SEL, int) = (void (*)(id, SEL, int))objc_msgSend;
    SEL setCur   = NSSelectorFromString(@"setCurIsland:");
    SEL setDist  = NSSelectorFromString(@"setDistanceToNext:");
    SEL setTotal = NSSelectorFromString(@"setTotleDistance:");
    SEL setSoul  = NSSelectorFromString(@"setCorrectionSoulOfTheSea:");
    SEL setLeft  = NSSelectorFromString(@"setLeftDaysNum:");

    // v15: 如果开"自动到终点"开关,设 curIsland=5(最后一站) + distanceToNext=0(已到达)
    BOOL win = MT_BOOL(kKeyGoldenWin, NO);
    if ([data respondsToSelector:setCur])   sendInt(data, setCur,   win ? 5 : 1);
    if ([data respondsToSelector:setDist])  sendInt(data, setDist,  win ? 0 : 100);
    if ([data respondsToSelector:setTotal]) sendInt(data, setTotal, 500);
    if ([data respondsToSelector:setSoul])  sendInt(data, setSoul,  9999);
    if ([data respondsToSelector:setLeft])  sendInt(data, setLeft,  99);

    SEL setSel = NSSelectorFromString(@"setCaribbeanData:");
    id me = self;
    if ([me respondsToSelector:setSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(me, setSel, data);
    }
    return data;
}

%end


%hook NewSceneUserInfoData

- (BOOL)isHackData {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return NO;
    return %orig;
}
- (void)setIsHackData:(BOOL)b {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) { %orig(NO); return; }
    %orig;
}

%end


%hook WrapperManager

- (void)showCheatWarningMessage {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return;  // 吞掉警告
    %orig;
}

%end


// ============================================================================
//                  v3-B) 魔法密码任意通过 (MagicNumberView)
// ============================================================================
%hook MagicNumberView

- (void)onButtonYesSelected:(id)sender {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyMagicBypass, NO)) {
        // 不走原密码比对,直接调成功回调
        id me = self;
        BOOL fired = NO;
        SEL delSel = NSSelectorFromString(@"magicNumberDelegate");
        if ([me respondsToSelector:delSel]) {
            id delegate = ((id (*)(id, SEL))objc_msgSend)(me, delSel);
            // v21 审查修复: onMagicNumberFinished 未在逆向 dump 确认, 探测多个候选回调名
            const char *cands[] = { "onMagicNumberFinished", "magicNumberFinished", "onMagicNumberCorrect" };
            for (int i = 0; i < 3; i++) {
                SEL cb = sel_registerName(cands[i]);
                if (delegate && [delegate respondsToSelector:cb]) {
                    ((void (*)(id, SEL))objc_msgSend)(delegate, cb);
                    fired = YES;
                    break;
                }
            }
        }
        if (fired) {
            SEL closeSel = NSSelectorFromString(@"doClose");
            if ([me respondsToSelector:closeSel]) {
                ((void (*)(id, SEL))objc_msgSend)(me, closeSel);
            }
            return;
        }
        // v21 审查修复: 无候选回调命中 → 不吞点击, 回落 %orig 走原生密码流程,
        // 避免「既没验证也没绕过、只是把对话框关掉」的静默失效
    }
    %orig;
}

%end


// ============================================================================
//                  v3-C) 秘密按钮显形 (EasterEggMainLayer.isControlOpenSecretButton_)
// ============================================================================
%hook EasterEggMainLayer

// 在 init 后既改 ivar 又调用 lightOpenSecretButton 主动点亮
- (id)init {
    id r = %orig;
    if (r && MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeySecretBtn, NO)) {
        Ivar v = class_getInstanceVariable(object_getClass(r), "isControlOpenSecretButton_");
        if (v) {
            *(char *)((char *)(__bridge void *)r + ivar_getOffset(v)) = 1;
        }
        // 主动调用游戏自己的"点亮按钮"方法
        SEL litSel = NSSelectorFromString(@"lightOpenSecretButton");
        if ([(id)r respondsToSelector:litSel]) {
            ((void (*)(id, SEL))objc_msgSend)(r, litSel);
        }
    }
    return r;
}

%end


// ============================================================================
//   v21) molecheats 对齐 —— 新增开关 hook
//   (max_facility / harvest_mult / free_quest / seabed_best / minigame_reward /
//    all_unlock 扩展 / all_achieve / kill_anticheat 扩展 / force_vip 字符串)
//   全部为 %orig-旁路 getter,来自 mole_cheats.rs intercept() 已验证 (class,sel)。
//   多类采用「另开一个 %hook 同类块」的方式,方法名与上文不冲突即合法。
// ============================================================================

// --- max_facility: 工人/空闲工人/房间数 getter 恒 99(收菜/建造不卡人力/容量)---
%hook UserInfoData
- (int)totalWorkers {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyMaxFacility, NO)) return 99;
    return %orig;
}
- (int)availableWorkers {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyMaxFacility, NO)) return 99;
    return %orig;
}
- (int)totalRooms {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyMaxFacility, NO)) return 99;
    return %orig;
}
%end

// --- harvest_mult: 收菜结算建筑加成 getter 恒 1000(=10倍经验/金币,走原生管线无溢出)---
%hook ObjectManager
- (int)getXPSpeedUpObjectMultiple {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyHarvestMult, NO)) return 1000;
    return %orig;
}
- (int)getGoldSpeedUpObjectMultiple {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyHarvestMult, NO)) return 1000;
    return %orig;
}
%end

// --- free_quest: 任务/催熟所需贝壳数 → 0(秒完成免费)---
%hook Quest
- (int)shellsNeeded {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeQuest, NO)) return 0;
    return %orig;
}
%end
%hook TimeQuest
- (int)shellsNeeded {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyFreeQuest, NO)) return 0;
    return %orig;
}
%end

// --- seabed_best: 海底寻宝必中稀有(generateRandomRewardId 恒最稀档 31169)---
%hook SeabedSeekingTreasureMainLayer
- (int)generateRandomRewardId {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeySeabedBest, NO)) return 31169;
    return %orig;
}
%end

// --- minigame_reward: 钓鱼/挖矿奖励满(类方法在实例上也可 hook 到)---
%hook FishingGame
- (int)getRewardCoin:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyMinigameReward, NO)) return 99999;
    return %orig;
}
%end
%hook MinerGame
- (int)getRewardCoin:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyMinigameReward, NO)) return 99999;
    return %orig;
}
- (int)getRewardXp:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyMinigameReward, NO)) return 99999;
    return %orig;
}
%end

// --- all_unlock 扩展: 各 getLockType4* → 0(0=已解锁), 音乐/头像解锁检查 → YES ---
%hook GameData
- (int)getLockType4Crop:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
- (int)getLockType4CropWithId:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
- (int)getLockType4Object:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
- (int)getLockType4Gift:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
%end
%hook NewSceneData
- (int)getLockType4Object:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
- (int)getLockType4Crop:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
%end
%hook MusicHallLayer
- (BOOL)checkIsUnlockMusic:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return YES;
    return %orig;
}
- (int)getLockType4Decorate:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
%end
%hook AvatarLayer
- (BOOL)checkRequiredVipLevel:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return YES;
    return %orig;
}
%end
%hook DecorateRoomLayer
- (int)getLockType4Decorate:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllUnlock, NO)) return 0;
    return %orig;
}
%end

// --- all_achieve: 成就检查恒通过 (仅 BOOL getter; 绝不 hook void checkAchieve_* 会崩) ---
%hook AchievementControl
- (BOOL)checkInAlreadyUnlockList:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllAchieve, NO)) return YES;
    return %orig;
}
%end
%hook NewSceneAchievement
- (BOOL)checkInAlreadyUnlockList:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllAchieve, NO)) return YES;
    return %orig;
}
%end
%hook AchievementItems
- (BOOL)unlocked:(id)a {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAllAchieve, NO)) return YES;
    return %orig;
}
%end

// --- kill_anticheat 扩展: AppDelegate 作弊警告 + 系统时间检测 ---
%hook iMoleVillageAppDelegate
- (void)showCheatWarningMessage {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return;
    %orig;
}
%end
%hook SystemTimeCheck
- (void)check {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return;
    %orig;
}
- (void)start {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyAntiCheat, NO)) return;
    %orig;
}
%end

// --- force_vip: vipLevelWithNewType 返回字符串(与数值 VIP 等级一致, 调用方走 intValue) ---
static NSString *MTVipLevelString(void) {
    int lv = MT_INT(kKeyVipLevel, 10);
    if (lv <= 0) lv = 1;
    if (lv > 10) lv = 10;
    return [NSString stringWithFormat:@"%d", lv];
}
%hook UserVIPInfoData
- (id)vipLevelWithNewType {
    if (MT_BOOL(kKeyEnabled, YES) && MT_BOOL(kKeyForceVip, NO)) return MTVipLevelString();
    return %orig;
}
%end


// ============================================================================
//                  v3-D) 打开/关闭 TestLayer 调试菜单
// ============================================================================
static __weak id gTestLayerRef = nil;  // 弱引用,避免循环;cocos2d 释放后自动 nil

static BOOL MTIsDebugMenuOpen(void) {
    return gTestLayerRef != nil;
}

static void MTOpenDebugMenu(void) {
    Class cdClass = NSClassFromString(@"CCDirector");
    if (!cdClass) return;
    SEL sd = @selector(sharedDirector);
    if (![cdClass respondsToSelector:sd]) return;
    id director = ((id (*)(id, SEL))objc_msgSend)(cdClass, sd);
    if (!director) return;

    SEL rsSel = NSSelectorFromString(@"runningScene");
    if (![director respondsToSelector:rsSel]) return;
    id scene = ((id (*)(id, SEL))objc_msgSend)(director, rsSel);
    if (!scene) return;

    Class TLClass = NSClassFromString(@"TestLayer");
    if (!TLClass) {
        TLClass = NSClassFromString(@"NewSceneTestLayer");
    }
    if (!TLClass) return;

    id testLayer = ((id (*)(id, SEL))objc_msgSend)([TLClass alloc], @selector(init));
    if (!testLayer) return;

    SEL addSel = NSSelectorFromString(@"addChild:z:");
    if ([scene respondsToSelector:addSel]) {
        ((void (*)(id, SEL, id, int))objc_msgSend)(scene, addSel, testLayer, 99999);
    } else {
        SEL addSel2 = NSSelectorFromString(@"addChild:");
        if ([scene respondsToSelector:addSel2]) {
            ((void (*)(id, SEL, id))objc_msgSend)(scene, addSel2, testLayer);
        }
    }
    gTestLayerRef = testLayer;
}

static void MTCloseDebugMenu(void) {
    id ref = gTestLayerRef;
    if (!ref) return;
    // cocos2d CCNode 移除自身的两个常用 selector
    SEL sel1 = NSSelectorFromString(@"removeFromParentAndCleanup:");
    SEL sel2 = NSSelectorFromString(@"removeFromParent");
    if ([ref respondsToSelector:sel1]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(ref, sel1, YES);
    } else if ([ref respondsToSelector:sel2]) {
        ((void (*)(id, SEL))objc_msgSend)(ref, sel2);
    }
    gTestLayerRef = nil;
}


// ============================================================================
//                  6) 悬浮菜单 UI
// ============================================================================
@interface MTFloatingMenu : NSObject <UITextFieldDelegate>
+ (instancetype)shared;
- (void)show;
- (void)attach;
@end

static UIButton *gFloatingBtn = nil;
static UIView   *gOverlay     = nil;  // 半透明背景遮罩
static UIView   *gMenuView    = nil;  // 白色卡片
static UIScrollView *gScroll  = nil;  // 滚动容器(横屏空间小)
static NSTimer  *gRefreshTimer = nil; // 当前值刷新定时器

// 取一个会跟随旋转的 host view —— rootVC.view 在系统旋转时 bounds 自动更新
static UIView *MTGetHost(void) {
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    if (!win) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.windowLevel == UIWindowLevelNormal) { win = w; break; }
        }
    }
    if (!win) return nil;
    UIViewController *rvc = win.rootViewController;
    return rvc.view ?: (UIView *)win;
}

// 判断设备真实方向
static BOOL MTDeviceIsLandscape(void) {
    UIInterfaceOrientation o = [UIApplication sharedApplication].statusBarOrientation;
    return UIInterfaceOrientationIsLandscape(o);
}

// 检查是否需要旋转(host 未对齐设备方向)
static BOOL MTNeedRotateUI(UIView *host) {
    CGSize hostSz = host.bounds.size;
    BOOL deviceLand = MTDeviceIsLandscape();
    BOOL hostLand = hostSz.width > hostSz.height;
    return deviceLand && !hostLand;
}

// 给"卡片" view 应用 transform 旋转(不旋转 overlay,避免 hit test 错乱)
// 调用前 card 应已 add 到 overlay,且 bounds 设好(landscape 尺寸)
// 函数会把 card 居中放在 overlay 中,并应用旋转 transform
static void MTApplyCardRotation(UIView *card, UIView *overlay) {
    CGSize ovrSz = overlay.bounds.size;
    if (!MTNeedRotateUI(overlay.superview)) {
        // 不需旋转
        card.center = CGPointMake(ovrSz.width / 2, ovrSz.height / 2);
        return;
    }
    UIInterfaceOrientation o = [UIApplication sharedApplication].statusBarOrientation;
    CGAffineTransform tr = (o == UIInterfaceOrientationLandscapeLeft)
        ? CGAffineTransformMakeRotation(-M_PI / 2)
        : CGAffineTransformMakeRotation(M_PI / 2);
    card.transform = tr;
    card.center = CGPointMake(ovrSz.width / 2, ovrSz.height / 2);
}

// 返回卡片内部应使用的 size:如果需要旋转 = swap 后的 landscape;否则 = host bounds
static CGSize MTGetWorkingSize(UIView *host) {
    CGSize sz = host.bounds.size;
    if (MTNeedRotateUI(host)) {
        return CGSizeMake(sz.height, sz.width);  // swap
    }
    return sz;
}

// iOS 6 ScrollView 内 button 假死的标准修复:
//   1. 不延迟 touch 给子视图
//   2. ScrollView 不能 cancel 子视图的 touch
//   3. ScrollView 的 panGestureRecognizer 不要 cancel button 的 touch
//   4. 所有 UIControl(含 UIButton/UISwitch) 设 exclusiveTouch=YES 独占 touch
//   5. 递归处理子 ScrollView
static void MTApplyScrollViewFix(UIScrollView *sv) {
    if (![sv isKindOfClass:[UIScrollView class]]) return;
    sv.delaysContentTouches = NO;
    sv.canCancelContentTouches = NO;
    sv.panGestureRecognizer.cancelsTouchesInView = NO;
    sv.panGestureRecognizer.delaysTouchesBegan = NO;
    for (UIView *v in sv.subviews) {
        if ([v isKindOfClass:[UIControl class]]) {
            v.exclusiveTouch = YES;
        }
        if ([v isKindOfClass:[UIScrollView class]]) {
            MTApplyScrollViewFix((UIScrollView *)v);
        }
    }
}

@implementation MTFloatingMenu

+ (instancetype)shared {
    static MTFloatingMenu *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [MTFloatingMenu new]; });
    return inst;
}

- (void)attach {
    if (gFloatingBtn && gFloatingBtn.superview) return;
    UIView *host = MTGetHost();
    if (!host) {
        // 还没准备好,1 秒后重试
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self attach]; });
        return;
    }
    CGSize sz = host.bounds.size;
    gFloatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    gFloatingBtn.frame = CGRectMake(sz.width - 65, 30, 55, 55);
    gFloatingBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    gFloatingBtn.backgroundColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:0.85];
    gFloatingBtn.layer.cornerRadius = 27.5;
    gFloatingBtn.layer.borderWidth = 2;
    gFloatingBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [gFloatingBtn setTitle:@"修改" forState:UIControlStateNormal];
    [gFloatingBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    gFloatingBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [gFloatingBtn addTarget:self action:@selector(show) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [gFloatingBtn addGestureRecognizer:pan];

    [host addSubview:gFloatingBtn];
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view;
    CGPoint p = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + p.x, v.center.y + p.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}

- (void)show {
    if (gOverlay) { [self closeMenu]; return; }
    UIView *host = MTGetHost();
    if (!host) return;

    // overlay 始终对齐 host (portrait 全屏黑色背景,不旋转)
    gOverlay = [[UIView alloc] initWithFrame:host.bounds];
    gOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    gOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:gOverlay];

    // 工作区尺寸 — 如果设备是 landscape 但 host 是 portrait,这里返回 swap 后的 landscape size
    CGSize sz = MTGetWorkingSize(host);
    BOOL landscape = sz.width > sz.height;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onBgTap:)];
    [gOverlay addGestureRecognizer:tap];

    // 卡片尺寸
    CGFloat w, h;
    if (landscape) {
        w = MIN(540, sz.width - 16);
        h = MIN(sz.height - 16, 300);
    } else {
        w = MIN(320, sz.width - 20);
        h = MIN(sz.height - 30, 540);
    }
    // 卡片用 bounds + center + 可选 transform 旋转(单层 transform 给 hit test 用)
    gMenuView = [[UIView alloc] init];
    gMenuView.bounds = CGRectMake(0, 0, w, h);
    gMenuView.backgroundColor = [UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0];
    gMenuView.layer.cornerRadius = 10;
    gMenuView.layer.borderWidth = 2;
    gMenuView.layer.borderColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:1.0].CGColor;
    [gOverlay addSubview:gMenuView];
    MTApplyCardRotation(gMenuView, gOverlay);

    // 标题栏(含两条分割线)
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, w, 24)];
    title.text = @"摩尔庄园 修改器 v21 (molecheats 对齐)";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:15];
    title.textColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.0 alpha:1.0];
    [gMenuView addSubview:title];

    UIView *sepTop = [[UIView alloc] initWithFrame:CGRectMake(8, 30, w - 16, 1)];
    sepTop.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
    [gMenuView addSubview:sepTop];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w - 32, 2, 28, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithRed:0.7 green:0.1 blue:0.1 alpha:1] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [gMenuView addSubview:closeBtn];

    // 底部按钮区高度
    CGFloat btnAreaH = 42;

    // 滚动容器
    gScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 32, w, h - 32 - btnAreaH)];
    gScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    gScroll.showsVerticalScrollIndicator = YES;
    gScroll.alwaysBounceVertical = YES;
    // iOS 6 ScrollView 默认 delaysContentTouches=YES,会吃掉 UISwitch 的快速点击
    gScroll.delaysContentTouches = NO;
    gScroll.canCancelContentTouches = NO;
    [gMenuView addSubview:gScroll];

    if (landscape) {
        // === 横屏:左列输入,右列开关 ===
        CGFloat colGap = 8;
        CGFloat colW = (w - 16 - colGap) / 2;
        CGFloat leftX = 8;
        CGFloat rightX = 8 + colW + colGap;
        CGFloat ly = 4, ry = 4;

        // 左列 - 数值输入
        [self addInputAtY:&ly title:@"摩尔豆数量"      key:kKeyGold     ph:@"留空=不改" colX:leftX colW:colW];
        [self addInputAtY:&ly title:@"贝壳数量"        key:kKeyVipGold  ph:@"留空=不改" colX:leftX colW:colW];
        [self addInputAtY:&ly title:@"经验值 XP"       key:kKeyXp       ph:@"留空=不改" colX:leftX colW:colW];
        [self addInputAtY:&ly title:@"等级 (1-100)"    key:kKeyLevel    ph:@"留空=不改" colX:leftX colW:colW];
        [self addInputAtY:&ly title:@"VIP 等级 (1-10)" key:kKeyVipLevel ph:@"默认 10"   colX:leftX colW:colW];
        [self addSliderAtY:&ly title:@"金币倍率 (1~50x)" key:kKeyGoldMul min:1.0f max:50.0f colX:leftX colW:colW];
        [self addSliderAtY:&ly title:@"经验倍率 (1~50x)" key:kKeyXpMul   min:1.0f max:50.0f colX:leftX colW:colW];

        // 右列 - 开关
        [self addSwitchAtY:&ry title:@"修改器总开关"     key:kKeyEnabled      defaultOn:YES colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"作物瞬间成熟"     key:kKeyInstant      defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"作物永不枯萎"     key:kKeyNoWither     defaultOn:YES colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"建筑/装修瞬完成"  key:kKeyInstantBuild defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"购物不扣钱"       key:kKeyFreeShop     defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"全局冷却归零"     key:kKeyNoCD         defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"VIP 强制激活"     key:kKeyForceVip     defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"关反作弊检测"     key:kKeyAntiCheat    defaultOn:YES colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"魔法密码任意通过" key:kKeyMagicBypass  defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"秘密按钮显形"     key:kKeySecretBtn    defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"激活彩蛋活动"     key:kKeyEasterEgg    defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"主菜单显示隐藏点位" key:kKeyShowHidden defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"NSLog 写日志文件"  key:kKeyLogToFile   defaultOn:NO  colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"修复黄金岛(加勒比)" key:kKeyFixGoldenIsland defaultOn:NO colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"黄金岛航行到终点"     key:kKeyGoldenWin       defaultOn:NO colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"💰 购买点击=直接成功"  key:kKeyInstantPurchase defaultOn:NO colX:rightX colW:colW];
        // v21 molecheats 新增开关(已验证 hook)
        [self addSwitchAtY:&ry title:@"工人/房间补满(99)"   key:kKeyMaxFacility     defaultOn:NO colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"产出×10(收菜结算)"   key:kKeyHarvestMult     defaultOn:NO colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"任务秒完成免费"       key:kKeyFreeQuest       defaultOn:NO colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"海底寻宝必中稀有"     key:kKeySeabedBest      defaultOn:NO colX:rightX colW:colW];
        [self addSwitchAtY:&ry title:@"小游戏奖励满"         key:kKeyMinigameReward  defaultOn:NO colX:rightX colW:colW];

        // 丝尔特 demo 庄园 section(横屏:跨两栏放在底部)
        CGFloat secY = MAX(ly, ry) + 4;
        [self addXiaoTuLvSectionAtY:&secY colX:8 colW:w - 16];

        gScroll.contentSize = CGSizeMake(w, secY + 8);
        MTApplyScrollViewFix(gScroll);
    } else {
        // === 竖屏:单列 ===
        CGFloat ly = 4;
        CGFloat colW = w - 16;
        CGFloat colX = 8;

        [self addSwitchAtY:&ly title:@"修改器总开关"     key:kKeyEnabled      defaultOn:YES colX:colX colW:colW];
        [self addInputAtY:&ly  title:@"摩尔豆数量"       key:kKeyGold         ph:@"留空=不改" colX:colX colW:colW];
        [self addInputAtY:&ly  title:@"贝壳数量"         key:kKeyVipGold      ph:@"留空=不改" colX:colX colW:colW];
        [self addInputAtY:&ly  title:@"经验值 XP"        key:kKeyXp           ph:@"留空=不改" colX:colX colW:colW];
        [self addInputAtY:&ly  title:@"等级 (1-100)"     key:kKeyLevel        ph:@"留空=不改" colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"作物瞬间成熟"     key:kKeyInstant      defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"作物永不枯萎"     key:kKeyNoWither     defaultOn:YES colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"建筑/装修瞬完成"  key:kKeyInstantBuild defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"购物不扣钱"       key:kKeyFreeShop     defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"全局冷却归零"     key:kKeyNoCD         defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"VIP 强制激活"     key:kKeyForceVip     defaultOn:NO  colX:colX colW:colW];
        [self addInputAtY:&ly  title:@"VIP 等级 (1-10)"  key:kKeyVipLevel     ph:@"默认 10"  colX:colX colW:colW];
        [self addSliderAtY:&ly title:@"金币倍率 (1~50x)" key:kKeyGoldMul min:1.0f max:50.0f colX:colX colW:colW];
        [self addSliderAtY:&ly title:@"经验倍率 (1~50x)" key:kKeyXpMul   min:1.0f max:50.0f colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"关反作弊检测"     key:kKeyAntiCheat    defaultOn:YES colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"魔法密码任意通过" key:kKeyMagicBypass  defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"秘密按钮显形"     key:kKeySecretBtn    defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"激活彩蛋活动"     key:kKeyEasterEgg    defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"主菜单显示隐藏点位" key:kKeyShowHidden defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"NSLog 写日志文件" key:kKeyLogToFile   defaultOn:NO  colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"修复黄金岛(加勒比)" key:kKeyFixGoldenIsland defaultOn:NO colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"黄金岛航行到终点"     key:kKeyGoldenWin       defaultOn:NO colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"💰 购买点击=直接成功"  key:kKeyInstantPurchase defaultOn:NO colX:colX colW:colW];
        // v21 molecheats 新增开关(已验证 hook)
        [self addSwitchAtY:&ly title:@"工人/房间补满(99)"   key:kKeyMaxFacility     defaultOn:NO colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"产出×10(收菜结算)"   key:kKeyHarvestMult     defaultOn:NO colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"任务秒完成免费"       key:kKeyFreeQuest       defaultOn:NO colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"海底寻宝必中稀有"     key:kKeySeabedBest      defaultOn:NO colX:colX colW:colW];
        [self addSwitchAtY:&ly title:@"小游戏奖励满"         key:kKeyMinigameReward  defaultOn:NO colX:colX colW:colW];

        [self addXiaoTuLvSectionAtY:&ly colX:colX colW:colW];

        gScroll.contentSize = CGSizeMake(w, ly + 8);
        MTApplyScrollViewFix(gScroll);
    }

    // === 底部按钮区:3 个按钮横排 ===
    UIView *btnBar = [[UIView alloc] initWithFrame:CGRectMake(0, h - btnAreaH, w, btnAreaH)];
    btnBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    btnBar.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
    [gMenuView addSubview:btnBar];

    UIView *sepBot = [[UIView alloc] initWithFrame:CGRectMake(8, 0, w - 16, 1)];
    sepBot.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
    [btnBar addSubview:sepBot];

    CGFloat btnGap = 4;
    CGFloat btnY = 5;
    CGFloat btnH = btnAreaH - 10;
    CGFloat btnW = (w - btnGap * 6) / 5.0;  // 5 按钮

    UIButton *harvestBtn = [self makeActionButtonTitle:@"成熟全部"
                                                  bgRGB:0x33aa33
                                                  frame:CGRectMake(btnGap, btnY, btnW, btnH)
                                                 action:@selector(onHarvestAll)];
    [btnBar addSubview:harvestBtn];

    UIButton *devBtn = [self makeActionButtonTitle:@"开发面板"
                                              bgRGB:0x6644aa
                                              frame:CGRectMake(btnGap*2 + btnW, btnY, btnW, btnH)
                                             action:@selector(onShowDevPanel)];
    [btnBar addSubview:devBtn];

    UIButton *openDebugBtn = [self makeActionButtonTitle:@"打开调试"
                                                    bgRGB:0x4488dd
                                                    frame:CGRectMake(btnGap*3 + btnW*2, btnY, btnW, btnH)
                                                   action:@selector(onOpenDebugMenu)];
    [btnBar addSubview:openDebugBtn];

    UIButton *closeDebugBtn = [self makeActionButtonTitle:@"关调试"
                                                     bgRGB:(MTIsDebugMenuOpen() ? 0x884488 : 0x999999)
                                                     frame:CGRectMake(btnGap*4 + btnW*3, btnY, btnW, btnH)
                                                    action:@selector(onCloseDebugMenu)];
    closeDebugBtn.enabled = MTIsDebugMenuOpen();
    [btnBar addSubview:closeDebugBtn];

    UIButton *applyBtn = [self makeActionButtonTitle:@"保存关闭"
                                                bgRGB:0xff7f1a
                                                frame:CGRectMake(btnGap*5 + btnW*4, btnY, btnW, btnH)
                                               action:@selector(closeMenu)];
    [btnBar addSubview:applyBtn];

    // 启动定时器实时刷新"当前"绿字
    if (gRefreshTimer) { [gRefreshTimer invalidate]; gRefreshTimer = nil; }
    gRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                     target:self
                                                   selector:@selector(refreshCurrentLabels)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (UIButton *)makeActionButtonTitle:(NSString *)title bgRGB:(unsigned int)rgb frame:(CGRect)f action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.backgroundColor = [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0
                                        green:((rgb>>8)&0xFF)/255.0
                                         blue:(rgb&0xFF)/255.0
                                        alpha:1.0];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    b.layer.cornerRadius = 5;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)addSwitchAtY:(CGFloat *)y title:(NSString *)t key:(NSString *)k defaultOn:(BOOL)def colX:(CGFloat)cx colW:(CGFloat)cw {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(cx + 4, *y, cw - 60, 30)];
    lbl.text = t;
    lbl.font = [UIFont systemFontOfSize:13];
    lbl.adjustsFontSizeToFitWidth = YES;
    lbl.minimumFontSize = 10;
    [gScroll addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    // v21 审查修复: 首次显示时把默认值落盘, 使开关显示与 hook 读取的 MT_BOOL(key, NO) 一致
    // (原来 defaultOn:YES 的「永不枯萎/关反作弊」只是显示开、没写进 plist → hook 读到 NO 而失效)
    if (![MTSettings() objectForKey:k]) MT_SET(k, @(def));
    sw.on = MT_BOOL(k, def);
    // UISwitch 的 frame 大小固定,只能调位置;放右对齐
    CGSize swSz = sw.bounds.size;
    sw.frame = CGRectMake(cx + cw - swSz.width - 2, *y + (30 - swSz.height)/2, swSz.width, swSz.height);
    objc_setAssociatedObject(sw, "mtkey", k, OBJC_ASSOCIATION_RETAIN);
    [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    [gScroll addSubview:sw];
    *y += 32;
}

// 读对应 key 的"游戏当前真实值"字符串(由 hook getter 实时缓存)
// === 滑块控件: 倍率类用 (1.0 ~ 50.0) ===
- (void)addSliderAtY:(CGFloat *)y title:(NSString *)t key:(NSString *)k
                 min:(float)minV max:(float)maxV
                colX:(CGFloat)cx colW:(CGFloat)cw {
    // 行 1: 标题 + 当前游戏数值 + 当前设置数值
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(cx + 4, *y, cw * 0.42, 14)];
    titleLbl.text = t;
    titleLbl.font = [UIFont systemFontOfSize:11];
    titleLbl.textColor = [UIColor darkGrayColor];
    [gScroll addSubview:titleLbl];

    UILabel *currentLbl = [[UILabel alloc] initWithFrame:CGRectMake(cx + 4 + cw * 0.42, *y, cw * 0.58 - 8, 14)];
    currentLbl.text = [NSString stringWithFormat:@"当前: %@", [self readRawValueForKey:k]];
    currentLbl.font = [UIFont systemFontOfSize:10];
    currentLbl.textColor = [UIColor colorWithRed:0.0 green:0.55 blue:0.1 alpha:1.0];
    currentLbl.textAlignment = NSTextAlignmentRight;
    objc_setAssociatedObject(currentLbl, "mtcurrent_for_key", k, OBJC_ASSOCIATION_RETAIN);
    [gScroll addSubview:currentLbl];

    // 行 2: slider + 右侧值显示
    float curVal = MT_FLT(k, 1.0f);
    if (curVal < minV) curVal = minV;
    if (curVal > maxV) curVal = maxV;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(cx + 4, *y + 14, cw - 60, 26)];
    slider.minimumValue = minV;
    slider.maximumValue = maxV;
    slider.value = curVal;
    slider.minimumTrackTintColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:1.0];
    objc_setAssociatedObject(slider, "mtkey", k, OBJC_ASSOCIATION_RETAIN);
    [slider addTarget:self action:@selector(onSlider:) forControlEvents:UIControlEventValueChanged];
    [gScroll addSubview:slider];

    UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(cx + cw - 52, *y + 14, 50, 26)];
    valLbl.text = [NSString stringWithFormat:@"x%.1f", curVal];
    valLbl.font = [UIFont boldSystemFontOfSize:13];
    valLbl.textAlignment = NSTextAlignmentRight;
    valLbl.textColor = (curVal > 1.01f) ? [UIColor colorWithRed:0.85 green:0.05 blue:0.05 alpha:1.0]
                                         : [UIColor blackColor];
    objc_setAssociatedObject(slider, "mtvallabel", valLbl, OBJC_ASSOCIATION_RETAIN);
    [gScroll addSubview:valLbl];

    *y += 42;
}

- (void)onSlider:(UISlider *)sl {
    NSString *k = objc_getAssociatedObject(sl, "mtkey");
    if (!k) return;
    float v = sl.value;
    // 0.1 步进取整
    v = roundf(v * 10) / 10.0f;
    MT_SET(k, @(v));
    UILabel *lbl = objc_getAssociatedObject(sl, "mtvallabel");
    if (lbl) {
        lbl.text = [NSString stringWithFormat:@"x%.1f", v];
        lbl.textColor = (v > 1.01f) ? [UIColor colorWithRed:0.85 green:0.05 blue:0.05 alpha:1.0]
                                     : [UIColor blackColor];
    }
}

- (NSString *)readRawValueForKey:(NSString *)k {
    if ([k isEqualToString:kKeyGold])     return [NSString stringWithFormat:@"%d", gRawGold];
    if ([k isEqualToString:kKeyVipGold])  return [NSString stringWithFormat:@"%d", gRawVipGold];
    if ([k isEqualToString:kKeyXp])       return [NSString stringWithFormat:@"%d", gRawXp];
    if ([k isEqualToString:kKeyLevel])    return [NSString stringWithFormat:@"%d", gRawLevel];
    if ([k isEqualToString:kKeyVipLevel]) return [NSString stringWithFormat:@"%u", gRawVipLevel];
    if ([k isEqualToString:kKeyGoldMul])  return [NSString stringWithFormat:@"%.2f", gRawGoldMul];
    if ([k isEqualToString:kKeyXpMul])    return [NSString stringWithFormat:@"%.2f", gRawXpMul];
    return @"--";
}

- (void)addInputAtY:(CGFloat *)y title:(NSString *)t key:(NSString *)k ph:(NSString *)ph colX:(CGFloat)cx colW:(CGFloat)cw {
    // 行 1: 标题 + "当前 X" 绿字
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(cx + 4, *y, cw * 0.42, 14)];
    titleLbl.text = t;
    titleLbl.font = [UIFont systemFontOfSize:11];
    titleLbl.textColor = [UIColor darkGrayColor];
    [gScroll addSubview:titleLbl];

    UILabel *currentLbl = [[UILabel alloc] initWithFrame:CGRectMake(cx + 4 + cw * 0.42, *y, cw * 0.58 - 8, 14)];
    currentLbl.text = [NSString stringWithFormat:@"当前: %@", [self readRawValueForKey:k]];
    currentLbl.font = [UIFont systemFontOfSize:10];
    currentLbl.textColor = [UIColor colorWithRed:0.0 green:0.55 blue:0.1 alpha:1.0];  // 绿
    currentLbl.textAlignment = NSTextAlignmentRight;
    currentLbl.adjustsFontSizeToFitWidth = YES;
    currentLbl.minimumFontSize = 9;
    objc_setAssociatedObject(currentLbl, "mtcurrent_for_key", k, OBJC_ASSOCIATION_RETAIN);
    [gScroll addSubview:currentLbl];

    // 行 2: 输入框
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(cx + 4, *y + 14, cw - 8, 24)];
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.font = [UIFont systemFontOfSize:13];
    tf.placeholder = ph;
    tf.keyboardType = UIKeyboardTypeDecimalPad;
    tf.delegate = self;
    id v = [MTSettings() objectForKey:k];
    BOOL hasOverride = NO;
    if (v) {
        NSString *vs = [NSString stringWithFormat:@"%@", v];
        // 0 / "0" / 0.0 视为"未设置"
        if ([k isEqualToString:kKeyGoldMul] || [k isEqualToString:kKeyXpMul]) {
            if ([v floatValue] > 0.0001f) { tf.text = vs; hasOverride = YES; }
        } else {
            if ([v intValue] > 0) { tf.text = vs; hasOverride = YES; }
        }
    }
    if (hasOverride) {
        tf.textColor = [UIColor colorWithRed:0.85 green:0.05 blue:0.05 alpha:1.0]; // 红 = 已修改
        tf.layer.borderColor = [UIColor colorWithRed:0.85 green:0.05 blue:0.05 alpha:1.0].CGColor;
        tf.layer.borderWidth = 1.0;
        tf.layer.cornerRadius = 5;
    }
    objc_setAssociatedObject(tf, "mtkey", k, OBJC_ASSOCIATION_RETAIN);
    [tf addTarget:self action:@selector(onText:) forControlEvents:UIControlEventEditingChanged];
    [gScroll addSubview:tf];

    // 行高 14(title)+24(input)+4(gap)= 42
    *y += 42;
}

// 定时器:菜单打开时每 0.5 秒刷新所有 currentLbl 的"当前: X"
- (void)refreshCurrentLabels {
    if (!gScroll) return;
    for (UIView *sv in gScroll.subviews) {
        if (![sv isKindOfClass:[UILabel class]]) continue;
        NSString *k = objc_getAssociatedObject(sv, "mtcurrent_for_key");
        if (!k) continue;
        ((UILabel *)sv).text = [NSString stringWithFormat:@"当前: %@", [self readRawValueForKey:k]];
    }
}

- (void)onSwitch:(UISwitch *)sw {
    NSString *k = objc_getAssociatedObject(sw, "mtkey");
    if (k) MT_SET(k, @(sw.on));
}

- (void)onText:(UITextField *)tf {
    NSString *k = objc_getAssociatedObject(tf, "mtkey");
    if (!k) return;
    NSString *txt = tf.text ?: @"";
    BOOL hasOverride = NO;
    if ([k isEqualToString:kKeyGoldMul] || [k isEqualToString:kKeyXpMul]) {
        float val = [txt floatValue];
        MT_SET(k, @(val));
        hasOverride = (val > 0.0001f);
    } else {
        int val = [txt intValue];
        MT_SET(k, @(val));
        hasOverride = (val > 0);
    }
    // 实时切换红/黑
    if (hasOverride) {
        tf.textColor = [UIColor colorWithRed:0.85 green:0.05 blue:0.05 alpha:1.0];
        tf.layer.borderColor = [UIColor colorWithRed:0.85 green:0.05 blue:0.05 alpha:1.0].CGColor;
        tf.layer.borderWidth = 1.0;
        tf.layer.cornerRadius = 5;
    } else {
        tf.textColor = [UIColor blackColor];
        tf.layer.borderWidth = 0;
    }
}

- (void)showToast:(NSString *)text {
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 240, 40)];
    UIView *target = gOverlay ?: MTGetHost();
    if (target) toast.center = CGPointMake(target.bounds.size.width/2, target.bounds.size.height - 60);
    toast.text = text;
    toast.textAlignment = NSTextAlignmentCenter;
    toast.textColor = [UIColor whiteColor];
    toast.font = [UIFont boldSystemFontOfSize:14];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
    toast.layer.cornerRadius = 6;
    toast.clipsToBounds = YES;
    toast.userInteractionEnabled = NO;  // 不拦截 touch
    [target addSubview:toast];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [toast removeFromSuperview]; });
}

- (void)onHarvestAll {
    MTHarvestAllNow();
    [self showToast:@"已触发所有作物成熟"];
}

- (void)onOpenDebugMenu {
    // 关闭当前菜单后再弹 TestLayer (避免覆盖)
    [self closeMenu];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MTOpenDebugMenu();
        [self showToast:@"已弹出 TestLayer 调试菜单"];
    });
}

- (void)onCloseDebugMenu {
    if (!MTIsDebugMenuOpen()) {
        [self showToast:@"调试菜单未打开"];
        return;
    }
    MTCloseDebugMenu();
    [self showToast:@"调试菜单已关闭"];
}

// =========================================================================
//  二级面板: 18 对 ± 按钮直接调 TestLayer 的 onButtonXxxPlus:/Minus: 方法
//  原理:alloc 一个不 addChild 的"幽灵"TestLayer 实例,通过它调原版方法
//  这样绕开 cocos2d touch dispatch 优先级问题(部分按钮没响应)
// =========================================================================
static id gGhostTestLayer = nil;

static id MTGhostTestLayer(void) {
    if (gGhostTestLayer) return gGhostTestLayer;
    Class TLClass = NSClassFromString(@"TestLayer");
    if (!TLClass) return nil;
    gGhostTestLayer = ((id (*)(id, SEL))objc_msgSend)([TLClass alloc], @selector(init));
    return gGhostTestLayer;
}

static void MTCallTestLayer(NSString *selName, int repeat) {
    id tl = MTGhostTestLayer();
    if (!tl) return;
    SEL sel = NSSelectorFromString(selName);
    if (![tl respondsToSelector:sel]) return;
    for (int i = 0; i < repeat && i < 1000; i++) {
        ((void (*)(id, SEL, id))objc_msgSend)(tl, sel, nil);
    }
}

static UIView *gDevPanelOverlay = nil;
static UIView *gDevPanelCard = nil;

- (void)onShowDevPanel {
    if (gDevPanelOverlay) { [self closeDevPanel]; return; }
    UIView *host = MTGetHost();
    if (!host) return;

    // overlay 全屏不旋转(只是底纹)
    gDevPanelOverlay = [[UIView alloc] initWithFrame:host.bounds];
    gDevPanelOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    gDevPanelOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:gDevPanelOverlay];

    CGSize sz = MTGetWorkingSize(host);
    BOOL landscape = sz.width > sz.height;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDevPanelBgTap:)];
    [gDevPanelOverlay addGestureRecognizer:tap];

    UIInterfaceOrientation _o = [UIApplication sharedApplication].statusBarOrientation;
    NSLog(@"[MoleTweak] DevPanel: workSize=%.0fx%.0f hostSz=%.0fx%.0f orient=%d landscape=%d",
          sz.width, sz.height, host.bounds.size.width, host.bounds.size.height,
          (int)_o, (int)landscape);

    CGFloat w = landscape ? MIN(540, sz.width - 20) : MIN(320, sz.width - 20);
    CGFloat h = MIN(sz.height - 30, landscape ? 300 : 480);

    // 卡片用 bounds + center,需要时给单层 transform
    gDevPanelCard = [[UIView alloc] init];
    gDevPanelCard.bounds = CGRectMake(0, 0, w, h);
    gDevPanelCard.backgroundColor = [UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0];
    gDevPanelCard.layer.cornerRadius = 10;
    gDevPanelCard.layer.borderWidth = 2;
    gDevPanelCard.layer.borderColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.9 alpha:1.0].CGColor;
    [gDevPanelOverlay addSubview:gDevPanelCard];
    MTApplyCardRotation(gDevPanelCard, gDevPanelOverlay);

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, w, 24)];
    title.text = @"开发者面板 (TestLayer 18 对 ± 按钮直调)";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.6 alpha:1.0];
    [gDevPanelCard addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w - 32, 2, 28, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [closeBtn addTarget:self action:@selector(closeDevPanel) forControlEvents:UIControlEventTouchUpInside];
    [gDevPanelCard addSubview:closeBtn];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 32, w, h - 32)];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.delaysContentTouches = NO;
    scroll.canCancelContentTouches = NO;
    scroll.alwaysBounceVertical = YES;
    [gDevPanelCard addSubview:scroll];

    // 18 行: 每行 [资源名 | -10 | -1 | +1 | +10]
    NSArray *items = @[
        @[@"经验 XP",       @"onButtonXPMinus:",       @"onButtonXPPlus:"],
        @[@"摩尔豆 Gold",   @"onButtonGoldMinus:",     @"onButtonGoldPlus:"],
        @[@"贝壳 VipGold",  @"onButtonVipGoldMinus:",  @"onButtonVipGoldPlus:"],
        @[@"VIP 值",        @"onButtonVipValueMinus:", @"onButtonVipValuePlus:"],
        @[@"时间 Time",     @"onButtonTimeMinus:",     @"onButtonTimePlus:"],
        @[@"任务 Quest",    @"onButtonQuestMinus:",    @"onButtonQuestPlus:"],
        @[@"限时任务",      @"onButtonTimeQuestMinus:",@"onButtonTimeQuestPlus:"],
        @[@"VIP 任务",      @"onButtonVipQuestMinus:", @"onButtonVipQuestPlus:"],
        @[@"食物 Food",     @"onButtonFoodMinus:",     @"onButtonFoodPlus:"],
        @[@"奖励券 Tickets",@"onButtonTicketsMinus:",  @"onButtonTicketsPlus:"],
    ];

    CGFloat y = 4;
    CGFloat rowH = 32;
    CGFloat lblW = w * 0.42;
    CGFloat btnGap = 4;
    CGFloat btnAreaW = w - lblW - 16 - btnGap * 3;
    CGFloat btnW = btnAreaW / 4;
    for (NSArray *row in items) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(8, y, lblW, rowH)];
        l.text = row[0];
        l.font = [UIFont systemFontOfSize:12];
        [scroll addSubview:l];

        // -10 / -1 / +1 / +10
        NSString *minusSel = row[1];
        NSString *plusSel  = row[2];
        NSArray *btnDefs = @[ @[@"-10", minusSel, @10], @[@"-1", minusSel, @1],
                              @[@"+1", plusSel, @1],   @[@"+10", plusSel, @10] ];
        CGFloat bx = lblW + 12;
        for (NSArray *def in btnDefs) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(bx, y + 2, btnW, rowH - 4);
            [b setTitle:def[0] forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            BOOL isMinus = [def[0] hasPrefix:@"-"];
            b.backgroundColor = isMinus ? [UIColor colorWithRed:0.85 green:0.3 blue:0.3 alpha:1.0]
                                         : [UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            b.layer.cornerRadius = 4;
            objc_setAssociatedObject(b, "mtsel",   def[1], OBJC_ASSOCIATION_RETAIN);
            objc_setAssociatedObject(b, "mtcount", def[2], OBJC_ASSOCIATION_RETAIN);
            [b addTarget:self action:@selector(onDevPanelButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [scroll addSubview:b];
            bx += btnW + btnGap;
        }
        y += rowH + 2;
    }

    // NewSceneTestLayer.onButtonbuildValuePlus:
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(8, y, lblW, rowH)];
    lbl.text = @"建筑值 (新场景)";
    lbl.font = [UIFont systemFontOfSize:12];
    [scroll addSubview:lbl];
    UIButton *bbn = [UIButton buttonWithType:UIButtonTypeCustom];
    bbn.frame = CGRectMake(lblW + 12, y + 2, btnW * 4 + btnGap * 3, rowH - 4);
    [bbn setTitle:@"+1 (NewSceneTestLayer)" forState:UIControlStateNormal];
    [bbn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    bbn.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:1.0];
    bbn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    bbn.layer.cornerRadius = 4;
    [bbn addTarget:self action:@selector(onDevPanelBuildValuePlus) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:bbn];
    y += rowH + 2;

    // ============================================================
    // v13 Section A: 🎨 玩家数据修改(头像/房间数/工人数)
    // ============================================================
    UILabel *secA = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 16, 18)];
    secA.text = @"--- 🎨 玩家数据修改 (UserInfoData) ---";
    secA.font = [UIFont boldSystemFontOfSize:11];
    secA.textColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.4 alpha:1];
    secA.textAlignment = NSTextAlignmentCenter;
    [scroll addSubview:secA];
    y += 22;

    // 3 个并排输入框
    CGFloat ipW = (w - 16 - 16) / 3;
    NSArray *ipDefs = @[
        @[@"头像 ID(1-61)", kKeyAvatarIcon],
        @[@"总房间数",      kKeyTotalRooms],
        @[@"工人数",        kKeyTotalWorkers],
    ];
    for (int i = 0; i < (int)ipDefs.count; i++) {
        NSArray *d = ipDefs[i];
        CGFloat ix = 8 + i * (ipW + 8);
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(ix, y, ipW, 14)];
        l.text = d[0];
        l.font = [UIFont systemFontOfSize:10];
        l.textColor = [UIColor darkGrayColor];
        [scroll addSubview:l];
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(ix, y + 14, ipW, 24)];
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.font = [UIFont systemFontOfSize:12];
        tf.placeholder = @"0=不改";
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.delegate = self;
        id v = [MTSettings() objectForKey:d[1]];
        if (v && [v intValue] > 0) tf.text = [NSString stringWithFormat:@"%@", v];
        objc_setAssociatedObject(tf, "mtkey", d[1], OBJC_ASSOCIATION_RETAIN);
        [tf addTarget:self action:@selector(onText:) forControlEvents:UIControlEventEditingChanged];
        [scroll addSubview:tf];
    }
    y += 42;

    UIButton *applyUI = [UIButton buttonWithType:UIButtonTypeCustom];
    applyUI.frame = CGRectMake(8, y, w - 16, 30);
    [applyUI setTitle:@"✅ 应用玩家数据修改" forState:UIControlStateNormal];
    [applyUI setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    applyUI.backgroundColor = [UIColor colorWithRed:0.2 green:0.65 blue:0.4 alpha:1];
    applyUI.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    applyUI.layer.cornerRadius = 4;
    [applyUI addTarget:self action:@selector(onApplyUserInfoOverrides) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:applyUI];
    y += 36;

    // ============================================================
    // v13 Section B: 🔄 一键任务/签到重置
    // ============================================================
    UILabel *secB = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 16, 18)];
    secB.text = @"--- 🔄 一键任务/签到重置 ---";
    secB.font = [UIFont boldSystemFontOfSize:11];
    secB.textColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.6 alpha:1];
    secB.textAlignment = NSTextAlignmentCenter;
    [scroll addSubview:secB];
    y += 22;

    NSArray *resetDefs = @[
        @[@"重置每日任务",   @"resetUnfinishedDailyQuestDataInMap"],
        @[@"重置限时任务",   @"resetTimeQuestDataInMap"],
        @[@"重置 VIP 任务",  @"resetVipQuestDataInMap"],
        @[@"重置今日签到",   @"resetLastGetDailyRewardDay"],
        @[@"重置每日列表",   @"resetDailyQuestList"],
        @[@"重置签到兑换",   @"resetDailySignExchangeData"],
        @[@"重置宝箱数据",   @"resetTreasureChestData"],
        @[@"重置加勒比",     @"resetCaribbeanData"],
    ];
    CGFloat rsBtnW = (w - 16 - 8) / 2;
    for (int i = 0; i < (int)resetDefs.count; i++) {
        NSArray *d = resetDefs[i];
        CGFloat rsx = 8 + (i % 2) * (rsBtnW + 8);
        CGFloat rsy = y + (i / 2) * 32;
        UIButton *rsb = [UIButton buttonWithType:UIButtonTypeCustom];
        rsb.frame = CGRectMake(rsx, rsy, rsBtnW, 28);
        [rsb setTitle:d[0] forState:UIControlStateNormal];
        [rsb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        rsb.backgroundColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.7 alpha:1];
        rsb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        rsb.layer.cornerRadius = 4;
        objc_setAssociatedObject(rsb, "mtreset_sel", d[1], OBJC_ASSOCIATION_RETAIN);
        [rsb addTarget:self action:@selector(onDevPanelReset:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:rsb];
    }
    y += ((int)resetDefs.count + 1) / 2 * 32;

    // v14: 奖励券输入 + 应用按钮
    UILabel *tkLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 16, 14)];
    tkLbl.text = @"奖励券数 (setRewardTickets:)";
    tkLbl.font = [UIFont systemFontOfSize:10];
    tkLbl.textColor = [UIColor darkGrayColor];
    [scroll addSubview:tkLbl];
    UITextField *tkTf = [[UITextField alloc] initWithFrame:CGRectMake(8, y + 14, w - 16 - 90, 24)];
    tkTf.borderStyle = UITextBorderStyleRoundedRect;
    tkTf.font = [UIFont systemFontOfSize:12];
    tkTf.placeholder = @"输入数字";
    tkTf.keyboardType = UIKeyboardTypeNumberPad;
    tkTf.delegate = self;
    id tv = [MTSettings() objectForKey:kKeyTickets];
    if (tv && [tv intValue] > 0) tkTf.text = [NSString stringWithFormat:@"%@", tv];
    objc_setAssociatedObject(tkTf, "mtkey", kKeyTickets, OBJC_ASSOCIATION_RETAIN);
    [tkTf addTarget:self action:@selector(onText:) forControlEvents:UIControlEventEditingChanged];
    [scroll addSubview:tkTf];
    UIButton *tkBn = [UIButton buttonWithType:UIButtonTypeCustom];
    tkBn.frame = CGRectMake(w - 8 - 80, y + 14, 80, 24);
    [tkBn setTitle:@"应用奖励券" forState:UIControlStateNormal];
    [tkBn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    tkBn.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.4 alpha:1];
    tkBn.titleLabel.font = [UIFont systemFontOfSize:11];
    tkBn.layer.cornerRadius = 4;
    [tkBn addTarget:self action:@selector(onApplyTickets) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:tkBn];
    y += 42;

    // v14: 一键奖励按钮(GameManager 上的两个 add*Reward)
    NSArray *rewardDefs = @[
        @[@"🎁 给宝藏奖励",  @"addTreasureReward"],
        @[@"🐰 给宝藏兔奖励", @"addTreasureRabbitReward"],
    ];
    for (int i = 0; i < (int)rewardDefs.count; i++) {
        NSArray *d = rewardDefs[i];
        CGFloat rx = 8 + (i % 2) * (rsBtnW + 8);
        UIButton *rb = [UIButton buttonWithType:UIButtonTypeCustom];
        rb.frame = CGRectMake(rx, y, rsBtnW, 28);
        [rb setTitle:d[0] forState:UIControlStateNormal];
        [rb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        rb.backgroundColor = [UIColor colorWithRed:0.85 green:0.6 blue:0.2 alpha:1];
        rb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        rb.layer.cornerRadius = 4;
        objc_setAssociatedObject(rb, "mtgm_sel", d[1], OBJC_ASSOCIATION_RETAIN);
        [rb addTarget:self action:@selector(onDevPanelGmCall:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:rb];
    }
    y += 32;

    // v14: 危险按钮 — 整库重置(全宽红色,带二次确认)
    UIButton *dangerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    dangerBtn.frame = CGRectMake(8, y, w - 16, 30);
    [dangerBtn setTitle:@"⚠️ 整库重置 resetUserGameData(不可逆)" forState:UIControlStateNormal];
    [dangerBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    dangerBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1];
    dangerBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    dangerBtn.layer.cornerRadius = 4;
    [dangerBtn addTarget:self action:@selector(onResetAllUserData) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:dangerBtn];
    y += 36;

    // ============================================================
    // v13 Section C: ⏰ 服务器时间魔法
    // ============================================================
    UILabel *secC = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 16, 18)];
    secC.text = @"--- ⏰ 服务器时间魔法(节日触发) ---";
    secC.font = [UIFont boldSystemFontOfSize:11];
    secC.textColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.5 alpha:1];
    secC.textAlignment = NSTextAlignmentCenter;
    [scroll addSubview:secC];
    y += 22;

    // 时间欺骗开关
    UILabel *swLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 80, 30)];
    swLbl.text = @"启用时间欺骗(覆盖服务器时间)";
    swLbl.font = [UIFont systemFontOfSize:12];
    [scroll addSubview:swLbl];
    UISwitch *tmsw = [[UISwitch alloc] initWithFrame:CGRectZero];
    tmsw.on = MT_BOOL(kKeyTimeMagic, NO);
    CGSize sz_ = tmsw.bounds.size;
    tmsw.frame = CGRectMake(w - sz_.width - 10, y + (30 - sz_.height)/2, sz_.width, sz_.height);
    objc_setAssociatedObject(tmsw, "mtkey", kKeyTimeMagic, OBJC_ASSOCIATION_RETAIN);
    [tmsw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    [scroll addSubview:tmsw];
    y += 36;

    // 4 个节日快捷按钮
    NSArray *fes = @[
        @[@"春节 2014",   @1391126400UL],  // 2014-01-31 00:00 UTC
        @[@"儿童节",      @1369958400UL],  // 2013-06-01 00:00 UTC
        @[@"圣诞 2013",   @1387929600UL],  // 2013-12-25 00:00 UTC
        @[@"万圣 2013",   @1383177600UL],  // 2013-10-31 00:00 UTC
    ];
    for (int i = 0; i < (int)fes.count; i++) {
        NSArray *d = fes[i];
        CGFloat fx = 8 + (i % 2) * (rsBtnW + 8);
        CGFloat fy = y + (i / 2) * 32;
        UIButton *fb = [UIButton buttonWithType:UIButtonTypeCustom];
        fb.frame = CGRectMake(fx, fy, rsBtnW, 28);
        [fb setTitle:d[0] forState:UIControlStateNormal];
        [fb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        fb.backgroundColor = [UIColor colorWithRed:0.7 green:0.4 blue:0.6 alpha:1];
        fb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        fb.layer.cornerRadius = 4;
        objc_setAssociatedObject(fb, "mtfake_ts", d[1], OBJC_ASSOCIATION_RETAIN);
        [fb addTarget:self action:@selector(onFestivalShortcut:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:fb];
    }
    y += 64;

    // 自定义 timestamp 输入
    UILabel *tsLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 16, 14)];
    tsLbl.text = @"自定义时间戳 (Unix epoch 秒, 例: 1391126400)";
    tsLbl.font = [UIFont systemFontOfSize:10];
    tsLbl.textColor = [UIColor darkGrayColor];
    [scroll addSubview:tsLbl];
    UITextField *tsTf = [[UITextField alloc] initWithFrame:CGRectMake(8, y + 14, w - 16, 24)];
    tsTf.borderStyle = UITextBorderStyleRoundedRect;
    tsTf.font = [UIFont systemFontOfSize:12];
    tsTf.placeholder = @"留空=不改";
    tsTf.keyboardType = UIKeyboardTypeNumberPad;
    tsTf.delegate = self;
    NSString *curTs = [MTSettings() objectForKey:kKeyFakeTime];
    if (curTs.length) tsTf.text = curTs;
    objc_setAssociatedObject(tsTf, "mtkey_str", kKeyFakeTime, OBJC_ASSOCIATION_RETAIN);
    [tsTf addTarget:self action:@selector(onTextStr:) forControlEvents:UIControlEventEditingChanged];
    [scroll addSubview:tsTf];
    y += 42;

    // ============================================================
    // v13 Section D: 🐦 隐藏 NPC 召唤
    // ============================================================
    UILabel *secD = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 16, 18)];
    secD.text = @"--- 🐦 隐藏 NPC 召唤 ---";
    secD.font = [UIFont boldSystemFontOfSize:11];
    secD.textColor = [UIColor colorWithRed:0.4 green:0.5 blue:0.3 alpha:1];
    secD.textAlignment = NSTextAlignmentCenter;
    [scroll addSubview:secD];
    y += 22;

    NSArray *npcs = @[
        @[@"💧 水塔",          @"WaterTower"],
        @[@"🦅 乌鸦祭司",      @"CrowPriest"],
        @[@"🐚 超级贝壳树",    @"SuperShellTree"],
        @[@"🎄 圣诞树",        @"ChrismasTreeView"],
        @[@"💎 免费贝壳墙",     @"ShowFreeShellsLayer"],
        @[@"🎉 圣诞主活动",     @"XmasMainLayer"],
        @[@"🥚 彩蛋主面板",     @"EasterEggMainLayer"],
        @[@"🌎 村庄菜单层",     @"VillageMenuLayer"],
        @[@"🎂 周年纪念",      @"AnniversaryMainLayer"],
        @[@"🍂 秋季活动",      @"AutumnMainLayer"],
        @[@"🎃 万圣节主活动",   @"HalloweenMainLayer"],
        @[@"🌸 Naram 春活",    @"NaramSpringMainLayer"],
        @[@"🛒 新版商店",       @"NewStyleStoreMainLayer"],
        @[@"💰 促销主层",       @"PromoteSalesMainLayer"],
        @[@"📋 广告墙板",       @"ShowAdwallBoardLayer"],
        @[@"👥 更多好友",       @"ShowMoreFriendsLayer"],
        @[@"📜 规则层",         @"ShowRuleLayer"],
        @[@"📜 活动规则层",     @"ShowActivityRuleLayer"],
    ];
    for (int i = 0; i < (int)npcs.count; i++) {
        NSArray *d = npcs[i];
        CGFloat nx = 8 + (i % 2) * (rsBtnW + 8);
        CGFloat ny = y + (i / 2) * 32;
        UIButton *nb = [UIButton buttonWithType:UIButtonTypeCustom];
        nb.frame = CGRectMake(nx, ny, rsBtnW, 28);
        [nb setTitle:d[0] forState:UIControlStateNormal];
        [nb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        nb.backgroundColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.4 alpha:1];
        nb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        nb.layer.cornerRadius = 4;
        objc_setAssociatedObject(nb, "mtsummon_class", d[1], OBJC_ASSOCIATION_RETAIN);
        [nb addTarget:self action:@selector(onDevPanelSummon:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:nb];
    }
    y += ((int)npcs.count + 1) / 2 * 32;


    // === 召唤未上线联名活动 ===
    UILabel *sepLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, y, w - 16, 18)];
    sepLbl.text = @"--- 召唤未上线联名活动(服务器停服了的) ---";
    sepLbl.font = [UIFont boldSystemFontOfSize:11];
    sepLbl.textColor = [UIColor colorWithRed:0.6 green:0.3 blue:0 alpha:1];
    sepLbl.textAlignment = NSTextAlignmentCenter;
    [scroll addSubview:sepLbl];
    y += 22;

    NSArray *summons = @[
        @[@"爱丽丝梦游", @"Activity_Alice_MainLayer"],
        @[@"史莱克",      @"Activity_Shrek_BasePopLayer"],
        @[@"龙猫",        @"Activity_Totoro_BasePopLayer"],
        @[@"冰激凌",      @"Activity_IceCream_BasePopLayer"],
        @[@"火焰战争",    @"Activity_FlameWars_MainLayer"],
        @[@"加勒比黄金岛", @"CaribbeanMainLayer"],
        @[@"海底寻宝",    @"SeabedSeekingTreasureMainLayer"],
        @[@"环游世界",    @"AroundTheWorldMainLayer"],
        @[@"春天的诗",    @"SpringPoemMainLayer"],
        @[@"放风筝",      @"FlyKiteMainLayer"],
        @[@"清明青团",    @"GreenRiceBallMainLayer"],
        @[@"开宝箱",      @"OpenTreasureChestMainLayer"],
        @[@"世界杯竞猜",  @"GuessWorldCupMainLayer"],
        @[@"冰夏",        @"IceSummerMainLayer"],
    ];

    CGFloat sumBtnW = (w - 16 - 8) / 2;  // 2 列
    CGFloat sumBtnH = 28;
    int idx = 0;
    for (NSArray *def in summons) {
        CGFloat sx = 8 + (idx % 2) * (sumBtnW + 8);
        CGFloat sy = y + (idx / 2) * (sumBtnH + 4);
        UIButton *sb = [UIButton buttonWithType:UIButtonTypeCustom];
        sb.frame = CGRectMake(sx, sy, sumBtnW, sumBtnH);
        [sb setTitle:def[0] forState:UIControlStateNormal];
        [sb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        sb.backgroundColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.7 alpha:0.9];
        sb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        sb.layer.cornerRadius = 4;
        objc_setAssociatedObject(sb, "mtsummon_class", def[1], OBJC_ASSOCIATION_RETAIN);
        [sb addTarget:self action:@selector(onDevPanelSummon:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:sb];
        idx++;
    }
    y += ((idx + 1) / 2) * (sumBtnH + 4);

    // (丝尔特按钮已移到主菜单内容区,这里不再放)

    scroll.contentSize = CGSizeMake(w, y + 8);
    MTApplyScrollViewFix(scroll);
}

// 在主菜单 gScroll 内绘制丝尔特 demo 庄园专区 + 隐藏功能按钮
- (void)addXiaoTuLvSectionAtY:(CGFloat *)y colX:(CGFloat)cx colW:(CGFloat)cw {
    // 顶部分隔线
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(cx, *y + 4, cw, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
    [gScroll addSubview:sep];
    *y += 8;

    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(cx, *y, cw, 18)];
    title.text = @"🏠 丝尔特(xiaotulv) Demo 庄园";
    title.font = [UIFont boldSystemFontOfSize:12];
    title.textColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:1.0];
    title.textAlignment = NSTextAlignmentCenter;
    [gScroll addSubview:title];
    *y += 22;

    // 第一行:进入参观(春季) + 加载冬季 demo
    CGFloat halfW = (cw - 8) / 2;
    UIButton *enterBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    enterBtn.frame = CGRectMake(cx, *y, halfW, 32);
    [enterBtn setTitle:@"进入参观(春季)" forState:UIControlStateNormal];
    [enterBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    enterBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.5 alpha:1.0];
    enterBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    enterBtn.layer.cornerRadius = 5;
    [enterBtn addTarget:self action:@selector(onEnterXiaoTuLv) forControlEvents:UIControlEventTouchUpInside];
    [gScroll addSubview:enterBtn];

    UIButton *winterBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    winterBtn.frame = CGRectMake(cx + halfW + 8, *y, halfW, 32);
    [winterBtn setTitle:@"❄️ 冬季 Demo" forState:UIControlStateNormal];
    [winterBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    winterBtn.backgroundColor = [UIColor colorWithRed:0.4 green:0.5 blue:0.7 alpha:1.0];
    winterBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    winterBtn.layer.cornerRadius = 5;
    [winterBtn addTarget:self action:@selector(onEnterXiaoTuLvWinter) forControlEvents:UIControlEventTouchUpInside];
    [gScroll addSubview:winterBtn];
    *y += 36;

    // 第二行:克隆覆盖(全宽危险红)
    UIButton *cloneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cloneBtn.frame = CGRectMake(cx, *y, cw, 32);
    [cloneBtn setTitle:@"⚠️ 克隆 Demo 到我的存档(不可逆)" forState:UIControlStateNormal];
    [cloneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cloneBtn.backgroundColor = [UIColor colorWithRed:0.85 green:0.3 blue:0.2 alpha:1.0];
    cloneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    cloneBtn.layer.cornerRadius = 5;
    [cloneBtn addTarget:self action:@selector(onCloneXiaoTuLv) forControlEvents:UIControlEventTouchUpInside];
    [gScroll addSubview:cloneBtn];
    *y += 38;

    // === 隐藏开发者工具 section ===
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(cx, *y + 4, cw, 1)];
    sep2.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
    [gScroll addSubview:sep2];
    *y += 8;

    UILabel *devTitle = [[UILabel alloc] initWithFrame:CGRectMake(cx, *y, cw, 18)];
    devTitle.text = @"🔧 程序员私货 / 一键操作";
    devTitle.font = [UIFont boldSystemFontOfSize:12];
    devTitle.textColor = [UIColor colorWithRed:0.6 green:0.3 blue:0.6 alpha:1.0];
    devTitle.textAlignment = NSTextAlignmentCenter;
    [gScroll addSubview:devTitle];
    *y += 22;

    // 全成就解锁开关 + 全物品解锁开关
    [self addSwitchAtY:y title:@"全部成就解锁(检查通过)" key:kKeyAllAchieve defaultOn:NO colX:cx colW:cw];
    [self addSwitchAtY:y title:@"全部物品视为已解锁"     key:kKeyAllUnlock  defaultOn:NO colX:cx colW:cw];

    // myfuctiion + reset achievement (一行 2 个)
    UIButton *myFnBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    myFnBtn.frame = CGRectMake(cx, *y, halfW, 32);
    [myFnBtn setTitle:@"调用 myfuctiion" forState:UIControlStateNormal];
    [myFnBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    myFnBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.7 alpha:1.0];
    myFnBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    myFnBtn.layer.cornerRadius = 5;
    [myFnBtn addTarget:self action:@selector(onCallMyFuctiion) forControlEvents:UIControlEventTouchUpInside];
    [gScroll addSubview:myFnBtn];

    UIButton *resetAchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetAchBtn.frame = CGRectMake(cx + halfW + 8, *y, halfW, 32);
    [resetAchBtn setTitle:@"重置成就数据" forState:UIControlStateNormal];
    [resetAchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetAchBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.4 blue:0.3 alpha:1.0];
    resetAchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    resetAchBtn.layer.cornerRadius = 5;
    [resetAchBtn addTarget:self action:@selector(onResetAchievements) forControlEvents:UIControlEventTouchUpInside];
    [gScroll addSubview:resetAchBtn];
    *y += 36;

    // v21 审查停用: 一键真解锁(unlockItem: 未验证 + 破坏性写档), 改用「全物品解锁」开关
#if 0
    UIButton *unlockBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    unlockBtn.frame = CGRectMake(cx, *y, cw, 32);
    [unlockBtn setTitle:@"🔓 一键真解锁所有商店物品(写存档)" forState:UIControlStateNormal];
    [unlockBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    unlockBtn.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.4 alpha:1.0];
    unlockBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    unlockBtn.layer.cornerRadius = 5;
    [unlockBtn addTarget:self action:@selector(onUnlockAllItems) forControlEvents:UIControlEventTouchUpInside];
    [gScroll addSubview:unlockBtn];
    *y += 38;
#endif

    // v15: testAnimation 按钮(MainMenu 上的另一个测试方法,反汇编显示是 0.5x 缩放动画)
    UIButton *testAnimBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    testAnimBtn.frame = CGRectMake(cx, *y, cw, 32);
    [testAnimBtn setTitle:@"🎬 调用 MainMenu.testAnimation" forState:UIControlStateNormal];
    [testAnimBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    testAnimBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.4 alpha:1.0];
    testAnimBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    testAnimBtn.layer.cornerRadius = 5;
    [testAnimBtn addTarget:self action:@selector(onCallTestAnimation) forControlEvents:UIControlEventTouchUpInside];
    [gScroll addSubview:testAnimBtn];
    *y += 38;

    // === Mini 游戏启动器 section ===
    UIView *sep3 = [[UIView alloc] initWithFrame:CGRectMake(cx, *y + 4, cw, 1)];
    sep3.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
    [gScroll addSubview:sep3];
    *y += 8;

    UILabel *miniTitle = [[UILabel alloc] initWithFrame:CGRectMake(cx, *y, cw, 18)];
    miniTitle.text = @"🎮 Mini 游戏直接启动器";
    miniTitle.font = [UIFont boldSystemFontOfSize:12];
    miniTitle.textColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.6 alpha:1.0];
    miniTitle.textAlignment = NSTextAlignmentCenter;
    [gScroll addSubview:miniTitle];
    *y += 22;

    // v21: 采用 molecheats 已验证的 gameId→游戏 映射 (startMiniGame:playType:... 的 gameId 1..5)
    NSArray *minigames = @[
        @[@"🍉 切水果 (1)", @1],
        @[@"🐛 拍虫子 (2)", @2],
        @[@"⛏️ 挖矿石 (3)", @3],
        @[@"🔨 敲木桩 (4)", @4],
        @[@"🐟 钓鱼 (5)",   @5],
    ];
    for (int i = 0; i < (int)minigames.count; i++) {
        NSArray *g = minigames[i];
        CGFloat bx = cx + (i % 2) * (halfW + 8);
        CGFloat by = *y + (i / 2) * 36;
        UIButton *gb = [UIButton buttonWithType:UIButtonTypeCustom];
        gb.frame = CGRectMake(bx, by, halfW, 32);
        [gb setTitle:g[0] forState:UIControlStateNormal];
        [gb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        gb.backgroundColor = [UIColor colorWithRed:0.3 green:0.55 blue:0.7 alpha:1.0];
        gb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        gb.layer.cornerRadius = 5;
        objc_setAssociatedObject(gb, "mtgameid", g[1], OBJC_ASSOCIATION_RETAIN);
        [gb addTarget:self action:@selector(onLaunchMiniGame:) forControlEvents:UIControlEventTouchUpInside];
        [gScroll addSubview:gb];
    }
    *y += 36 * 3;  // 3 行
}

- (void)onEnterXiaoTuLv {
    [self closeMenu];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // 详细诊断
        id gd  = MTGameData();
        id ngm = MTNewGameManager();
        id gm  = MTGameManager();

        if (!gd) {
            [self showToast:@"❌ GameData 实例未找到 (启动时未 init?)"];
            return;
        }
        BOOL load = MTLoadXiaoTuLvIntoMemory();
        if (!load) {
            [self showToast:@"❌ loadMapdataFromResource: 失败"];
            return;
        }
        BOOL reload = MTReloadCurrentMap();
        if (reload) {
            [self showToast:@"✅ 已加载丝尔特,场景已刷新"];
        } else if (ngm || gm) {
            [self showToast:@"⚠️ 已加载,但场景刷新方法没找到 — 重启游戏看效果"];
        } else {
            [self showToast:@"⚠️ 已加载,GameManager 未初始化 — 重启游戏"];
        }
    });
}

- (void)onCloneXiaoTuLv {
    // 二次确认
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"⚠️ 危险操作"
        message:@"将把丝尔特(xiaotulv) demo 庄园数据**覆盖**你的玩家存档,此操作不可逆!\n\n建议先 SSH 到设备备份 GameData 存档文件再操作。\n\n确定继续吗?"
        delegate:self
        cancelButtonTitle:@"取消"
        otherButtonTitles:@"确认覆盖", nil];
    alert.tag = 88001;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)idx {
    if (alertView.tag == 88001 && idx == 1) {
        id gd = MTGameData();
        if (!gd) {
            [self showToast:@"❌ GameData 实例未找到"];
            return;
        }
        BOOL ok = MTOverwriteSaveWithXiaoTuLv();
        [self showToast:ok ? @"✅ 已克隆并持久化,重启游戏" : @"❌ loadMap/loadUserInfo 失败"];
    } else if (alertView.tag == 88002 && idx == 1) {
        // v14: 整库重置
        int r = MTResetByName(@"resetUserGameData");
        [self showToast:r == 0 ? @"✅ 已 resetUserGameData(重启游戏)" : @"❌ GameData/方法找不到"];
    }
}

// 加载冬季版丝尔特
- (void)onEnterXiaoTuLvWinter {
    [self closeMenu];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!MTGameData()) { [self showToast:@"❌ GameData 实例未找到"]; return; }
        BOOL ok = MTLoadXiaoTuLvWinterIntoMemory();
        if (!ok) { [self showToast:@"❌ 冬季资源加载失败"]; return; }
        BOOL r = MTReloadCurrentMap();
        [self showToast:r ? @"❄️ 已加载冬季丝尔特" : @"⚠️ 已加载,需重启游戏看效果"];
    });
}

// 调用程序员私货 myfuctiion
- (void)onCallMyFuctiion {
    [self closeMenu];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL ok = MTCallMainMenuMethod(@"myfuctiion");
        [self showToast:ok ? @"🔮 已调用 MainMenu.myfuctiion" : @"❌ MainMenu 实例 / 方法找不到"];
    });
}

// 调用 MainMenu.testAnimation(反汇编显示是 0.5x 缩放动画)
- (void)onCallTestAnimation {
    [self closeMenu];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL ok = MTCallMainMenuMethod(@"testAnimation");
        [self showToast:ok ? @"🎬 已调用 MainMenu.testAnimation" : @"❌ MainMenu 实例 / 方法找不到"];
    });
}

// 重置全部成就数据
- (void)onResetAchievements {
    id ac = MTAchievementControl();
    if (!ac) { [self showToast:@"❌ AchievementControl 单例找不到"]; return; }
    SEL s = NSSelectorFromString(@"resetAllAchievementData");
    if ([ac respondsToSelector:s]) {
        ((void(*)(id,SEL))objc_msgSend)(ac, s);
        [self showToast:@"✅ 成就数据已重置"];
    } else {
        [self showToast:@"❌ resetAllAchievementData 方法不存在"];
    }
}

// 一键真解锁所有商店物品 —— v21 审查停用(unlockItem: 未验证 + 破坏性), 改用「全物品解锁」开关
#if 0
- (void)onUnlockAllItems {
    int n = MTUnlockAllItems();
    if (n > 0) {
        [self showToast:[NSString stringWithFormat:@"✅ 已解锁 %d 个物品 + 已存盘", n]];
    } else if (n == -1) {
        [self showToast:@"❌ GameData/WrapperManager 实例没找到"];
    } else if (n == -2 || n == -3) {
        [self showToast:@"❌ shopItems 字典还没加载(等下游戏初始化完再试)"];
    } else {
        [self showToast:[NSString stringWithFormat:@"❌ 失败 (code %d)", n]];
    }
}
#endif

// 启动指定 ID 的 mini 游戏
- (void)onLaunchMiniGame:(UIButton *)b {
    NSNumber *gid = objc_getAssociatedObject(b, "mtgameid");
    if (!gid) return;
    [self closeMenu];
    int gameId = gid.intValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL ok = MTStartMiniGame(gameId);
        [self showToast:ok ? [NSString stringWithFormat:@"🎮 已启动 gameId=%d", gameId]
                            : @"❌ MiniGameManager 不存在或方法找不到"];
    });
}

- (void)onDevPanelSummon:(UIButton *)b {
    NSString *cls = objc_getAssociatedObject(b, "mtsummon_class");
    if (!cls) return;
    if (!NSClassFromString(cls)) {
        [self showToast:[NSString stringWithFormat:@"类 %@ 不存在", cls]];
        return;
    }
    [self closeDevPanel];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MTSummonActivityLayer(cls);
        [self showToast:[NSString stringWithFormat:@"已召唤: %@", cls]];
    });
}

// v13 新增 handlers
- (void)onApplyUserInfoOverrides {
    int n = MTApplyUserInfoOverrides();
    if (n > 0) {
        [self showToast:[NSString stringWithFormat:@"✅ 已应用 %d 项玩家数据修改", n]];
    } else if (n == -1) {
        [self showToast:@"❌ UserInfoData 实例没找到"];
    } else {
        [self showToast:@"⚠️ 没有要应用的修改 (输入框都是 0)"];
    }
}

- (void)onDevPanelReset:(UIButton *)b {
    NSString *selName = objc_getAssociatedObject(b, "mtreset_sel");
    if (!selName) return;
    int r = MTResetByName(selName);
    if (r == 0) {
        [self showToast:[NSString stringWithFormat:@"✅ 已调用 %@", selName]];
    } else if (r == -1) {
        [self showToast:@"❌ GameData 实例没找到"];
    } else {
        [self showToast:[NSString stringWithFormat:@"❌ %@ 方法不存在", selName]];
    }
}

- (void)onFestivalShortcut:(UIButton *)b {
    NSNumber *ts = objc_getAssociatedObject(b, "mtfake_ts");
    if (!ts) return;
    NSString *str = [NSString stringWithFormat:@"%@", ts];
    MT_SET(kKeyFakeTime, str);
    MT_SET(kKeyTimeMagic, @YES);
    [self showToast:[NSString stringWithFormat:@"⏰ 时间已设为 %@ (开关已开)", b.currentTitle]];
}

// 字符串型输入框(用于 fake timestamp 等)
- (void)onTextStr:(UITextField *)tf {
    NSString *k = objc_getAssociatedObject(tf, "mtkey_str");
    if (!k) return;
    MT_SET(k, tf.text ?: @"");
}

// v14: 应用奖励券数量
- (void)onApplyTickets {
    int n = MT_INT(kKeyTickets, 0);
    if (n <= 0) { [self showToast:@"⚠️ 请先输入奖励券数量"]; return; }
    int r = MTSetRewardTickets(n);
    if (r == 0) {
        [self showToast:[NSString stringWithFormat:@"✅ 奖励券已设为 %d", n]];
    } else if (r == -1) {
        [self showToast:@"❌ GameData 实例没找到"];
    } else {
        [self showToast:@"❌ setRewardTickets: 方法不存在"];
    }
}

// v14: 调 GameManager 上的 void 方法
- (void)onDevPanelGmCall:(UIButton *)b {
    NSString *selName = objc_getAssociatedObject(b, "mtgm_sel");
    if (!selName) return;
    int r = MTGameManagerCallVoid(selName);
    if (r == 0) {
        [self showToast:[NSString stringWithFormat:@"✅ 已调用 GameManager.%@", selName]];
    } else if (r == -1) {
        [self showToast:@"❌ GameManager 实例没找到"];
    } else {
        [self showToast:[NSString stringWithFormat:@"❌ %@ 方法不存在", selName]];
    }
}

// v14: 危险按钮 — 整库重置
- (void)onResetAllUserData {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"⚠️ 整库重置游戏数据"
        message:@"将调用 [GameData resetUserGameData] 清空所有玩家进度!\n\n金币/等级/物品/任务/成就 全部归零,**不可逆**。\n\n建议先 SSH 备份存档。"
        delegate:self
        cancelButtonTitle:@"取消"
        otherButtonTitles:@"确认重置", nil];
    alert.tag = 88002;
    [alert show];
}

- (void)onDevPanelButtonTapped:(UIButton *)b {
    NSString *selName = objc_getAssociatedObject(b, "mtsel");
    NSNumber *count = objc_getAssociatedObject(b, "mtcount");
    if (!selName) return;
    int n = count.intValue;
    BOOL isMinus = [b.currentTitle hasPrefix:@"-"];
    MTCallTestLayer(selName, n);
    [self showToast:[NSString stringWithFormat:@"已调用 %@ × %d 次%@",
                     selName, n, isMinus ? @" (减)" : @" (加)"]];
}

- (void)onDevPanelBuildValuePlus {
    Class C = NSClassFromString(@"NewSceneTestLayer");
    if (!C) { [self showToast:@"NewSceneTestLayer 不存在"]; return; }
    static id ghost = nil;
    if (!ghost) ghost = ((id(*)(id,SEL))objc_msgSend)([C alloc], @selector(init));
    SEL s = NSSelectorFromString(@"onButtonbuildValuePlus:");
    if ([ghost respondsToSelector:s]) {
        ((void(*)(id,SEL,id))objc_msgSend)(ghost, s, nil);
        [self showToast:@"建筑值 +1"];
    }
}

- (void)onDevPanelBgTap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:gDevPanelOverlay];
    if (!CGRectContainsPoint(gDevPanelCard.frame, p)) [self closeDevPanel];
}

- (void)closeDevPanel {
    if (gDevPanelOverlay) { [gDevPanelOverlay removeFromSuperview]; gDevPanelOverlay = nil; }
    gDevPanelCard = nil;
}

- (void)onBgTap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:gOverlay];
    if (!CGRectContainsPoint(gMenuView.frame, p)) [self closeMenu];
}

- (void)closeMenu {
    if (gRefreshTimer) { [gRefreshTimer invalidate]; gRefreshTimer = nil; }
    if (gMenuView) [gMenuView endEditing:YES];
    if (gOverlay) { [gOverlay removeFromSuperview]; gOverlay = nil; }
    gMenuView = nil;
    gScroll = nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

@end


// ============================================================================
//                   7) UIWindow 钩子 - 注入悬浮按钮
// ============================================================================
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[MTFloatingMenu shared] attach];
        });
    });
}

%end


// ============================================================================
//                   ctor: 加载标记 + 调试日志
// ============================================================================
%ctor {
    @autoreleasepool {
        // E) NSLog 重定向到 sandbox/Documents/moletweak_nslog.txt
        if (MT_BOOL(kKeyLogToFile, NO)) {
            NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (docs.count > 0) {
                NSString *logPath = [[docs firstObject] stringByAppendingPathComponent:@"moletweak_nslog.txt"];
                // freopen stderr → 文件,NSLog 内部写 stderr 也会被捕获
                freopen([logPath UTF8String], "a+", stderr);
                NSLog(@"=== MoleTweak NSLog redirect started at %@ ===", [NSDate date]);
            }
        }

        // 写到 app 沙盒内的 tmp 目录(任何 iOS 应用都可写)
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        NSString *content = [NSString stringWithFormat:@"loaded at %@\nbundle=%@\n",
                             [NSDate date], bid];
        // 同时尝试多个路径
        [content writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"moletweak_loaded.txt"]
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        // 也尝试写到 Documents
        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docs.count > 0) {
            [content writeToFile:[[docs firstObject] stringByAppendingPathComponent:@"moletweak_loaded.txt"]
                      atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        // 写 /var/mobile/Library
        [content writeToFile:@"/var/mobile/Library/moletweak_loaded.txt"
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        // 系统 /tmp 也试一下
        [content writeToFile:@"/tmp/moletweak_loaded.txt"
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[MoleTweak] dylib loaded into %@", bid);
    }
}
