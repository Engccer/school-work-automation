<#
  제목 부분일치로 최상위 창을 찾아 PNG 로 캡처한다.
  사용: pwsh -NoProfile -File capture.ps1 -TitleLike "수신자지정" -Out C:\path\shot.png
#>
param(
  [string]$TitleLike = "",
  [string]$Out = "",
  [switch]$Restore
)

Add-Type -AssemblyName System.Drawing

$sig = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class CapWin {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
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

[CapWin]::Scan()
$idx = -1
for ($i = 0; $i -lt [CapWin]::H.Count; $i++) {
  if ([CapWin]::T[$i] -like "*$TitleLike*") { $idx = $i; break }
}
if ($idx -lt 0) { "ERR: 창 없음 ($TitleLike)"; exit 1 }
$h = [CapWin]::H[$idx]
"TITLE=" + [CapWin]::T[$idx]

if ($Restore) { [CapWin]::ShowWindow($h, 9) | Out-Null; Start-Sleep -Milliseconds 400 }
[CapWin]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 600

$r = New-Object CapWin+RECT
[CapWin]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
"RECT=$($r.Left),$($r.Top) ${w}x${ht}"
if ($w -le 0 -or $ht -le 0) { "ERR: 크기 0"; exit 1 }

$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
# 1순위: PrintWindow(PW_RENDERFULLCONTENT=2) — 다른 창에 가려져도 대상 창만 찍힌다
$hdc = $g.GetHdc()
$ok = [CapWin]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc)
# 화면 복사 폴백 (PrintWindow 실패 또는 전부 검은 화면일 때)
$blank = $true
if ($ok) {
  for ($yy = 0; $yy -lt $ht -and $blank; $yy += 17) {
    for ($xx = 0; $xx -lt $w -and $blank; $xx += 23) {
      $p = $bmp.GetPixel($xx, $yy)
      if ($p.R -ne 0 -or $p.G -ne 0 -or $p.B -ne 0) { $blank = $false }
    }
  }
}
if (-not $ok -or $blank) {
  "PrintWindow 실패/빈화면 → CopyFromScreen 폴백"
  $g2 = [System.Drawing.Graphics]::FromImage($bmp)
  $g2.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
  $g2.Dispose()
}
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"SAVED=$Out"
