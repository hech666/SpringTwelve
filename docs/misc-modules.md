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

前两项仅在进程启动时一次性读取开关；缺键、无效值或读取失败均关闭。开启或关闭后，先结束录屏、通话并保存工作，再由用户手动重启用户空间，应用也需重新启动。右上角普通「注销」不保证刷新所有应用、replayd和backboardd。没有热卸载、自动killall、安装时强杀脚本或系统高刷参数持久化写入。独立状态栏/MotionX及其他同类插件应先停用；合集开关不能关闭另一个插件。

微信输入法仍使用原实时偏好机制，只在SpringBoard安装其免跳转hook，功能为转场动画/快照遮挡，不是微信通话录音。

## 单库与宿主隔离

保持一个HaogeSpringTwelve注入库。过滤器为原合集、状态栏和MotionX的并集：UIKit、SpringBoard、MobilePhone、通知UI及druid/pasted/backboardd/replayd等。即使开关关闭，主库和链接依赖也会加载，不能称为零注入或零开销。原共享配置预加载限于原宿主；新增模块不订阅全部配置，不依赖constructor顺序。扩展应用不安装新增模块；druid/pasted不安装前两项；replayd/backboardd只允许MotionX。

前两项都在调用显式安装入口之前门控，每个安装器还单独防重复。MotionX保持文件级MRC；其余合集文件ARC及录音六核心源锁不变。没有额外状态栏/MotionX dylib、原包二进制或独立配置面板。

## 验证限制

状态栏名称不代表兼容iOS27；该移植在iOS16及以上才尝试安装。MotionX请求120Hz显示和系统录屏120fps，不提升屏幕硬件能力；查询值可能被hook，不能拿它证明实际刷新率。原录屏代码只覆盖systemRecording的同步线程上下文及特定采样间隔，没有改分辨率、码率或音频参数。耗电、发热、实际帧率和有效帧时间需设备测量。

CI运行真实共享启动策略的macOS原生测试、四分类/32键契约、微信输入法原验证和录音冻结校验，再编译单arm64e RootHide包并核查签名/权限/entitlements。它不运行iOS私有hook，不证明设备功能等价。普通沙箱应用是否能读取共享偏好、冷启动/内存影响及与通话录音并用均需真机回归；不借用录音授权或扩大录音目录权限解决偏好读取。
