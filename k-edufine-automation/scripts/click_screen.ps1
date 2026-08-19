<#
  대상 창을 앞으로 올린 뒤, 창 기준 상대좌표에 실제 마우스 클릭을 보낸다.
  사용: pwsh -NoProfile -File click_screen.ps1 -TitleLike "결재경로설정" -X 435 -Y 276
        (X,Y 는 창 좌상단 기준 픽셀 = 캡처 이미지 좌표와 동일)
#>
param(
  [string]$TitleLike = "",
  [int]$X = 0,
  [int]$Y = 0,
  [int]$Index = 0,
  [switch]$DoubleClick
)

$sig = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class Clk {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  public static List<IntPtr> H = new List<IntPtr>();
  public static List<string> T = new List<string>();
  public static void Scan() {
    H.Clear(); T.Clear();
    EP cb = delegate(IntPtr h, IntPtr l) {
      if (IsWindowVisible(h)) {
        StringBuilder s = new StringBuilder(512); GetWindowText(h, s, 512);
        if (s.Length > 0) { H.Add(h); T.Add(s.ToString()); }
      }
      return true;
    };
    EnumWindows(cb, IntPtr.Zero);
  }
}
"@
Add-Type -TypeDefinition $sig

[Clk]::Scan()
$c = @()
for ($i = 0; $i -lt [Clk]::H.Count; $i++) { if ([Clk]::T[$i] -like "*$TitleLike*") { $c += $i } }
if ($c.Count -eq 0) { "ERR: 창 없음 ($TitleLike)"; exit 1 }
$h = [Clk]::H[$c[$Index]]
"TITLE=" + [Clk]::T[$c[$Index]]

[Clk]::BringWindowToTop($h) | Out-Null
[Clk]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 500

$r = New-Object Clk+RECT
[Clk]::GetWindowRect($h, [ref]$r) | Out-Null
$sx = $r.Left + $X
$sy = $r.Top + $Y
"CLICK screen=($sx,$sy) from win=($($r.Left),$($r.Top)) + rel=($X,$Y)"

[Clk]::SetCursorPos($sx, $sy) | Out-Null
Start-Sleep -Milliseconds 250
# LEFTDOWN=0x02, LEFTUP=0x04
[Clk]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
[Clk]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero)
if ($DoubleClick) {
  Start-Sleep -Milliseconds 80
  [Clk]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [Clk]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero)
}
Start-Sleep -Milliseconds 400
"DONE"
