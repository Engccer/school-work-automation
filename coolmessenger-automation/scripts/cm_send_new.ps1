<#
    조직도에서 한 사람을 찾아 새 메시지를 쓰고, 선택적으로 보낸다.
    같은 안내문을 여러 사람에게 "개별 발송"할 때 이 스크립트를 사람 수만큼 돌린다.

      pwsh -NoProfile -File scripts/cm_send_new.ps1 -Name 홍길동 `
           -TitleFile 제목.txt -BodyFile 본문.txt -Attach '.\양식.hwp' -Shot shot.png [-Send]

    열기와 채우기를 한 번에 해야 한다. 조직도에서 연 작성 창은 손대지 않으면 저절로 닫힌다(실측).
    -Send 없이 부르면 채우기까지만 하고 캡처를 남긴다. 발송 여부는 창이 아니라 tbl_send로 판정한다.
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$TitleFile,
    [Parameter(Mandatory = $true)][string]$BodyFile,
    [string]$Attach,
    [string]$Shot,
    [switch]$Send
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cm_tree.ps1"

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

if ($Attach -and -not (Test-Path -LiteralPath $Attach)) { throw "첨부 파일이 없습니다: $Attach" }
if (Find-CMCompose) { throw '이미 열린 작성 창이 있습니다. 먼저 정리하세요.' }

# 1. 조직도에서 대상을 찾아 더블클릭
[void](Set-CMActive ([IntPtr](Find-CMWindow -Title 'COOLMESSENGER')))
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
Get-Content -LiteralPath $TitleFile -Raw -Encoding UTF8 | Set-Clipboard
$rt = Get-Rect $titleEdit
Invoke-PointClick ([int](($rt.L + $rt.R) / 2)) ([int](($rt.T + $rt.B) / 2))
Send-CtrlKey 0x41; Send-CtrlKey 0x56
Start-Sleep -Milliseconds 300

# 4. 본문 · CEF라 클립보드로 붙인다. 캐럿을 맨 앞으로 두고 붙인다
Get-Content -LiteralPath $BodyFile -Raw -Encoding UTF8 | Set-Clipboard
$rb = Get-Rect $bodyWnd
Invoke-PointClick ([int](($rb.L + $rb.R) / 2)) ([int]($rb.T + 60))
Send-CtrlKey 0x24; Send-CtrlKey 0x56
Start-Sleep -Milliseconds 600

# 5. 첨부 · 모달이라 PostMessage, "열기" 창은 경로 입력란(1148) + WM_COMMAND 1
if ($Attach) {
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
    $ptr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('"' + $Attach + '"')
    try { [void][CM]::Msg($edit, 0x000C, [IntPtr]::Zero, $ptr) }
    finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
    Start-Sleep -Milliseconds 400
    [void][CM]::PostMessage([IntPtr]$dlg, 0x0111, [IntPtr]1, [IntPtr]::Zero)
    Start-Sleep -Seconds 3

    $stem = [IO.Path]::GetFileNameWithoutExtension($Attach)
    $labels = @()
    foreach ($k in [CM]::Kids([IntPtr]$win)) {
        $t = [CM]::Txt($k)
        if ($t -like "*$stem*" -and [CM]::IsWindowVisible($k)) { $labels += $t }
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
