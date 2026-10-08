param([Parameter(Mandatory = $true)][int]$GameProcessId, [Parameter(Mandatory = $true)][string]$OutputDirectory, [int]$Seconds = 15, [switch]$BackgroundCapture)
$ErrorActionPreference = 'Stop'
$p = Get-Process -Id $GameProcessId
if ($p.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
    throw 'Owned isolated game required.'
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @'
using System;using System.IO;using System.Diagnostics;using System.Drawing;using System.Drawing.Imaging;using System.Runtime.InteropServices;
public static class LanVisualSeries {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int L,T,R,B; }
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int cmd);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool attach);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h,IntPtr p,byte[] b,UIntPtr n,out UIntPtr read);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 static uint Read(IntPtr h,long p) { byte[] b=new byte[4];UIntPtr n;if(!ReadProcessMemory(h,new IntPtr(p),b,new UIntPtr(4),out n))throw new Exception("Memory read failed");return BitConverter.ToUInt32(b,0); }
 public static void Capture(int pid,string output,int seconds,bool background) {
  var p=Process.GetProcessById(pid);var handle=OpenProcess(0x10,false,pid);
  try { long game=Read(handle,p.MainModule.BaseAddress.ToInt64()+0x871678);Rect r;GetWindowRect(p.MainWindowHandle,out r);
   using(var b=new Bitmap(r.R-r.L,r.B-r.T))using(var g=Graphics.FromImage(b))using(var log=new StreamWriter(Path.Combine(output,"frames.csv"))) {
    log.WriteLine("sample,tick,room,r,g,b,color_r,color_g,color_b,color_a,brightness,contrast");var watch=Stopwatch.StartNew();int sample=0;
    while(watch.Elapsed.TotalSeconds<seconds) {
     if(!background && GetForegroundWindow()!=p.MainWindowHandle)throw new Exception("Owned fixture lost foreground; capture is inconclusive");
     if(background) { var dc=g.GetHdc();try { if(!PrintWindow(p.MainWindowHandle,dc,2))throw new Exception("Window capture failed"); } finally { g.ReleaseHdc(dc); } }
     else g.CopyFromScreen(r.L,r.T,0,0,b.Size);
     double red=0,green=0,blue=0;int count=0;
     for(int y=180;y<220;y+=4)for(int x=400;x<440;x+=4){var v=b.GetPixel(x,y);red+=v.R;green+=v.G;blue+=v.B;count++;}
     string line=sample+","+Read(handle,game+0x264f8)+","+Read(handle,game+0x18304)+","+(red/count)+","+(green/count)+","+(blue/count);
     for(int i=0;i<6;i++)line+=","+BitConverter.ToSingle(BitConverter.GetBytes(Read(handle,game+0x676b8+i*4)),0).ToString(System.Globalization.CultureInfo.InvariantCulture);
     if(red+green+blue<100)throw new Exception("Window capture did not contain a rendered room");
     log.WriteLine(line);if(sample%3==0)b.Save(Path.Combine(output,"frame-"+sample.ToString("D4")+".png"),ImageFormat.Png);
     sample++;System.Threading.Thread.Sleep(25);
    }
   }
  } finally { CloseHandle(handle); }
 }
}
'@
if (!$BackgroundCapture) {
    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.AppActivate($GameProcessId)
    [uint32]$foregroundId = 0
    $other = [LanVisualSeries]::GetWindowThreadProcessId([LanVisualSeries]::GetForegroundWindow(), [ref]$foregroundId)
    $current = [LanVisualSeries]::GetCurrentThreadId()
    [void][LanVisualSeries]::AttachThreadInput($current, $other, $true)
    [void][LanVisualSeries]::ShowWindow($p.MainWindowHandle, 9)
    [void][LanVisualSeries]::SetForegroundWindow($p.MainWindowHandle)
    [void][LanVisualSeries]::AttachThreadInput($current, $other, $false)
    Start-Sleep -Milliseconds 200
}
[LanVisualSeries]::Capture($GameProcessId, $OutputDirectory, $Seconds, [bool]$BackgroundCapture)
