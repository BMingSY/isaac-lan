param([Parameter(Mandatory = $true)][int]$GameProcessId, [switch]$HostFixture, [switch]$AltPathFixture, [switch]$EndingsFixture, [switch]$HushFixture)
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId
if ($process.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
    throw 'Owned isolated game required.'
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LanProgressFixture {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr handle,IntPtr address,byte[] data,UIntPtr size,out UIntPtr read);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool WriteProcessMemory(IntPtr handle,IntPtr address,byte[] data,UIntPtr size,out UIntPtr written);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
$handle = [LanProgressFixture]::OpenProcess(0x0038, $false, $GameProcessId)
if ($handle -eq [IntPtr]::Zero) {
    throw 'Cannot open the owned fixture.'
}
try {
    $bytes = New-Object byte[] 4
    [UIntPtr]$count = [UIntPtr]::Zero
    $base = $process.MainModule.BaseAddress.ToInt64()
    if (-not [LanProgressFixture]::ReadProcessMemory($handle, [IntPtr]($base + 0x87169c), $bytes, [UIntPtr]([uint32]4), [ref]$count)) {
        throw 'Cannot read manager.'
    }
    [long]$progress = [BitConverter]::ToUInt32($bytes, 0) + 0x14
    [byte[]]$achievement = @(0); [int]$counter = 321
    if ($HostFixture) {
        $achievement[0] = 1; $counter = 98765
    }
    if (-not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x38 + 640), $achievement, [UIntPtr]([uint32]1), [ref]$count)) {
        throw 'Cannot set achievement fixture.'
    }
    $bytes = [BitConverter]::GetBytes($counter)
    if (-not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x2bc + 522 * 4), $bytes, [UIntPtr]([uint32]4), [ref]$count)) {
        throw 'Cannot set counter fixture.'
    }
    Write-Output "Fixture achievement640=$($achievement[0]) counter522=$counter"
    if ($EndingsFixture) {
        if ($HostFixture) {
            [byte[]]$routes = New-Object byte[] 642
            for ($i = 0; $i -lt $routes.Length; $i++) {
                $routes[$i] = 1
            }
            if (-not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x38), $routes, [UIntPtr]([uint32]$routes.Length), [ref]$count)) {
                throw 'Cannot set ending-route unlock fixture.'
            }
        } else {
            # Retain existing achievements consistent with the saved counters.
            # Clearing every flag in memory leaves the old persistent file and
            # native completion records able to restore them at the menu.
            [byte[]]$locked = @(0)
            if (-not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x38 + 407), $locked, [UIntPtr]([uint32]1), [ref]$count)) {
                throw 'Cannot lock the guest alternate-path entrance.'
            }
        }
        Write-Output "Fixture ending routes host_unlocked=$($HostFixture.IsPresent) guest_prior_progress_retained=True"
    }
    if ($HushFixture) {
        [byte[]]$voidUnlock = @([byte][int]$HostFixture.IsPresent)
        [int]$hushKills = 0
        if ($HostFixture) {
            $hushKills = 3
        }
        $bytes = [BitConverter]::GetBytes($hushKills)
        if (-not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x38 + 320), $voidUnlock, [UIntPtr]([uint32]1), [ref]$count) -or
            -not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x2bc + 158 * 4), $bytes, [UIntPtr]([uint32]4), [ref]$count)) {
            throw 'Cannot set Hush continuation fixture.'
        }
        Write-Output "Fixture achievement320=$($voidUnlock[0]) counter158=$hushKills"
    }
    if ($AltPathFixture) {
        # A Secret Exit is unlocked only on the host. Keep Dross locked on both
        # peers so the natural entrance reproducibly selects Downpour.
        [byte[]]$secretExit = @([byte][int]$HostFixture.IsPresent)
        [byte[]]$locked = @(0)
        if (-not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x38 + 407), $secretExit, [UIntPtr]([uint32]1), [ref]$count) -or
            -not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($progress + 0x38 + 412), $locked, [UIntPtr]([uint32]1), [ref]$count)) {
            throw 'Cannot set alternate-path unlock fixture.'
        }
        Write-Output "Fixture achievement407=$($secretExit[0]) achievement412=0"
    }
} finally {
    [void][LanProgressFixture]::CloseHandle($handle)
}
