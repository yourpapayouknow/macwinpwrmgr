# 应用 Windows 原生交流空闲睡眠策略。

param(
    [ValidateRange(1, 86400)][int]$SleepSeconds = 60,
    [ValidateRange(1, 86400)][int]$UnattendSeconds = 60
)

. (Join-Path $PSScriptRoot 'head.ps1')

if (-not (Tst-Admin)) { throw 'idle.ps1 requires an elevated PowerShell 7 process' }
Set-SlpSec -Seconds $SleepSeconds
Set-UatSec -Seconds $UnattendSeconds
[ordered]@{
    Applied = $true
    SleepSeconds = Get-SlpSec
    UnattendSeconds = Get-UatSec
} | ConvertTo-Json
