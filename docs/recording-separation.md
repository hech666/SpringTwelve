# 通话录音并入设置合集

## 集成范围

- 输入源码：用户提供的 `AxsCallRecorder-5.2.0-4-source.zip`（SHA-256 `b97ba7e4ff1cf5a1eac78c40f050fc9844231689696b603d2d51aae16942ab94`）。
- 蜂窝通话双路实时 PCM → 单个 MP3 helper、录音协调、收尾校验、可信文件发布、联系人可读命名、电话内录音列表和媒体回放均来自该版本源码。
- 录音 Hook 编入 `HaogeSpringTwelve.dylib`，不产生第二个注入 dylib；`HaogeCallRecorderRealtime` 是采集/编码所需的独立可执行 helper，设置页面仍由现有 PreferenceBundle 提供。
- 四个录音开关放在「电话设置」，全部默认关闭；录音文件保存在真实路径 `/var/mobile/Documents/CallRecordings`。
- 源码/类/selector/helper 名称采用 Haoge 前缀。包身份为 `com.haoge.springtwelve`；旧 Axs 包列为冲突/替换，防止两套 tweak 同时注入。旧设置仅作为只读迁移来源，第一次保存后写入新域；既有音频文件不移动、不删除、不重命名，旧 `AxsSpringTwelve-` 文件仍可被识别。
- 录音列表可替换个人收藏或语音留言；若对应标签设置为隐藏，隐藏优先。更改标签替换/隐藏选项后需完全退出并重开电话 App。

## 构建与验收边界

此集成尚须经 GitHub Actions 编译及新 deb 静态验包。成功编译和签名检查不等于已在设备上验证自动接通、挂断收尾、双路声音、列表授权或系统路由。实际录音前请取得所有参与者同意。
