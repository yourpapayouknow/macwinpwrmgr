# 执行经用户批准的 Windows S3 或 S5 集成测试。

param(
    [Parameter(Mandatory)][ValidateSet('Sleep', 'Shutdown')][string]$Mode,
    [ValidateRange(1, 30)][int]$DelaySeconds = 5
)

. (Join-Path $PSScriptRoot 'head.ps1')

if (-not (Tst-Admin)) { throw 'power-state.ps1 requires gsudo/elevated PowerShell 7' }
Start-Sleep -Seconds $DelaySeconds

if ($Mode -eq 'Sleep') {
    if (-not [MacWinPwrMgr.PwrApi]::SetSuspendState($false, $false, $false)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    exit 0
}

Stop-Computer -Force
