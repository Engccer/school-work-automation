# cm_lib.ps1·cm_reply.ps1·cm_save_attachments.ps1 시험. 창 찾기 함수를 가짜로 바꿔 실제 쿨메신저 창은 건드리지 않는다.
#
#   pwsh -NoProfile -File scripts/tests/test_cm_lib.ps1      # 실패가 있으면 종료 코드 1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\cm_lib.ps1')

$script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $script:fail++ }
}

# ---- 가짜 창 환경: 메인 창만 있고, 관리함은 $script:appearAfter번째 조회부터 보인다.
# 관리함 열기 버튼은 [IntPtr]::Zero를 돌려줘 실제 창에 메시지가 가지 않게 한다.
$script:archiveCalls = 0
function Find-CMWindow {
    param([string]$TitlePattern, [string]$Class = '#32770')
    switch ($TitlePattern) {
        '^메시지 관리함$'   { $script:archiveCalls++
                              if ($script:appearAfter -gt 0 -and $script:archiveCalls -ge $script:appearAfter) { return [IntPtr]777 }
                              return [IntPtr]::Zero }
        '^COOLMESSENGER$'   { return [IntPtr]555 }
        default             { return [IntPtr]::Zero }
    }
}
function Find-CMControl { param([IntPtr]$Parent, [string]$Class, [string]$TextLike) return [IntPtr]::Zero }
function Set-CMActive   { param([IntPtr]$Hwnd, [int]$Tries = 3) return $true }

# 관리함이 늦게 떠도(세 번째 조회) 기다렸다가 핸들을 돌려준다.
$script:archiveCalls = 0; $script:appearAfter = 3
$sw = [Diagnostics.Stopwatch]::StartNew()
$h = Open-CMArchive
Check 'Open-CMArchive: 늦게 뜬 관리함을 기다려 찾는다' (($h -is [IntPtr]) -and $h -eq [IntPtr]777) "got $h"
Check 'Open-CMArchive: 뜨면 바로 돌려준다(10초 미만)' ($sw.Elapsed.TotalSeconds -lt 10) "$($sw.Elapsed.TotalSeconds)s"

# 끝내 안 뜨면 0을 돌려주지 않고 오류를 낸다(최대 20초).
$script:archiveCalls = 0; $script:appearAfter = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
$threw = $false; $msg = ''
try { $h = Open-CMArchive } catch { $threw = $true; $msg = $_.Exception.Message }
$t = $sw.Elapsed.TotalSeconds
Check 'Open-CMArchive: 안 뜨면 오류를 낸다' $threw "returned $h"
Check 'Open-CMArchive: 오류 문구가 관리함을 말한다' ($msg -like '*메시지 관리함*') $msg
Check 'Open-CMArchive: 약 20초 기다린 뒤 포기한다' ($t -ge 18 -and $t -lt 30) "${t}s"
Check 'Open-CMArchive: 기다리는 동안 다시 조회한다' ($script:archiveCalls -ge 5) "calls=$($script:archiveCalls)"

# ---- 발송 뒤 안내: 창이 닫혔든 남았든 '발송 완료'라고 단정하지 않고 tbl_send 확인으로 보낸다.
$hasNotice = [bool](Get-Command Get-CMSendNotice -ErrorAction SilentlyContinue)
Check 'Get-CMSendNotice가 있다' $hasNotice
if ($hasNotice) {
    # 창이 남은 경우는 실제로 살아 있는 숨은 창(화면에 띄우지 않는 폼)의 핸들로, 닫힌 경우는 0 핸들로 본다.
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $live = $form.Handle
    $closed = Get-CMSendNotice -Compose ([IntPtr]::Zero) -Name '홍길동'
    $open   = Get-CMSendNotice -Compose $live -Name '홍길동'
    $form.Dispose()
    foreach ($pair in @(@('창 닫힘', $closed), @('창 남음', $open))) {
        $label, $text = $pair
        Check "${label}: '발송 완료'라고 하지 않는다" ($text -notmatch '발송 완료') $text
        Check "${label}: tbl_send 확인을 안내한다" ($text -match 'tbl_send' -and $text -match 'cm_export\.py --sent') $text
    }
    Check '창 남음: 다시 누르지 말라고 한다' ($open -match '다시 누르지') $open
    Check '창 닫힘: 창이 닫혔다고만 말한다' ($closed -match '창 닫힘') $closed
}

$reply = Get-Content (Join-Path $PSScriptRoot '..\cm_reply.ps1') -Raw -Encoding utf8
Check "cm_reply.ps1: '발송 완료' 문구가 없다" ($reply -notmatch '발송 완료')
Check 'cm_reply.ps1: 회신 창 핸들을 그대로 넘겨 안내한다' ($reply -match 'Get-CMSendNotice -Compose \$compose ')

# ---- 첨부 대상 고르기: 파일명 패턴과 보낸사람 필터
$rows = @(
    [pscustomobject]@{ Index = 0; C0 = '홍길동'; C3 = '체크리스트.hwp' },
    [pscustomobject]@{ Index = 1; C0 = '김철수'; C3 = '체크리스트.hwp' },
    [pscustomobject]@{ Index = 2; C0 = '홍길동'; C3 = '사진.jpg' },
    [pscustomobject]@{ Index = 3; C0 = '이[영]희'; C3 = '계획서.hwp' }
)
$r = Find-CMAttachmentRow -Rows $rows -Match '*체크리스트*'
Check 'Find-CMAttachmentRow: -From 없으면 파일명만 본다' ($r.Count -eq 2) "count=$($r.Count)"
$r = Find-CMAttachmentRow -Rows $rows -Match '*체크리스트*' -From '홍길동'
Check 'Find-CMAttachmentRow: -From으로 보낸사람을 가린다' ($r.Count -eq 1 -and $r[0].C0 -eq '홍길동') "count=$($r.Count)"
$r = Find-CMAttachmentRow -Rows $rows -Match '*' -From '홍'
Check 'Find-CMAttachmentRow: -From은 부분일치다' ($r.Count -eq 2) "count=$($r.Count)"
$r = Find-CMAttachmentRow -Rows $rows -Match '*' -From '이[영]희'
Check 'Find-CMAttachmentRow: -From의 대괄호는 글자 그대로 본다' ($r.Count -eq 1 -and $r[0].Index -eq 3) "count=$($r.Count)"
$r = Find-CMAttachmentRow -Rows $rows -Match '*.pdf' -From '홍길동'
Check 'Find-CMAttachmentRow: 맞는 게 없으면 0건' ($r.Count -eq 0) "count=$($r.Count)"

$save = Get-Content (Join-Path $PSScriptRoot '..\cm_save_attachments.ps1') -Raw -Encoding UTF8
Check 'cm_save_attachments.ps1: 행을 다시 찾을 때 보낸사람까지 맞춘다' ($save -match '\$_\.C3 -eq \$file -and \$_\.C0 -eq \$sender')

""
if ($script:fail) { "실패 $($script:fail)건"; exit 1 } else { '모두 통과'; exit 0 }
