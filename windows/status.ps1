# 输出 Windows 调配层、电源与 WoL 状态。

. (Join-Path $PSScriptRoot 'head.ps1')

$nic = Get-NetAdapter -Physical | Where-Object MacAddress -eq $script:Cfg.NicMac
[ordered]@{
    State = 'awake'
    ComputerName = $env:COMPUTERNAME
    PowerShell = $PSVersionTable.PSVersion.ToString()
    SleepSeconds = Get-SlpSec
    UnattendSeconds = Get-UatSec
    Nic = $nic | Select-Object Name, Status, MacAddress, LinkSpeed
    WakeArmed = @(& $script:PwrCfg /devicequery wake_armed)
    SleepTask = (Get-ScheduledTask -TaskName $script:Cfg.SleepTaskName -ErrorAction SilentlyContinue).State.ToString()
    PowerRequests = Get-PwrRq
    RequestOverrides = Get-PwrOvr
} | ConvertTo-Json -Depth 4
