<#
  run_daily.ps1 밀폐 시험. 서버·작업 스케줄러·claude 를 부르지 않는다.
  실행(스킬 루트에서): pwsh -NoProfile -File scripts/tests/test_run_daily.ps1
  - 시험용 프로젝트 트리를 임시 폴더에 만들고 run_daily.ps1 사본을 그 안에서 돌린다.
  - Test-Path(서버 확인)·python·claude 는 같은 이름의 함수로 가린다(함수가 명령보다 먼저 잡힌다).
  - alim_export.py 는 진짜 스크립트를 가짜 dbfread·가짜 DB 폴더(--src)로 돌린다.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$realScripts = Split-Path $here
$realPython = (Get-Command python -CommandType Application | Select-Object -First 1).Source
$fails = 0
function Assert($cond, $msg) {
  if ($cond) { Write-Host "ok   $msg" } else { Write-Host "FAIL $msg"; $script:fails++ }
}

function New-Fixture {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("alimrd_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $skill = Join-Path $tmp 'proj\.claude\skills\알림장-자동화\scripts'
  New-Item -ItemType Directory -Force $skill | Out-Null
  Copy-Item (Join-Path $realScripts 'run_daily.ps1'), (Join-Path $realScripts 'alim_export.py') $skill
  $fake = Join-Path $tmp 'fakemods'; New-Item -ItemType Directory $fake | Out-Null
  @'
import datetime, json
class DBF:
    def __init__(self, path, encoding=None, char_decode_errors=None):
        self.path = path
    def __iter__(self):
        with open(self.path, encoding="utf-8") as f:
            rows = json.load(f)
        for r in rows:
            r = dict(r)
            if r.get("ALDATE"):
                r["ALDATE"] = datetime.date.fromisoformat(r["ALDATE"])
            yield r
'@ | Set-Content -Encoding utf8NoBOM (Join-Path $fake 'dbfread.py')
  $db = Join-Path $tmp 'db'; New-Item -ItemType Directory $db | Out-Null
  '[{"ALID": "4", "ALBU": "연구부"}]' | Set-Content -Encoding utf8NoBOM (Join-Path $db 'AGICHO.DBF')
  $local = Join-Path $tmp 'local'; New-Item -ItemType Directory $local | Out-Null
  [pscustomobject]@{ Tmp = $tmp; Script = Join-Path $skill 'run_daily.ps1'; Proj = Join-Path $tmp 'proj'
                     Fake = $fake; Db = $db; Local = $local }
}

function Write-Rows($fx, $date, $att) {
  $r = [ordered]@{ ALDATE = $date; ALJOGI = '' }
  1..20 | ForEach-Object { $r[('ALME{0:D2}' -f $_)] = '' }
  $r['ALME04'] = '연구부 안내'
  1..5 | ForEach-Object { $r["ALHWP$_"] = ''; $r["ALID0$_"] = '' }
  if ($att) { $r['ALHWP1'] = $att; $r['ALID01'] = '4'; [IO.File]::WriteAllBytes((Join-Path $fx.Db $att), [byte[]](1, 2, 3)) }
  ConvertTo-Json @($r) | Set-Content -Encoding utf8NoBOM (Join-Path $fx.Db 'ALIM.DBF')
}

# 가짜 명령. $global:mode 로 alim_export 동작을 고른다: 'real'(진짜 스크립트+가짜 DB) / 'fail'(종료 코드 1)
function Test-Path { param([Parameter(Position = 0)]$Path, [string]$LiteralPath)
  $p = if ($LiteralPath) { $LiteralPath } else { "$Path" }
  if ($p -like '\\*') { return $p -like '*ALIM.DBF' }   # 서버(UNC) 경로는 실제로 묻지 않는다
  Microsoft.PowerShell.Management\Test-Path -LiteralPath $p
}
function python {
  $a = @($args)
  if ($a[0] -like '*alim_export.py') {
    if ($global:mode -eq 'fail') {   # 실제처럼 표준 오류로 내고 0 아닌 코드
      Write-Error "dbfread가 없습니다. 'pip install dbfread' 후 다시 실행하세요."
      $global:LASTEXITCODE = $global:failCode; return
    }
    $env:PYTHONPATH = $global:fx.Fake
    & $realPython @a --src $global:fx.Db
    return
  }
  if ($a[0] -like '*extract_attachments.py') {
    $work = $a[2]; New-Item -ItemType Directory -Force $work | Out-Null
    Get-ChildItem -LiteralPath $a[1] -Filter '첨부*' -File | ForEach-Object {
      "본문" | Set-Content -Encoding utf8NoBOM (Join-Path $work ($_.Name + '.md'))
      "WARN $($_.Name) -> x (2자) 본문 이미지 1개(이미지 속 글자는 추출 안 됨)"
    }
    $global:LASTEXITCODE = 0; return
  }
  throw "예상 밖 python 호출: $a"
}
function claude {
  $global:prompt = $args[1]
  if ($global:prompt -match '출력 파일: "([^"]+)"') { '요약' | Set-Content -Encoding utf8NoBOM $Matches[1] }
  $global:LASTEXITCODE = 0
}

function Invoke-Daily($fx, $date) {
  # PATH 를 빈 폴더로 바꿔, 함수 가림이 깨져도 진짜 python·claude 가 잡히지 않게 한다
  $saved = $env:LOCALAPPDATA, $env:PATH
  $env:LOCALAPPDATA = $fx.Local
  $env:PATH = $fx.Local
  try { & $fx.Script -Date $date 2>$null | Out-Null; return $LASTEXITCODE }
  finally { $env:LOCALAPPDATA, $env:PATH = $saved; Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
}
function Read-Log($fx, $date) { Get-Content -Raw -Encoding utf8 (Join-Path $fx.Local "알림장-자동화\log\$date.log") }

# 1. alim_export 가 실패하면 '첨부 없음'(0)이 아니라 3으로 끝난다(양수·음수 종료 코드 모두)
foreach ($fc in 1, -1073741819) {
  $global:fx = New-Fixture; $global:mode = 'fail'; $global:failCode = $fc; $global:prompt = $null
  try {
    $code = Invoke-Daily $fx '2020-09-21'
    Assert ($code -eq 3) "export 실패($fc) → 종료 코드 3 (실제 $code)"
    Assert ((Read-Log $fx '2020-09-21') -match 'dbfread') "로그에 export 오류 출력이 남는다($fc)"
    Assert ($null -eq $global:prompt) "export 실패 시 claude 를 부르지 않는다($fc)"
  } finally { Remove-Item -Recurse -Force $fx.Tmp }
}

# 2. 첨부 없는 날은 그대로 0
$global:fx = New-Fixture; $global:mode = 'real'; $global:prompt = $null
try {
  Write-Rows $fx '2020-09-21' $null
  $code = Invoke-Daily $fx '2020-09-21'
  Assert ($code -eq 0) "첨부 없음 → 0 (실제 $code)"
  Assert ($null -eq $global:prompt) '첨부 없으면 claude 를 부르지 않는다'
} finally { Remove-Item -Recurse -Force $fx.Tmp }

# 3. 학년도 경계: 2월 날짜도 추출 폴더와 첨부를 찾는 폴더가 같아 요약까지 간다(실행일은 다른 학년도)
$global:fx = New-Fixture; $global:mode = 'real'; $global:prompt = $null
try {
  Write-Rows $fx '2020-02-27' 'H02271.PDF'
  $code = Invoke-Daily $fx '2020-02-27'
  $folder = Join-Path $fx.Proj '2019 업무\4. 교무\알림장\2020-02-27(목)'
  Assert (Microsoft.PowerShell.Management\Test-Path -LiteralPath (Join-Path $folder '첨부1_연구부_H02271.PDF')) '첨부가 대상 날짜 학년도(2019) 폴더에 복사된다'
  Assert ($code -eq 0) "요약 생성 → 0 (실제 $code)"
  Assert (Microsoft.PowerShell.Management\Test-Path -LiteralPath (Join-Path $folder '2020-02-27(목) 알림장 첨부 요약.txt')) '요약 파일이 같은 폴더에 생긴다'
  # 4. 프롬프트: WARN 이든 FAIL 이든 '읽지 못했습니다' 문장을 붙이라고 한다
  Assert ("$global:prompt" -match 'WARN 또는 FAIL') '프롬프트 조건이 WARN 또는 FAIL'
  Assert ("$global:prompt" -match '(?m)^WARN 첨부1_') '프롬프트에 WARN 추출 결과 줄이 들어간다'
} finally { Remove-Item -Recurse -Force $fx.Tmp }

# 5. 3월 1일 이후 날짜는 그해 학년도 폴더
$global:fx = New-Fixture; $global:mode = 'real'; $global:prompt = $null
try {
  Write-Rows $fx '2020-03-02' 'H03021.PDF'
  $code = Invoke-Daily $fx '2020-03-02'
  $folder = Join-Path $fx.Proj '2020 업무\4. 교무\알림장\2020-03-02(월)'
  Assert ($code -eq 0) "3월 날짜 → 0 (실제 $code)"
  Assert (Microsoft.PowerShell.Management\Test-Path -LiteralPath (Join-Path $folder '2020-03-02(월) 알림장 첨부 요약.txt')) '3월 날짜 요약이 그해(2020) 학년도 폴더에 생긴다'
} finally { Remove-Item -Recurse -Force $fx.Tmp }

if ($fails) { Write-Host "$fails 건 실패"; exit 1 }
Write-Host '모두 통과'
