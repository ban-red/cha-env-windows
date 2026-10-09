# SPDX-License-Identifier: GPL-2.0-or-later
# The first logon after Setup: make the VM suit a stream, set viogpu3d (the
# 3D display driver, from UTM's guest tools) to install at the next logon,
# then write done.txt on the setup floppy and shut down. cha-windows reads
# done.txt to know Setup finished, then boots the disk with 3D on.
$ErrorActionPreference = 'Stop'
Start-Transcript -Path 'C:\cha-setup.log' -Append

try {
    # Log in on every boot: the portal already decided who may see this VM.
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty $winlogon AutoAdminLogon '1'
    Set-ItemProperty $winlogon DefaultUserName '@@USER@@'
    Set-ItemProperty $winlogon DefaultPassword '@@PASSWORD@@'
    Remove-ItemProperty $winlogon AutoLogonCount -ErrorAction SilentlyContinue

    # A container can be stopped mid-boot. Windows would then open Recovery,
    # a screen that waits for a choice, on the next start; boot normally.
    bcdedit.exe /set '{default}' recoveryenabled No
    bcdedit.exe /set '{default}' bootstatuspolicy IgnoreAllFailures
    # Crash dumps for debugging the display driver: C:\Windows\Minidump.
    $crash = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    Set-ItemProperty $crash CrashDumpEnabled 3
    Set-ItemProperty $crash AutoReboot 0

    # Stopping the environment presses the VM's power button, and the launcher
    # waits 75 s before it pulls the plug. Close apps instead of waiting on
    # them (with Edge open, Windows 26H2 once took over 25 s).
    $desktop = 'HKCU:\Control Panel\Desktop'
    Set-ItemProperty $desktop AutoEndTasks '1'
    Set-ItemProperty $desktop WaitToKillAppTimeout '2000'
    Set-ItemProperty $desktop HungAppTimeout '2000'
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' WaitToKillServiceTimeout '3000'

    # A streamed VM never sleeps, blanks or hibernates on its own.
    powercfg.exe /hibernate off
    powercfg.exe /change monitor-timeout-ac 0
    powercfg.exe /change standby-timeout-ac 0

    # Installed at the next logon, not now: binding viogpu3d during this boot
    # would move Setup's display (plain virtio-vga, no 3D) onto it, which
    # hangs. The next boot has the 3D device, and the guest tools' drive is
    # gone, so the driver is copied to C:\cha first.
    $inf = Get-PSDrive -PSProvider FileSystem |
        ForEach-Object { "$($_.Root)Drivers\viogpu3d\w11\amd64\viogpu3d.inf" } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $inf) { throw 'viogpu3d.inf not found on any drive (UTM guest tools)' }
    New-Item -ItemType Directory -Force 'C:\cha\viogpu3d' | Out-Null
    Copy-Item "$(Split-Path $inf)\*" 'C:\cha\viogpu3d' -Recurse -Force
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' ChaDisplayDriver `
        'cmd.exe /c pnputil.exe /add-driver C:\cha\viogpu3d\viogpu3d.inf /install > C:\cha\viogpu3d-install.log 2>&1'

    # The virtio keyboard and tablet the next boots have (cha-windows): they
    # take over input from the USB pair once this driver binds them.
    $inputDir = Join-Path (Split-Path (Split-Path (Split-Path (Split-Path $inf)))) 'vioinput\w11\amd64'
    if (-not (Test-Path "$inputDir\vioinput.inf")) { throw "vioinput.inf not found beside viogpu3d ($inputDir)" }
    New-Item -ItemType Directory -Force 'C:\cha\vioinput' | Out-Null
    Copy-Item "$inputDir\*" 'C:\cha\vioinput' -Recurse -Force
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' ChaInputDriver `
        'cmd.exe /c pnputil.exe /add-driver C:\cha\vioinput\vioinput.inf /install > C:\cha\vioinput-install.log 2>&1'

    Set-Content -Path 'A:\done.txt' -Value "Windows set up $(Get-Date -Format o); driver $inf"
    Stop-Transcript
    shutdown.exe /s /t 0 /c 'Cha: Windows is set up'
} catch {
    $_ | Out-String | Add-Content 'C:\cha-setup.log'
    Stop-Transcript
    throw
}
