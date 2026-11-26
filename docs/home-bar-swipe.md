# 禁用横条左右滑动切换 App

## 设置与边界

- 位置：SpringTwelve → 禁用和隐藏 → **禁用横条左右滑动切换 App**。
- 独立键：`disableBottomHomeBarSwipe`，域 `com.haoge.springtwelve`，默认 **OFF**。
- 与 `hideHomeBar`（隐藏 Home Bar）完全独立：隐藏横条不会自动禁用手势，禁用本手势不会自动隐藏横条。
- 不新增配置读取器、持久化默认值或通知观察者；只读现有 `HaogeSpringTwelveOn` 配置快照，沿用已有设置更新机制。

## Hook 语义

实现位于 `Hooks/HaogeSpringTwelveHomeBarSwipe.xm`，依据用户提供的 `DisableBottomHomeBarSwipe.xm`。仅迁移目标 Hook 的行为，不迁移附件中的旧配置域和加载适配器。

目标为 `SBHomeGestureFinalDestinationSwitcherModifier` 的实例方法 `-currentFinalDestination`。每次调用首先以 `NSInteger` 接收一次且仅一次 `%orig`，然后读取快照：

| 开关 | 原始返回值 | 最终返回值 |
| --- | --- | --- |
| OFF | 任意有符号 64 位值 | 原值 |
| ON | `1` 或 `2` | `0` |
| ON | 其他任意有符号 64 位值 | 原值 |

不先缩窄为 `int`、`BOOL` 或无符号值；例如 `0x100000001`、`0x100000002` 不得被误当成 `1`、`2`。目标方法原有副作用无论开关状态均会执行。

构造器仅允许 bundle ID 为 `com.apple.springboard` 且进程名为 `SpringBoard` 的宿主。注册前验证：

1. 目标类存在。
2. `NSInteger` 与指针均为 64 位。
3. 实例方法存在，运行时参数数目为 `2`（仅 `self`、`_cmd`，无显式参数）。
4. 返回编码严格为有符号整数 `q` 或 `l`，对应本机 `long long` 或 `long` 的宽度必须为 8 字节。
5. 隐式参数编码分别为 `@` 和 `:`。

校验失败直接跳过本模块，不尝试猜测其他选择器。注册**不依赖开关当前值**，因此启动时 OFF 不会阻止后续在已有配置刷新机制下开启；无需为切换此开关额外重装 Hook。

`Makefile` 已使用 `$(wildcard Hooks/*.xm Sources/*.m)`，自动纳入新文件，无须修改。偏好契约现为 Phone/DisableHide/General **5/13/7** 项，共 **25** 个唯一键。

## 已执行验证

- 独立模型从新文件提取实际 ABI guard 和方法体，以宿主 C++ stub 编译执行，并以附件方法体及独立期望值交叉核对。
- ABI 矩阵 **1082** 例：缺失类/方法、正确 `q/l`、错误返回类型、0–5 个参数、错误隐式参数编码。
- 行为矩阵 **20056** 例：开关 OFF/ON、正负 64 位边界、32 位边界、低位为 `1/2` 的大整数、10000 个固定种子的随机 64 位值；验证 `%orig` 恰好一次且先于快照读取、运行时切换后按新快照判断、与附件语义一致。
- Logos 预处理通过；使用真实 iPhoneOS 16.5 SDK、Apple Substrate framework 头文件，以 ARC、blocks、`-Wall -Wextra -Werror` 对 `arm64e-apple-ios15.0` 和 `arm64-apple-ios15.0` 作语法检查通过。
- `python3 scripts/verify-preferences.py` 通过：3 个真实导航链接，5/13/7 个开关，25 个键唯一，cell/default/domain/notification 与契约相符，plist 可解析。
- 仅对本功能涉及文件执行 `git diff --check -- <paths>`，通过。

上述模型/语法检查不等同于真机验证、完整链接或打包验证。未安装插件、未注销设备。私有类或方法 ABI 变化时本功能按设计跳过，不承诺所有 iOS 版本具有相同手势终点枚举。

## 真机验收清单

1. 首次无配置安装：新开关为 OFF，底部左右切换 App 保持系统行为。
2. OFF → ON：配置快照刷新后，底部横条左右切换不再切换 App；ON → OFF 后恢复。
3. 分别组合 `hideHomeBar` 的 OFF/ON，确认两个开关互不联动。
4. 核查上滑回桌面、进入 App 切换器及其他手势的结果；本模块只更改目标方法返回 `1/2` 的路径，不能仅凭静态模型认定真机全部手势已验收。
5. 在非 SpringBoard 宿主（如 MobilePhone）确认不注册本 Hook；缺失目标类或 ABI 不符的系统应安全跳过。
