# 粘贴提示与自动允许

- 设置键 `allowPasteWithoutPrompt`，偏好域 `com.axs.springtwelve`，默认关闭；使用既有配置快照与刷新通知，不写入默认值。
- 开启后会自动允许粘贴并屏蔽提示，应用可能不经询问读取剪贴板。关闭后各 hook 恢复系统原实现，不撤销已完成授权。
- 原始依据：用户上传 `禁用粘贴.zip` 中的 `Clipboard-PasteTip-Source/PasteTipHooks.xm` 与 Evidence 反汇编/解析结果；归档内 SHA256SUMS 的六项均校验通过。保留 reply(YES) 后 authorizationDidCompleteWithPasteAllowed:YES 的次序，以及 pasted 提示响应值 1，不自行猜测枚举名。
- 主过滤器保留 SpringBoard / MobilePhone，并添加 druid / pasted 可执行文件；本模块仅在 SpringBoard、druid、pasted 安装。仅这三个宿主需要粘贴逻辑，不做全应用注入。
- 安装前检查类、实例/类方法、参数数目与 ABI。SBAlertItem 分支仅匹配 SBUserNotificationAlert 且对象类型 _alertSource 为字符串 pasted，响应方法不兼容则回退原实现。
- dyld 通知只合并投递到主队列；支持后加载类尽力重试，不同步等待或无限轮询。缺类/方法时保留系统行为。
- 首次安装需要相关宿主重新载入插件。仅重启桌面未必刷新已运行的粘贴服务；必要时由用户手动重启用户空间，不在设置开关回调中结束服务。
- Logos + arm64e iOS 16.5 SDK、ARC、Wall/Werror 语法预检通过；最终包及真机需分别验证。真机验收：默认关闭原提示、开启自动允许并隐藏、关闭恢复、新复制内容不被记录、无关系统提示不被拦截。晚加载时序与 daemon 主队列处理属于真机覆盖边界。
