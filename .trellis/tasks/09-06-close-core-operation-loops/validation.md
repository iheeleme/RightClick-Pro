# 核心操作闭环验证

日期：2026-09-06。分支：`task/settings-visual-unify`。本轮代码未提交、未发布，任务保持 `in_progress`，等待完整 XCTest 和已安装 Finder 的实机验收。

## 实现与回归证据

| 链路 | 结果 |
| --- | --- |
| 两项粘贴，第二项缺失 | 首项已移动并出现在 `affectedURLs`；剪切板仅保留失败项；补回文件后重试成功，剪切板清空 |
| 批量复制遇到缺失源项 | 后续有效源项仍完成复制，源文件内容保留 |
| 批量冲突取消 | 已完成项保留，冲突项与未执行项保持待处理，未覆盖已有文件 |
| 动作后的持久化失败 | 历史或剪切板写入失败仍返回真实 `affectedURLs` / `remainingURLs`；剪切板失败会说明再次粘贴前需重新剪切，避免把旧记录视为可直接重试 |
| 动作异常与历史 | 抛出的粘贴失败记录为 `.paste`；Finder 传输失败按捕获的动作类型补写 `OperationRecord` 后发布通知，业务失败不重复记账 |
| XPC 数据兼容 | `ActionResult` 新字段 `remainingURLs` 往返正确，旧 JSON 缺字段时解码为空数组 |
| 5 秒超时、忽略 SIGTERM | 最新探针约 6.3 秒结束，最终状态为 `timedOut` |
| 停止普通后台子进程 | 最终状态 `stopped`，子进程未继续写入完成标记 |
| 遗留运行快照 | 无所有者的 `running` 快照进入 `error` 终态，停止请求不再保留虚假的运行状态 |
| 两份 XPC 服务并存 | 每次运行持有 `<run-id>.lock` 文件锁；同进程另一服务和独立进程观察者均未把活动运行改成错误，之后可读到最终状态 |
| UTF-8 分块 | 中文 stdout 保留 3 字节；独立 stdout/stderr 尾部缓存保留多字节字符，退出时不完整尾部以替换字符输出 |
| 默认目录删除 | 删除 Desktop 的书签、快捷 ID、关联动作后再次 bootstrap，均未复活；旧配置缺默认目录的首次迁移测试仍保留 |
| 未保存命令运行 | 设置页直接给出先保存提示，不打开运行窗口或向 XPC 发送旧配置运行请求 |
| 命令密钥草稿 | 草稿更新、删除、重新加载均不提前修改已保存密钥；成功提交新引用后才删除旧引用 |
| 保存失败重试 | 阻断书签文件写入后，新写入的内存密钥被回收，原配置与原密钥保留；移除阻断后保存成功 |
| 配置第二个文件写入失败 | 书签先写成功、配置路径被目录阻断时，原书签字节被恢复，新密钥回收且草稿保持未保存；解除阻断后同一草稿保存成功 |
| 恢复默认配置 | 损坏的 JSON 可被默认配置修复，已知旧密钥在保存成功后清理 |
| 配置通知 | 主保存、目录自动保存、恢复默认共用持久化入口；扩展收到通知强制后台读取，读取期间的新通知触发再次读取；已完成源码与类型检查 |
| 文档声明 | README 已说明当前版本尚不支持撤销，不再把占位能力列为已实现功能 |

持久化密钥测试使用 `InMemoryCommandSecretStore`，夹具位于临时目录；未修改用户真实 Keychain，未安装扩展或重启 Finder。

## 自动检查

