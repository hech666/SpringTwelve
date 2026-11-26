# 双卡拨号按钮：尺寸、原生添加号码代理及镜像布局

## 设备反馈

2026-11-26 视频 `video_70A074BB.mp4`：拨号盘起初为系统单个绿色电话键；切到通讯录再回拨号盘后，出现两个很小的“主号/数据”按钮。视频没有测试发起通话，不能据此判断选卡拨号成功与否。

## 窄修复

- 原实现把原生圆形 callButton 的宽度拆半，再以半宽限制高度；圆键因此被拆成两个小圆点。现在只用原生按钮矩形的中心定位，按用户参考图改成两个宽扁胶囊：固定高 48 pt、圆角 24 pt、间距 18 pt，整体宽度按安全区域宽度的 72% 计算并限制在 240–320 pt，同时保留左右各 12 pt 边距；常见屏宽下每个按钮约 130 pt 宽。每按钮宽度不足 96 pt 或可用高度不足 48 pt 时恢复原生按钮，不硬塞。仅改变形状与尺寸，原有文字、颜色和拨号动作保持不变。
- 在确认的 dialerView 祖先内挂载并转换坐标，避免原生小 wrapper 限制绘制与点击；按安全区域约束边界。每轮布局保持原生按钮隐藏，关闭开关/线路不足时仍移除自有按钮并恢复记录的原生 hidden 状态。
- 补充 viewWillAppear/viewDidAppear、前台恢复及偏好更新时刷新。把双卡的 load 后一次性 0.3 秒刷新移至 didAppear 后，且只在页面仍显示时执行；没有新增轮询。
- 仅在 `captureDualSimDialerEnabled` 开启、两个原生线路身份及全部原生控件/ABI/几何检查均成功时，左胶囊正下方显示 SF Symbols `plus` 图标代理，右胶囊正下方平移原生 `deleteButton`。两者中心到双胶囊中轴的距离相等、垂直中心一致；辅助行位于胶囊下方 8 pt，高度为 `max(44 pt, 原生删除键高度)`，加号点击区 44×44 pt。删除按钮不重建、不换父视图、不缩小，不改原生 targets、手势、hidden、enabled、alpha 或点按/长按处理。不得越过原生 callButton 顶部侵入数字键区；安全区域、删除键原有任一祖先或宿主祖先 bounds 放不下、两辅助控件相交时，移除全部自有控件并恢复原生整排，绝不保留只有一部分可点击的布局。
- 每次系统布局前撤销仍由本插件持有的位移，再取原生新几何；有后续系统 transform 覆写时不盲目恢复旧值。关闭双卡、线路不足、控件或宿主更换及回退时恢复已保存的原生变换。新增经 void/无显式参数 ABI 检查的 showOrHideDeleteButton hook：先调用系统原实现，主队列合并一次补定位，不改系统号码为空时的显隐逻辑，不自调该私有方法。
- 继续使用系统 defaultCallProvider 的前两个 sender identities；保留原有标题与拨号 action。不调整 T9、设置项、其他功能或独立录音插件。

## 原生 Add Number 代理与兼容回退

