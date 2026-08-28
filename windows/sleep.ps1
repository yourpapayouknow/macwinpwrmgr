# 检查安全边界并通过 SYSTEM 任务请求 Windows 进入 S3。

param([switch]$Internal)

. (Join-Path $PSScriptRoot 'head.ps1')

if ($Internal) {
    if (-not (Tst-Admin)) { throw 'internal sleep requires the SYSTEM task' }
    foreach ($attempt in 1..12) {
        Start-Sleep -Seconds 5
        if (Tst-UsrDesk) { exit 3 }
        if (@(Get-ActRq).Count -gt 0) { continue }
        if (-not [MacWinPwrMgr.PwrApi]::SetSuspendState($false, $false, $false)) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        exit 0
    }
    exit 3
}

$seconds = Get-SlpSec
$unattend = Get-UatSec
if ($seconds -le 0 -or $seconds -gt $script:Cfg.SleepSeconds -or $unattend -le 0 -or $unattend -gt $script:Cfg.UnattendSeconds) {
    [Console]::Error.WriteLine("safe sleep is not armed; configured AC timeout is ${seconds}s")
    exit 2
}
$active = @(Get-ActRq)
$desktop = Tst-UsrDesk
if ($desktop -or $active.Count -gt 0) {
    [ordered]@{
        Armed = $true
        Queued = $false
        InteractiveDesktop = $desktop
        ActiveRequests = $active
        Message = 'Safe sleep refused because interactive work or an unapproved power request is active.'
    } | ConvertTo-Json -Depth 4
    exit 3
}
Start-PwrSlp
[ordered]@{
    Armed = $true
    SleepSeconds = $seconds
    UnattendSeconds = $unattend
    Forced = $false
    Queued = $true
    RetrySeconds = 60
    PowerRequests = Get-PwrRq
    RequestOverrides = Get-PwrOvr
    Message = 'Windows accepted the safe native S3 sleep request.'
} | ConvertTo-Json -Depth 4
