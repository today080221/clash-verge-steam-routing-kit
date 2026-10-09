# 变更记录 / Changelog

## 未发布 / Unreleased

### 亮点

- 增加完整 24 组业务订阅的循环回归：公开 v1.5.0 脚本复现 `UnityGlobal → UnityWeb → UnityGlobal`，当前脚本的首次/重复/乱序输入与 Owner 组合均验证所有候选引用无环，公共路由逻辑保持不变。
- 明确旧同步器迁移与当前全局脚本挂载的区别，以及 `main` 新能力尚未进入 v1.7.2 ZIP 的发行落差；固定哈希源采用 `.gitattributes` 保留原字节，避免 Git 自动换行导致下游校验漂移。
- 安装器不再覆盖通用 `Script.js`；独立公共脚本用哈希记录所有权，手工修改会报冲突。
- 退役所有订阅无条件重绑与自动重启，提供显式旧同步器迁移、原文件备份和公共层/Owner 增强组合入口。
- 新增独立的 Claude 隐私工具：Chrome 定向 WebRTC 策略、已验证 Claude 程序路径的 UDP 出站阻止、状态/预览/启用/刷新/回滚。
- 新增六域名 JSON 接口、写前日志、受管理规则指纹、隔离验证与明确打包清单。
- 新增显式自动维护：同一用户登录/每两分钟刷新，部署脚本与任务权限受保护，记录最近执行与异常，回滚先停维护并阻止旧刷新重新启用。
- 新增一次 UAC 的启用与验收入口：真实任务运行、回滚防重启用、恢复启用及受保护结果文件；不将配置验收误称为 Claude 实际 UDP 阻止证据。
- 修复 Windows PowerShell 5.1 中 `File.Replace` 的 null 字符串参数兼容问题，确保状态和失败回执能覆盖保存；新增真实文件、ACL、文件锁失败保留与 Pending 恢复回归。
- 兼容 Windows 将任务登录触发用户保存为账号名的行为：解析 SID 后严格比较，保留原有权限校验与陌生用户拒绝。
- 增加显式 `DesktopAndCli` 范围，将官方 Windows 原生 Claude Code 纳入精确 UDP 规则和自动维护；分别验证签名与产品身份，CLI 未运行时仍从当前用户安装位置发现。旧状态兼容仅桌面范围，已验证 CLI 不再干扰桌面刷新，未知同名程序仍拒绝。范围持久化并支持显式缩回桌面，不操作 Claude UI、登录或模型请求。
- 修复定时 PowerShell 闪窗：任务改为受保护的 GUI 宿主，从进程创建时禁止 worker 控制台窗口；系统编译器本地生成 EXE，源码、二进制与构建记录均校验所有权、权限和哈希。
- 降低无变更维护开销：按工具前缀查询防火墙，状态完全一致时省去重复逐规则回读和状态写回，保留每轮签名、完整指纹、有效策略与碰撞检查；继续每两分钟检查，分别记录墙钟和 CPU 时间。
- 新增 `-MaintenanceOnly`：只升级已有维护部署并验收任务，全程保留已启用范围、规则和 Chrome 策略；本机两个自然周期实测无任务归属可见窗口，无变更轮次约 10.7/11.1 秒，保护状态不变。两套 PowerShell 各 208 项断言通过。

### 说明

普通安装不会启用隐私防护。创建/更新 Clash 增强卡片并选择订阅是显式步骤；旧安装需要先迁移。现有公共路由脚本和默认分组保持不变。本次尚未发布 Release，`VERSION` 保持 `v1.7.2`，不能据此认为已下载的 v1.7.2 资产包含这些改动。本机最终 `DesktopAndCli` 组合范围的两条真实规则、有效策略、维护任务运行、回滚防重启用与最终恢复启用已通过完整验收，既有 Chrome 策略保持不变；结果与边界见交接文档，不将配置成功等同于实际 UDP 阻止或 Pro 登录已验证。

---

### English Summary

Add a complete 24-group subscription regression: the public v1.5.0 script reproduces the UnityGlobal/UnityWeb cycle, while current routing, repeated/reordered inputs and Owner composition remain acyclic across every choice. Public routing behavior is unchanged. Clarify that watcher migration preserves existing global-script bindings and that the v1.7.2 ZIP does not contain the new `main` features. Preserve fixed-hash source bytes through Git attributes so downstream provenance survives clean exports.

Unreleased: preserve existing scripts and bindings; retire background rebinding; add explicit legacy migration and public/owner composition. Add optional scoped Claude privacy controls with previews, ownership-aware refresh/rollback, shared domain data, isolated tests, and explicit packaging. Explicit maintenance uses a protected deployment and same-user elevated two-minute/logon task; rollback disables maintenance before removing protection. A one-UAC entry checks real-task execution and rollback coordination, then restores protection, with a durable receipt and no unsupported UDP-enforcement claim. Public routing defaults remain unchanged. This machine's final `DesktopAndCli` scope passed both rule/effective-policy checks, task execution, rollback, prevention of queued-refresh reactivation, and final re-enablement, with existing Chrome policy unchanged. These results do not establish actual UDP blocking or Pro authentication. See the handoff for evidence and limits. No release has been published; `VERSION` remains `v1.7.2` until an authorized release.

Fix Windows PowerShell 5.1 null-string binding for atomic file replacement so state and failure receipts can be updated. Real filesystem regressions cover destination ACLs, readers and locks, retained failure evidence, retries, and recovery from a pending journal.

Resolve task principal and logon-trigger account names back to SIDs before strict identity comparison, preserving ACL checks and rejection of other or unresolvable users.

Add explicit, persisted `DesktopAndCli` coverage for the official Windows native Claude Code executable, with separate signature/product identity checks and discovery even when it is not running. Legacy state stays desktop-only; verified CLI processes no longer disrupt desktop refresh, while unknown identities still stop it. Users can explicitly return to desktop-only coverage. Discovery never operates Claude UI, logs in, or makes model requests; Node/WSL/VM hosts remain outside this scope.

Fix scheduled PowerShell flashes with a protected GUI host that creates its worker without a console window; compile locally with the verified system compiler and validate source, binary, build-record hashes and permissions. Query only the tool's firewall prefix and skip redundant rule reads/state writes on fully unchanged runs, retaining fresh signature, fingerprint, effective-policy and collision checks at the same two-minute interval. Record wall and worker CPU time separately.

Add `-MaintenanceOnly` to upgrade the owned maintenance deployment without disabling or rolling back existing protection. Two natural cycles on this machine showed no visible windows attributable to the task or its descendants, completed unchanged checks in about 10.7/11.1 seconds, and retained both effective rules and Chrome policy. Both PowerShell versions passed 208 assertions; see the handoff for evidence and measurement limits.
