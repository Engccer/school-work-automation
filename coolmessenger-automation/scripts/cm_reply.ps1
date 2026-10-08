# 받은 메시지에 회신 창을 열고 본문을 채운다. 기본은 '채우기까지'이고,
# -Send 를 줘야 실제로 [보내기]를 누른다.
#
#   pwsh -File scripts/cm_reply.ps1 -Sender '홍길동' -BodyFile 'C:\...\body.txt'          # 채우기만
#   pwsh -File scripts/cm_reply.ps1 -Sender '홍길동' -BodyFile 'C:\...\body.txt' -Send    # 발송까지
#
# 본문은 CEF(크롬) 에디터라 타이핑 대신 클립보드 붙여넣기를 쓴다.
# 붙여넣기는 캐럿 위치에 들어가므로 Ctrl+Home으로 맨 앞에 올린 뒤 붙인다.
# 아래쪽 인용문은 그대로 두어 상대가 무엇에 대한 답인지 알 수 있게 한다.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Sender,      # 목록의 보낸사람에 포함된 이름
    [Parameter(Mandatory)][string]$BodyFile,    # UTF-8 텍스트
    [switch]$Send,
    [string]$ShotPath                           # 확인용 캡처 저장 경로
)

. "$PSScriptRoot\cm_lib.ps1"
Add-Type -AssemblyName System.Drawing

function Save-CMShot {
    param([IntPtr]$Hwnd, [string]$Path)
    $r = New-Object CM+RECT
    [void][CM]::GetWindowRect($Hwnd, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][CM]::PrintWindow($Hwnd, $hdc, 2)     # 가려져 있어도 찍힌다
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

$mw = Open-CMArchive
$list = Find-CMControl -Parent $mw -Class 'SysListView32' -TextLike '메시지 리스트*'
$row = (Read-CMList -List $list -Cols 4 -Max 60).Rows |
       Where-Object { $_.C0 -like "$Sender*" } | Select-Object -First 1
if (-not $row) { throw "'$Sender' 님의 메시지를 목록에서 찾지 못했습니다." }

if (-not (Select-CMMessage -MsgWin $mw -List $list -ExpectSender $row.C0 -Index $row.Index)) {
    throw "'$($row.C0)' 메시지를 미리보기로 띄우지 못했습니다."
}
Write-Host "대상: $($row.C0)"

$before = @{}
foreach ($t in [CM]::Tops([uint32](Get-CMPid))) { $before[$t.ToString()] = $true }
$btn = Find-CMControl -Parent $mw -Class 'Button' -TextLike '메시지 회신*'
[void][CM]::Msg($btn, 0x00F5, [IntPtr]0, [IntPtr]0)
Start-Sleep -Seconds 4

$compose = Find-CMWindow -TitlePattern '메시지 전송'
if ($compose -eq [IntPtr]::Zero) { throw '회신 창이 열리지 않았습니다.' }
if (-not (Set-CMActive -Hwnd $compose)) { throw '회신 창을 활성화하지 못했습니다.' }

# 받는사람이 의도한 사람인지 창 안에서 다시 확인한다(엉뚱한 사람에게 가는 것을 막는다).
$short = ($row.C0 -split '\(')[0]
$toOk = $false
foreach ($c in [CM]::Kids($compose)) { if ([CM]::Txt($c) -like "$short*") { $toOk = $true } }
if (-not $toOk) { throw "회신 창의 받는사람이 '$short' 이 아닙니다. 중단합니다." }

# 본문 에디터에 커서를 두고 맨 앞으로 올린 뒤 붙여넣는다.
$cef = Find-CMControl -Parent $compose -Class 'CefBrowserWindow'
$r = New-Object CM+RECT
[void][CM]::GetWindowRect($cef, [ref]$r)
Invoke-CMClick -X ([int](($r.L + $r.R) / 2)) -Y ($r.T + 30)

Get-Content $BodyFile -Encoding UTF8 | Set-Clipboard
$ws = New-Object -ComObject WScript.Shell
$ws.SendKeys('^{HOME}')
Start-Sleep -Milliseconds 400
$ws.SendKeys('^v')
Start-Sleep -Seconds 2

if (-not $ShotPath) { $ShotPath = Join-Path $env:TEMP ("cm_reply_{0}.png" -f $short) }
Save-CMShot -Hwnd $compose -Path $ShotPath
Write-Host "확인용 캡처: $ShotPath"

if (-not $Send) {
    Write-Host '채우기까지 완료. 발송하려면 -Send 를 주거나 [보내기]를 직접 누르세요.'
    return
}

$send = Find-CMControl -Parent $compose -Class 'Button' -TextLike '보내기*'
[void][CM]::Msg($send, 0x00F5, [IntPtr]0, [IntPtr]0)
Start-Sleep -Seconds 4
Write-Host (Get-CMSendNotice -Compose $compose -Name $short)
