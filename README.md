<div align="center">

![macwinpwrmgr 项目徽章](assets/readme-badge.png)

# macwinpwrmgr

通过局域网让 Mac 按需唤醒并调用 Windows；任务结束后，在确认安全的前提下让 Windows 尽快进入 S3 睡眠。

![macOS](https://img.shields.io/badge/macOS-Zsh-000000?style=flat-square&logo=apple)
![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?style=flat-square&logo=windows11)
![PowerShell 7](https://img.shields.io/badge/PowerShell-7-5391FE?style=flat-square&logo=powershell)
![WoL](https://img.shields.io/badge/Wake--on--LAN-S3%20%7C%20S5-2ea44f?style=flat-square)

[功能](#功能) · [工作原理](#工作原理) · [快速开始](#快速开始) · [使用](#使用) · [排错](#排错)

</div>

## 项目简介

`macwinpwrmgr` 是一个面向同一局域网内 Mac 与 Windows 工作站的轻量调配层。Mac 使用标准 Magic Packet 唤醒 Windows，通过已有的 Windows OpenSSH 和 PowerShell 7 执行任务；Windows 使用原生电源请求保护运行中的任务，并在任务全部完成后通过安全门禁进入 S3。

项目不引入常驻 HTTP 服务、数据库或第三方消息队列。控制面只有 SSH，电源管理使用 Windows 原生 API 与计划任务。

> [!IMPORTANT]
> “可唤醒”取决于主板、网卡、固件和待机供电。断电、网线断开、固件禁用 WoL 或网卡失去待机电源时，软件无法恢复机器。S5 唤醒必须在目标硬件上实测。

## 功能

- 从 Mac 人工唤醒处于 S3 或受支持 S5 状态的 Windows。
- Windows 已在线时直接确认 SSH 与 PowerShell 7 就绪。
- 从 Mac 执行任意一个前台 PowerShell 7 命令，并保留原始退出码。
- 每个受管任务持有独立的 Windows 原生执行电源请求。
- 支持并发任务；最后一个任务退出前不会进入睡眠。
- 任务结束后自动启动安全睡眠检查。
- Windows 从 S3 恢复 30 秒后自动重新启动安全睡眠检查。
- 支持人工请求安全睡眠。
- 拒绝在交互桌面或未批准电源请求仍活动时睡眠。
- 同时配置普通睡眠超时和 WoL 无人值守睡眠超时。
- 安装前保存电源、防火墙、OpenSSH 服务和请求覆盖状态，可完整回滚。
- WoL 等待期间持续重发 Magic Packet，减少网卡低功耗切换造成的丢包竞态。

## 工作原理

```text
Mac                                      Windows
 │                                          │
 ├─ Magic Packet ──────────────────────────►│ S3 / S5 → 启动
 │                                          │
 ├─ SSH + PowerShell 7 就绪检查 ──────────►│
 │                                          │
 ├─ 命令文本（SSH stdin）─────────────────►│ run.ps1
 │                                          ├─ 创建执行电源请求
 │                                          ├─ 启动前台子进程
 │◄──────────── 输出 + 原始退出码 ─────────┤
 │                                          ├─ 清除电源请求
 │                                          └─ 启动安全睡眠任务
 │                                                │
 │                                  无交互桌面、无未知请求
 │                                                ▼
 │                                               S3
```

安全睡眠任务每 5 秒复查一次，最长等待 60 秒；Windows 从 S3 恢复后会延迟 30 秒启动同一项检查。它只会忽略你在 Windows 配置中明确列出的请求覆盖；任何未知调用者都会继续阻止睡眠。

## 目录结构

```text
mac/                         Mac Zsh 控制端与安装脚本
windows/                     Windows PowerShell 7 调配层
tests/test_wol.zsh           Magic Packet 字节级测试
tests/power-state.ps1        S3/S5 集成测试辅助脚本
assets/readme-badge.png      README 项目徽章
```

## 前置条件

### Mac

- macOS，使用 `/bin/zsh`。
- 与 Windows 位于同一二层网络，或通过一条可广播 WoL 的直连网线连接。
- 系统自带 OpenSSH 客户端与 Perl。
- 已为 Windows 配置 SSH 密钥登录。

### Windows

- Windows 11，传统 S3 睡眠可用。
- PowerShell 7，可通过 `pwsh.exe` 启动。
- Windows OpenSSH Server 已安装并运行。
- OpenSSH 默认 Shell 已设置为 PowerShell 7。
- 有线网卡、驱动和 BIOS/UEFI 已启用 Magic Packet；如需 S5，还需启用关机 WoL/PCIe 唤醒。
- 安装阶段需要管理员权限。

可以在提升权限的 PowerShell 7 中设置 OpenSSH 默认 Shell：

```powershell
$pwsh = (Get-Command pwsh.exe).Source
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $pwsh -PropertyType String -Force
Set-Service -Name sshd -StartupType Automatic
Restart-Service sshd
```

## 快速开始

### 1. 获取代码

分别在 Mac 和 Windows 上克隆仓库，或使用你自己的安全方式同步项目目录：

```zsh
git clone https://github.com/yourpapayouknow/macwinpwrmgr.git
cd macwinpwrmgr
```

### 2. 配置 Windows 端

在 Windows PowerShell 7 中：

```powershell
Copy-Item .\windows\config.example.psd1 .\windows\config.psd1
```

编辑 `windows/config.psd1`：

```powershell
@{
    InstallRoot = 'C:\ProgramData\MacWinPwrMgr'
    SleepSeconds = 60
    UnattendSeconds = 60
    MacIp = '192.168.1.10'
    NicMac = 'AA-BB-CC-DD-EE-FF'
    FirewallRule = 'OpenSSH-Server-In-TCP'
    TaskName = 'MacWinPwrMgr-IdlePolicy'
    SleepTaskName = 'MacWinPwrMgr-SafeSleep'
    RequestOverrides = @()
}
```

- `MacIp`：允许访问 Windows SSH 的 Mac 地址。
- `NicMac`：Windows 有线网卡 MAC。
- `RequestOverrides`：可选。只添加你已经核实、愿意忽略的 `SYSTEM` 请求。

先做只读 WoL 检查：

```powershell
pwsh.exe -NoProfile -File .\windows\check-wol.ps1
```

然后在提升权限的 PowerShell 7 中安装：

```powershell
pwsh.exe -NoProfile -File .\windows\install.ps1
```

安装器会：

- 备份当前电源方案、防火墙范围和 `sshd` 启动类型。
- 安装脚本到 `C:\ProgramData\MacWinPwrMgr`。
- 把普通与无人值守睡眠超时设为配置值。
- 将 OpenSSH 入站规则限制为配置的 Mac IP。
- 注册启动策略任务和按需安全睡眠任务。

### 3. 配置 Mac 端

```zsh
cp mac/config.example.zsh mac/config.zsh
```

编辑 `mac/config.zsh`：

```zsh
typeset -gr WIN_HOST="windows"
typeset -gr WIN_MAC="AA:BB:CC:DD:EE:FF"
typeset -gr WIN_BCAST="192.168.1.255"
typeset -gr WIN_WOL_PORT="9"
typeset -gr WIN_IFACE="en0"
typeset -gr WIN_ROOT='C:\ProgramData\MacWinPwrMgr'
typeset -gr WIN_WAIT_SECS="120"
```

确保 `WIN_HOST` 与 `~/.ssh/config` 中的别名一致，例如：

```sshconfig
Host windows
    HostName 192.168.1.20
    User your-windows-user
    IdentityFile ~/.ssh/id_ed25519
```

安装 Mac 命令：

```zsh
/bin/zsh mac/install.zsh
```

默认入口为：

```text
~/.local/bin/winctl
```

## 使用

### 人工唤醒

```zsh
winctl wake
```

支持目标硬件允许的 S3 和 S5 WoL。命令会持续等待 SSH 与 PowerShell 7 就绪，而不是只判断端口开放。

### 执行 Windows 命令

```zsh
winctl run "Get-ComputerInfo | Select-Object WindowsProductName"
```

任务结束后，Windows 会自动排队执行安全睡眠检查。远程命令的退出码会原样返回给 Mac。

> [!WARNING]
> `winctl run` 接受任意 PowerShell 7 命令。只有可信用户才应持有对应 SSH 私钥；不要把私钥、`config.zsh` 或 `config.psd1` 提交到仓库。

### 查询状态

```zsh
winctl status
```

Windows 在线时会返回电源策略、网卡、WoL、活动请求和计划任务状态。离线时返回 `sleeping-or-offline`。

### 人工安全睡眠

```zsh
winctl sleep
```

检查通过时返回 `Queued: true`。如果存在交互桌面、受管任务或未知电源请求，则返回 `Queued: false` 和退出码 `3`，不会强制打断工作。

## 请求覆盖

先在 Windows 上查看真实调用者：

```powershell
powercfg.exe /requests
```

仅在明确理解影响后，才把请求加入 `RequestOverrides`：

```powershell
RequestOverrides = @(
    @{ Type = 'PROCESS'; Name = 'example.exe'; Request = 'SYSTEM' }
    @{ Type = 'DRIVER'; Name = 'Example Driver'; Request = 'SYSTEM' }
)
```

> [!CAUTION]
> 错误覆盖可能让 Windows 在音视频播放、文件传输或后台计算时睡眠。项目不会默认忽略任何请求。

## 验证

Mac 端语法与 Magic Packet 测试：

```zsh
/bin/zsh -n mac/*.zsh tests/test_wol.zsh
/bin/zsh tests/test_wol.zsh
```

Windows 端脚本可使用 PowerShell AST 做静态解析；真正的 S3/S5 验证会改变机器电源状态，执行前应确保可物理恢复。

## 卸载与回滚

Mac：

```zsh
/bin/zsh mac/uninstall.zsh
```

Windows（提升权限的 PowerShell 7）：

```powershell
pwsh.exe -NoProfile -File 'C:\ProgramData\MacWinPwrMgr\uninstall.ps1'
```

Windows 卸载脚本会恢复安装前保存的：

- 普通与无人值守睡眠超时。
- OpenSSH 防火墙远程地址。
- `sshd` 启动类型。
- 本项目管理的请求覆盖状态。
- 两项计划任务。

## 排错

### Magic Packet 无法唤醒

1. 确认使用有线网卡而不是 Wi-Fi。
2. 检查 `powercfg.exe /devicequery wake_armed`。
3. 检查网卡的 Magic Packet、关机 WoL 与低功耗链路设置。
4. 检查 BIOS/UEFI 的 PCIe/PME/WoL 设置。
5. 先验证 S3，再验证 S5。

### 能唤醒但 SSH 不就绪

```powershell
Get-Service sshd
Get-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell
```

确认防火墙规则名称与 `config.psd1` 一致，并确认 Mac IP 没有变化。

### Windows 拒绝睡眠

```powershell
powercfg.exe /requests
Get-ScheduledTask -TaskName 'MacWinPwrMgr-*'
```

拒绝通常意味着仍有交互桌面、受管命令或未知请求。优先处理真实活动，不要直接扩大覆盖列表。

## 技术依据

- [Microsoft：Wake on LAN 行为](https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/wake-on-lan-feature)
- [Microsoft：Windows OpenSSH](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
- [Microsoft：Power Requests](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Microsoft：无人值守睡眠超时](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/sleep-settings-sleep-unattended-idle-timeout)
- [Microsoft：SetSuspendState](https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-setsuspendstate)
