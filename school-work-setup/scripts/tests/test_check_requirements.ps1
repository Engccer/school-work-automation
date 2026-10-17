<#
  check_requirements.ps1 시험. 실제 환경을 읽기만 하므로 결과 값이 아니라 계약(종료 코드·구조)을 본다.
  실행(스킬 루트에서): powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/test_check_requirements.ps1
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # 점검 스크립트의 UTF-8 출력을 그대로 받는다
$script = Join-Path (Split-Path $PSScriptRoot) 'check_requirements.ps1'
$fails = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok   $msg" } else { Write-Host "FAIL $msg"; $script:fails++ }
}

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Skill nope 2>&1 | Out-String
Assert ($LASTEXITCODE -eq 2) "알 수 없는 스킬 → 2 (실제 $LASTEXITCODE)"
Assert ($out -match 'neis-automation') '가능한 값을 알려 준다'

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script 2>&1 | Out-String
$code = $LASTEXITCODE
Assert ($code -in 0, 1) "전체 점검 → 0 또는 1 (실제 $code)"
foreach ($h in '공통', '업무포털 공통', 'neis-automation', 'k-edufine-automation', 'kyodetong-submit', 'coolmessenger-automation', 'alimjang-automation') {
  Assert ($out -match "(?m)^$([regex]::Escape($h))") "제목 '$h' 이 나온다"
}
Assert (($code -eq 1) -eq ($out -match '\[없음\]')) '종료 코드 1 과 [없음] 줄의 존재가 일치한다'
Assert (([regex]::Matches($out, 'KCase Agent')).Count -eq 1) '업무포털 공통 항목은 한 번만 나온다'

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Skill coolmessenger-automation 2>&1 | Out-String
Assert ($out -notmatch '업무포털 공통') '브라우저 스킬이 없으면 업무포털 공통을 건너뛴다'
Assert ($out -notmatch 'alimjang-automation') '고르지 않은 스킬은 점검하지 않는다'

if ($fails) { Write-Host "$fails 건 실패"; exit 1 }
Write-Host '모두 통과'
