# 쿨메신저 받은메시지의 첨부파일을 골라서 일괄로 내려받아 지정 폴더에 모은다.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/cm_save_attachments.ps1 -Match '*체크리스트*' -Dest "$env:USERPROFILE\Documents\수합\체크리스트"
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/cm_save_attachments.ps1 -Match '*체크리스트*' -Dest '...' -WhatIf   # 대상만 확인
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/cm_save_attachments.ps1 -Match '*' -From '홍길동' -Dest '...'       # 그 사람이 보낸 첨부만
#
# 저장 위치는 레지스트리 DownPath로 정해져 있고 선택할 수 없다.
# 그래서 저장된 파일을 파일명으로 찾아 -Dest로 옮기는 방식으로 동작한다.

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Match,      # 첨부파일명 와일드카드
    [Parameter(Mandatory)][string]$Dest,       # 모아 둘 폴더
    [string]$From,                             # 보낸사람 이름에 이 문구가 들어간 것만
    [string[]]$WatchDirs,                      # 저장 위치 후보(생략 시 기본값)
    [int]$DownloadTimeoutSec = 25
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # 에이전트가 출력을 받아도 한글이 깨지지 않게

# 상대 경로 -Dest는 Split-Path -Qualifier가 실패해 드라이브 루트 탐색이 깨지므로 먼저 절대 경로로 바꾼다
$Dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Dest)

. "$PSScriptRoot\cm_lib.ps1"

if (-not $WatchDirs) {
    $WatchDirs = @(
        "$env:USERPROFILE\Documents\CoolMessenger Files\Received Files",
        "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\OneDrive\Desktop", $Dest, (Split-Path $Dest -Parent)
    )
}
# 실제 저장 위치는 레지스트리 DownPath다. 이것이 빠져 있으면 파일을 저장해 놓고도 못 찾아
# 전부 '저장안됨'으로 끝난다.
try {
    $WatchDirs = @((Get-ItemProperty 'HKCU:\Software\Jiransoft\CoolMsg50\Option\GetFile' -ErrorAction Stop).DownPath) + $WatchDirs
} catch {}
# 열린 탐색기 창의 폴더도 폴백 후보에 넣는다(저장 후 탐색기가 저장 폴더로 열릴 때가 있다).
foreach ($w in (New-Object -ComObject Shell.Application).Windows()) {
    try { $WatchDirs += $w.Document.Folder.Self.Path } catch {}
}
$WatchDirs = $WatchDirs | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

# 저장 폴더를 고를 수 없고 후보 목록이 빗나갈 수 있으므로, 최후에는 파일명으로 찾는다.
# 탐색 뿌리는 사용자 프로필과 업무 드라이브 정도로 제한한다.
$SearchRoots = @($env:USERPROFILE, (Split-Path $Dest -Qualifier) + '\') |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

function Find-SavedFile {
    param([string]$FileName, [datetime]$Since)
    foreach ($d in $WatchDirs) {
        $p = Join-Path $d $FileName
        if ((Test-Path $p) -and ((Get-Item $p).LastWriteTime -gt $Since.AddSeconds(-5))) { return $p }
    }
    foreach ($root in $SearchRoots) {
        $hit = Get-ChildItem $root -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue |
               Where-Object { $_.LastWriteTime -gt $Since.AddSeconds(-5) } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Force $Dest | Out-Null }

$msgWin = Open-CMArchive
$list = Find-CMControl -Parent $msgWin -Class 'SysListView32' -TextLike '메시지 리스트*'
$save = Find-CMControl -Parent $msgWin -Class 'Button' -TextLike '모든파일 저장*'

$targets = @(Find-CMAttachmentRow -Rows (Read-CMList -List $list).Rows -Match $Match -From $From)
Write-Host ("대상 {0}건 (패턴 {1}{2})" -f $targets.Count, $Match, $(if ($From) { ", 보낸사람 $From" }))

$result = @()
foreach ($t in $targets) {
    $sender = $t.C0
    $file   = $t.C3
    if (Test-Path (Join-Path $Dest $file)) {
        Write-Host "  SKIP  $sender — 이미 보관됨"
        $result += [pscustomobject]@{ 보낸사람=$sender; 파일=$file; 결과='이미보관' }
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($sender, '첨부 저장')) { continue }

    # 새 메시지가 들어오면 행이 밀리므로 인덱스를 다시 찾는다. 같은 파일명을 여러 사람이 보냈을 수 있어 보낸사람까지 맞춘다.
    $cur = (Read-CMList -List $list).Rows | Where-Object { $_.C3 -eq $file -and $_.C0 -eq $sender } | Select-Object -First 1
    if (-not $cur) {
        Write-Host "  MISS  $sender — 목록에서 사라짐"
        $result += [pscustomobject]@{ 보낸사람=$sender; 파일=$file; 결과='목록없음' }
        continue
    }
    if (-not (Select-CMMessage -MsgWin $msgWin -List $list -ExpectSender $sender -Index $cur.Index)) {
        Write-Host "  FAIL  $sender — 미리보기 전환 실패"
        $result += [pscustomobject]@{ 보낸사람=$sender; 파일=$file; 결과='선택실패' }
        continue
    }

    $t0 = Get-Date
    [void][CM]::Msg($save, 0x00F5, [IntPtr]0, [IntPtr]0)     # BM_CLICK
    $state = Wait-CMDownload -TimeoutSec $DownloadTimeoutSec
    Start-Sleep -Seconds 2
    $saved = Find-SavedFile -FileName $file -Since $t0

    if (-not $saved) {
        $why = if ($state -eq 'STALLED') { '전송멈춤(관리함에서 재시도)' } else { '저장안됨' }
        Write-Host "  FAIL  $sender — $why"
        $result += [pscustomobject]@{ 보낸사람=$sender; 파일=$file; 결과=$why }
        continue
    }
    Move-Item $saved $Dest -Force
    Write-Host "  OK    $sender — $file"
    $result += [pscustomobject]@{ 보낸사람=$sender; 파일=$file; 결과='저장' }
}

Write-Host ''
$result | Format-Table -AutoSize
