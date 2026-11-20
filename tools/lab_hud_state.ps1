param([Parameter(Mandatory = $true)][int]$GameProcessId, [int]$WatchSeconds = 0, [string]$OutputFile = '')
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId
. (Join-Path $PSScriptRoot 'lab_observations.ps1')
$layout = Get-LabObservationLayout $process
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LanHudRead {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr handle,IntPtr address,byte[] data,UIntPtr size,out UIntPtr read);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
$handle = [LanHudRead]::OpenProcess(0x0010, $false, $GameProcessId)
if ($handle -eq [IntPtr]::Zero) {
    throw 'Cannot read the owned fixture.'
}
function Read32([long]$address) {
    $bytes = New-Object byte[] 4
    [UIntPtr]$count = [UIntPtr]::Zero
    if (-not [LanHudRead]::ReadProcessMemory($handle, [IntPtr]$address, $bytes, [UIntPtr]([uint32]4), [ref]$count)) {
        throw 'Cannot read HUD state.'
    }
    return [BitConverter]::ToUInt32($bytes, 0)
}
function ReadHud {
    $base = $process.MainModule.BaseAddress.ToInt64()
    $game = Read32 ($base + $layout.game)
    $stats = $game + $layout.hud + $layout.stats
    $entries = @()
    for ($i = 0; $i -lt 2; $i++) {
        $player = Read32 ($stats + 0x114 + $i * 0xcc)
        if ($player -ne 0) {
            $damageBits = Read32 ($stats + 0x140 + $i * 0xcc)
            $entries += [ordered]@{column = $i; controller = (Read32 ($player + $layout.controller)); damage = [BitConverter]::ToSingle([BitConverter]::GetBytes([uint32]$damageBits), 0) }
        }
    }
    $primary = Read32 ($game + $layout.hud)
    $players = @(); $history = @()
    for ($i = 0; $i -lt 8; $i++) {
        $part = $game + $layout.hud + $i * $layout.partBytes; $p = Read32 $part
        if ($p) {
            $hearts = 0
            for ($j = 0; $j -lt 24; $j++) {
                if ((Read32 ($part + 0x10 + $j * 0x10)) -band 255) {
                    $hearts++
                }
            }
            $players += [ordered]@{slot = $i; controller = (Read32 ($p + $layout.controller)); hearts = $hearts; max_hearts = (Read32 ($p + $layout.maxHearts)); visible = ((Read32 ($p + $layout.visible)) -band 255) }
        }
    }
    for ($i = 0; $i -lt 2; $i++) {
        $p = Read32 ($game + $layout.hud + $layout.history + $i * 0x14)
        if ($p) {
            $history += [ordered]@{column = $i; controller = (Read32 ($p + $layout.controller)) }
        }
    }
    return [ordered]@{entries = @($entries); players = @($players); history = @($history); primary_controller = $(if ($primary) {
                Read32 ($primary + $layout.controller)
            } else {
                -1
            }); stage = (Read32 $game); stage_transition = (Read32 ($game + $layout.stageTransition))
    }
}
try {
    if ($WatchSeconds -eq 0) {
        ReadHud | ConvertTo-Json -Depth 4
    } else {
        if ($WatchSeconds -lt 1 -or $WatchSeconds -gt 90 -or -not $OutputFile) {
            throw 'Watch requires an output file and 1..90 seconds.'
        }
        $writer = New-Object System.IO.StreamWriter($OutputFile, $false, (New-Object System.Text.UTF8Encoding($false)))
        try {
            $clock = [Diagnostics.Stopwatch]::StartNew(); $seenFloor = $false
            while ($clock.Elapsed.TotalSeconds -lt $WatchSeconds) {
                $sample = ReadHud; $sample['elapsed'] = $clock.Elapsed.TotalSeconds
                $writer.WriteLine(($sample | ConvertTo-Json -Depth 4 -Compress)); $writer.Flush()
                if ($sample.stage_transition -ne 0) {
                    $seenFloor = $true
                } elseif ($seenFloor) {
                    break
                }
                Start-Sleep -Milliseconds 100
            }
        } finally {
            $writer.Dispose()
        }
    }
} finally {
    [void][LanHudRead]::CloseHandle($handle)
}
