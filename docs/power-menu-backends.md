# 电源操作后端与权限边界

长按桌面空白的主菜单与二次确认均由 `UIAlertControllerStyleAlert` 系统弹窗显示，不手动设置宽高或自绘卡片。原透明 overlay 只作为弹窗宿主与上下文授权边界；主菜单选择不会提交后端。两个弹窗之间通过可撤销、最多约三秒的主队列等待，确认旧呈现已结束再呈现下一层；取消确认回到主菜单，取消主菜单关闭窗口。失焦或关闭会同步撤销所有待呈现任务。桌面菜单仅由前台 SpringBoard 内的中文二次确认发出请求：取消、窗口失焦、离开前台或关闭菜单同步撤销一次性令牌。确认 handler 内验证上下文并消耗令牌后提交原后端；普通按钮操作让 UIKit 自动解散弹窗，不依赖或重复调用解散完成回调。没有后台自动执行、任意命令或破坏性 fallback。

设置首页右上角“注销”使用原生导航栏按钮，与返回文字同行。中文系统确认卡确认后，由设置进程直接提交下表“重启桌面”的 FBS/SBS 请求，逐项校验方法签名；不在设置进程执行 `kill(getpid())`，不注册可广播触发的注销通知。不更改设置宿主权限，服务授权取决于目标系统/越狱环境，失败回调或异常显示中文提示；接口存在或请求接受不等于实机注销完成。

| 动作 | 后端 |
|---|---|
| 注销 | 当前 SpringBoard 对自身 `kill(getpid(), SIGTERM)` |
| 强制注销 | 当前 SpringBoard 对自身 `kill(getpid(), SIGKILL)` |
| 重启桌面 | `SBSRelaunchAction actionWithReason:@"RestartRenderServer" options:4 targetURL:nil` → `FBSSystemService sendActions:withResult:` |
| 重启用户空间 | 专用 setuid root `HaogeSpringTwelvePowerHelper userspace-reboot` → `reboot3(0x2000000000000000ULL)` |
| 重启设备 | `FBSSystemService reboot` |
| 关机 | `FBSSystemService shutdown` |

## 原生服务

显式加载系统原始路径下的 SpringBoardServices / FrontBoardServices，逐项检查类、selector、参数数量、返回与参数类型；不依赖固定地址或手动去 PAC。

重启桌面的参数照用 [Cephei HBRespringController](https://github.com/hbang/cephei/blob/main/main/HBRespringController.m) 的实际 `FadeToBlackTransition = 4`，不猜其他 flags。`reboot`/`shutdown` 返回 void，日志只表示请求提交，不保证设备已经执行；没有改用硬件重启或杀 backboardd 的 fallback。

## 用户空间重启工具

ABI/flags 来自 [RootHide Dopamine jbctl](https://github.com/roothide/Dopamine/blob/2.x/BaseBin/jbctl/src/main.m)。只复用其明确的 reboot3 调用，不复用原 MUtool 多用途 helper，也不删除系统状态文件或执行 shell/launchctl 等额外后备动作。

工具只接受固定参数，要求 real uid 501、effective uid 0，核对父进程真实可执行路径为系统 SpringBoard；再次校验父 PID 后才调用唯一动作。提权与身份校验失败立即退出。签名只含 platform/no-sandbox 和 userspace-reboot 两项授权，不给 tweak dylib 虚加 entitlement。

父进程以固定路径、固定参数、白名单环境 spawn；关闭其他继承描述符，标准流接 `/dev/null`，后台等待并回收。10 秒未返回时报告仍在处理、禁止重复提交，继续负责回收，不自动换用更强操作。

包验证要求工具真实现代 arm64e、root:wheel 所有者、setuid 且不可被组/其他用户写入、正确签名权限和所有代码页哈希。RootHide 具体签名/提权策略和最终重启效果仍需用户真机测试；接口存在、编译成功、请求返回均不能冒充实机验收。

自动录音源码、路径、列表及两个原版采集/混音工具相对已验收的 `f583596` 不变。
