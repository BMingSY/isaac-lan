param([Parameter(Mandatory = $true)][int]$GameProcessId, [Parameter(Mandatory = $true)][string]$OutputFile)
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId
if ($process.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
    throw 'Owned isolated game required.'
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LanExitRead {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr handle,uint timeout);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
$handle = [LanExitRead]::OpenProcess(0x101000, $false, $GameProcessId)
if ($handle -eq [IntPtr]::Zero) {
    throw 'Cannot observe the owned isolated game.'
}
try {
    if ([LanExitRead]::WaitForSingleObject($handle, [uint32]::MaxValue) -ne 0) {
        throw 'Cannot wait for the owned isolated game.'
    }
    [uint32]$code = 0
    if (-not [LanExitRead]::GetExitCodeProcess($handle, [ref]$code)) {
        throw 'Cannot read the native exit code.'
    }
    $signed = [BitConverter]::ToInt32([BitConverter]::GetBytes($code), 0)
    $result = @{ pid = $GameProcessId; exit_code = $signed; exit_hex = ('{0:X8}' -f $code) } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($OutputFile, $result, [Text.UTF8Encoding]::new($false))
} finally {
    [void][LanExitRead]::CloseHandle($handle)
}
