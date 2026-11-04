<# 선택 의존성 없는 환경에서 기본 기능을 사용 가능으로 판정하는지 확인한다. #>
$ErrorActionPreference = 'Stop'
$realPython = (Get-Command python -CommandType Application | Select-Object -First 1).Source
$srcRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('school_optional_' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PYTHONPATH
$oldLegacy = $env:HWPX_AUTOMATION_DIR
$oldHwp = $env:ALIM_HWP_CMD
$oldHwpx = $env:ALIM_HWPX_CMD
try {
  $setup = Join-Path $tmp 'school-work-setup\scripts'
  $alim = Join-Path $tmp 'alimjang-automation\scripts'
  $mods = Join-Path $tmp 'fake'
  New-Item -ItemType Directory -Force $setup, $alim, $mods | Out-Null
  Copy-Item (Join-Path (Split-Path $PSScriptRoot) 'check_requirements.ps1') $setup
  Copy-Item (Join-Path $srcRoot 'alimjang-automation\scripts\extract_attachments.py') $alim
  '' | Set-Content -LiteralPath (Join-Path (Split-Path $alim) 'SKILL.md')
  '' | Set-Content -LiteralPath (Join-Path $mods 'dbfread.py')
  foreach ($module in 'hwpx_tomd', 'openpyxl') {
    'raise ImportError("optional module absent")' | Set-Content -LiteralPath (Join-Path $mods "$module.py")
  }
  $env:PYTHONPATH = $mods
  $env:HWPX_AUTOMATION_DIR = Join-Path $tmp 'missing'
  $env:ALIM_HWP_CMD = ''
  $env:ALIM_HWPX_CMD = ''
  # 실제 앱·서버·사용자 설정에 닿지 않는다. 설치된 공통 실행 파일만 모의한다.
  function Get-Command { param($Name, $CommandType, $ErrorAction)
    if ($Name -eq 'python') { [pscustomobject]@{ Source=$realPython } }
    elseif ($Name -eq 'npx') { [pscustomobject]@{ Source='npx' } }
  }
  function Test-Path { param($Path, $LiteralPath)
    $p = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ("$p" -notlike "$tmp*") { return $false }
    Microsoft.PowerShell.Management\Test-Path -LiteralPath $p
  }
  $output = & (Join-Path $setup 'check_requirements.ps1') -Skill alimjang-automation 6>&1 | Out-String
  $code = $LASTEXITCODE
  if ($code -ne 0 -or $output -match '\[없음\]') { throw "선택 도구 부재가 기본 기능을 막음: $output" }
  foreach ($format in 'HWPX', 'HWP') {
    if ($output -notmatch "\[확인\] $format 첨부 읽기: 미설정") { throw "$format 상태 누락: $output" }
  }
  if ($output -notmatch '\[확인\] Python 패키지 openpyxl' -or $output -notmatch '\[확인\] pdftotext') {
    throw "다른 첨부 도구도 권장 항목이어야 함: $output"
  }
  # 잘못 설정된 선택 도구도 기본 기능과 분리해 보고한다.
  $env:ALIM_HWP_CMD = 'invalid-json'
  $output = & (Join-Path $setup 'check_requirements.ps1') -Skill alimjang-automation 6>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or $output -notmatch 'JSON 문자열 배열') { throw "설정 오류 분리 실패: $output" }
  Write-Host '선택 도구 미설치·설정 오류가 기본 기능을 막지 않음: 통과'
} finally {
  $env:PYTHONPATH = $oldPath
  $env:HWPX_AUTOMATION_DIR = $oldLegacy
  $env:ALIM_HWP_CMD = $oldHwp
  $env:ALIM_HWPX_CMD = $oldHwpx
  # 이번 시험에서 생성한 임시 폴더만 정리한다.
  if ([IO.Path]::GetFullPath($tmp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and
      (Split-Path $tmp -Leaf) -like 'school_optional_*') {
    Remove-Item -LiteralPath $tmp -Recurse -Force
  }
}

