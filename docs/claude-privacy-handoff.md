# Claude 隐私防护与脚本所有权交接

更新日期：2026-10-08。静默维护升级已于 21:19:57（UTC+08:00）完成，协调方与本任务独立读回均为 `Completed / success=true / maintenanceOnly=true`。此次升级全程保留 `DesktopAndCli` 范围、两条有效规则和 Chrome 已有策略；七文件源摘要及自然周期实测见第 10 节。此前 20:04:37 的组合配置完整验收（包含真实回滚、防止旧刷新重启用和最终恢复）保留在第 9 节，19:29:59 桌面验收保留在第 5 节。Chrome 三条策略由协调方在浏览器中确认为 Mandatory / OK。ICE、Claude 实际进程 UDP 阻止及 CLI Pro 登录仍不能从这些回执证明；配置验收不等于流量或账号验收。未发布 Release，`VERSION` 仍为 `v1.7.2`，变化记在 `CHANGELOG.md` 的「未发布」中。

## 1. 稳定公共接口

| 接口 | 契约 |
| --- | --- |
| `Script.js` | 保持原始公共路由脚本不变，入口 `main(config)`；原有 12 个分组、顺序语义与默认出口不变。下游可以继续 vendor。 |
| `config/claude-privacy-domains.json` | JSON 对象，`schemaVersion: 1`，`domainSuffixes` 为无 URL、无 `*` 的后缀数组。消费者忽略不认识的说明字段。 |
| 域名初值 | `anthropic.com`、`claude.ai`、`claude.com`、`claude.app`、`claudeusercontent.com`、`claudemcpcontent.com`。用于网络分流；后缀匹配应覆盖顶级域及其子域。 |
| `compose-routing-script.ps1` | `-OwnerScriptPath <源文件> -OutputPath <新文件>`；公共层在前，Owner 层在后，各自作用域隔离。 |
| `claude-privacy.ps1` / `.bat` | `status` / `audit` / `apply` / `refresh` / `rollback` / `maintenance-enable` / `maintenance-disable`；直接调用 `.ps1` 用 `-Action`，`.bat` 可使用位置参数。变更操作支持 `-WhatIf`。 |
| `enable-claude-privacy.ps1` / `.bat` | 一次同用户 UAC，完成部署、真实维护任务、回滚协调验收，再恢复启用；`-MaintenanceOnly` 仅升级已启用且未漂移的维护部署，全程保留防护；`-WhatIf` 只读。 |
| `-ProtectionScope` | `Desktop` 或显式 `DesktopAndCli`；新状态和旧状态默认仅桌面，省略参数沿用保存的选择。一次启用入口和手动 `apply` 可变更；`status` / `audit` 仅预演，`refresh` 不能自行扩围。 |
| `install-steam-routing.ps1` | 普通安装只交付独立公共文件；`-MigrateLegacy` 显式退役已识别旧同步器。所有订阅绑定由用户在 Clash UI 明确选择。 |
| `sync-clash-verge-steam-script.ps1` | 保留原文件名，改为单次同步独占文件；`-Audit` 只检查所有权哈希。无循环、无重绑、无重启。 |
| `release-files.txt` | 打包的唯一显式文件白名单，包括运行模块、配置、文档和测试。 |

