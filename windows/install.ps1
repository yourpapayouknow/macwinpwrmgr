# 安装 Windows 调配脚本、原生空闲策略、任务与 SSH 防火墙限制。

param([string]$SourceRoot = $PSScriptRoot)

. (Join-Path $SourceRoot 'head.ps1')

if (-not (Tst-Admin)) { throw 'install.ps1 requires gsudo/elevated PowerShell 7' }

$root = $script:Cfg.InstallRoot
$backupPath = Join-Path $root 'install-backup.json'
$rule = Get-NetFirewallRule -Name $script:Cfg.FirewallRule
$remoteAddress = @($rule | Get-NetFirewallAddressFilter | Select-Object -ExpandProperty RemoteAddress)
$service = Get-Service sshd

New-Item -ItemType Directory -Path $root -Force | Out-Null
if (-not (Test-Path $backupPath)) {
    [ordered]@{
        SleepSeconds = Get-SlpSec
        UnattendSeconds = Get-UatSec
        FirewallRemoteAddress = $remoteAddress
        SshdStartType = $service.StartType.ToString()
        RequestOverrides = Get-OvrBkp
    } | ConvertTo-Json -Depth 3 | Set-Content -Path $backupPath -Encoding utf8NoBOM
} else {
    $backup = Get-Content $backupPath -Raw | ConvertFrom-Json
    $changed = $false
    if (-not ($backup.PSObject.Properties.Name -contains 'RequestOverrides')) {
        $backup | Add-Member -NotePropertyName RequestOverrides -NotePropertyValue (Get-OvrBkp)
        $changed = $true
    }
    if (-not ($backup.PSObject.Properties.Name -contains 'UnattendSeconds')) {
        $backup | Add-Member -NotePropertyName UnattendSeconds -NotePropertyValue (Get-UatSec)
        $changed = $true
    }
    if ($changed) { $backup | ConvertTo-Json -Depth 4 | Set-Content -Path $backupPath -Encoding utf8NoBOM }
}

$files = 'config.psd1', 'head.ps1', 'run.ps1', 'idle.ps1', 'status.ps1', 'sleep.ps1', 'check-wol.ps1', 'uninstall.ps1'
foreach ($file in $files) {
    Copy-Item -Path (Join-Path $SourceRoot $file) -Destination (Join-Path $root $file) -Force
}

Set-SlpSec -Seconds $script:Cfg.SleepSeconds
Set-UatSec -Seconds $script:Cfg.UnattendSeconds
foreach ($override in $script:Cfg.RequestOverrides) { Set-PwrOvr -Override $override }
Set-NetFirewallRule -Name $script:Cfg.FirewallRule -RemoteAddress $script:Cfg.MacIp
Set-Service -Name sshd -StartupType Automatic
if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }

$pwsh = (Get-Process -Id $PID).Path
$action = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoLogo -NoProfile -NonInteractive -File `"$root\idle.ps1`" -SleepSeconds $($script:Cfg.SleepSeconds) -UnattendSeconds $($script:Cfg.UnattendSeconds)" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $script:Cfg.TaskName -Action $action -Trigger $trigger -Principal $principal -Description 'Reapply MacWinPwrMgr native idle sleep policy at startup.' -Force | Out-Null
$sleepAction = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoLogo -NoProfile -NonInteractive -File `"$root\sleep.ps1`" -Internal" -WorkingDirectory $root
Register-ScheduledTask -TaskName $script:Cfg.SleepTaskName -Action $sleepAction -Principal $principal -Description 'Run a MacWinPwrMgr safe S3 request on demand.' -Force | Out-Null

[ordered]@{
    Installed = $true
    InstallRoot = $root
    SleepSeconds = Get-SlpSec
    UnattendSeconds = Get-UatSec
    RequestOverrides = Get-PwrOvr
    FirewallRemoteAddress = @((Get-NetFirewallRule -Name $script:Cfg.FirewallRule | Get-NetFirewallAddressFilter).RemoteAddress)
    Task = (Get-ScheduledTask -TaskName $script:Cfg.TaskName).State.ToString()
    SleepTask = (Get-ScheduledTask -TaskName $script:Cfg.SleepTaskName).State.ToString()
    Sshd = (Get-Service sshd).Status.ToString()
} | ConvertTo-Json -Depth 3
