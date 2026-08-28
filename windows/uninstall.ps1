# 恢复安装前的 Windows 电源、防火墙与服务设置。

. (Join-Path $PSScriptRoot 'head.ps1')

if (-not (Tst-Admin)) { throw 'uninstall.ps1 requires gsudo/elevated PowerShell 7' }
$backupPath = Join-Path $script:Cfg.InstallRoot 'install-backup.json'
if (-not (Test-Path $backupPath)) { throw "backup not found: $backupPath" }
$backup = Get-Content $backupPath -Raw | ConvertFrom-Json

if ([int]$backup.SleepSeconds -gt 0) {
    Set-SlpSec -Seconds ([int]$backup.SleepSeconds)
} else {
    & $script:PwrCfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0 | Out-Null
    & $script:PwrCfg /setactive SCHEME_CURRENT | Out-Null
}
if ($backup.PSObject.Properties.Name -contains 'UnattendSeconds') {
    if ([int]$backup.UnattendSeconds -gt 0) {
        Set-UatSec -Seconds ([int]$backup.UnattendSeconds)
    } else {
        & $script:PwrCfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP $script:UatGuid 0 | Out-Null
        & $script:PwrCfg /setactive SCHEME_CURRENT | Out-Null
    }
}
foreach ($override in $script:Cfg.RequestOverrides) { Clr-PwrOvr -Override $override }
if ($backup.PSObject.Properties.Name -contains 'RequestOverrides') {
    foreach ($override in @($backup.RequestOverrides | Where-Object Existing)) {
        Set-PwrOvr -Override @{
            Type = $override.Type
            Name = $override.Name
            Request = $override.Request
        }
    }
}
Set-NetFirewallRule -Name $script:Cfg.FirewallRule -RemoteAddress @($backup.FirewallRemoteAddress)
Set-Service -Name sshd -StartupType $backup.SshdStartType
Unregister-ScheduledTask -TaskName $script:Cfg.TaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $script:Cfg.SleepTaskName -Confirm:$false -ErrorAction SilentlyContinue

[ordered]@{
    Restored = $true
    SleepSeconds = Get-SlpSec
    UnattendSeconds = Get-UatSec
    RequestOverrides = Get-PwrOvr
    FilesRetainedAt = $script:Cfg.InstallRoot
} | ConvertTo-Json
