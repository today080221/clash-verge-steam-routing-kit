# Clash Verge Steam Routing Kit

面向 Windows 上 Clash Verge Rev 的共享分流工具包，处理 Steam、Unity、NVIDIA 与可选的 B 站视频 CDN，并提供更强硬的 Unity 中国绕行方案。

[![简体中文](https://img.shields.io/badge/简体中文-当前-2ea44f?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-Read-0366d6?style=for-the-badge)](README.en.md)

## 项目状态

这是一个 AI 生成项目。

本仓库的代码、结构和文档通过 AI 辅助生成与迭代完成。请在自己的环境中使用前先自行审阅脚本。

将公共或组合脚本挂载到明确选择的 Clash Verge Rev 订阅后，会注入 12 个可复用分组：

- `UnityGlobal`：Unity 全球主分组，用来收敛 `UnityHub`、`UnityEditor`、`UnityDownload` 的默认出口
- `UnityWeb`：Unity 网页与账号分组，负责浏览器里的 Unity ID、Asset Store 和相关 Web API
- `UnityHub`：Unity 全球控制面，负责登录、许可、版本清单、配置与服务网关
- `UnityEditor`：Unity Editor 相关 API、包管理、分析与辅助云服务
- `UnityDownload`：Unity 全球下载面，负责 Editor、模块与包下载链路
- `UnityChina`：Unity 中国链路隔离组，负责 `unity.cn`、`unitychina.cn`、`u3d.cn` 等中国专用域名
- `NvidiaServices`：NVIDIA 网页、登录、控制面与其他官方服务流量，默认直连
- `NvidiaDownload`：NVIDIA 驱动、NVIDIA App 与 OTA 包体下载流量，默认直连
- `SteamCommunity`：Steam 社区、聊天、头像，以及其他常见被拦截的 Steam Web 内容
- `SteamMainland`：Steam 商店、登录、帮助，以及通常在中国大陆可正常访问的 Steam Web 流量
- `SteamDownload`：Steam CDN、内容服务器，以及下载相关流量
- `BilibiliVideo`：可选的 B 站视频 CDN 分组，用来在网页播放器 6003、CDN/DNS 异常时单独切换视频链路

## 这个仓库解决什么问题

- 在多台电脑之间复用同一套 Steam、Unity 与 NVIDIA 分流逻辑
- 在不同服务商之间复用同一套规则，而不是反复手改订阅
- 保留每个订阅已有的自定义脚本绑定，通过明确选择复用公共脚本或组合脚本
- 把 Steam 社区、商店/登录、下载流量拆开分别调控
- 把 B 站网页播放器相关 CDN 从通用中国直连规则里单独剥出来，必要时只切视频链路
- 把 NVIDIA 服务流量与驱动/App 下载流量拆开，避免大文件下载被迫跟随登录或网页出口
- 把 Unity 全球控制面、全球下载面、Unity 中国链路拆开分别调控
- 让所有 Unity 全球相关分组都可以默认指向同一个 `UnityGlobal`，需要时再单独覆盖
- 把浏览器里的 Unity ID、Asset Store 和 Unity Hub / Editor 链路拆开分别调控

## 为什么要单独拆 UnityChina

Unity 官方面向全球的 Hub 与下载链路主要在 `unity.com`、`unity3d.com`、`public-cdn.cloud.unity3d.com`、`download.unity3d.com` 一侧，而 Unity 中国官方文档又明确存在单独的中国账号和中国包下载链路，例如 `upm-cdn-china.unitychina.cn`。

这意味着如果你的目标是“从地区识别到 CDN 分配都尽量避开 Unity 中国”，只把 `download.unitychina.cn` 代理掉还不够，必须把整类中国专用域名单独剥出来。当前版本的默认策略就是：

- `UnityGlobal`：走代理，作为 Unity 全球链路的统一上游组
- `UnityWeb`：默认指向 `UnityGlobal`，负责浏览器里的 Unity ID、Asset Store 与相关 Web API
- `UnityHub`：默认指向 `UnityGlobal`，负责把地区识别和服务上下文留在全球链路
- `UnityEditor`：默认指向 `UnityGlobal`，负责 Unity Editor 相关 API、包管理、分析与辅助云服务
- `UnityDownload`：默认指向 `UnityGlobal`，负责把 Editor 和模块下载留在全球链路
- `UnityChina`：默认 `REJECT`，直接拦掉 Unity 中国专用域名，避免 Hub 回落到中国链路

## 为什么要单独拆 NvidiaDownload

NVIDIA 驱动和 NVIDIA App 包体通常体积很大，而且 NVIDIA App 可能使用并发分段传输。NVIDIA 官方支持文档明确说明，代理或下载管理器可能影响文件传输并造成下载损坏；NVIDIA App 的官方安装入口也直接使用 `us.download.nvidia.com` 这类下载主机。

当前规则因此采用“服务与下载分离”的保守边界。NVIDIA 在中国大陆提供官方 NVIDIA App 与中国账户入口；v1.7.1 也用 NVIDIA App 日志中的实际服务主机验证了直连 DNS、TLS 与 HTTP 可达性，因此两个 NVIDIA 分组都把 `DIRECT` 放在第一项，同时保留代理兜底。v1.7.2 进一步根据真实驱动下载响应补齐了从 `.com` 重定向到 `.cn` 的第二跳：

- `NvidiaServices`：接管更宽的 `nvidia.com` 与 `nvidia.cn` 官方服务域名，默认 `DIRECT`，直连登录或服务异常时可单独切到代理
- `NvidiaDownload`：以更高优先级接管 `*.download.nvidia.com`、`*.download.nvidia.cn` 与 `ota-downloads.nvidia.com`，默认 `DIRECT`，同时保留代理选项用于直连 CDN 异常时切换
- 不自动接管 GeForce NOW 等独立域名生态，避免把低延迟流媒体服务和驱动下载混为一组

参考：[NVIDIA 中国 App 官方页](https://www.nvidia.cn/software/nvidia-app/)；[NVIDIA 中国账户常见问题](https://www.nvidia.cn/account/faq/)；[NVIDIA 关于代理影响下载完整性的说明](https://nvidia.custhelp.com/app/answers/detail/a_id/21)。

注意：Clash 规则只能控制已经进入 Clash 的连接。如果 Proxifier 又把 NVIDIA 进程单独送到另一个上游代理，仍可能形成双层代理；这时应让 NVIDIA 进程直接进入 Clash，或在 Proxifier 中对下载流量设为直连。

## 在另一台 Windows 电脑上安装

1. 安装 Clash Verge Rev，并至少打开一次。
2. 正常导入你的订阅。
3. 克隆本仓库，或把整个目录复制到目标电脑。
4. 运行：

```bat
install-steam-routing.bat
```

5. 在 Clash Verge Rev 中新建一个「脚本」增强卡片，将 `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\profiles\SteamRoutingKit.js` 的内容复制进去；只为需要公共分流的订阅选择这张卡片，然后重新加载该订阅。

安装器只维护独立的 `SteamRoutingKit.js` 文件及哈希记录，不修改 `profiles.yaml`、已有 `Script.js`、`Merge.yaml` 或任何订阅绑定。卡片由 Clash 管理；以后更新工具包时，需要把更新后的文件内容复制到同一张卡片。被手工修改过的受管理文件会报冲突，不会覆盖。普通安装不设置自启动，不重启 Clash，也不启用 Claude 防护。

### 从旧版安全迁移

旧版同步器会反复重绑订阅，单纯更新仓库不会停止已运行的旧进程。关闭 Clash 后，从新工具包目录预览并执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-steam-routing.ps1 -MigrateLegacy -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-steam-routing.ps1 -MigrateLegacy
```

迁移只停止命令行 `-File` 精确指向本安装目录的旧同步进程，并把已识别的旧脚本与启动项改名为带随机标识的 `.disabled` 备份。未识别或修改过的版本需要先人工检查，不会盲目停进程或覆盖文件。原有订阅绑定完全保留；历史上已被改成空脚本的内容无法凭空恢复，需要从自己的备份恢复。不要重新启用旧同步器。

### 公共分流与自定义增强组合

自定义脚本保持独立。用以下命令生成新文件，将结果放入一张单独的增强卡片，再明确选择需要使用它的订阅：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\compose-routing-script.ps1 -OwnerScriptPath C:\Private\Owner.js -OutputPath C:\Private\Owner.combined.js
```

两段脚本各自保留 `main` 和辅助函数作用域，先执行公共 `main(config)`，再执行 Owner 的 `main(config, profileName)`。Owner 必须同步返回配置对象；不要在同一订阅重复挂载公共层。组合器不执行 Owner 代码、不覆盖已有输出，也不自动绑定订阅。升级公共脚本后重新生成并检查组合结果。不要把包含个人配置的组合文件提交到本仓库。

## 通过 Release 快速安装

1. 从 Releases 页面下载最新版本 zip。
2. 解压到任意目录。
3. 双击 `install-steam-routing.bat`。
4. 按上面的说明创建/更新增强卡片并明确选择订阅；旧安装先执行安全迁移。

你只需要下载一次。之后继续运行同一个 `install-steam-routing.bat`，它会先检查 GitHub 上是否有新的 Release；如果有，就会自动下载并切换到新版本后再执行安装。若 GitHub 检查超时，会在控制台提示你是只执行一次本地脚本，还是直接退出。

## 可选 Claude 隐私防护

独立入口 `claude-privacy.bat` 默认仅检查状态。普通分流安装不调用它。需要 Windows PowerShell 5.1、Windows 防火墙组件，以及所选范围内可验证的 Claude 程序；Chrome URL 策略要求 Chrome 133 或更新版本。首次使用默认保护当前用户的 Claude 桌面版；推荐一次启用防护与自动维护：

```powershell
.\claude-privacy.bat status
.\enable-claude-privacy.bat -WhatIf
.\enable-claude-privacy.bat
```

若还需要保护已安装的官方 Windows 原生 Claude Code，显式选择组合范围：

```powershell
.\enable-claude-privacy.bat -ProtectionScope DesktopAndCli -WhatIf
.\enable-claude-privacy.bat -ProtectionScope DesktopAndCli
```

范围选择保存在状态中；以后省略 `-ProtectionScope` 会沿用它，旧状态没有该字段时仍按 `Desktop` 处理。切回仅桌面范围可运行 `enable-claude-privacy.bat -ProtectionScope Desktop`，按所有权检查移除 CLI 规则并更新维护部署。选择范围不会安装、启动或登录 Claude，也不会发送模型请求。

最后一步请求一次 Windows PowerShell 的 UAC 提权，必须仍是同一 Windows 用户；无需输入或保存任务密码。隐藏的安装进程会应用规则、部署受保护脚本、运行真实维护任务、验证回滚后旧刷新不能重新启用，再恢复防护和自动维护。结果写入 `%ProgramData%\ClashVergeSteamRoutingKit-ClaudePrivacy\<用户 SID>\enablement-result.json`；`Completed` 与 `success: true` 才表示这套配置验收完成，启动命令返回本身不代表完成。也可以在同一用户的管理员 PowerShell 中单独运行 `claude-privacy.bat apply`，此时不会自动建立维护任务。

它增量合并当前用户 Chrome 的 `WebRtcIPHandlingUrl`，只为 `https://[*.]claude.ai`、`https://[*.]claude.com`、`https://[*.]anthropic.com` 设置 `disable_non_proxied_udp`；其他域名值保留，冲突会停止并报告。已有相同条目不归工具所有，回滚不会删除它们。策略有首个匹配优先级，已有前置规则可能要求人工检查。还需要在 `chrome://policy` 确认策略实际加载，并在目标页面验证 ICE。

桌面防护按当前用户已注册的 Claude MSIX、仍运行的旧版本，以及手动命令的可选 `-ClaudePath` 显式路径发现 `Claude.exe`，验证 Anthropic 有效签名和产品信息，然后为精确路径创建全配置文件的 UDP 出站阻止规则。`DesktopAndCli` 还检查当前用户主目录下的 `.local\bin\claude.exe`，即使 CLI 未运行也会保留其规则；分别核对桌面版与 CLI 的产品和公司信息，不按同名进程直接放行。`Desktop` 范围会记录并跳过已验证的 CLI，未知签名、无法确认的同名进程或缺失的已选 CLI 仍会阻止刷新和清理。不使用全机 UDP 阻断，也不依赖未经实测的 MSIX 包身份防火墙匹配。多版本可并存；需要立即刷新时，在同一用户的管理员 PowerShell 中运行：

```powershell
.\claude-privacy.bat refresh -WhatIf
.\claude-privacy.bat refresh
.\claude-privacy.bat status
```

自动维护在当前用户登录时触发，并在登录期间每两分钟检查一次；从状态读取已选范围，先补新路径规则，再清理已不再被发现的旧路径规则。任务使用该用户的最高可用权限，不使用 SYSTEM 身份，只执行受保护的部署代码；读取 CLI 签名和元数据不会执行 CLI。部署代码与任务定义仅管理员/SYSTEM 可改；每次运行验证所有权和文件哈希。关机、休眠、任务延迟或失败仍会延长升级保护空档，不保证零空档。`status` 显示最近结果、任务状态及超过六分钟未成功运行的告警。独立安装的显式 `-ClaudePath` 不会被任务保存，应继续手动传入并刷新。

维护用于跟上 Claude 升级后的程序路径，并检查已有规则是否被改变，不是维持联网所需的常驻进程。任务通过受保护的 GUI 启动器创建无控制台窗口的 PowerShell 子进程；单独设置 `-WindowStyle Hidden` 或任务的 Hidden 字段不足以证明静默。启动器用系统 .NET Framework 编译器本地生成并记录哈希，不依赖 Python；编译器缺失或身份无法验证时停止部署。无变更时仍核验签名、策略和规则指纹，但省去重复逐规则回读与原状态重写；最近结果记录墙钟时间与工作进程 CPU 时间。

已有防护仅升级维护实现时，使用下面的入口，保留当前范围、规则和 Chrome 设置；若已有配置需要修复则停止报告：

```powershell
.\enable-claude-privacy.bat -MaintenanceOnly -WhatIf
.\enable-claude-privacy.bat -MaintenanceOnly
```

此模式仍请求一次同用户 UAC，并更新现有自有任务；回执带 `maintenanceOnly: true`，不会执行启用/回滚防护。维护频率仍为两分钟。静默验收需观察真实自然触发周期及其子进程的可见窗口，不能只凭参数或退出码判断。

只停自动维护、保留现有防护，可运行 `claude-privacy.bat maintenance-disable`；再次开启用 `maintenance-enable`，两者都支持 `-WhatIf` 并要求同一用户提权。需要撤销防护时：

```powershell
.\claude-privacy.bat rollback -WhatIf
.\claude-privacy.bat rollback
```

回滚先持久关闭刷新开关、移除工具拥有的维护任务，再撤销记录且未被他人改动的配置；组合范围的桌面和 CLI 规则一起撤销，之后的用户修改会保留并报告冲突。排队中的旧刷新不会重新启用，只有显式 `apply` 才能恢复；回滚保留范围选择，之后省略范围的显式启用仍沿用该选择。状态、维护所有权和最近执行结果保存在同一受保护目录的 `state.json`、`maintenance.json`、`maintenance-last-run.json`；保留这些记录用于可靠回滚。已部署代码留作审计，回滚后不自动执行。退出码 `0` 表示命令完成，`1` 表示失败，`2` 表示审计不完整、维护异常或需处理冲突；配置存在不代表实际网络阻止已经验收。

状态和结果回执采用完整临时文件替换；覆盖时保留目标文件权限，失败时保留原文件与临时证据，不要手工删除这些记录来消除错误。Windows PowerShell 5.1 与 PowerShell 7 均有真实文件覆盖回归。

这项措施限制的是相关页面 WebRTC 的非代理 UDP，以及已选范围内确认过的 `Claude.exe` 的 UDP 出站。它不强制所有 TCP 走代理，不证明 DNS、子进程、Node 托管 CLI、WSL/VM、资源页面或全部指纹均已受保护；Chrome 策略也不会配置 Electron。原生 CLI 仅在显式选择后纳入精确路径规则，不拦截通用 `node.exe`。Mihomo/Hysteria2 的 UDP 仍由其自己的进程使用。Python STUN 探测不能替代 Chrome 目标页面和受保护 Claude 进程的实测。

网络分流共享名单见 [`config/claude-privacy-domains.json`](config/claude-privacy-domains.json)，该六域名接口包含资源/预览主机，不等于 Chrome 页面策略名单。详见 [交接与真实机器验收](docs/claude-privacy-handoff.md)。来源：[Claude 网络要求](https://code.claude.com/docs/en/desktop#network-access-requirements)、[Chrome 策略定义](https://raw.githubusercontent.com/chromium/chromium/main/components/policy/resources/templates/policy_definitions/WebRtc/WebRtcIPHandlingUrl.yaml)、[Windows 程序防火墙规则](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)。

## 推荐默认设置

- `UnityGlobal`：`自动选择`，或手动指定一个稳定的海外节点
- `UnityWeb`：默认指向 `UnityGlobal`
- `UnityHub`：默认指向 `UnityGlobal`
- `UnityEditor`：默认指向 `UnityGlobal`
- `UnityDownload`：默认指向 `UnityGlobal`
- `UnityChina`：`REJECT`
- `NvidiaServices`：`DIRECT`；如果登录、版本信息或网页服务直连异常，再单独切到稳定节点
- `NvidiaDownload`：`DIRECT`；只有直连 CDN 异常时再切到稳定节点
- `SteamCommunity`：`自动选择`，或手动指定香港/日本节点
- `SteamMainland`：`DIRECT`
- `SteamDownload`：`DIRECT`
- `BilibiliVideo`：默认 `DIRECT`；如果网页播放器出现 6003、但开启系统代理/全局代理后恢复，就临时切到一个稳定节点

如果 Unity Hub 仍然出现 `Validation Failed`：

- 先确认 `UnityGlobal`、`UnityHub`、`UnityEditor`、`UnityDownload` 都不是 `DIRECT`
- 默认先把 `UnityHub`、`UnityEditor`、`UnityDownload` 都指向 `UnityGlobal`
- 如果需要单独覆盖，再只调整某一个 Unity 细分组
- 先运行 `test-unity-routing.bat` 做对照验证
- 如果脚本显示“直连链路是 `302 -> download.unitychina.cn -> 404`，但 Clash 代理链路是 `200`”，说明 Unity 请求没有稳定进 Clash，优先改成 `规则模式 + 开启 TUN`
- 如果脚本显示“Clash 代理链路本身仍然是 `302` 或 `404`”，说明当前节点虽然在海外，但 Unity 还是被分配到了中国镜像，直接换 `UnityHub`/`UnityDownload` 节点并重测
- 如果某个节点能通过 `200/206` 检查，但大文件中途 `ECONNRESET`，继续用脚本对比其他节点；不要只看地区名，先看真实 Unity 链路结果
- 如果你在活动连接里看到 `unity-connect-prd.storage.googleapis.com`、`config.uca.cloud.unity3d.com`、`api.hub-proxy.unity3d.com`、`unity-assetstorev2-prd.storage.googleapis.com` 之类的请求，它们现在会分别落到 `UnityEditor`、`UnityHub` 或 `UnityWeb`，不再被泛化的 `google` 规则抢走
- 如果 Unity Package Manager 能看到包列表，但下载 `.tgz` 包体经常卡住，先确认 `UnityEditor` 没有单独绑到别的节点，优先和 `UnityHub`、`UnityDownload` 一起指向 `UnityGlobal`
- 给 Unity 做代理时，最好额外用 Proxifier 之类的工具把 `Unity Hub.exe`、`Unity.exe` 和 `UnityPackageManager.exe` 强制 reroute 到 Clash Verge Rev 的本地代理，例如 `127.0.0.1:7897`
- 当前规则额外覆盖了 `storage.googleapis.com` 与兼容旧版 `upm-cdn.unity.com`，用来接住 Unity 官方文档里提到的 UPM 签名包文件与旧 CDN 域名
- 浏览器里的 `assetstore.unity.com`、`kharma.unity3d.com`、`unity-assetstorev2-prd.storage.googleapis.com`、`id.unity.com`、`login.unity.com` 和 `accounts.unity3d.com` 现在会单独走 `UnityWeb`
- 如果 UPM 仍然偶发不走 Clash，可按 Unity 官方代理文档给启动 Unity Hub / Editor 的进程注入 `HTTP_PROXY` 和 `HTTPS_PROXY`

如果 Steam 商店出现 `-100` 错误，可以临时把 `SteamMainland` 从 `DIRECT` 改成和 `SteamCommunity` 相同的节点再测试。

如果 NVIDIA App 驱动下载失败：

- 先确认 `NvidiaDownload` 仍为 `DIRECT`，再重新开始下载任务；`international-gfe.download.nvidia.com`、`international-gfe.download.nvidia.cn`、`us.download.nvidia.com` 等下载主机和重定向后的中国 CDN 会持续命中这个组
- `NvidiaServices` 与下载组互不绑定；它也默认 `DIRECT`，但登录、版本信息或网页访问需要代理时，可以只切这个服务组
- 如果同时使用系统代理和 Proxifier，避免再把 NVIDIA 进程送往第二个远端代理；让连接只经过一次 Clash 决策
- 如果运营商直连 CDN 本身很慢或失败，再把 `NvidiaDownload` 临时切到一个稳定节点，不需要改动整个 NVIDIA 服务出口

如果 B 站网页视频播放页出现错误码 `6003`：

- 先把 `BilibiliVideo` 从 `DIRECT` 改成一个已经验证可用的节点或自动选择组
- 这只会接管 `bilivideo.com` 与 `hdslb.com` 这类视频/静态 CDN，不会把所有 `bilibili.com` API 一起改走代理
- 如果切换后立刻恢复，问题通常在本地直连 DNS/CDN 分配或运营商链路，而不是浏览器硬件解码
- 如果仍然报错，再清一次页面缓存或打开无痕窗口测试，避免旧播放器请求继续复用失败连接

用于 Unity 404/302/掉线排查的推荐命令：

```bat
test-unity-routing.bat
```

它会直接对照当前配置下的“直连”和“Clash 代理”结果。切到别的 `UnityHub`/`UnityDownload` 节点后，再重新运行一次，就能继续做人工对照。

## 文件说明

- `bootstrap-install.ps1`：自动更新启动器，负责检查 GitHub Release、下载新版本并切换执行
- `AGENTS.md`：面向 Codex 或其他 agent 的项目操作约定
- `install-steam-routing.bat`：面向 Release 用户的一键安装入口，每次运行都会先检查更新
- `Script.js`：共享的 Clash Verge Rev 配置脚本
- `install-steam-routing.ps1`：安装独立公共脚本，提供显式旧安装迁移
- `sync-clash-verge-steam-script.ps1`：兼容入口，单次更新受管理文件；`-Audit` 只检查哈希，不重绑订阅
- `Start ClashVerge Steam Sync.vbs`：保留的兼容提示入口，不再启动后台进程
- `compose-routing-script.ps1`：显式生成公共层与 Owner 增强的组合脚本
- `claude-privacy.bat` / `claude-privacy.ps1`：独立可选的状态、启用、刷新、维护开关和回滚入口
- `enable-claude-privacy.bat` / `enable-claude-privacy.ps1`：一次提权完成启用、维护任务与回滚协调验收，最终保持启用
- `scripts/`：安装所有权、隐私计划、Windows 适配、维护与验收模块，以及 GUI 宿主 C# 源码，必须随包携带
- `config/claude-privacy-domains.json`：供下游 vendor 的共享网络域名接口
- `docs/claude-privacy-handoff.md`：接口、实现边界、验证结果和机器验收步骤
- `tests/`：不修改机器配置的隔离测试，需要 Node.js 执行 JavaScript 验证
- `release-files.txt` / `build-release.ps1`：显式打包清单与本地打包入口
- `CHANGELOG.md`：尚未发布的变更和后续发布说明
- `test-unity-routing.bat`：Unity 下载 404/302/掉线的一键排查入口
- `test-unity-routing.ps1`：Unity 诊断脚本，可对比直连/代理结果，并额外测试 Package Manager tarball 链路
- `VERSION`：当前本地包版本号，供自动更新逻辑比较使用
- `Merge.yaml`：用于兼容全局 Merge 卡片的占位文件

## 安全说明

- 不要提交 `profiles.yaml`、服务商订阅 YAML，或者带 token 的订阅链接
- 这个公开仓库只包含可复用的分流框架，不包含你的个人服务商配置
- 安装脚本不会复制你的服务商订阅文件，它只安装共享分流层

## 许可证

MIT，详见 [LICENSE](LICENSE)。
