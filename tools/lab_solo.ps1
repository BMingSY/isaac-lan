param([Parameter(Mandatory = $true)][int]$GameProcessId, [ValidateSet("SaveExit", "Continue")][string]$Action)
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
    [long]$manager = [BitConverter]::ToUInt32($bytes, 0)
    function Write-Field([int]$offset, [byte[]]$value) {
        [UIntPtr]$written = [UIntPtr]::Zero
        if (-not [LanProgressFixture]::WriteProcessMemory($handle, [IntPtr]($manager + $offset), $value, [UIntPtr]([uint32]$value.Length), [ref]$written) -or $written.ToUInt64() -ne $value.Length) {
            throw 'Native fixture write failed.'
        }
    }
    if ($Action -eq 'SaveExit') {
        Write-Field 0x4b284 ([byte[]]@(1))
        Write-Field 0x4b28c ([BitConverter]::GetBytes([int]2))
        [byte[]]$color = @()
        1..4 | ForEach-Object { $color += [BitConverter]::GetBytes([single]1) }
        $color += [BitConverter]::GetBytes([int]0)
        Write-Field 0x4b290 $color
        Write-Field 0x4b288 ([byte[]]@(1))
    } else {
        Write-Field 0x4b131 ([byte[]]@(1, 0))
        Write-Field 0x4b19c ([byte[]]@(0))
        foreach ($offset in @(0x4b1c0, 0x4b1c4, 0x4b1cc)) {
            Write-Field $offset ([BitConverter]::GetBytes([int]0))
        }
        Write-Field 0x4b1c8 ([byte[]]@(0))
        Write-Field 0x4b130 ([byte[]]@(1))
    }
    Write-Output "Queued isolated native solo $Action"
} finally {
    [void][LanProgressFixture]::CloseHandle($handle)
}