- Core：直接 `swiftc -emit-library -emit-module -enable-testing -swift-version 6 -strict-concurrency=complete -warnings-as-errors` 编译成功。
- AppPreview、FinderExtension、ActionRunnerService：导入重新构建的 Core 模块，Swift 6 严格并发与 warnings-as-errors 类型检查成功。
- `Package.swift`：使用 ManifestAPI 进行不链接的类型检查成功，新增 AppPreview 测试目标语法有效。
- XCTest 源码：`swiftc -frontend -parse` 成功；这仅证明语法通过，不等同于 XCTest 编译或运行通过。
- `bash -n scripts/ci-swift-check.sh scripts/package-macos.sh`、`git diff --check` 通过。
- `DIST_DIR=dist/closure-validation-IcvmPe RIGHTCLICKPRO_PACKAGE_DMG=0 RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=0 bash scripts/package-macos.sh debug` 成功。SwiftPM 失败后使用项目原有直接 swiftc 回退，App、Finder 扩展以及两处 XPC 的 ad-hoc 签名和结构校验通过，最终打包无 Swift 编译警告。
- 本次继续检查先用 `PersistenceProbe.swift` 复现历史失败丢失结果、配置失败残留新书签两项问题，再修复并验证通过。命令终态的资源清理改为 `defer`，确保快照保存失败也释放权限访问和运行锁。
- 最新代码重新完成 Core/App 严格编译、Finder/XPC 严格类型检查，以及四个独立探针。最新超时结果为 6320 ms；已保存密钥、批次重试、双服务锁和 UTF-8 输出回归均通过。
- 最新预览重新运行 `DIST_DIR=dist/closure-followup-5RWhtx RIGHTCLICKPRO_PACKAGE_DMG=0 RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=0 bash scripts/package-macos.sh debug`，直接编译回退、App/Finder/两处 XPC 签名和结构校验均通过。
- 修正任务上下文 JSONL 的 `path` 为 Trellis 实际识别的 `file` 字段，并加入存储规范，避免后续审查缺少规范输入。

临时探针源码及可执行文件：

- `/tmp/rightclickpro-closure-audit.xw6UAp/Audit.swift`，使用最新 Core 重新链接到 `/tmp/righttool-close-check.IcvmPe/core-audit`。
- `/tmp/righttool-close-check.IcvmPe/BoundaryProbe.swift` 与 `boundary-probe`。
- `/tmp/righttool-close-check.IcvmPe/SettingsProbe.swift` 与 `settings-probe`。
- `/tmp/righttool-close-check.IcvmPe/PersistenceProbe.swift` 与 `persistence-probe`。

最新预览产物：`dist/closure-followup-5RWhtx/RightClick Pro-0.0.0-dev-arm64-preview.zip`。上一轮产物仍保留在 `dist/closure-validation-IcvmPe/`。独立构建目录与既有 `dist` 产物分开，未注册其中的 `.appex`。

仓库已补回归用例：`ActionRunnerTests`、`FileOperationServiceTests`、`StorageTests`、`ConfigurationBootstrapperTests`、`CommandTemplateTests`、新增 `RightClickProAppPreviewTests/SettingsViewModelTests`。

## 待验收项

1. `bash scripts/ci-swift-check.sh debug` 再次确认在 SwiftPM manifest 链接阶段失败：`PackageDescription.Package.__allocating_init` arm64 符号缺失。本机 Swift 为 6.3.2，但 ManifestAPI 的私有接口来自 Swift 5.10，声明 `SwiftVersion`；公开接口将其别名到 `SwiftLanguageMode`，动态库也只导出后者对应的构造符，接口与库版本不一致。直接编译测试仍缺少 `XCTest`，未发现可用 Xcode。完整 XCTest 必须在完整工具链或 CI 中运行；本轮未改系统工具链。
2. Finder 通知刷新和 XPC 通信失败的持久化路径已实现并通过类型检查，尚未在已安装扩展中制造真实 XPC 故障、切换权限或完成 UI 验收。内存密钥探针也不等同于真实 Keychain 授权弹窗验收。
3. 本轮未合并、打标签或发布新版。发布交付、Developer ID 签名、公证和完整文件撤销仍按原范围留待后续工作。
