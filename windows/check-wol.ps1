# 只读验证目标 Windows 网卡与睡眠能力。

. (Join-Path $PSScriptRoot 'head.ps1')

$nic = Get-NetAdapter -Physical | Where-Object MacAddress -eq $script:Cfg.NicMac
if ($null -eq $nic) { throw "NIC not found: $($script:Cfg.NicMac)" }
$props = $nic | Get-NetAdapterAdvancedProperty | Where-Object {
    $_.RegistryKeyword -match 'Wake|S5|Shutdown'
}
[ordered]@{
    Nic = $nic | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed
    Power = $nic | Get-NetAdapterPowerManagement | Select-Object AllowComputerToTurnOffDevice, WakeOnMagicPacket, WakeOnPattern
    Advanced = $props | Select-Object DisplayName, DisplayValue, RegistryKeyword, RegistryValue
    WakeArmed = @(& $script:PwrCfg /devicequery wake_armed)
    SleepStates = @(& $script:PwrCfg /a)
} | ConvertTo-Json -Depth 5

