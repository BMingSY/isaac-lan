param([Parameter(Mandatory = $true)][int]$GameProcessId, [switch]$HostFixture, [switch]$AltPathFixture, [switch]$EndingsFixture, [switch]$HushFixture, [switch]$AscentFixture)
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId
if ($process.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
    throw 'Owned isolated game required.'
}
# Fixtures are prepared on disk before launch. Editing character unlocks here
# leaves native menu counts stale and can overflow its rendering buffer.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LanProgressFixture {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr handle,IntPtr address,byte[] data,UIntPtr size,out UIntPtr read);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
$handle = [LanProgressFixture]::OpenProcess(0x0010, $false, $GameProcessId)
if ($handle -eq [IntPtr]::Zero) {
    throw 'Cannot read the owned fixture.'
}
function Read-Bytes([long]$Address, [uint32]$Length) {
    $bytes = New-Object byte[] $Length
    [UIntPtr]$count = [UIntPtr]::Zero
    if (-not [LanProgressFixture]::ReadProcessMemory($handle, [IntPtr]$Address, $bytes, [UIntPtr]$Length, [ref]$count) -or $count.ToUInt64() -ne $Length) {
        throw 'Cannot read complete progress fixture.'
    }
    return , $bytes
}
function Assert-Achievement([int]$Identifier, [byte]$Expected) {
    if ((Read-Bytes ($progress + 0x38 + $Identifier) 1)[0] -ne $Expected) {
        throw "Startup achievement fixture $Identifier differs."
    }
}
function Assert-Counter([int]$Identifier, [int]$Expected) {
    if ([BitConverter]::ToInt32((Read-Bytes ($progress + 0x2bc + $Identifier * 4) 4), 0) -ne $Expected) {
        throw "Startup counter fixture $Identifier differs."
    }
}
try {
    $base = $process.MainModule.BaseAddress.ToInt64()
    [long]$progress = [BitConverter]::ToUInt32((Read-Bytes ($base + 0x87169c) 4), 0) + 0x14
    [byte]$achievement = [int]$HostFixture.IsPresent
    [int]$counter = 321
    if ($HostFixture) {
        $counter = 98765
    }
    Assert-Achievement 640 $achievement
    Assert-Counter 522 $counter
    Write-Output "Fixture achievement640=$achievement counter522=$counter verified_at_startup=True"
    if ($AscentFixture -and $HostFixture) {
        foreach ($id in @(4, 57, 635)) {
            Assert-Achievement $id 1
        }
        Write-Output 'Fixture Ascent prerequisites achievement4=1 achievement57=1 achievement635=1'
    }
    if ($EndingsFixture) {
        if ($HostFixture) {
            $flags = Read-Bytes ($progress + 0x38) 642
            for ($i = 0; $i -lt $flags.Length; $i++) {
                $expected = 1
                if ($AltPathFixture -and $i -eq 412) {
                    $expected = 0
                }
                if ($flags[$i] -ne $expected) {
                    throw "Startup ending-route fixture $i differs."
                }
            }
        } else {
            Assert-Achievement 407 0
        }
        Write-Output "Fixture ending routes host_unlocked=$($HostFixture.IsPresent) guest_prior_progress_retained=True"
    }
    if ($HushFixture) {
        [int]$hushKills = 0
        if ($HostFixture) {
            $hushKills = 3
        }
        Assert-Achievement 320 $achievement
        Assert-Counter 158 $hushKills
        Write-Output "Fixture achievement320=$achievement counter158=$hushKills"
    }
    if ($AltPathFixture) {
        Assert-Achievement 407 $achievement
        Assert-Achievement 412 0
        Write-Output "Fixture achievement407=$achievement achievement412=0"
    }
} finally {
    [void][LanProgressFixture]::CloseHandle($handle)
}
