<#
.SYNOPSIS
  K-에듀파인 결재 클라이언트 앱(WXSClient.exe / "문서관리카드결재" 창) 내부 DOM 제어 브리지.

.DESCRIPTION
  결재 문서 창은 브라우저 탭이 아니라 네이티브 Windows 창이지만, 내부 렌더러가
  임베디드 IE(MSHTML, 클래스명 "Internet Explorer_Server")다. 따라서
  WM_HTML_GETOBJECT 메시지 + oleacc!ObjectFromLresult 로 IHTMLDocument2 를 얻어
  일반 웹페이지처럼 DOM 을 읽고 조작할 수 있다.

  반드시 STA 모드로 실행할 것 (COM 요구사항):
    pwsh -STA -NoProfile -File kyul_dom.ps1 -JsFile <js파일> [-Var __r] [-WaitMs 1500]

.PARAMETER JsFile
  주입할 JavaScript 파일 경로(UTF-8). 결과를 window.<Var> 에 문자열로 담을 것.

.PARAMETER Var
  실행 후 읽어올 window 변수명. 기본 __r.

.PARAMETER WaitMs
  주입 후 변수를 읽기까지 대기(ms). 비동기(setTimeout) 로직이 있으면 넉넉히 줄 것.

.PARAMETER WindowName
  대상 창 제목. 결재 창은 "HCLTAPP_KYUL_".

.PARAMETER Index
  같은 제목의 창이 여러 개일 때 선택할 인덱스(0부터).

.NOTES
  - execScript 는 이 문서 모드에 없다. <script> 엘리먼트 주입으로 실행한다.
  - 창 탐색은 UI Automation 이 아니라 Get-Process 의 MainWindowHandle 을 쓴다.
    UIA 최상위 열거는 가상 데스크톱 전환 시 창을 놓친다.
#>
param(
  [Parameter(Mandatory = $true)][string]$JsFile,
  [string]$Var = "__r",
  [int]$WaitMs = 1000,
  [string]$WindowName = "HCLTAPP_KYUL_",
  [int]$Index = 0
)

$sig = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class KyulDom {
  public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hwnd, EnumWindowsProc cb, IntPtr lp);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hwnd, StringBuilder sb, int max);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern uint RegisterWindowMessage(string lpString);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
  [DllImport("oleacc.dll")] public static extern int ObjectFromLresult(IntPtr lResult, ref Guid riid, IntPtr wParam, [MarshalAs(UnmanagedType.IDispatch)] out object ppvObject);

  public static IntPtr FindIEServer(IntPtr root) {
    IntPtr found = IntPtr.Zero;
    EnumWindowsProc cb = null;
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
  public static object GetDocument(IntPtr ieServer) {
    uint msg = RegisterWindowMessage("WM_HTML_GETOBJECT");
    IntPtr res;
    SendMessageTimeout(ieServer, msg, IntPtr.Zero, IntPtr.Zero, 2, 3000, out res);
    if (res == IntPtr.Zero) return null;
    Guid iid = new Guid("626FC520-A41E-11CF-A731-00A0C9082637"); // IID_IHTMLDocument2
    object doc; int hr = ObjectFromLresult(res, ref iid, IntPtr.Zero, out doc);
    return hr == 0 ? doc : null;
  }
}
"@
Add-Type -TypeDefinition $sig

function Get-Prop($obj, $name) {
  try { return $obj.GetType().InvokeMember($name, [System.Reflection.BindingFlags]::GetProperty, $null, $obj, $null) } catch { return $null }
}
function Set-Prop($obj, $name, $val) {
  $obj.GetType().InvokeMember($name, [System.Reflection.BindingFlags]::SetProperty, $null, $obj, @($val)) | Out-Null
}
function Call-Method($obj, $name, $argsArr) {
  return $obj.GetType().InvokeMember($name, [System.Reflection.BindingFlags]::InvokeMethod, $null, $obj, $argsArr)
}

# 1. 대상 창 핸들 (프로세스 기반 — 가상 데스크톱/최소화에 영향 없음)
$procs = @(Get-Process WXSClient -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowTitle -eq $WindowName -and $_.MainWindowHandle -ne 0 })
if ($procs.Count -eq 0) { "ERR: '$WindowName' 창 없음 (결재 문서가 열려 있는지 확인)"; exit 1 }
if ($procs.Count -gt 1) { "WARN: 같은 제목 창 $($procs.Count)개 — index $Index 사용 (pid $($procs[$Index].Id))" }
$hwnd = $procs[$Index].MainWindowHandle

# 2. 임베디드 IE → IHTMLDocument2
$srv = [KyulDom]::FindIEServer($hwnd)
if ($srv -eq [IntPtr]::Zero) { "ERR: Internet Explorer_Server 자식 창 없음"; exit 1 }
$doc = [KyulDom]::GetDocument($srv)
if ($null -eq $doc) { "ERR: IHTMLDocument2 획득 실패"; exit 1 }
$win = Get-Prop $doc "parentWindow"
if ($null -eq $win) { "ERR: parentWindow 없음"; exit 1 }

# 3. <script> 주입 실행 (execScript 는 이 문서 모드에 없음)
$code = Get-Content -Path $JsFile -Raw -Encoding UTF8
$el = Call-Method $doc "createElement" @("script")
Set-Prop $el "type" "text/javascript"
Set-Prop $el "text" $code
$body = Get-Prop $doc "body"
Call-Method $body "appendChild" @($el) | Out-Null

# 4. 결과 회수
Start-Sleep -Milliseconds $WaitMs
Get-Prop $win $Var
