<#
  표준 "열기" 파일 대화상자에 경로를 넣고 [열기]를 누른다.
  - 파일 이름 편집란(class=Edit, id=1148)에 WM_SETTEXT 로 전체 경로를 넣는다.
    WM_SETTEXT 는 시스템이 문자열을 마샬링해 주는 안전한 메시지다.
    (WM_USER 계열에 문자열 포인터를 넘기면 대상 프로세스가 죽는다 — 절대 금지)
  - 그 다음 WM_COMMAND 로 [열기](id=1) 를 누른다.
  사용: pwsh -NoProfile -File pick_file.ps1 -TitleLike "열기" -Path "C:\...\a.hwpx"
#>
param(
  [string]$TitleLike = "열기",
  [string]$Path = "",
  [int]$Index = 0
)

$sig = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class Pick {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll", EntryPoint="SendMessageW", CharSet=CharSet.Unicode)]
    public static extern IntPtr SendText(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll", EntryPoint="PostMessageW")] public static extern bool PostMsg(IntPtr h, uint m, IntPtr w, IntPtr l);

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
  public static IntPtr FoundEdit = IntPtr.Zero;
  public static void FindEdit(IntPtr root, int wantId) {
    FoundEdit = IntPtr.Zero;
    EP cb = null;
    cb = delegate(IntPtr h, IntPtr l) {
      StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
      if (c.ToString() == "Edit" && GetDlgCtrlID(h) == wantId && FoundEdit == IntPtr.Zero) { FoundEdit = h; return false; }
      if (FoundEdit == IntPtr.Zero) EnumChildWindows(h, cb, IntPtr.Zero);
      return FoundEdit == IntPtr.Zero;
    };
    EnumChildWindows(root, cb, IntPtr.Zero);
  }
}
"@
Add-Type -TypeDefinition $sig

[Pick]::Scan()
$c = @()
for ($i = 0; $i -lt [Pick]::H.Count; $i++) { if ([Pick]::T[$i] -like "*$TitleLike*") { $c += $i } }
if ($c.Count -eq 0) { "ERR: 창 없음 ($TitleLike)"; exit 1 }
$dlg = [Pick]::H[$c[$Index]]
"DLG=" + [Pick]::T[$c[$Index]]

[Pick]::FindEdit($dlg, 1148)
$edit = [Pick]::FoundEdit
if ($edit -eq [IntPtr]::Zero) { "ERR: 파일 이름 편집란(id=1148) 없음"; exit 1 }
"EDIT hwnd=$edit"

# WM_SETTEXT = 0x000C — 공백·괄호가 있으므로 따옴표로 감싼다
$quoted = '"' + $Path + '"'
[Pick]::SendText($edit, 0x000C, [IntPtr]::Zero, $quoted) | Out-Null
Start-Sleep -Milliseconds 500

$sb = New-Object System.Text.StringBuilder 1024
[Pick]::GetWindowText($edit, $sb, 1024) | Out-Null
"EDIT NOW=[" + $sb.ToString() + "]"

# WM_COMMAND = 0x111, [열기] 버튼 컨트롤 ID = 1
[Pick]::PostMsg($dlg, 0x111, [IntPtr]1, [IntPtr]::Zero) | Out-Null
"OPEN clicked"
