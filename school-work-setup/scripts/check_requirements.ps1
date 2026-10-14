<#
  school-work-automation 번들 요구사항 점검. 읽기만 하고 아무것도 설치·변경하지 않는다.
  사용: pwsh -NoProfile -File scripts/check_requirements.ps1 [-Skill neis-automation,alimjang-automation]
  출력: 스킬마다 "OK / 없음 / 확인" 줄. 종료 코드 0 = 빠진 것 없음, 1 = 빠진 것 있음, 2 = 잘못된 인자.
  브라우저 제어 확장 연결처럼 스크립트로 볼 수 없는 것은 SKILL.md 절차가 맡는다.
#>
param([string[]]$Skill)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # bash 등 다른 셸이 출력을 받아도 한글이 깨지지 않게

$all = 'neis-automation', 'k-edufine-automation', 'kyodetong-submit', 'coolmessenger-automation', 'alimjang-automation'
$targets = if ($Skill) { $Skill -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { $all }
$bad = $targets | Where-Object { $_ -notin $all }
if ($bad) { Write-Host "알 수 없는 스킬: $($bad -join ', '). 가능한 값: $($all -join ', ')"; exit 2 }

$skillsRoot = Split-Path (Split-Path $PSScriptRoot)
$script:missing = 0
function Report($state, $item, $hint) {
  if ($state -eq '없음') { $script:missing++ }
  $line = "  [$state] $item"
  if ($hint) { $line += " : $hint" }
  Write-Host $line
}

# ---- 공통 판정 함수 (결과를 한 번만 계산한다)
$isWin = $IsWindows -or $env:OS -eq 'Windows_NT'
$pyExe = $null
foreach ($c in 'python', 'py') {
  $cmd = Get-Command $c -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) {   # WindowsApps 의 스토어 안내용 python.exe 는 실행해 봐야 가려진다
    $v = & $cmd.Source -c "import sys; print(sys.version_info[0])" 2>$null
    if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { $pyExe = $cmd.Source; break }
  }
}
function PyModule($m) {
  if (-not $pyExe) { return $false }
  & $pyExe -c "import $m" 2>$null | Out-Null
  $LASTEXITCODE -eq 0
}
# $why 가 있으면 일부 기능에만 필요한 선택 의존성이라 '없음' 대신 '확인'으로 보고한다
function CheckModules($mods, $why) {
  if (-not $pyExe) { return }   # Python 자체가 없으면 공통에서 이미 보고했다
  foreach ($m in $mods) {
    if (PyModule $m) { Report 'OK' "Python 패키지 $m" }
    elseif ($why) { Report '확인' "Python 패키지 $m" "pip install $m ($why)" }
    else { Report '없음' "Python 패키지 $m" "pip install $m" }
  }
}
function SkillFolder($name) {
  if (Test-Path (Join-Path $skillsRoot "$name\SKILL.md")) { Report 'OK' "스킬 폴더 $name" }
  else { Report '없음' "스킬 폴더 $name" 'npx skills add Engccer/school-work-automation -g' }
}
function BrowserNeeds {
  Report '확인' '브라우저 제어 확장 연결' '에이전트가 탭 목록 조회로 확인한다(SKILL.md 2단계)'
  $kcase = Join-Path ${env:ProgramFiles(x86)} 'Ksign\KCase\KCaseAgent.exe'
  if (${env:ProgramFiles(x86)} -and (Test-Path -LiteralPath $kcase)) { Report 'OK' '인증서 로그인 프로그램(KCase Agent)' }
  else { Report '없음' '인증서 로그인 프로그램(KCase Agent)' '업무포털 로그인 페이지 하단 [인증서프로그램다운로드]로 설치(서울 업무포털 기준)' }
  $certDir = 'C:\GPKI\Certificate\class2'
  $sig = @(Get-ChildItem -LiteralPath $certDir -Filter '*_sig.cer' -File -ErrorAction SilentlyContinue)
  if ($sig.Count -eq 0) { Report '확인' '교육행정 전자서명 인증서' "$certDir 에 없음. 이동식 매체·다른 경로에 있으면 사용자에게 확인" ; return }
  foreach ($f in $sig) {
    try {
      $until = [Security.Cryptography.X509Certificates.X509Certificate2]::new($f.FullName).NotAfter
      if ($until -gt (Get-Date)) { Report 'OK' "인증서 $($f.Name)" "만료 $($until.ToString('yyyy-MM-dd'))" }
      else { Report '없음' "인증서 $($f.Name)" "만료됨 $($until.ToString('yyyy-MM-dd')). 재발급 대상" }
    } catch { Report '확인' "인증서 $($f.Name)" '읽지 못함' }
  }
}

