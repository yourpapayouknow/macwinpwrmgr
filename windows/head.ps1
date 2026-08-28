# 集中定义 Windows 端依赖、电源 API 与共享设置函数。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot 'config.psd1'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'config missing; copy config.example.psd1 to config.psd1 and edit it first'
}
$script:Cfg = Import-PowerShellDataFile -Path $configPath
$script:PwrCfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
$script:UatGuid = '7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'

if (-not ('MacWinPwrMgr.PwrApi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace MacWinPwrMgr {
    public static class PwrApi {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct ReasonContext {
            public UInt32 Version;
            public UInt32 Flags;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string ReasonString;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr PowerCreateRequest(ref ReasonContext context);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool PowerSetRequest(IntPtr handle, int requestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool PowerClearRequest(IntPtr handle, int requestType);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("powrprof.dll", SetLastError = true)]
        public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
    }
}
'@
}

# 检查当前 PowerShell 是否已提升。
function Tst-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = [Security.Principal.WindowsPrincipal]::new($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 读取当前方案的交流睡眠秒数。
function Get-SlpSec {
    $text = (& $script:PwrCfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'powercfg query failed' }
    $hex = [regex]::Matches($text, '0x[0-9a-fA-F]{8}')
    if ($hex.Count -lt 2) { throw 'unable to parse standby timeout' }
    return [Convert]::ToInt32($hex[$hex.Count - 2].Value.Substring(2), 16)
}

# 设置当前方案的交流睡眠秒数。
function Set-SlpSec {
    param([Parameter(Mandatory)][ValidateRange(1, 86400)][int]$Seconds)
    & $script:PwrCfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE $Seconds | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'powercfg setacvalueindex failed' }
    & $script:PwrCfg /setactive SCHEME_CURRENT | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'powercfg setactive failed' }
}

# 读取当前方案的交流无人值守睡眠秒数。
function Get-UatSec {
    $text = (& $script:PwrCfg /qh SCHEME_CURRENT SUB_SLEEP $script:UatGuid) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'powercfg hidden query failed' }
    $hex = [regex]::Matches($text, '0x[0-9a-fA-F]{8}')
    if ($hex.Count -lt 2) { throw 'unable to parse unattended timeout' }
    return [Convert]::ToInt32($hex[$hex.Count - 2].Value.Substring(2), 16)
}

# 设置当前方案的交流无人值守睡眠秒数。
function Set-UatSec {
    param([Parameter(Mandatory)][ValidateRange(1, 86400)][int]$Seconds)
    & $script:PwrCfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP $script:UatGuid $Seconds | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'powercfg unattended setacvalueindex failed' }
    & $script:PwrCfg /setactive SCHEME_CURRENT | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'powercfg setactive failed' }
}

# 创建并设置执行所需的原生电源请求。
function New-PwrRq {
    param([Parameter(Mandatory)][string]$Reason)
    $ctx = [MacWinPwrMgr.PwrApi+ReasonContext]::new()
    $ctx.Version = 0
    $ctx.Flags = 1
    $ctx.ReasonString = $Reason
    $handle = [MacWinPwrMgr.PwrApi]::PowerCreateRequest([ref]$ctx)
    if ($handle -eq [IntPtr](-1)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    if (-not [MacWinPwrMgr.PwrApi]::PowerSetRequest($handle, 3)) {
        [void][MacWinPwrMgr.PwrApi]::CloseHandle($handle)
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    return $handle
}

# 清除执行请求并关闭原生句柄。
function Clr-PwrRq {
    param([Parameter(Mandatory)][IntPtr]$Handle)
    if (-not [MacWinPwrMgr.PwrApi]::PowerClearRequest($Handle, 3)) {
        Write-Warning 'PowerClearRequest failed'
    }
    if (-not [MacWinPwrMgr.PwrApi]::CloseHandle($Handle)) {
        Write-Warning 'CloseHandle failed'
    }
}

# 读取 Windows 当前电源请求文本。
function Get-PwrRq {
    return @(& $script:PwrCfg /requests)
}

# 读取 Windows 当前电源请求覆盖文本。
function Get-PwrOvr {
    return @(& $script:PwrCfg /requestsoverride)
}

# 判断指定电源请求覆盖是否已存在。
function Tst-PwrOvr {
    param([Parameter(Mandatory)][hashtable]$Override)
    $line = '^\s*' + [regex]::Escape($Override.Name) + '\s+' + [regex]::Escape($Override.Request) + '\s*$'
    return [bool](Get-PwrOvr | Select-String -Pattern $line -Quiet)
}

# 设置指定 Windows 电源请求覆盖。
function Set-PwrOvr {
    param([Parameter(Mandatory)][hashtable]$Override)
    & $script:PwrCfg /requestsoverride $Override.Type $Override.Name $Override.Request | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg requestsoverride failed: $($Override.Name)" }
}

# 清除指定 Windows 电源请求覆盖。
function Clr-PwrOvr {
    param([Parameter(Mandatory)][hashtable]$Override)
    & $script:PwrCfg /requestsoverride $Override.Type $Override.Name | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg requestsoverride clear failed: $($Override.Name)" }
}

# 生成托管覆盖项的安装前状态。
function Get-OvrBkp {
    return @($script:Cfg.RequestOverrides | ForEach-Object {
        [ordered]@{
            Type = $_.Type
            Name = $_.Name
            Request = $_.Request
            Existing = Tst-PwrOvr -Override $_
        }
    })
}

# 读取未被批准覆盖的活动电源请求调用者。
function Get-ActRq {
    $section = ''
    $active = foreach ($line in Get-PwrRq) {
        if ($line -match '^\s*([A-Z]+):\s*$') {
            $section = $Matches[1]
            continue
        }
        if ($line -notmatch '^\s*\[(PROCESS|DRIVER|SERVICE)\]\s+(.+?)\s*$') { continue }
        $type = $Matches[1]
        $caller = $Matches[2]
        $ignored = $false
        if ($section -eq 'SYSTEM') {
            foreach ($override in @($script:Cfg.RequestOverrides | Where-Object { $_.Type -eq $type -and $_.Request -eq 'SYSTEM' })) {
                if ($type -eq 'PROCESS' -and [IO.Path]::GetFileName($caller) -eq $override.Name) { $ignored = $true }
                if ($type -ne 'PROCESS' -and ($caller -eq $override.Name -or $caller.StartsWith("$($override.Name) ("))) { $ignored = $true }
            }
        }
        if (-not $ignored) { "[$type] $caller" }
    }
    return @($active)
}

# 判断是否存在应保留唤醒状态的交互桌面。
function Tst-UsrDesk {
    return [bool](Get-Process explorer -ErrorAction SilentlyContinue)
}

# 启动非强制的原生 S3 SYSTEM 任务。
function Start-PwrSlp {
    Start-ScheduledTask -TaskName $script:Cfg.SleepTaskName
}
