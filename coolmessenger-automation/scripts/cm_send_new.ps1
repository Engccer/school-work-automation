<#
    조직도에서 한 사람을 찾아 새 메시지를 쓰고, 선택적으로 보낸다.
    같은 안내문을 여러 사람에게 "개별 발송"할 때 이 스크립트를 사람 수만큼 돌린다.

      pwsh -NoProfile -File scripts/cm_send_new.ps1 -Name 홍길동 `
           [-TitleFile 제목.txt] -BodyFile 본문.txt -Attach '.\양식.hwp' -Shot shot.png [-Send]

    열기와 채우기를 한 번에 해야 한다. 조직도에서 연 작성 창은 손대지 않으면 저절로 닫힌다(실측).
    -Send 없이 부르면 채우기까지만 하고 캡처를 남긴다. 발송 여부는 창이 아니라 tbl_send로 판정한다.
    -TitleFile을 빼거나 빈 파일을 주면 제목 칸을 건드리지 않는다. 쿨메신저가 본문 앞 약 30자를
    제목으로 채운다(실측 2026-11-12).
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$TitleFile,
    [Parameter(Mandatory = $true)][string]$BodyFile,
    [string[]]$Attach,
    [string]$Shot,
    [switch]$PlainText,
    [switch]$Send
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cm_tree.ps1"

# 본문 평문 → 쿨메신저 에디터가 손으로 친 글에 만드는 것과 같은 HTML.
# 줄마다 <div style="line-height: 1.35;">, 빈 줄은 <div ...><br></div>,
# URL은 <a href="URL" style="cursor: pointer;">URL</a> (손으로 스페이스를 쳐 링크가 걸린 메시지의 MessageBody 실측).
function ConvertTo-CMBodyHtml([string]$text) {
    $div = '<div style="line-height: 1.35;">'
    $lines = ($text -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n") -split "`n"
    $sb = [Text.StringBuilder]::new()
    foreach ($ln in $lines) {
        if ($ln -eq '') { [void]$sb.Append("$div<br></div>"); continue }
        $out = [Text.StringBuilder]::new(); $pos = 0
        foreach ($m in [regex]::Matches($ln, 'https?://[^\s<>"]+')) {
            $url = $m.Value -replace '[\.,;:!?\)\]」』]+$', ''    # 문장부호·닫는 괄호는 링크에서 뺀다
            [void]$out.Append([Net.WebUtility]::HtmlEncode($ln.Substring($pos, $m.Index - $pos)))
            $u = [Net.WebUtility]::HtmlEncode($url)
            [void]$out.Append("<a href=`"$u`" style=`"cursor: pointer;`">$u</a>")
            $pos = $m.Index + $url.Length
        }
        [void]$out.Append([Net.WebUtility]::HtmlEncode($ln.Substring($pos)))
        $s = $out.ToString() -replace '  ', ' &nbsp;'     # 연속 공백 보존
        if ($s.StartsWith(' ')) { $s = '&nbsp;' + $s.Substring(1) }
        [void]$sb.Append("$div$s</div>")
    }
    # 기본 글꼴로 감싼다. 빼면 붙인 글이 Times New Roman 12pt가 된다(실측). 평문 붙여넣기의 틀과 같다.
    "$div<font face=`"굴림`" size=`"2`">" + $sb.ToString() + '</font></div>'
}

# CF_HTML(+평문) 클립보드 쓰기. 오프셋은 UTF-8 바이트 기준. pwsh는 MTA라 STA 스레드에서 넣는다.
function Set-CMClipboardHtml([string]$Html, [string]$Text) {
    $pre  = '<html><body><!--StartFragment-->'
    $post = '<!--EndFragment--></body></html>'
    $fmt  = "Version:0.9`r`nStartHTML:{0:D10}`r`nEndHTML:{1:D10}`r`nStartFragment:{2:D10}`r`nEndFragment:{3:D10}`r`n"
    $u = [Text.Encoding]::UTF8
    $hlen = $u.GetByteCount(($fmt -f 0, 0, 0, 0))
    $sH = $hlen; $sF = $sH + $u.GetByteCount($pre); $eF = $sF + $u.GetByteCount($Html); $eH = $eF + $u.GetByteCount($post)
    $cf = ($fmt -f $sH, $eH, $sF, $eF) + $pre + $Html + $post
    if (-not ('CMClip' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class CMClip {
    [DllImport("user32.dll", SetLastError=true)] static extern bool OpenClipboard(IntPtr h);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint f, IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string s);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint f, UIntPtr n);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr h);
    static IntPtr Mem(byte[] b) {
        IntPtr h = GlobalAlloc(0x0002, (UIntPtr)(b.Length + 2));
        IntPtr p = GlobalLock(h); Marshal.Copy(b, 0, p, b.Length);
        Marshal.WriteInt16(p, b.Length, 0); GlobalUnlock(h); return h;
    }
    public static void Set(string cfHtml, string text) {
        bool ok = false;
        for (int i = 0; i < 20 && !(ok = OpenClipboard(IntPtr.Zero)); i++) System.Threading.Thread.Sleep(100);
        if (!ok) throw new Exception("OpenClipboard failed");
        try {
            EmptyClipboard();
            SetClipboardData(RegisterClipboardFormat("HTML Format"), Mem(Encoding.UTF8.GetBytes(cfHtml)));
            SetClipboardData(13, Mem(Encoding.Unicode.GetBytes(text)));   // CF_UNICODETEXT
        } finally { CloseClipboard(); }
    }
}
'@
    }
    [CMClip]::Set($cf, $Text)
}

