# 电话 App 标签禁用

## 设置及生效方式

- `disablePhoneFavoritesTab`：禁用电话 App 个人收藏标签，默认 `false`。
- `disablePhoneContactsTab`：禁用电话 App 通讯录标签，默认 `false`；不影响独立通讯录 App、联系人数据或拨号盘 T9。
- `disablePhoneVoicemailTab`：禁用电话 App 语音留言标签，默认 `false`。
- 三项独立工作，沿用 `com.haoge.springtwelve` 的不可变配置快照、缺键回退 `NO` 和面板单写入方流程；不持久化默认值。
- 修改任一开关后，请完全结束并重新打开电话 App。没有主动退出、注销、重启设备或调用私有刷新方法。
- 当前设置合集已将独立 5.2.0-4 录音源码合入主注入动态库；录音列表可替换个人收藏或语音留言。对应隐藏开关开启时隐藏优先，不强行恢复系统已移除的标签。
- 最近通话、拨号键盘两个参数始终保留系统原值；三个可隐藏标签的开关关闭时也保留各自系统原值，不强制开启系统原本不显示的标签。

## 原始实现证据

通过 GitHub Contents API 实际读取并 base64 解码原始文件（并非只凭搜索摘要或 URL 推断）：

- API：`https://api.github.com/repos/LacertosusRepo/Open-Source-Tweaks/contents/PhoneTabsCustomizer/Tweak.x`
- 原始文件：`https://github.com/LacertosusRepo/Open-Source-Tweaks/blob/master/PhoneTabsCustomizer/Tweak.x`
- 原始源码明确 hook `PhoneTabBarController` 的 `-showFavoritesTab:recentsTab:contactsTab:keypadTab:voicemailTab:`，返回 `void`，五个参数均为 `BOOL`。其用途是将五个标签显示开关传入原方法。
- 原始源码声明 `-viewControllerForTabViewType:(int)` 返回对象，并 hook `-switchToTab:(int)`；当目标标签控制器不存在时，遍历 `1...5`，选择第一个存在控制器的类型。这为本模块的安全切换回退提供依据，没有自行猜测数值到标签的映射。
- 未移植原作者的偏好变更逻辑、`exit(0)` 或 `_updateBottomTabs` 刷新调用。
- SystemBox 1.5-8end 未找到这两个标签的禁用实现；当前依据为上述真实读取的开源实现。未取得目标设备对应 iOS 16 Phone 二进制或类 dump，不能宣称已确认所有 iOS 16 小版本均存在这些方法。

## Hook 边界

新文件：`Hooks/HaogeSpringTwelvePhoneTabs.xm`。

仅在 `com.apple.mobilephone` 内、`PhoneTabBarController` 可解析时尝试安装：基础隐藏组独立校验五 BOOL 配置方法，可选切换回退组另行校验切换与查询方法。

- 配置方法：7 个运行时参数（含 self/_cmd）、返回 `void`、五个一字节 BOOL 参数（允许 `B` / `c` 编码）。
- 切换方法：3 个运行时参数、返回 `void`、一个 `int` 参数。
- 控制器查询：3 个运行时参数、返回对象、一个 `int` 参数。

配置方法签名不符或缺类/方法时，基础隐藏组不安装；可选回退方法缺失或 ABI 不符只阻止回退组，不阻断基础隐藏。三项开关均关闭时，五个配置参数与切换参数严格透传；任一开启时只将对应显示参数置为 `NO`，其他参数保持原值。切换回退仅在任一禁用开关开启且系统请求的标签控制器不存在时执行；未发现可用回退时仍透传原请求。

现有过滤器已经包含 `com.apple.mobilephone`，Makefile 已自动收集 `Hooks/*.xm`，无需扩大注入范围或修改构建清单。

## 验证及真机验收

- 当前设置为电话设置 9 项、禁用隐藏 13 项、常规 8 项，共 30 个开关（原 29 个开关保持，常规新增默认关闭的微信输入法语音免跳转）。
- 新 hook 的 Logos 预处理及共享 `arm64e-modern/clang++`、iPhoneOS 16.5 SDK、`arm64e-apple-ios15.0`、ARC、`-Wall -Werror` 语法预检通过；此检查不等同于完整链接/打包成功。
- 本地完整 Theos 尝试受共享环境限制：`roothide` scheme 不存在；使用 `rootless` 预检完整工程时默认 modules 编译在 SDK pthread 初始化宏处失败。没有因此修改工程的 scheme、SDK、Makefile 或屏蔽警告；由主代理统一完成目标构建。
- 未安装、注入或执行设备操作，iOS 16 真机尚未验证。

待实测：八种开关组合；系统原默认/上次选中个人收藏、通讯录或语音留言时的回退；最近通话和拨号键盘保持原状；独立通讯录 App、联系人数据及 T9 不受影响；关闭后完全重开电话恢复；缺失方法/签名不符时不安装 hook 且不崩溃。本次不改双卡胶囊及其下方删除键的布局。
