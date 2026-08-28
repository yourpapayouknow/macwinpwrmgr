# 在原生 Windows 电源请求保护下运行一个前台 PowerShell 7 命令。

. (Join-Path $PSScriptRoot 'head.ps1')

$cmd = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($cmd)) {
    [Console]::Error.WriteLine('stdin must contain one PowerShell command string')
    exit 2
}

$handle = [IntPtr]::Zero
$exitCode = 1
try {
    $handle = New-PwrRq -Reason 'MacWinPwrMgr managed command'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $start.UseShellExecute = $false
    [void]$start.ArgumentList.Add('-NoLogo')
    [void]$start.ArgumentList.Add('-NoProfile')
    [void]$start.ArgumentList.Add('-NonInteractive')
    [void]$start.ArgumentList.Add('-EncodedCommand')
    [void]$start.ArgumentList.Add($encoded)
    $child = [Diagnostics.Process]::Start($start)
    $child.WaitForExit()
    $exitCode = $child.ExitCode
}
finally {
    if ($handle -ne [IntPtr]::Zero) { Clr-PwrRq -Handle $handle }
    Start-PwrSlp
}
exit $exitCode
