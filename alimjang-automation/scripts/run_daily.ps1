<#
  알림장 일일 자동 정리(작업 스케줄러용).
  1) alim_export.py 로 전달사항 텍스트 저장 + 첨부 복사
  2) 첨부가 있고 요약 파일이 아직 없으면 extract_attachments.py 로 첨부를 텍스트로 추출
     (%LOCALAPPDATA%\알림장-자동화\extract\<날짜>\, 14일 지나면 삭제)
  3) claude -p 는 추출된 텍스트만 읽어 첨부 요약 작성
  로그: %LOCALAPPDATA%\알림장-자동화\log\<날짜>.log

  사용(스킬 루트에서): pwsh -NoProfile -File scripts/run_daily.ps1 [-Date 2026-09-22] [-Force]
#>
param(
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [switch]$Force
)

$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'
$env:TTS_SUMMARY = 'off'   # 자동 실행 세션은 음성 요약·누락 가드를 끈다
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$scripts = $PSScriptRoot
$projectRoot = if ($env:ALIM_PROJECT_ROOT) { $env:ALIM_PROJECT_ROOT } else { (Resolve-Path (Join-Path $scripts '..\..\..\..')).Path }
$logDir = Join-Path $env:LOCALAPPDATA '알림장-자동화\log'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "$Date.log"
function Write-Log($m) { "[$(Get-Date -Format 'HH:mm:ss')] $m" | Out-File -Append -Encoding utf8 $log }

Write-Log "시작 date=$Date"
if (-not (Test-Path '\\관리자\$ALIM$\ALIM.DBF')) { Write-Log '서버(\\관리자\$ALIM$) 접근 불가 — 종료'; exit 1 }

$out = & python (Join-Path $scripts 'alim_export.py') --date $Date 2>&1
$exportCode = $LASTEXITCODE
$out | ForEach-Object { Write-Log "export: $_" }
if ($exportCode -ne 0) { Write-Log "alim_export 실패(종료 코드 $exportCode) — 종료"; exit 3 }

$d = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null)
$label = '{0}({1})' -f $Date, '일월화수목금토'[[int]$d.DayOfWeek]
$sy = if ($d.Month -ge 3) { $d.Year } else { $d.Year - 1 }
$folder = Join-Path $projectRoot "$sy 업무\4. 교무\알림장\$label"
$summary = Join-Path $folder "$label 알림장 첨부 요약.txt"

$atts = @(Get-ChildItem -LiteralPath $folder -Filter '첨부*' -File -ErrorAction SilentlyContinue)
if ($atts.Count -eq 0) { Write-Log '첨부 없음 — 요약 생략, 종료'; exit 0 }
if ((Test-Path -LiteralPath $summary) -and -not $Force) { Write-Log '요약 파일 이미 있음 — 생략, 종료'; exit 0 }

# 첨부 텍스트 추출(결정론적). 추출본은 로컬 작업 폴더에만 두고 알림장 폴더에는 쓰지 않는다.
$work = Join-Path $env:LOCALAPPDATA "알림장-자동화\extract\$Date"
Get-ChildItem (Split-Path $work) -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$ext = & python (Join-Path $scripts 'extract_attachments.py') $folder $work 2>&1
$ext | ForEach-Object { Write-Log "extract: $_" }
$mds = @(Get-ChildItem -LiteralPath $work -Filter '*.md' -File -ErrorAction SilentlyContinue)
if ($mds.Count -eq 0) { Write-Log '추출된 텍스트 없음 — 요약 생략'; exit 2 }
$extLines = ($ext | Where-Object { "$_" -match '^(OK|WARN|FAIL) ' }) -join "`n"

$prompt = @"
알림장 첨부 요약을 써 줘. 첨부 텍스트는 스크립트로 이미 추출해 두었으니 아래 .md 파일만 Read로 읽어(원본 첨부를 다시 변환하지 마).
추출 결과:
$extLines

참고용 당일 전달사항: "$folder\$label 알림장 전달사항.txt"
출력 파일: "$summary"

형식: 첫 줄 "$label 알림장 첨부 요약", 빈 줄, 이후 첨부마다 "첨부<n> <부서>, <문서 제목>" 한 줄로 시작해 1. 2. 숫자 제목으로 섹션을 나눈다. 첨부 여러 개를 이 파일 하나에 통합한다.
규칙: 순수 텍스트(마크다운 기호·불릿·구분선 금지, 표는 산문으로), 연속 빈 줄 금지, 원문 톤의 합니다체, 원문의 30~50% 분량, URL·전화번호·공문번호 원형 보존, QR은 "(QR 코드 동봉)", 숫자·영문은 원래 표기. 요약에 넣는 날짜의 요일은 python으로 계산해 검증한다. 추출 결과가 WARN 또는 FAIL인 첨부는 요약 끝에 "이 첨부는 일부 내용(그림 속 글자 등)을 읽지 못했습니다." 한 문장을 붙인다.
작성 후 연속 빈 줄 검사(grep -nE "^$" | awk)를 한다. 질문하지 말고 끝까지 처리한 뒤, 마지막에 요약 파일 경로와 첨부별 한 줄 요지만 출력해.
"@

Write-Log "claude -p 시작 (첨부 $($atts.Count)건, 추출 $($mds.Count)건)"
Push-Location $projectRoot
try {
  $res = & claude -p $prompt `
    --allowedTools 'Read' 'Write' 'Edit' 'Bash(python:*)' 'Bash(grep:*)' 'Bash(awk:*)' 2>&1
  $res | ForEach-Object { Write-Log "claude: $_" }
} finally { Pop-Location }

if (Test-Path -LiteralPath $summary) { Write-Log "완료: $summary"; exit 0 }
Write-Log '실패: 요약 파일이 만들어지지 않음'; exit 2
