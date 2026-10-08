<#
  제목으로 찾은 최상위 창에 WM_CLOSE 를 보낸다. 기본은 부분일치, -Exact 면 제목 완전일치.
  사용: pwsh -NoProfile -File close_win.ps1 -TitleLike "-- 웹 페이지 대화 상자" -Exact
  주의: 제목이 비슷한 창을 잘못 닫지 않도록 -List 로 먼저 확인하고 -Index 로 고를 것.
        -Index 는 그때의 -TitleLike·-Exact 로 거른 목록 안 순번이고 부를 때마다 다시 센다.
        -List 는 닫을 때와 같은 -TitleLike·-Exact 로 돌리고, 하나 닫을 때마다 다시 -List 한다.
#>
param(
  [string]$TitleLike = "",
  [int]$Index = 0,
  [switch]$List,
  [switch]$Exact
)

# 제목 목록에서 대상 후보의 인덱스를 고른다(-Exact 면 완전일치, 아니면 부분일치)
function Select-WindowIndex([string[]]$Titles, [string]$TitleLike, [switch]$Exact) {
  for ($i = 0; $i -lt $Titles.Count; $i++) {
    if ($Exact) { if ($Titles[$i] -ceq $TitleLike) { $i } }
    elseif ($Titles[$i] -like "*$TitleLike*") { $i }
  }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # 시험용 점-소싱: 함수만 불러오고 창은 건드리지 않는다

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
$c = @(Select-WindowIndex -Titles ([CloseW]::T.ToArray()) -TitleLike $TitleLike -Exact:$Exact)
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
