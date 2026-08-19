<#
  네이티브 대화상자(#32770)의 자식 컨트롤을 덤프하거나 버튼을 누른다.
  사용:
    pwsh -NoProfile -File dlg.ps1 -TitleLike "웹 페이지 메시지"                # 전부 덤프
    pwsh -NoProfile -File dlg.ps1 -TitleLike "웹 페이지 메시지" -Click 1        # 컨트롤ID 1 클릭
    pwsh -NoProfile -File dlg.ps1 -TitleLike "웹 페이지 메시지" -Index 1 -Click 2
#>
param(
  [string]$TitleLike = "",
  [int]$Index = 0,
  [int]$Click = -1
)

$sig = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class Dlg {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
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
        if (s.Length > 0) { H.Add(h); T.Add(s.ToString()); C.Add(c.ToString()); }
      }
      return true;
    };
    EnumWindows(cb, IntPtr.Zero);
  }
  public static List<string> Kids = new List<string>();
  public static void Dump(IntPtr root) {
    Kids.Clear();
    EP cb = delegate(IntPtr h, IntPtr l) {
      StringBuilder s = new StringBuilder(1024); GetWindowText(h, s, 1024);
      StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
      int id = GetDlgCtrlID(h);
      int st = GetWindowLong(h, -16);
      Kids.Add(string.Format("{0}\tid={1}\tstyle=0x{2:X}\tvis={3}\t[{4}]",
               c.ToString(), id, st, IsWindowVisible(h), s.ToString()));
      return true;
    };
    EnumChildWindows(root, cb, IntPtr.Zero);
  }
}
"@
Add-Type -TypeDefinition $sig

[Dlg]::Scan()
$c = @()
for ($i = 0; $i -lt [Dlg]::H.Count; $i++) { if ([Dlg]::T[$i] -like "*$TitleLike*") { $c += $i } }
if ($c.Count -eq 0) { "ERR: 창 없음 ($TitleLike)"; exit 1 }
"후보 $($c.Count)개 — index $Index 사용"
$h = [Dlg]::H[$c[$Index]]
"TITLE=" + [Dlg]::T[$c[$Index]] + "  CLASS=" + [Dlg]::C[$c[$Index]] + "  HWND=$h"

[Dlg]::Dump($h)
[Dlg]::Kids

if ($Click -ge 0) {
  # WM_COMMAND = 0x111
  [Dlg]::PostMsg($h, 0x111, [IntPtr]$Click, [IntPtr]::Zero) | Out-Null
  "CLICKED id=$Click"
}
