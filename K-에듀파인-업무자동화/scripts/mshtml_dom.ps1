<#
.SYNOPSIS
  범용 MSHTML 브리지 — 최상위 창을 "제목 부분일치"로 찾아 임베디드 IE DOM 을 제어한다.

.DESCRIPTION
  `kyul_dom.ps1` 은 대상 창을 `Get-Process WXSClient` + 제목 완전일치로 고정한다.
  그런데 K-에듀파인 결재 창에서 파생되는 대화상자들(파일저장·문서저장 등)은
  프로세스가 같아도 **클래스가 `Internet Explorer_TridentDlgFrame`** 이고 제목이
  "파일저장 | 업무관리시스템 -- 웹 페이지 대화 상자" 처럼 다르다. 이 스크립트는
  EnumWindows 로 모든 최상위 창을 훑어 제목 부분일치로 고르므로 그 대화상자들까지 닿는다.

  반드시 STA 로 실행할 것 (COM 요구사항):
    pwsh -STA -NoProfile -ExecutionPolicy Bypass -File mshtml_dom.ps1 `
         -TitleLike "파일저장" -JsFile <js> [-Var __r] [-WaitMs 1500] [-Index 0]

.PARAMETER TitleLike
  대상 창 제목의 일부. 와일드카드 없이 부분일치로 매칭한다.

.PARAMETER JsFile
  주입할 JavaScript 파일(UTF-8). 결과를 window.<Var> 에 **문자열로** 담을 것.

.PARAMETER Var
  실행 후 읽어올 window 변수명. 기본 __r.

.PARAMETER WaitMs
  주입 후 변수를 읽기까지 대기(ms). 비동기 로직이 있으면 넉넉히.

.PARAMETER Index
  제목이 매칭되는 창이 여러 개일 때 선택할 인덱스(0부터).

.PARAMETER ListOnly
  창 목록만 출력한다(인덱스/클래스/IE 보유 여부/제목). 대상 탐색·상태 확인용.

.NOTES
  - 헬퍼 함수 이름에 `SP`/`GP`/`CM` 같은 두 글자를 쓰지 말 것.
    PowerShell 은 **별칭이 함수보다 우선**이라 Set-ItemProperty/Get-ItemProperty 로 잡힌다.
  - 같은 DLL 함수를 시그니처만 바꿔 여러 번 선언할 땐 `EntryPoint=` 를 반드시 지정한다.
#>
param(
  [string]$TitleLike = "",
  [string]$JsFile = "",
  [string]$Var = "__r",
  [int]$WaitMs = 1000,
  [int]$Index = 0,
  [switch]$ListOnly
)

$sig = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class MsDom {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EP cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int m);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern uint RegisterWindowMessage(string s);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("oleacc.dll")] public static extern int ObjectFromLresult(IntPtr lr, ref Guid riid, IntPtr w, [MarshalAs(UnmanagedType.IDispatch)] out object o);

  public static List<IntPtr> Handles = new List<IntPtr>();
  public static List<string> Titles = new List<string>();
  public static List<string> Classes = new List<string>();

  public static void Scan() {
    Handles.Clear(); Titles.Clear(); Classes.Clear();
    EP cb = delegate(IntPtr h, IntPtr l) {
      if (IsWindowVisible(h)) {
        StringBuilder t = new StringBuilder(512); GetWindowText(h, t, 512);
        StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
        if (t.Length > 0) { Handles.Add(h); Titles.Add(t.ToString()); Classes.Add(c.ToString()); }
      }
      return true;
    };
    EnumWindows(cb, IntPtr.Zero);
  }

  public static IntPtr FindIEServer(IntPtr root) {
    IntPtr found = IntPtr.Zero;
    EP cb = null;
    cb = delegate(IntPtr h, IntPtr l) {
      StringBuilder sb = new StringBuilder(256);
      GetClassName(h, sb, 256);
      if (sb.ToString() == "Internet Explorer_Server" && found == IntPtr.Zero) { found = h; return false; }
      if (found == IntPtr.Zero) EnumChildWindows(h, cb, IntPtr.Zero);
      return found == IntPtr.Zero;
    };
    EnumChildWindows(root, cb, IntPtr.Zero);
    return found;
  }

  public static object GetDocument(IntPtr ie) {
    uint msg = RegisterWindowMessage("WM_HTML_GETOBJECT");
    IntPtr res;
    SendMessageTimeout(ie, msg, IntPtr.Zero, IntPtr.Zero, 2, 3000, out res);
    if (res == IntPtr.Zero) return null;
    Guid iid = new Guid("626FC520-A41E-11CF-A731-00A0C9082637"); // IID_IHTMLDocument2
    object doc; int hr = ObjectFromLresult(res, ref iid, IntPtr.Zero, out doc);
    return hr == 0 ? doc : null;
  }
}
"@
Add-Type -TypeDefinition $sig

function Get-DomProp($o, $n) { try { return $o.GetType().InvokeMember($n, [System.Reflection.BindingFlags]::GetProperty, $null, $o, $null) } catch { return $null } }
function Set-DomProp($o, $n, $v) { $o.GetType().InvokeMember($n, [System.Reflection.BindingFlags]::SetProperty, $null, $o, @($v)) | Out-Null }
function Invoke-DomMethod($o, $n, $a) { return $o.GetType().InvokeMember($n, [System.Reflection.BindingFlags]::InvokeMethod, $null, $o, $a) }

[MsDom]::Scan()

if ($ListOnly) {
  for ($i = 0; $i -lt [MsDom]::Handles.Count; $i++) {
    $ie = [MsDom]::FindIEServer([MsDom]::Handles[$i])
    "{0}`t{1}`tIE={2}`t{3}" -f $i, [MsDom]::Classes[$i], ($ie -ne [IntPtr]::Zero), [MsDom]::Titles[$i]
  }
  exit 0
}

$cands = @()
for ($i = 0; $i -lt [MsDom]::Handles.Count; $i++) {
  if ([MsDom]::Titles[$i] -like "*$TitleLike*") { $cands += $i }
}
if ($cands.Count -eq 0) { "ERR: 제목에 '$TitleLike' 포함된 창 없음"; exit 1 }
if ($cands.Count -gt ($Index + 1)) { "WARN: 후보 $($cands.Count)개 — index $Index 사용" }
$h = [MsDom]::Handles[$cands[$Index]]

$srv = [MsDom]::FindIEServer($h)
if ($srv -eq [IntPtr]::Zero) { "ERR: Internet Explorer_Server 없음"; exit 1 }
$doc = [MsDom]::GetDocument($srv)
if ($null -eq $doc) { "ERR: IHTMLDocument2 획득 실패"; exit 1 }
$win = Get-DomProp $doc "parentWindow"
if ($null -eq $win) { "ERR: parentWindow 없음"; exit 1 }

$code = Get-Content -Path $JsFile -Raw -Encoding UTF8
$el = Invoke-DomMethod $doc "createElement" @("script")
Set-DomProp $el "type" "text/javascript"
Set-DomProp $el "text" $code
$body = Get-DomProp $doc "body"
Invoke-DomMethod $body "appendChild" @($el) | Out-Null

Start-Sleep -Milliseconds $WaitMs
Get-DomProp $win $Var
