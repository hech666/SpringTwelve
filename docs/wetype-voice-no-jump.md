# 微信输入法语音免跳转

## 范围与来源

本模块依据用户提供的 `com.axs.wtvrbglauncher_1.1_iphoneos-arm64.deb`（SHA256 `1f11e53d92eb96d28f9b4b46ac3d8b15545c577383e0b5d88aacc4cd6b43e075`）中的 WeType 分支逆向重构，原 control 标注作者/维护者 Lessica。不是作者原始源码。没有导入原 dylib、图标、设置面板、其他三个键盘或两个仅日志的 setter hook。

用户指定入口：**常规设置 → 微信输入法语音免跳转**。

- 唯一偏好键 `weTypeVoiceNoJump`，沿用合集域 `com.haoge.springtwelve` 及原快照通知，默认关闭。
- 仅 SpringBoard 安装两个 hook。Phone、druid、pasted 虽仍加载合集主库，此模块均不初始化。
- 不增加独立注入库、不注入 WeChat/WeType、不修改录音引擎/路径/播放器、双卡或其他开关。

## 实现

`SBWorkspaceTransitionContext -animationDisabled` 先调用原 getter 一次。开启且双方 entity 都是 SBApplicationSceneEntity 时：

1. 目标为 `com.tencent.wetype`。
2. 目标 activationSettings 编号 5 的 object 是 NSURL。
3. scheme 精确为 `wetype`，host 精确为 `WXKBURL_STARTVOICERECORD`。
4. 命中后保存来源 bundle ID，返回 YES 禁用转场动画。

另保留原插件的路径：目标 `flagForActivationSetting:42` 非零且来源为 WeType 时也返回 YES。42 的私有枚举名未证，不采用旧第三方头中的枚举名。

`SBApplicationSceneView -layoutSubviews` 总是先 orig。来源 scene 命中时，截取该 scene 的整个 window，设置 frame=window.bounds、关闭交互并叠加；后续有应用 ID 的 scene 布局使已有快照在延迟 0.3 秒后以 0.3 秒淡出并移除。未改为 source-only fade 或轮询。

**这是禁用动画和快照遮挡过渡，不是取消 openURL，也不是自行后台启动 API。**

## 集合适配与安全边界

相对独立重构工程的有意改动：只用一个默认 OFF 的合集开关，不读取/写入原 `com.82flex.wtvrbgprefs`，时间固定为原缺省 300/300ms，不增加滑条；采用合集命名空间。

初始化前对两个 hook 与相关私有 getter 检查参数数目、self/selector、返回编码及 setting 整数宽度；接口不符则整个模块不装 hook，其他功能保持原样。该守卫只验证安装时的方法签名，并不证明返回对象满足全部未来版本契约。

UIKit 快照只在主线程进行。开关关闭时清空待处理来源，并立即移除缓存及正在淡出的快照，避免旧状态留到下次开启；主线程集合只跟踪淡出中的视图，完成回调仅清除自身。偏好通知使用已有主队列转发机制，不另注册 Darwin observer、不写默认偏好、不启新线程或定时器。

不要与原 WTVRBGLauncher 或其他同类免跳转功能同时开启，避免重复 hook/截图。未自动修改原插件设置或卸载原插件。

## 验证与验收

- 偏好合同应为电话 9 / 禁用隐藏 13 / 常规 8，共 30 个唯一、默认 OFF 开关。
- 新模块 Logos + 真实 iPhoneOS16.5 SDK arm64e 对象预检；正式整包仅 GitHub Actions 云编译。
- 原录音六个核心源锁与其他旧模块保持基线字节，不把源锁/编译通过说成所有功能真机验收。

安装云构建包后重载 SpringBoard；打开常规设置中的本开关，在微信输入法启用的普通应用输入框点语音，验证画面、语音权限提示、识别回填/取消/连续使用；关闭本开关检查恢复原生切换。新系统或新版微信输入法的 URL/私有 selector 变化仍可能导致该功能不生效。须在用户设备实际测试，不承诺兼容所有版本。
