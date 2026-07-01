# MoleTweak — 摩尔庄园 5.5.0 修改器 (越狱真机 Substrate Tweak)

`com.taomee.MoleWorld`(摩尔庄园移动版 5.5.0)的 **MobileSubstrate/Theos tweak**,为**老版本 iOS 越狱设备**打造。游戏 2015 年停运下架,服务器已停;本 tweak 在真机上离线复活并深度修改玩法,是同项目 [`MoleWorld-5.5.0-touchHLE-offline`](https://github.com/moleworld-dev/MoleWorld-5.5.0-touchHLE-offline)(touchHLE 离线移植 + 内置 `molecheats`)的**真机分支**。

- **目标**:`iphone:clang:9.3:6.0`,`armv7`
- **实测设备**:iPad 4 (iPad3,4) · iOS 6.1.3 (10B329) · CydiaSubstrate
- **依赖**:`mobilesubstrate`
- **游戏入口**:在游戏内点右上角悬浮 **「修改」** 按钮弹出菜单

## 与 molecheats 的关系(v21 对齐)

`molecheats`(touchHLE 离线版的内置修改器,`mole_cheats.rs` + `mole_menu.rs`)在**模拟器层**用完全可见的 ObjC 消息派发,重新验证并整理了本 tweak 的作弊面 —— 每个开关对应的 **(类, 选择器) 拦截表都是已验证的**。v21 以 molecheats 为**权威**回填对齐:冲突处一律以 molecheats 为准。

**v21 新增/修正(来自 molecheats 已验证选择器):**

| 开关 | 机制 |
|---|---|
| 工人/房间补满 | `UserInfoData -totalWorkers/-availableWorkers/-totalRooms` → 99 |
| 产出×10(收菜) | `ObjectManager -getXP/GoldSpeedUpObjectMultiple` → 1000 |
| 任务秒完成免费 | `Quest/TimeQuest -shellsNeeded` → 0 |
| 海底寻宝必中稀有 | `SeabedSeekingTreasureMainLayer -generateRandomRewardId` → 31169 |
| 小游戏奖励满 | `FishingGame/MinerGame -getRewardCoin:/-getRewardXp:` → 99999 |
| 全物品解锁(扩展) | `GameData/NewSceneData -getLockType4*` → 0;`MusicHallLayer -checkIsUnlockMusic:`、`AvatarLayer -checkRequiredVipLevel:` → YES |
| 全成就通过 | `AchievementControl/NewSceneAchievement -checkInAlreadyUnlockList:`、`AchievementItems -unlocked:` → YES(**不** hook void `checkAchieve_*`,会崩) |
| 关反作弊(扩展) | `iMoleVillageAppDelegate -showCheatWarningMessage`、`SystemTimeCheck -check/-start` 吞掉;`checkUserinfoMd5:/CheckUserInfoData:` 归入本开关 |
| 强制VIP(扩展) | `UserVIPInfoData -vipLevelWithNewType` 返回字符串 |
| 小游戏启动器 | gameId 映射改用 molecheats 已验证:1=切水果 2=拍虫子 3=挖矿石 4=敲木桩 5=钓鱼 |

## 已有功能(v20 起,均保留)

数值直改(摩尔豆/贝壳/经验/等级/VIP)、金币/经验倍率、作物瞬熟/永不枯萎、建筑瞬完成、全局冷却归零、VIP 强制激活、免费购物、内购直通(StoreKit passthrough)、魔法密码任意过、TestLayer 18 对 ± 直调、隐藏 NPC / 联名活动层召唤、一键任务/签到重置、时间魔法(节日触发)、丝尔特(xiaotulv)demo 庄园加载、黄金岛(加勒比)修复、头像/房间/工人/奖励券直改等。详见 [`docs/MOLECHEATS_MERGE_BLUEPRINT.md`](docs/MOLECHEATS_MERGE_BLUEPRINT.md)。

## 构建

> ⚠️ Theos **不支持带空格的项目路径**。若本仓库 clone 到含空格的目录,请在无空格目录构建(见 Makefile 注释)。

```sh
export THEOS=/path/to/theos
make package        # -> ./packages/com.xiaochoumao.moletweak_*.deb
```

## 安装(真机)

```sh
scp -O packages/com.xiaochoumao.moletweak_*.deb root@<设备IP>:/tmp/mt.deb
ssh root@<设备IP> 'dpkg -i /tmp/mt.deb && killall -9 MoleWorld'
```
> 连接 iOS 6 的 OpenSSH(旧 `ssh-rsa` 主机密钥)需给现代 ssh 客户端加:
> `-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa`

## 路线图(施工中 🚧)

molecheats 完整对齐仍有两块待真机迭代(见 blueprint §2.C / §2.D):

- [ ] **破解字节补丁(6 个)**:`去越狱检测 / 修复占卜 / 节日村进入 / 商城免VIP / 进新岛门 / 跳对象校验` —— 运行时 `vm_protect`+`memcpy`+`sys_icache_invalidate` 打 `__TEXT` 补丁,或对应方法 %hook。
- [ ] **离线可建筑黄金岛(`enable_newscene_island`)**:约 25 处 %hook 的进岛状态机(真机无法读调用方 LR,改 hook 具体 call-site 方法绕过 gameMode 门)。
- [ ] **菜单 5 页 tab 化**:数值 / 召唤 / Mini·任务·重置 / 开关·解锁·成就 / 开发者·调试。

## 许可 / 免责

仅供**离线单机、个人存档、游戏保育与逆向学习**之用。摩尔庄园 © 淘米网络。请勿用于联网作弊或任何商业用途。
