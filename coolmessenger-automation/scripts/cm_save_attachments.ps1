# 쿨메신저 받은메시지의 첨부파일을 골라서 일괄로 내려받아 지정 폴더에 모은다.
#
#   .\cm_save_attachments.ps1 -Match '*체크리스트*' -Dest '.\수합\체크리스트'
#   .\cm_save_attachments.ps1 -Match '*체크리스트*' -Dest '...' -WhatIf   # 대상만 확인
#
# 저장 위치는 쿨메신저가 마지막으로 쓴 폴더로 고정돼 있고 선택할 수 없다.
# 그래서 저장된 파일을 찾아 -Dest로 옮기는 방식으로 동작한다.

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Match,      # 첨부파일명 와일드카드
    [Parameter(Mandatory)][string]$Dest,       # 모아 둘 폴더
    [string[]]$WatchDirs,                      # 저장 위치 후보(생략 시 기본값)
    [int]$DownloadTimeoutSec = 25
)

. "$PSScriptRoot\cm_lib.ps1"

if (-not $WatchDirs) {
    $WatchDirs = @(
        "$env:USERPROFILE\Documents\CoolMessenger Files\Received Files",
        "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\OneDrive\Desktop", $Dest, (Split-Path $Dest -Parent)
    )
}
# 쿨메신저가 마지막에 쓴 폴더도 후보에 넣는다(저장 후 탐색기가 그 폴더로 열릴 때가 있다).
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
if ($msgWin -eq [IntPtr]::Zero) {
    throw '메시지 관리함을 열지 못했습니다.'
}
$list = Find-CMControl -Parent $msgWin -Class 'SysListView32' -TextLike '메시지 리스트*'
$save = Find-CMControl -Parent $msgWin -Class 'Button' -TextLike '모든파일 저장*'

$targets = (Read-CMList -List $list).Rows | Where-Object { $_.C3 -like $Match }
Write-Host ("대상 {0}건 (패턴 {1})" -f $targets.Count, $Match)

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

    # 새 회신이 들어오면 행이 밀리므로 인덱스를 다시 찾는다.
    $cur = (Read-CMList -List $list).Rows | Where-Object { $_.C3 -eq $file } | Select-Object -First 1
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
        $why = if ($state -eq 'STALLED') { '전송멈춤(보낸분 PC 응답없음)' } else { '저장안됨' }
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