Write-Host '공통'
if ($isWin) { Report 'OK' 'Windows' } else { Report '없음' 'Windows' 'K-에듀파인·쿨메신저·알림장 스킬은 Windows 전용' }
if ($PSVersionTable.PSVersion.Major -ge 7) { Report 'OK' "PowerShell $($PSVersionTable.PSVersion)" }
else { Report '없음' 'PowerShell 7' 'winget install Microsoft.PowerShell' }
if (Get-Command npx -ErrorAction SilentlyContinue) { Report 'OK' 'Node.js(npx)' }
else { Report '없음' 'Node.js(npx)' '스킬 설치·갱신에 필요. https://nodejs.org' }
$web = 'neis-automation', 'k-edufine-automation', 'kyodetong-submit'
if ($targets | Where-Object { $_ -ne 'k-edufine-automation' -and $_ -ne 'kyodetong-submit' }) {
  if ($pyExe) { Report 'OK' "Python 3 ($pyExe)" } else { Report '없음' 'Python 3' 'python.org 또는 winget install Python.Python.3.12' }
}
if ($targets | Where-Object { $_ -in $web }) {
  Write-Host ''
  Write-Host '업무포털 공통 (나이스·K-에듀파인·교데통)'
  BrowserNeeds
}

foreach ($s in $targets) {
  Write-Host ''
  Write-Host $s
  SkillFolder $s
  switch ($s) {
    'neis-automation' { CheckModules @('openpyxl') '급여명세서 CSV 변환에만 필요' }
    'coolmessenger-automation' {
      $memo = Join-Path "$env:LOCALAPPDATA" 'CoolMessenger\Memo'
      if (Test-Path -LiteralPath $memo) { Report 'OK' '쿨메신저 클라이언트 메시지 DB' }
      else { Report '없음' '쿨메신저 클라이언트 메시지 DB' "$memo 없음. 쿨메신저(Gentoo)를 설치하고 한 번 로그인한다" }
    }
    'alimjang-automation' {
      CheckModules @('dbfread', 'openpyxl') ''
      # 평일 자동 정리(run_daily.ps1)가 부르는 에이전트 CLI. 수동 사용에는 필요 없다
      $agent = if ($env:ALIM_AGENT_CMD) { @($env:ALIM_AGENT_CMD -split '\s+' | Where-Object { $_ })[0] } else { 'claude' }
      if (Get-Command $agent -ErrorAction SilentlyContinue) { Report 'OK' "에이전트 CLI $agent (자동 정리용)" }
      else { Report '확인' "에이전트 CLI $agent" '평일 자동 정리에만 필요. 다른 에이전트는 ALIM_AGENT_CMD 로 지정' }
      $hwpx = if ($env:HWPX_AUTOMATION_DIR) { $env:HWPX_AUTOMATION_DIR } else { Join-Path $skillsRoot 'hwpx-automation' }
      if (Test-Path -LiteralPath (Join-Path $hwpx 'hwpx_edit.py')) { Report 'OK' "hwpx-automation 스킬 ($hwpx)" }
      else { Report '없음' 'hwpx-automation 스킬' 'npx skills add Engccer/hwpx-automation -g (또는 HWPX_AUTOMATION_DIR)' }
      if (PyModule 'hwpx_tomd') { Report 'OK' 'Python 패키지 hwpx-tomd' } else { Report '없음' 'Python 패키지 hwpx-tomd' 'pip install hwpx-tomd' }
      $java = $null
      if ($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin\java.exe'))) { $java = Join-Path $env:JAVA_HOME 'bin\java.exe' }
      if (-not $java -and $env:ProgramFiles) {
        $java = Get-ChildItem (Join-Path $env:ProgramFiles 'Eclipse Adoptium') -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue |
          ForEach-Object { Join-Path $_.FullName 'bin\java.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
      }
      if (-not $java) { $java = (Get-Command java -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
      $major = if ($java) { if ("$(& $java -version 2>&1 | Select-Object -First 1)" -match 'version "(\d+)') { [int]$Matches[1] } else { 0 } } else { 0 }
      if ($major -ge 21) { Report 'OK' "Java $major ($java)" }
      else { Report '없음' 'JDK 21' "첨부 HWP 변환에 필요$(if ($java) { " (찾은 것: Java $major)" }). winget install EclipseAdoptium.Temurin.21.JDK" }
      $pdf = (Get-Command pdftotext -ErrorAction SilentlyContinue | Select-Object -First 1).Source
      if (-not $pdf -and $env:ProgramFiles) {
        $g = Join-Path $env:ProgramFiles 'Git\mingw64\bin\pdftotext.exe'
        if (Test-Path -LiteralPath $g) { $pdf = $g }
      }
      if ($pdf) { Report 'OK' "pdftotext ($pdf)" } else { Report '없음' 'pdftotext' '첨부 PDF 추출에 필요. Git for Windows 또는 poppler 설치' }
      if (Test-Path -LiteralPath '\\관리자\$ALIM$\ALIM.DBF') { Report 'OK' '알림장 서버 공유 폴더' }
      else { Report '확인' '알림장 서버 공유 폴더' '학교 내부망에서 서버 PC가 켜져 있을 때만 보인다. 교내에서 다시 확인' }
    }
  }
}

Write-Host ''
if ($script:missing) { Write-Host "빠진 것 $($script:missing)건."; exit 1 }
Write-Host '빠진 것 없음.'
exit 0