域名来源已核验：[Claude Desktop network access requirements](https://code.claude.com/docs/en/desktop#network-access-requirements)。官方清单同时覆盖应用代码与用户内容 CDN，因此不能机械地把六个后缀全部当成 Chrome 顶层网页策略目标。当前 Chrome 页面集合为 `https://[*.]claude.ai`、`https://[*.]claude.com`、`https://[*.]anthropic.com`；资源域、预览域、嵌入页面不据此宣称覆盖。

`remote-proxy-server` 的接入方式：继续 vendor 原样 `Script.js`，同时 vendor 这里的 JSON 文件；更新时核对两个文件的哈希和 JSON schema。域名维护源只在本仓库。本次没有修改或验证另一个工作区的实际接入结果。

## 2. 安装、迁移与组合

旧实现会覆盖 AppData 下通用 `Script.js`，并在后台将所有 remote 订阅的 `option.script` 改成 `Script`。新实现不解析或重写 `profiles.yaml`，避免把自定义脚本、空绑定、订阅层级或陌生 YAML 结构当成工具包所有。

安装器维护 `profiles/SteamRoutingKit.js` 和 `steam-routing-kit-state.json`。首次遇到同名无所有权文件，即使内容相同也报冲突。后续更新必须与上次哈希一致，更新前备份原文件。更新后的卡片内容需要在 Clash 中明确复制/选择；安装成功本身不等于订阅已挂载公共层。这是此次行为变化，不能继续使用「自动接管所有订阅」的旧说明。

新工具包不会自动部署或启动后台同步器。旧 VBS 文件名保留为兼容提示入口。仓库里的新脚本不会自动替换已经运行的 AppData 旧进程，协调方应先关闭 Clash，再执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-steam-routing.ps1 -MigrateLegacy -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-steam-routing.ps1 -MigrateLegacy
```

迁移校验旧 watcher 的规范化内容哈希与旧 VBS 内容，只停 PowerShell 进程中 `-File` 精确指向目标 watcher 的进程。原 watcher 和启动项改名为唯一 `.disabled` 备份，不删除。未知版本、修改过的启动器或无法读取的运行源需要人工处理，不自动扩大匹配范围。它不恢复历史上丢失的增强内容，也不推断漂移由谁造成。

Owner 增强应维护在自己的私有源文件中：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\compose-routing-script.ps1 -OwnerScriptPath C:\Private\Owner.js -OutputPath C:\Private\Owner.combined.js
```

生成器将两份源代码分别包在函数作用域中，调用公共 `main(config, profileName)` 的结果，再交给 Owner `main(config, profileName)`。公共脚本忽略额外的 `profileName` 参数。Owner 必须同步返回配置对象；返回空值、数组或 Promise 会报错。生成过程中不运行 Owner 代码，输出已存在则拒绝覆盖。将结果放进一张单独的 Clash 脚本增强卡片，并为目标订阅明确选择该卡片。公共层不要在同一链路重复挂载；Owner 修改规则优先级的最终语义由 Owner 负责验证。升级公共源后重新生成新组合文件。

## 3. 隐私工具的所有权与权限

默认 `status` 与 `audit` 只读，普通分流安装不会调用隐私工具。`apply`、`refresh`、`rollback` 与维护开关必须由同一 Windows 用户的管理员 PowerShell 显式执行；不要换管理员账号，否则 HKCU 和 MSIX 发现范围会变。普通命令不自行提权；单独的 `enable-claude-privacy` 入口会请求一次 UAC，核对提权前后的用户 SID 与七文件源摘要（含 GUI 宿主源码），再用隐藏的管理员进程完成已授权部署。工具不开 TUN、不改系统代理、不重启浏览器或 Clash。

Chrome 使用当前用户的 `HKCU\Software\Policies\Google\Chrome\WebRtcIPHandlingUrl`，值类型为 `REG_SZ`，内容为 JSON 对象数组 `{url, handling}`。策略从 Chrome 133 起支持，并按首个匹配项决定行为。新条目放在现有项之前；既有相同目标项不改动、不认领。已有不同处理值、重复 URL、类型错误、无效 JSON、或可能影响现有目标项的前置规则会要求人工处理。前置规则检查刻意保守，可能要求审查实际并不重叠的旧项。来源：[Chromium 策略定义](https://raw.githubusercontent.com/chromium/chromium/main/components/policy/resources/templates/policy_definitions/WebRtc/WebRtcIPHandlingUrl.yaml)。

防火墙仅接受明确的 `Claude.exe` 绝对路径，并验证 Authenticode 为有效的 Anthropic 签名及 Claude 产品信息。桌面路径来自当前用户的 `Claude_pzs8sxrjxfjjc` 已注册包、仍运行的旧版本，或 `-ClaudePath` 显式候选。组合范围还发现当前用户主目录下 `.local\bin\claude.exe`，与是否运行无关；分别要求桌面产品/公司为 `Claude` / `Anthropic`，原生 CLI 为 `Claude Code` / `Anthropic PBC`，不只凭发布者或同名进程接受程序。来源与类型不一致、签名无效或无法检查的同名进程会停止刷新，保留旧规则；仅桌面范围记录并跳过已验证 CLI。不会遍历 WindowsApps 任意 EXE，也不执行发现的程序。规则为 `PersistentStore` 下全配置文件、`Outbound / UDP / Block / 精确 Program`，名称以 `CVSRK-ClaudeUDP-` 开头，包含用户和路径的摘要；Group 为 `ClashVergeSteamRoutingKit.ClaudePrivacy.v1`。不使用 `-Package`、通用 `node.exe` 或全机 UDP 封锁。来源：[New-NetFirewallRule 官方文档](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)。

状态文件位于 `%ProgramData%\ClashVergeSteamRoutingKit-ClaudePrivacy\<用户 SID>\state.json`。目录与文件归 Administrators 所有，只允许 Administrators/SYSTEM 写入，当前用户保留读取权限；拒绝不安全 ACL、跨用户状态及 reparse point。更新先写完整临时文件并设置所有者，再用同目录 Move/Replace 保存，不先删除目标，不忽略 ACL/元数据合并错误。共享的保存路径使用 `[NullString]::Value` 向 .NET `File.Replace` 传递真正的 null 备份路径，避免 Windows PowerShell 5.1 将普通 `$null` 转为非法空路径。替换失败保留原文件与临时证据。依据：[File.Replace](https://learn.microsoft.com/en-us/dotnet/api/system.io.file.replace?view=netframework-4.8.1)、[PowerShell NullString](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.nullstring)。用户级互斥锁避免本工具并发；本机私有日志不应提交到仓库。

每一步先保存所有权，再做变更并回读。防火墙指纹包含规则属性和关联的应用、端口、地址、服务、接口及安全过滤器。所有权前缀相同但没有日志的规则不会被接管。若程序在创建规则后、指纹持久化前中断，则标记需要人工审查，不盲删未知状态。`Failed`、`Conflict` 与 `lastError` 保留可读原因。不要删除状态文件或直接覆盖它来消除报错。

回滚规则：未改动的 Chrome 值恢复原值；有后续编辑时，仅删仍与工具新增内容一致的条目，保留其他域名和被修改条目。防火墙仅删除所有权日志与完整指纹仍吻合的规则。被外部改动的内容保留并报冲突。执行前再次对照快照，发现并发变更即停止；这不等同于与外部注册表/防火墙编辑器共享事务锁。

`refresh` 不作为首次启用或回滚后的自动重启用入口；需先显式 `apply`。范围选择保存在 `state.protectionScope`，旧状态缺失时解释为 `Desktop`；省略参数时沿用选择，刷新不能自行改范围。回滚撤销桌面/CLI 的自有规则并关闭开关，但保留范围供后续显式启用。刷新重新发现版本，先添加新规则，再删已不再被发现的旧规则，仍在运行的旧版本保留。如果新规则创建失败，不移除旧规则。发现不完整则拒绝清理。旧式独立安装若使用 `-ClaudePath`，后续刷新也需传入该路径。

显式 `maintenance-enable` 将五份运行源部署到同一受保护状态目录的 `runtime-<源内容摘要>`：隐私 CLI、Core/Windows/Maintenance 三模块及 `ClaudePrivacy.Host.cs`。使用签名有效的 Windows .NET Framework 系统编译器生成 GUI 子系统的 `ClaudePrivacy.Host.exe`，生成的 EXE 哈希与 `runtime-build.json` 一同受管理员 ACL 保护；维护记录绑定五源和 EXE 共六个文件的哈希，构建记录与所有权记录必须一致，目录只能包含这七个文件。每次验证所有者、ACL、无 reparse point、精确集合、源摘要与生成二进制哈希，已有部署通过完整验证后复用，拒绝原位覆盖或额外配置文件。兼容读取旧四源部署以便按所有权升级。

计划任务直接启动受保护的 GUI 宿主；宿主仅接受固定 `--scheduled` 模式，以 `UseShellExecute=false / CreateNoWindow=true` 创建系统 PowerShell 子进程，重定向并排空标准流，限制模块搜索到系统目录，退出时返回子进程结果，55 秒超时只终止自己创建的 worker。PowerShell 仍使用 `-NoProfile -NonInteractive -WindowStyle Hidden`，但静默保证来自 GUI 子系统和进程创建方式，不能只凭窗口隐藏参数或任务 Hidden 字段断言。没有常驻守护进程，也不依赖安装 Python 或 Visual Studio。依据：[CreateNoWindow](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.createnowindow?view=netframework-4.8.1)、[C# 输出类型](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/output)。

任务名为 `CVSRK-ClaudePrivacy-<用户 SID 摘要>`；Principal 为该 SID 的 `InteractiveToken` / `HighestAvailable`，无密码，不使用 SYSTEM。触发条件是该用户登录及登录期间每两分钟一次，重复运行忽略，执行上限一分钟，允许电池供电，错过触发后尽快补跑，不主动唤醒电脑。任务所有者为 Administrators，当前用户只读/执行；注册使用 `TASK_DONT_ADD_PRINCIPAL_ACE` 防止系统额外添加可写用户权限。读取 XML 和 SDDL 后校验并记录指纹，遇到同名无所有权任务或后续编辑时不接管。依据：[Microsoft RegisterTask](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskfolder-registertask)。

Windows 可能将登录触发器的 `UserId` 从 SID 规范化为 `计算机名\账号`。工具将主体和触发用户分别解析回 SID，再严格要求等于当前用户；空值、无法解析的名字或其他用户都拒绝，不通过放宽 ACL 或接受任意登录用户来绕过差异。

每次定时刷新同时要求 `state.enabled=true`、`AppliedConfigurationOnly` 以及 `maintenance.enabled=true`、`Enabled`。失败、待处理、跨用户或被修改的状态会停止自动变更。回滚先保存 `state.enabled=false`、关闭维护记录并删除未改动的任务，然后撤销规则/策略。排队中的已部署旧 runner 在开关关闭后只记录 `SkippedDisabled`；普通 `refresh` 也不能重新启用。`maintenance-disable` 单独停止自动维护，不移除现有防护。

`maintenance.json` 保存任务和部署所有权；`maintenance-last-run.json` 保存 UTC 时间、退出码、错误，以及 worker PID、实际墙钟时长、进程 CPU 时间、操作数与各快照步骤耗时。`status` 输出 `RecentSuccess` / `AwaitingFirstRun` / `Failed` / `Stale` / `TaskMissing` / `TaskChanged` / `RuntimeChanged` / `NeedsReview` / `UnexpectedTask` 等状态；超过六分钟无成功结果标为过期。两分钟是计划间隔，休眠、调度延迟、任务失败或无法验证新版本都可能扩大空档，不能宣称升级时零空档。自动维护从状态读取范围，发现已注册 MSIX、正在运行的已验证程序，并在组合范围检查固定的当前用户 CLI 安装路径；不持久保存手动 `-ClaudePath` 参数。

维护的用途是跟进更新后的精确程序路径、检查签名和防护漂移。每轮仍重新读取 PersistentStore / ActiveStore、完整规则指纹和 Chrome 策略；防火墙查询在提供程序侧只取工具前缀，仍检查同名前缀的无所有权碰撞。若新快照与已存状态一致且计划无操作，跳过重复的逐规则最终读取和原状态重写；有变更时仍逐步写日志与回读。没有通过降低频率、缓存签名或跳过有效策略检查节省时间。

## 4. 推荐启用和回滚命令

协调方完成审阅后，从完整仓库/发行包目录触发下面的入口，由用户完成一次同用户 UAC。预期应用为 Windows PowerShell，签名发布者 Microsoft Windows；不要在其他 chat 重复触发：

```powershell
.\claude-privacy.bat status
.\enable-claude-privacy.bat -WhatIf
.\enable-claude-privacy.bat
```

需要纳入已安装的官方 Windows 原生 CLI 时，改用下面的明确选择；选择本身不安装、启动或登录程序，也不发模型请求：

```powershell
.\enable-claude-privacy.bat -ProtectionScope DesktopAndCli -WhatIf
.\enable-claude-privacy.bat -ProtectionScope DesktopAndCli
```

切回仅桌面可使用 `enable-claude-privacy.bat -ProtectionScope Desktop`；已有部署应使用这个完整入口，同时更新受保护运行版本。手动 `claude-privacy.bat apply -ProtectionScope DesktopAndCli` 或 `Desktop` 只变更范围与规则，不自动更新维护部署。显式缩围只删除所有权与指纹仍吻合的 CLI 规则，保持桌面规则；未知改动仍报冲突。

只升级当前维护实现、全程保留已启用防护时使用：

```powershell
.\enable-claude-privacy.bat -MaintenanceOnly -WhatIf
.\enable-claude-privacy.bat -MaintenanceOnly
```

该模式要求原防护已启用、范围不变且当前预案无操作/冲突；核对源摘要后更新原工具拥有的任务，执行一次真实任务并再次验证规则和策略。不会执行 apply、rollback 或关闭防护。需要新增/缩减范围或修复实际规则漂移时使用完整入口。

完整入口依次执行：只读预演、应用与 PersistentStore/ActiveStore 回读、维护部署与真实任务运行、真实回滚、回放旧定时 runner 并确认不能重启用、再次应用/启用维护/运行真实任务。验收中途失败时保留明确失败结果；若已开始回滚，只通过正常所有权检查路径尝试恢复所要求的启用状态，恢复失败也如实记录。不会为了测试伪造或改名进程。

受保护结果在 `%ProgramData%\ClashVergeSteamRoutingKit-ClaudePrivacy\<用户 SID>\enablement-result.json`；启动器返回 `ElevatedSetupStarted` 只是异步启动。必须等待结果为 `Completed`、`success=true`，且最后状态为启用、维护有本次真实成功运行，才能宣布配置验收完成。`sourceDigest` 是七个执行源的聚合 SHA-256，可与审阅时摘要核对。结果中的 `chromePolicyUnchanged` 只描述前后是否相同：已有三条策略的机器应为 true；首次合法新增策略的机器可以为 false，成功条件是与审核预案一致。

需要立即手动刷新时，在同一用户的管理员 PowerShell 中执行：

```powershell
.\claude-privacy.bat refresh -WhatIf
.\claude-privacy.bat refresh
.\claude-privacy.bat status
```

撤销本工具拥有的变化：

```powershell
.\claude-privacy.bat rollback -WhatIf
.\claude-privacy.bat rollback
.\claude-privacy.bat status
```

`status` 回滚后仍可输出拟启用步骤，它不会重新启用。退出码：`0` 命令正常完成；`1` 失败（可能有写前日志记录的部分成功）；`2` 审计不完整或回滚仍有冲突。`AppliedConfigurationOnly` 仅表示配置层完成，不能解释为网络验收完成。状态输出包含 `PersistentStore` 与 `ActiveStore` 的工具前缀规则，便于对照是否进入有效策略；还需实际流量归属验证。

只停止维护：`claude-privacy.bat maintenance-disable`。重新显式启用：先确保 `apply` 成功，再执行 `claude-privacy.bat maintenance-enable`。这两项都支持预演。回滚保留部署文件和验收记录供审计，但不保留自动运行任务；不要直接删除日志来绕开所有权检查。

本机此前已存在的三条 Chrome 策略被视为外部配置，本工具不会认领。按当前快照，`apply` 只计划新增 Claude 程序防火墙规则；其 `rollback` 会保留此前的 Chrome 策略。如需撤销此前的改动，应由协调方基于原始备份及当前值单独比较处理。

## 5. 已完成验证

### 首次桌面范围实机结果

桌面范围回执完成时间：`2026-10-08T11:29:59.6748845Z`。以下是 CLI 扩展前的历史配置验收，不能代替第 9 节的组合范围验收。原始回执和历史失败临时文件保存在本机受保护目录，不纳入公共仓库。

| 项目 | 本次独立回读结果 |
| --- | --- |
| 总结果 | `Completed`，`success=true`，无 error / recoveryError |
| 防护状态 | `enabled=true`，`AppliedConfigurationOnly` |
| 规则 | 1 条精确 Claude.exe UDP 出站阻止；PersistentStore 与 ActiveStore 均为 1 条并通过规格回读 |
| Chrome | `chromePolicyUnchanged=true`；既有条目未认领、未被回滚删除 |
| 自动维护 | `enabled=true`，`Enabled`，任务启用，`RecentSuccess`，任务最近结果 `0` |
| 真实维护运行 | `2026-10-08T11:29:53.0777891Z`，`Refreshed`，退出码 `0`，无新增操作 |
| 真实回滚 | 工具任务与规则移除；回放旧 scheduled runner 不能重启用；普通 refresh 也被拒绝 |
| 最终恢复 | 再次应用规则、启用维护并真实运行任务成功；随后代码权限、哈希与任务安全条件复查通过 |
| 流量观察 | 验收当时已验证 Claude 运行进程数、UDP endpoint 数、对应阻止事件数均为 0；不能由此证明 Claude UDP 已被阻止 |

上述桌面范围成功执行的六源摘要：`3F4A718B5A75AD00BA20F3213E7D76FD2645105D25DEC86E330B99E322939ACF`。受保护运行目录内容摘要：`d4361bbd47ebd785d1fdc858`。后续经明确授权增加原生 CLI 支持，新版摘要见第 9 节。

### 回归与失败修复证据

- Git 预检：远端 fetch 成功；开始时 `main` 与 `origin/main` 同步，工作区干净，版本 `v1.7.2`。
- Windows PowerShell 5.1 和 PowerShell 7 均运行 `tests/run-tests.ps1`，静默维护优化后各 208 项断言及额外 JavaScript 路由/组合/JSON 检查通过；测试使用临时目录、固定公开 fixtures 和内存适配器，不写真实策略、防火墙、AppData 或计划任务。
- 安装/同步：自定义绑定、空绑定、原 `Script.js` 逐字节保持；已修改或无所有权公共文件拒绝覆盖；普通安装不创建自启动；迁移预览无副作用；迁移仅停止精确匹配的 mock 进程并保留两个旧文件备份。
- JavaScript：原有 12 个分组、Unity 继承关系、China 拒绝、NVIDIA/Steam/Bilibili 默认直连、下载规则优先级、重复运行，以及 Owner 在公共层之后执行均通过。
- 隐私：相同项幂等、不接管既有策略、增量合并、用户后续修改、无效数据、宽泛策略优先级、权限/写入失败、部分成功恢复、同名规则冲突、过滤器漂移、并发修改、多版本与升级失败均有行为断言。
- 只读 Windows 审计：发现已安装且签名有效的 Claude MSIX 可执行文件；当前 Chrome 的三条 JSON 策略可读；防火墙三个配置文件均开启且允许本地规则；没有本工具拥有的规则；预案只有 `AddRule`。普通权限读取防火墙返回拒绝访问，工具正确报告不完整；允许只读提权后审计通过。
- 对真实已有 Windows 防火墙规则做只读适配检查：关联过滤器可完整转换，空 Package 归一为 `Any`，得到 64 位十六进制 SHA-256 指纹。
- 真实 `apply -WhatIf` 预览退出码为 `0`，确实输出 WhatIf 提示；前后比较确认 Chrome 值、工具前缀防火墙规则和状态文件存在性全部不变，实际工具规则仍为零。
- 自动维护：同用户主体、无密码、权限读回、无所有权碰撞、被编辑任务保留、关闭开关后旧刷新不重启用、重复启停与 UTC 时间处理均有隔离断言。真实 Windows 任务服务通过 `TASK_VALIDATE_ONLY` 接受 XML，前后没有任务。
- 一次入口：首次合法新增 Chrome 策略按预案验收、不认领既有相同策略、缺少有效规则时拒绝成功、回滚后的失败恢复与最终启用顺序均有隔离断言。真实 `enable-claude-privacy.ps1 -WhatIf` 成功且机器状态前后不变，预案只新增已签名 Claude 路径规则，无冲突，明确 `needsUac=true`。
- 修复 Windows PowerShell 5.1 内置 `Get-FileHash` 受继承 `WhatIf` 影响而无返回的问题；入口源摘要与部署/校验摘要采用只读文件流和 SHA-256，并有预演回归检查。Windows Appx 模块导入时可能在 JSON 前打印 `Set Alias` 的 WhatIf 提示，不代表机器配置写入。
- 首次真实部署失败后独立回读：state 为 `enabled=false / Pending / rules=[] / policy=null`，PersistentStore 与 ActiveStore 均无本工具规则，维护任务不存在。原 Running 回执与全部 Failed 临时回执保留；未盲目接管或清理任何资源。
- 在 Windows PowerShell 5.1.26100.9444 实证普通 `$null` 引发 `File.Replace` 的路径格式异常，`[NullString]::Value` 替换成功。新增 `persistence.tests.ps1`，使用真实临时文件验证创建、Running→Failed 完整写回、ACL/owner 保持、旧读取句柄看到完整旧内容、新读取看到完整新内容、禁止删除共享的文件锁导致替换失败但保留旧文件与暂存证据、释放锁后重试成功。运行时管理员归属仍由提权安装验收；测试没有把它伪装成已通过。
- 新版入口从实际 Pending 状态只读预演通过，仍仅计划 AddRule、无冲突。前后核对策略、规则、任务以及所有旧证据文件名和哈希，均保持原样。显式 apply 恢复 Pending 状态也有隔离断言，不依赖删除状态文件。
- 第二次真实部署中状态和 Failed 回执成功原子写回；精确 Claude 规则在 PersistentStore / ActiveStore 均通过验收，Chrome 原值不变。维护任务已登记且指纹持久化，但触发用户表示法差异导致安全校验误报，维护记录保持 `Pending / enabled=false`。
- 上述 Pending 任务已真实定时执行，留下 `SkippedDisabled / exitCode=0 / No changes made`，证明关闭的维护开关和原子结果保存已在实际任务中工作；这不代替启用后的刷新验收。
- SID 解析修复后，现有真实任务通过全部安全条件和 ACL 校验，指纹未变。新增真实注册 XML 的脱敏 fixture、同一账号解析、空值/无效账号/其他主体拒绝及自有 Pending 任务恢复用例。最新恢复预演无新增规则、无冲突，现有规则与任务所有权保持。定时任务独立更新的最近执行记录不与预演的静态证据混算。
- 发布白名单、本地 zip、README 结构、入口路径、UTF-8/BOM/换行和 Git diff 检查纳入最终验证。测试数量与最新执行结果以任务最终报告及脚本输出为准。

运行隔离验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
pwsh -NoProfile -File .\tests\run-tests.ps1
```

Windows PowerShell 5.1 为安装和隐私入口的兼容基线；只有测试 JavaScript 需要 Node.js，最终用户安装/隐私操作不依赖 Node.js 或 Python。

真实文件替换需要临时测试目录中的创建、删除及元数据权限；某些执行沙箱会拒绝 Replace。此时应在具备测试目录权限的普通用户环境运行测试，不为测试请求 UAC，也不要把文件持久化测试改成 mock 来掩盖限制。

## 6. 真实机器验收状态与边界

1. 由协调方停用实际旧同步器、恢复或选择真实 Owner 增强源、生成组合卡片，验证切换订阅后绑定和最终规则仍正确。此任务没有改 AppData 或停止任何实际旧进程。
2. 桌面与原生 CLI 组合范围的实际规则、状态 ACL、两层规则回读、启用后任务运行、真实回滚与最终恢复启用已全部通过；第 9 节为组合配置验收，第 10 节为后续静默维护升级，第 5 节为此前桌面历史记录。其他机器仍需独立执行入口并核对自己的结果。
3. 协调方已报告当前浏览器中三条 Chrome 策略加载为 Platform / Current user / Mandatory / OK，此项已完成。本入口保持这些已有值、不认领。其他机器仍需在 `chrome://policy` 确认版本、来源、优先级及目标值。
4. 在实际 Claude 目标 Chrome 页面触发 WebRTC/ICE，使用 `chrome://webrtc-internals` 和适当抓包核验，区分缓存候选、mDNS、本地接口和非代理 UDP。Python STUN 只能作一般网络探测，不能代替目标页面实测。
5. 实际 Claude 进程 UDP 阻止尚未证明：本次验收时 Claude 未运行，也没有对应阻止事件。后续需用受保护进程产生实际网络行为，通过 Windows 过滤平台事件/抓包结合路径归属确认 IPv4/IPv6 UDP 阻止。Claude 启动/登录/会话和 Mihomo/Hysteria2 健康由协调方另外验收，不从本回执推导已完成。
6. 升级变化的添加/保留/清理顺序已通过隔离用例；真实版本升级尚未发生，不能伪造为已测。维护任务会在登录时和每两分钟刷新，仍需检查最近成功时间、签名识别失败等异常。
7. 真实回滚、旧 runner 防重启用以及再次启用均已执行并通过；最终状态为防护与维护均启用。失败时留下的临时证据与旧部署目录均保留，未为通过验收而手工篡改所有权日志。

能力边界：只针对三类 Chrome 页面 WebRTC 非代理 UDP 和所选范围内确认的 `Claude.exe` UDP 出站。官方 Windows 原生 CLI 只有显式选择后才纳入精确程序规则；不保证所有 TCP、DNS、辅助/子进程、Node 托管 CLI、WSL/虚拟机、嵌入或资源域页面、所有浏览器或全部指纹都被约束。Chrome 策略不配置 Electron；Windows 程序规则也不自动继承到其启动的不同可执行文件。服务可回退 TCP，程序代理配置和真实出口仍需另行验收。

## 7. 修改文件与打包

- 改写：`install-steam-routing.ps1`、`sync-clash-verge-steam-script.ps1`、`Start ClashVerge Steam Sync.vbs`；调整安装 BAT 完成提示。
- 新增安装模块和组合器：`scripts/RoutingKit.psm1`、`compose-routing-script.ps1`。
- 新增隐私入口、模块和宿主源：`claude-privacy.bat`、`claude-privacy.ps1`、`enable-claude-privacy.bat`、`enable-claude-privacy.ps1`、`scripts/ClaudePrivacy.Core.psm1`、`scripts/ClaudePrivacy.Windows.psm1`、`scripts/ClaudePrivacy.Maintenance.psm1`、`scripts/ClaudePrivacy.Enablement.psm1`、`scripts/ClaudePrivacy.Host.cs`。
- 新增域名接口、测试与公开旧版 fixtures：`config/claude-privacy-domains.json`、`tests/`。
- 同步文档和清单：两个 README、`AGENTS.md`、`.gitignore`、`CHANGELOG.md`、本报告、`release-files.txt`、`build-release.ps1`。
- 未改公共路由源 `Script.js`、`Merge.yaml`、Unity 诊断源及 `VERSION`，未改其他项目、VPS 或发布状态。真实隐私部署由协调方统一触发 UAC，结果按本报告的验收状态记录。

本地打包示例（仅构建，不发布；正式发布前需另行决定版本号）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-release.ps1 -OutputPath C:\Temp\clash-verge-steam-routing-kit-review.zip
```

只从当前仓库文件按 `release-files.txt` 复制，输出已存在则拒绝覆盖，不读取个人运行配置。正式发布仍应采用 `clash-verge-steam-routing-kit-vX.Y.Z.zip` 名称，并在获得发布授权后同步 `VERSION` 与 Release 说明。

## 8. 下游复核交接

下游 `remote-proxy-server` 只需继续核对这两个公共源；本次没有要求将 Windows 机器状态、Owner 私有组合、防火墙日志或本机任务配置复制到下游：

| 公共源 | SHA-256（当前工作区文件字节） |
| --- | --- |
| `Script.js` | `ED3C7424AADB45D76D7483F90429F69AC7B880B48F9BA9EEBD498145196A79CD` |
| `config/claude-privacy-domains.json` | `B7A66FB1F1610299F793B8DACFE7508725BB8DF1247E9A185FC17EA399338C8C` |

复核要点：公共 `main(config)` 与原有 12 个分组/defaults 保持；JSON 的 `schemaVersion=1` 和六个后缀是网络接口，不能误用为 Chrome 三页面策略；组合时公共层先运行，Owner 后运行且作用域隔离。域名维护源仍在本仓库，消费方应校验 schema 并忽略不认识的说明字段。

这些新文件和修复目前存在于本工作区，尚未提交或发布；旧版 `v1.7.2` 下载包不能作为包含本次改动的证明。下游先按上述路径与哈希复核，自己的集成、订阅绑定和实际出口仍需由负责方确认。本机配置验收通过不替代下游网络验收。

## 9. 原生 Claude Code 范围扩展

用户授权后，新增 `DesktopAndCli` 选择；本任务只处理精确程序 UDP 规则与维护兼容，不操作 Claude 桌面 UI。CLI 安装、PATH、代理与 Pro 认证由协调方负责，不能从本工具回执推导登录或模型调用已经完成。

独立读取本机安装文件，确认原生 CLI 产品为 `Claude Code`、公司为 `Anthropic PBC`、文件版本 `2.1.286.0`，Authenticode 有效且发布者为 Anthropic；桌面程序仍按自身产品信息单独验证。此处记录的是验收时快照，不将版本和个人路径写入通用发现逻辑。官方说明可参见 [Claude Code 原生安装](https://code.claude.com/docs/en/setup)。

此次组合扩展的历史六源摘要：`41572400DCDC0112002D2BAF6080E2BD7786F17E8FB013AD11FE79D896561C25`；当时受保护运行内容摘要：`8f35d97b73b10923eea2e2f9`。协调方独立核对摘要后统一执行一次 UAC，回执由双方独立读回；后续获授权的静默维护修改见第 10 节，以下不作为当前执行源摘要。

| 项目 | 最终组合验收结果 |
| --- | --- |
| 完成时间 | `2026-10-08T12:04:37.9369623Z`，即 UTC+08:00 的 20:04:37 |
| 总结果 | `Completed / success=true`；五项真实配置检查全部通过，无 error / recoveryError |
| 范围与状态 | `DesktopAndCli`，`enabled=true`，`AppliedConfigurationOnly` |
| 规则 | Desktop 与 NativeCli 各一条精确程序 UDP 出站阻止；PersistentStore 与 ActiveStore 均为 2 条 |
| Chrome | `chromePolicyUnchanged=true`；原有三条外部策略保留且未认领 |
| 自动维护 | `RecentSuccess`；本次验收运行于 `2026-10-08T12:04:27.7619957Z` 返回 `Refreshed / exitCode=0`，回执中任务结果为 `0` |
| 回滚与恢复 | 两条自有规则与任务真实移除，旧 queued runner 和普通 refresh 不能重启用；最终恢复两条规则与维护并执行成功 |
| 权限与来源复查 | 当前部署文件所有权、ACL、集合和哈希，以及任务主体、命令、触发器和权限均独立验证通过 |
| 流量观察 | 已验证 Claude 运行进程、UDP endpoint、对应阻止事件均为 0；实际 UDP 阻止仍未证明 |

- 两套 PowerShell 各 178 项断言通过；新增分类、有效签名/错误产品拒绝、已验证 CLI 不干扰桌面模式、CLI 未运行仍发现、老版本并存、未知同名进程拒绝、旧状态兼容、显式扩围/缩围、刷新不能自行改范围与回滚保持 Chrome/关闭开关的用例。
- 真实只读预演发现 Desktop 与 NativeCli 两条已验证路径，没有发现错误或冲突；只计划新增一条 CLI 精确路径规则，保留原桌面规则，下一状态为 `DesktopAndCli`、两条规则。
- 前后独立比较 state、maintenance、任务指纹、Chrome 值、规则和静态证据文件均保持不变。定时任务自然更新的最近运行文件不纳入静态文件哈希比较。
- 最终验收已重新覆盖 PersistentStore / ActiveStore、实际任务刷新、两条规则回滚、旧 runner 防重启用和最终恢复启用；成功来自本次 `DesktopAndCli` 新回执，并非沿用此前单桌面回执。
- 验收入口的现有 WFP 事件读取只覆盖桌面 WindowsApps 路径，不是 CLI UDP 测试；无论配置是否成功，都不能用它证明 CLI 实际 UDP 阻止。真实 CLI 登录、会话、TCP 代理出口和流量验证由协调方另外完成。

## 10. 静默维护与无变更开销优化

此前已配置 `-WindowStyle Hidden` 的直接 PowerShell 任务仍发生闪窗。诊断方在本机 20:36:07 捕获到该任务的可见 `ConsoleWindowClass`，事件与精确脚本路径、进程归属一致；无变更任务约用时 23 秒，每两分钟执行一次。该 23 秒是历史墙钟观察，没有旧版 CPU 时间基线，也不是同条件性能基准。

当前七源聚合 SHA-256：`E3EFE3DA90502ABFCDE60319A9628CF52EE9D135222C7D63CAEE8A1503674A8D`。聚合顺序为 `enable-claude-privacy.ps1`、`scripts/ClaudePrivacy.Enablement.psm1`、`claude-privacy.ps1`、`scripts/ClaudePrivacy.Core.psm1`、`scripts/ClaudePrivacy.Windows.psm1`、`scripts/ClaudePrivacy.Maintenance.psm1`、`scripts/ClaudePrivacy.Host.cs`；各项为 `相对路径:文件 SHA-256`，以 `|` 拼接后对 UTF-8 求 SHA-256。当前受保护运行源摘要为 `ac100a9f7cd3bda7944a0f64`，格式为 `runtimeFormat=2`；生成 EXE 的哈希另存于受保护维护记录与构建记录，不能用源摘要替代二进制校验。

协调方核对冻结源和只读预演后统一触发一次 UAC，执行 `-MaintenanceOnly`。配置验收完成时间为 `2026-10-08T13:19:57.5720375Z`，即 UTC+08:00 的 21:19:57。双方独立回读 `Completed / success=true / maintenanceOnly=true`，三项检查通过，无 error / recoveryError。任务切换为受保护 GUI 宿主的固定 `--scheduled` 入口；任务主体、ACL、指纹、部署集合和哈希均验证通过，EXE 的 PE subsystem 为 `2`。此次只升级维护，全程保留两条防护规则和 Chrome 策略，没有重新执行回滚。

随后等待两个自然触发周期，不调用任务 Run，也不重新提权。只读观察器同时使用窗口 SHOW 事件与约 10–20 毫秒的可见窗口枚举，结合进程树和精确宿主映像路径，将窗口归属于任务宿主及其后代；不读取窗口标题或页面内容。观察区间为 UTC+08:00 的 21:25:04–21:27:53，正式结果 `success=true`：

| 指标 | 第一轮 | 第二轮 |
| --- | --- | --- |
| 成功回执时间（UTC+08:00） | 21:25:39 | 21:27:39 |
| 任务结果 / 变更操作数 | 0 / 0 | 0 / 0 |
| worker 墙钟时长 | 10.692 秒 | 11.138 秒 |
| worker CPU 时间 | 3.7656 秒 | 4.1562 秒 |
| 程序发现 | 2.466 秒 | 2.533 秒 |
| PersistentStore 规则读取 | 6.452 秒 | 6.712 秒 |
| ActiveStore 规则读取 | 1.262 秒 | 1.385 秒 |
| 归属本任务及后代的可见窗口 | 0 | 0 |

观察共完成 9,583 次窗口枚举、1,390 次进程快照，观察到其他程序的 69 个不同可见窗口；SHOW hook 安装与移除成功，两轮均准确关联宿主、PowerShell worker 及其后代。记录中存在 `conhost.exe` 后代，未观察到它们的可见窗口，因此不将“没有可见窗口”写成“没有 conhost 进程”。这是本机两个自然周期的实测，不是对所有 Windows 状态的绝对保证。

实测后再次验证 `DesktopAndCli / enabled=true / AppliedConfigurationOnly`，PersistentStore 与 ActiveStore 各两条规则，状态内容及文件哈希、Chrome 策略均与观察前一致。无变更轮次未重写防护状态；维护结果日志正常更新。维护间隔仍为两分钟，worker 结束即退出，没有常驻维护进程。当前主要时间花在 Windows 防火墙读取；不能把墙钟时长当作持续满核运行，也不能据历史 23 秒计算 CPU 降幅。

正式原始观察结果保留于本机忽略目录 `.test-tmp/quiet-acceptance/natural-cycles-20261008T132753Z.json`，SHA-256 为 `3D34DB1FB728303BF18C79FB1E4855F7B3A4665C99CC07EDCCCDFE293CC2328A`，不进入发行包。此前一轮观察器在 JSON 汇总时触发 Windows PowerShell 集合转换错误，未生成完整回查结果；改用明确数组转换并验证空/非空集合后重新观察，前一轮不计入验收结论。

Windows PowerShell 5.1 与 PowerShell 7 各 208 项断言通过。新增真实编译 GUI 宿主、子进程无控制台句柄、退出码传递、受保护运行集与构建记录篡改拒绝、旧部署兼容、无变更不写状态、前缀查询保留碰撞检测，以及维护专用升级不调用 apply/rollback 的验证。公开打包白名单现为 43 个文件；源、测试和文档来自当前工作区，尚未提交或发布。静默维护验收不扩展第 6 节的实际 UDP、ICE、账户与网络出口证据边界。
