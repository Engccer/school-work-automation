<#
  제목 부분일치로 찾은 최상위 창에 WM_CLOSE 를 보낸다.
  사용: pwsh -NoProfile -File close_win.ps1 -TitleLike "-- 웹 페이지 대화 상자" -Exact
  주의: 제목이 비슷한 창을 잘못 닫지 않도록 -List 로 먼저 확인할 것.
#>
param(
  [string]$TitleLike = "",
  [int]$Index = 0,
  [switch]$List
)

$sig = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class CloseW {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", EntryPoint="PostMessageW")] public static extern bool PostMsg(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static List<IntPtr> H = new List<IntPtr>();
  public static List<string> T = new List<string>();
  public static List<string> C = new List<string>();
  public static void Scan() {
    H.Clear(); T.Clear(); C.Clear();
    EP cb = delegate(IntPtr h, IntPtr l) {
      if (IsWindowVisible(h)) {
        StringBuilder s = new StringBuilder(512); GetWindowText(h, s, 512);
        StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
        H.Add(h); T.Add(s.ToString()); C.Add(c.ToString());
      }
      return true;
    };
    EnumWindows(cb, IntPtr.Zero);
  }
}
"@
Add-Type -TypeDefinition $sig

[CloseW]::Scan()
$c = @()
for ($i = 0; $i -lt [CloseW]::H.Count; $i++) { if ([CloseW]::T[$i] -like "*$TitleLike*") { $c += $i } }
if ($c.Count -eq 0) { "ERR: 창 없음 ($TitleLike)"; exit 1 }

if ($List) {
  for ($k = 0; $k -lt $c.Count; $k++) {
    "{0}`t{1}`t[{2}]" -f $k, [CloseW]::C[$c[$k]], [CloseW]::T[$c[$k]]
  }
  exit 0
}

$h = [CloseW]::H[$c[$Index]]
"CLOSING [" + [CloseW]::T[$c[$Index]] + "] class=" + [CloseW]::C[$c[$Index]]
[CloseW]::PostMsg($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
"WM_CLOSE sent"
