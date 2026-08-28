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