- 旧版公开 classdump 仅作为名称与历史接口证据：`PHAbstractDialerView.addContactButton` 是 `UIControl`；`PHHandsetDialerLCDView.addContactButton` 是 `UIButton`，并公开 `addContactPressed:` 及两个 `updateAddAndDeleteButtonForText:...`；`DialerController` 有 `_addButtonClicked:`。缓存头文件来自本次上下文给出的 `phone-native-evidence/chashmeetsingh_MobilePhone-Headers_*.h`，**不是目标 iOS 版本的运行时证明**。
- 新路径对 `dialerView`、`callButton`、`lcdView`、`deleteButton`、`addContactButton` getter 检查无显式参数、对象返回 ABI，再检查 UIKit 类型及真实祖先关系；先尝试 dialerView 的添加控件，再尝试 LCD 添加控件。必须确有原生 `TouchUpInside` 事件。代理点击前重新验证当前布局与源控件，然后临时恢复原生控件的可见状态，仅在同步派发期间直接执行原生 UIControl 的 `sendActionsForControlEvents:UIControlEventTouchUpInside`，派发结束立即恢复插件隐藏状态；不调用、替换或猜测 `_addButtonClicked:` / `addContactPressed:` 的方法签名，不移植 target/action，不自行创建联系人。
- 双卡布局成功后，按当前两个 sender identity 的显示名称，在拨号键盘上方扫描原生 UIControl；仅隐藏同时满足“位于键盘上方、包含线路名称、不是 LCD/键盘/删除键/自定义线路键”的控件，并保存其原始 hidden 状态。关闭或布局回退时恢复；不隐藏号码 LCD 或号码标签。
- 两个已知 LCD 更新方法分别要求精确的 `void(id,id,BOOL)` 和 `void(id,id,id,BOOL,BOOL)` 实例方法 ABI（包括 self/_cmd）；只在匹配时 hook。调用系统原实现前恢复原生期望 hidden，返回后重新记录原生结果并同步/隐藏源控件；嵌套调用用深度计数只在最外层捕获，`@finally` 保证配对。控制器原生布局及删除显隐刷新也使用同样的恢复/捕获包装。未观察到的方法、未知 ABI、未被这些 hooks 覆盖的子类 override 均不激活整套自定义 UI；不通过自调私有状态方法猜测显隐。
- 关闭开关、线路不足、宿主/源控件更换、缺少方法/图标/事件或空间不足时移除两个胶囊和加号，恢复原生 callButton hidden、添加控件最近记录的原生 hidden、仍属插件持有的删除键 transform；系统已覆盖的 transform 不回滚。原生 callButton 仍仅在双卡模式成功显示期间隐藏，没有猜测独立的 SIM 选择控件。弱引用 LCD→控制器映射避免循环持有。

## 验证边界

本地执行 Logos 预处理、真实 iPhoneOS 16.5 SDK / arm64e / iOS 15.0 目标的 ARC Objective-C++ 语法检查（`-Wall -Werror`）、`python3 scripts/verify-preferences.py`、`python3 scripts/test-dialer-add-proxy.py`、更新后的外部 `st-delete-layout-check.py` 和 `git diff --check`。不在本地构建/安装 deb，不承诺整包链接或真机行为已验证。专用静态/模型测试覆盖镜像中心、辅助行预留、空间不足回退、原生状态嵌套更新和恢复、代理转发与 ABI 守卫，以及未修改的 T9/拨号动作；这不是 UIKit 运行时测试。

待设备验收：首次进入/切页返回/前后台切换均显示正常尺寸双卡键；输入数字及 `*`/`#` 后加号在左胶囊下、原生删除在右胶囊下且水平对称可点；加号弹出的操作应与系统原生添加按钮完全一致；点按删一位、长按原生删除、删至空的显隐均由系统决定；LCD 号码不消失；两个键各用对应线路；关闭开关恢复原生单键、添加入口及删除键位置。分别检查空号码、已有联系人、建议号码、源控件 disabled/隐藏、尺寸或安全区不足、重建 LCD 和重复开关。

仍不确定：目标系统是否保留这些旧版接口、原生添加行为是否使用 TouchUpInside、是否由未覆盖的其他路径改变 hidden/交互状态、原生祖先是否允许目标位置的 hit-testing、其他 tweak 是否在已安装 hook 之后替换实现；本实现优先不激活自定义 UI而不是猜测。已知状态方法之外的更新不能保证即时视觉同步（在后续布局/刷新及代理点击前重新同步），也不能区分所有外部写入相同 hidden 值的情况。身份列表异步加载超过单次跟进窗口的情况仍需实测，不承诺任意时刻均即时更新。