function Send-CtrlKey([byte]$vk) {
    [CM]::keybd_event(0x11, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 40
    [CM]::keybd_event($vk, 0, 0, [IntPtr]::Zero);  Start-Sleep -Milliseconds 40
    [CM]::keybd_event($vk, 0, 2, [IntPtr]::Zero);  Start-Sleep -Milliseconds 40
    [CM]::keybd_event(0x11, 0, 2, [IntPtr]::Zero); Start-Sleep -Milliseconds 150
}
function Invoke-PointClick([int]$x, [int]$y) {
    [void][CM]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 120
    [CM]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [CM]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 250
}
function Get-Rect([IntPtr]$h) { $r = New-Object CM+RECT; [void][CM]::GetWindowRect($h, [ref]$r); $r }
function Find-CMCompose {
    foreach ($t in [CM]::Tops([uint32](Get-CMPid))) {
        if ([CM]::IsWindowVisible($t) -and [CM]::Txt($t) -like '*크롬에디터*') { return $t }
    }
    $null
}
function Save-WindowShot([IntPtr]$win, [string]$path) {
    Add-Type -AssemblyName System.Drawing
    $rw = Get-Rect $win
    $bmp = New-Object Drawing.Bitmap (($rw.R - $rw.L), ($rw.B - $rw.T))
    $g = [Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    [void][CM]::PrintWindow($win, $hdc, 2)     # 가려져 있어도 찍힌다
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

foreach ($a in @($Attach)) { if ($a -and -not (Test-Path -LiteralPath $a)) { throw "첨부 파일이 없습니다: $a" } }
$titleText = ''
if ($TitleFile) { $titleText = [string](Get-Content -LiteralPath $TitleFile -Raw -Encoding UTF8) }
if (Find-CMCompose) { throw '이미 열린 작성 창이 있습니다. 먼저 정리하세요.' }
if (Test-CMDesktopLocked) { throw 'Windows 잠금 화면이거나 맨 앞 창이 없습니다(화면 꺼짐·보안 데스크톱). 사용자에게 잠금 해제를 요청한 뒤 다시 실행하세요(아무것도 보내지 않음).' }

# 1. 조직도에서 대상을 찾아 더블클릭
$mainWin = [IntPtr](Find-CMWindow -Title 'COOLMESSENGER')
if ([CM]::IsIconic($mainWin)) { [void][CM]::ShowWindow($mainWin, 9); Start-Sleep -Milliseconds 500 }   # SW_RESTORE
[void](Set-CMActive $mainWin)
Start-Sleep -Milliseconds 300
$tree = Get-CMTree
$buf = New-CMRemoteBuf
try {
    $person = Find-CMPerson -Tree $tree -Buf $buf -Name $Name
    Write-Output "대상 계정: $($person.Account) (조직도 $($person.Count)곳)"
    Invoke-CMTreeDoubleClick -Tree $tree -Item $person.Item -Buf $buf
} finally { Remove-CMRemoteBuf $buf }

$win = $null
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 300; $win = Find-CMCompose; if ($win) { break } }
if (-not $win) { throw '작성 창이 열리지 않았습니다.' }
[void](Set-CMActive ([IntPtr]$win))
Start-Sleep -Milliseconds 400

# 2. 받는사람 검증 · 학생 라벨은 '이름(학년-반) 번호 담당(이름)', 교직원 라벨은 '이름 계정번호 담당(이름)' 꼴이다
#    (예: '홍길동 101 기획(홍길동)'). 첨부 라벨 '파일명 (NN KB)'은 두 꼴 어디에도 맞지 않는다.
$kids = [CM]::Kids([IntPtr]$win)
$recips = @()
foreach ($k in $kids) {
    $t = [CM]::Txt($k)
    $isRecip = ($t -match '^\S+\(\d-\d\)') -or ($t -match '^\S+ \d+ .+\(\S+\)$')
    if ($isRecip -and [CM]::IsWindowVisible($k)) { $recips += $t }
}
Write-Output "받는사람: $($recips -join ' | ')"
if ($recips.Count -ne 1 -or $recips[0] -notlike "*$Name*") {
    throw "받는사람이 기대와 다릅니다: $($recips -join ' | ')"
}

$titleEdit = $kids | Where-Object { [CM]::Cls($_) -eq 'Edit' -and [CM]::GetDlgCtrlID($_) -eq 4362 } | Select-Object -First 1
$btnAttach = $kids | Where-Object { [CM]::Txt($_) -eq '파일첨부' } | Select-Object -First 1
$btnSend   = $kids | Where-Object { [CM]::Txt($_) -eq '보내기' } | Select-Object -First 1
$bodyWnd   = $kids | Where-Object { [CM]::Cls($_) -eq 'AfxWnd140u' -and ((Get-Rect $_).B - (Get-Rect $_).T) -gt 300 } | Select-Object -First 1
if (-not $titleEdit -or -not $btnAttach -or -not $btnSend -or -not $bodyWnd) { throw '작성 창 컨트롤을 찾지 못했습니다.' }

# 3. 제목 · GetWindowText로는 빈 문자열로 읽힌다. 캡처나 tbl_send로 확인한다
#    제목이 비면 칸을 건드리지 않는다(쿨메신저가 본문 앞부분으로 채움). 빈 문자열을 붙여 넣으려다
#    클립보드에 남은 엉뚱한 글이 제목에 들어가는 일을 막는다.
if ($titleText.Trim()) {
    Set-Clipboard -Value $titleText
    $rt = Get-Rect $titleEdit
    Invoke-PointClick ([int](($rt.L + $rt.R) / 2)) ([int](($rt.T + $rt.B) / 2))
    Send-CtrlKey 0x41; Send-CtrlKey 0x56
    Start-Sleep -Milliseconds 300
} else {
    Write-Output '제목: 비움(쿨메신저가 본문 앞부분으로 채움)'
}

# 4. 본문 · CEF라 클립보드로 붙인다. 캐럿을 맨 앞으로 두고 붙인다
#    기본은 HTML 붙여넣기다. 평문으로 붙이면 URL이 글자로만 들어가 받는 쪽에서 눌리지 않는다
#    (에디터는 손으로 스페이스·엔터를 칠 때만 자동 링크를 건다). 그래서 손으로 친 메시지와 같은
#    <div> 줄 구조에 URL을 <a href> 링크로 감싸 CF_HTML로 넣는다. -PlainText면 예전처럼 평문.
$bodyText = [string](Get-Content -LiteralPath $BodyFile -Raw -Encoding UTF8)
if ($PlainText) { Set-Clipboard -Value $bodyText }
else {
    $html = ConvertTo-CMBodyHtml $bodyText
    Set-CMClipboardHtml -Html $html -Text $bodyText
    Write-Output "본문: HTML 붙여넣기(링크 $(([regex]::Matches($html, '<a href=')).Count)개)"
}
$rb = Get-Rect $bodyWnd
Invoke-PointClick ([int](($rb.L + $rb.R) / 2)) ([int]($rb.T + 60))
Send-CtrlKey 0x24; Send-CtrlKey 0x56
Start-Sleep -Milliseconds 600

# 5. 첨부 · 모달이라 PostMessage, "열기" 창은 경로 입력란(1148) + WM_COMMAND 1
#    -Attach에 여러 파일을 주면 한 개씩 차례로 붙인다(-Attach a,b,c).
foreach ($att in @($Attach | Where-Object { $_ })) {
    [void][CM]::PostMessage($btnAttach, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    $dlg = $null
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 300
        foreach ($t in [CM]::Tops([uint32](Get-CMPid))) {
            if ([CM]::IsWindowVisible($t) -and [CM]::Cls($t) -eq '#32770' -and [CM]::Txt($t) -like '*열기*') { $dlg = $t; break }
        }
        if ($dlg) { break }
    }
    if (-not $dlg) { throw '"열기" 대화상자가 뜨지 않았습니다.' }
    $edit = [CM]::Kids([IntPtr]$dlg) | Where-Object { [CM]::GetDlgCtrlID($_) -eq 1148 } | Select-Object -First 1
    if (-not $edit) { throw '"열기" 대화상자의 경로 입력란(1148)을 찾지 못했습니다.' }
    $ptr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('"' + $att + '"')
    try { [void][CM]::Msg($edit, 0x000C, [IntPtr]::Zero, $ptr) }
    finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
    Start-Sleep -Milliseconds 400
    [void][CM]::PostMessage([IntPtr]$dlg, 0x0111, [IntPtr]1, [IntPtr]::Zero)
    Start-Sleep -Seconds 3

    $stem = [IO.Path]::GetFileNameWithoutExtension($att)
    $labels = @()
    foreach ($k in [CM]::Kids([IntPtr]$win)) {
        $t = [CM]::Txt($k)
        # 첨부가 4개를 넘으면 라벨 칸이 스크롤돼 뒤 라벨은 IsWindowVisible가 false다(실측). 보임 여부는 보지 않는다
        if ($t -like "*$stem*" -and $t -match '\(\d[\d,.]* ?[KMG]?B\)$') { $labels += $t }
    }
    Write-Output "첨부: $($labels -join ' | ')"
    if ($labels.Count -lt 1) { throw '첨부가 붙지 않았습니다.' }
}

if ($Shot) { Save-WindowShot ([IntPtr]$win) $Shot; Write-Output "캡처: $Shot" }

# 6. 발송 · 사용자가 발송에 동의했을 때만
if ($Send) {
    [void][CM]::Msg($btnSend, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Seconds 5
    Write-Output "보내기 클릭함. 작성 창 남음=$([bool](Find-CMCompose)). 다시 누르지 말고 tbl_send로 확인하세요."
} else {
    Write-Output '채우기까지만 했습니다(미발송).'
}
