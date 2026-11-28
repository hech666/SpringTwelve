# 杂七杂八

本集成基于45版 `3aa96fa`，保留微信输入法免跳转与现有精简配置；独立分支发布，不替换 main。

## 设置结构

根页保留电话设置、禁用和隐藏、常规设置，新增「杂七杂八」。四页开关为 9/13/7/3，共32个唯一键。

| 名称 | 偏好键 | 来源 |
| --- | --- | --- |
| iOS27 状态栏 | ios27StatusBarEnabled | iOS27StatusBar reconstruction/arm64e-roothide，daee8112ccca374ff915ecc130a5606932e7fba6 |
| 120hz加120hz 录屏 | motionX120HzRecordingEnabled | MotionX，01c4cd6cbf38bf62238254d835afe3ff4a1a82d0 |
| 微信输入法语音免跳转 | weTypeVoiceNoJump | 45版既有模块，原键和实现保留，只迁移设置入口 |

全部缺省关闭，使用 `com.haoge.springtwelve` 和现有偏好写入/通知实现，不写默认值、不清空既有配置。前两项是二进制语义重建来源，不是原作者逐字源码。状态栏原包 SHA256：c4941a3a6c34854420fa7c7bebcdad2768ede4c7392a052ca15bb5618fedddb7；MotionX 原包 SHA256：9cc469193bf5e8f5b73fbf21ce4f0c2d2036dbccc6e7040f9dd56f1f79c797fb。

## 安装与关闭

前两项仍在进程启动时一次性读取开关；缺键、无效值或读取失败均关闭。47版新增：120开关从关闭切为开启、共享偏好写入成功且回读为开启后，设置面板自动调用既有权限助手，先对 Apple replayd、再对 backboardd 发送 SIGKILL 9，由系统重新拉起。这会中断当前录屏，可能造成黑屏或桌面重载，请先结束录屏与通话、保存工作。不是完整用户空间重启，也不热卸载 Hook；普通应用仍需重开。重复保存开启、页面加载、关闭此开关或修改其他项不触发强制结束。失败显示错误并保留已保存的开关，可手动重启用户空间。

iOS27开关变更、120开关关闭后，仍需手动重启用户空间确保旧 Hook 清除；右上角普通「注销」不保证刷新所有应用。没有安装时强杀脚本、自动完整重启或系统参数持久化写入。独立状态栏/MotionX及其他同类插件应先停用；合集开关不能关闭另一个插件。按用户截图要求移除「杂七杂八」底部大段说明，风险和适用条件保留在本文档。

新助手动作仅接受真实 UID501、有效 UID0 且父进程路径精确为 `/Applications/Preferences.app/Preferences` 的调用；原 `userspace-reboot` 仍只接受 SpringBoard。服务按固定进程名预筛、固定完整路径核对并在发信号前再次核对，不接受任意 PID、路径、命令或信号，不通过 shell/killall，不增添权限项。replayd 可按需尚未运行；前台设置环境下未识别 backboardd 则返回失败。PID路径双核对降低竞态，但不等于内核原子进程身份保证。

微信输入法仍使用原实时偏好机制，只在SpringBoard安装其免跳转hook，功能为转场动画/快照遮挡，不是微信通话录音。

## 单库与宿主隔离

保持一个HaogeSpringTwelve注入库。过滤器为原合集、状态栏和MotionX的并集：UIKit、SpringBoard、MobilePhone、通知UI及druid/pasted/backboardd/replayd等。即使开关关闭，主库和链接依赖也会加载，不能称为零注入或零开销。原共享配置预加载限于原宿主；新增模块不订阅全部配置，不依赖constructor顺序。扩展应用不安装新增模块；druid/pasted不安装前两项；replayd/backboardd只允许MotionX。

前两项都在调用显式安装入口之前门控，每个安装器还单独防重复。MotionX保持文件级MRC；其余合集文件ARC及录音六核心源锁不变。没有额外状态栏/MotionX dylib、原包二进制或独立配置面板。

## 验证限制

状态栏名称不代表兼容iOS27；该移植在iOS16及以上才尝试安装。MotionX请求120Hz显示和系统录屏120fps，不提升屏幕硬件能力；查询值可能被hook，不能拿它证明实际刷新率。原录屏代码只覆盖systemRecording的同步线程上下文及特定采样间隔，没有改分辨率、码率或音频参数。耗电、发热、实际帧率和有效帧时间需设备测量。

CI运行真实共享启动策略的macOS原生测试、四分类/32键契约、微信输入法原验证和录音冻结校验，再编译单arm64e RootHide包并核查签名/权限/entitlements。它不运行iOS私有hook，不证明设备功能等价。普通沙箱应用是否能读取共享偏好、冷启动/内存影响及与通话录音并用均需真机回归；不借用录音授权或扩大录音目录权限解决偏好读取。
