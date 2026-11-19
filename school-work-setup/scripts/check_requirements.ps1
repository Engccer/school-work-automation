<#
  school-work-automation 번들 요구사항 점검. 읽기만 하고 아무것도 설치·변경하지 않는다.
  사용: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_requirements.ps1 [-Skill neis-automation,alimjang-automation]
  크롬 원격 디버깅 시험만 임시 프로필로 화면 없는 크롬을 잠깐 띄웠다가 지운다.
  출력: 스킬마다 "OK / 없음 / 확인" 줄. 종료 코드 0 = 빠진 것 없음, 1 = 빠진 것 있음, 2 = 잘못된 인자.
  Playwright 브라우저 도구처럼 스크립트로 볼 수 없는 것은 SKILL.md 절차가 맡는다.
#>
param([string[]]$Skill)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # bash 등 다른 셸이 출력을 받아도 한글이 깨지지 않게

$all = 'neis-automation', 'k-edufine-automation', 'kyodetong-submit', 'coolmessenger-automation', 'alimjang-automation', 'ealimi-points', 'comcigan-timetable'
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
# 임시 프로필의 화면 없는 크롬을 원격 디버깅 포트로 띄워 실제로 붙어 본다. 평소 프로필과 설정은 건드리지 않고, 끝나면 임시 프로필을 지운다.
# RemoteDebuggingAllowed=0 이면 포트가 열리지 않고, DeveloperToolsAvailability=2 이면 포트는 열려도 탭에 붙지 못한다(실측).
# 레지스트리 정책은 시험 전에 따로 읽으므로, 여기서 포트가 안 열리는 것은 원인을 단정하지 않고 미확인으로 둔다
function RemoteDebugProbe($chrome) {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('swa_rdp_' + [guid]::NewGuid().ToString('N'))
  $proc = $null; $ws = $null
  try {
    $proc = Start-Process -FilePath $chrome -ArgumentList '--headless=new', "--user-data-dir=`"$tmp`"", '--remote-debugging-port=0', '--no-first-run', 'about:blank' -PassThru -WindowStyle Hidden
    $portFile = Join-Path $tmp 'DevToolsActivePort'
    $lines = @()
    for ($i = 0; $i -lt 40 -and $lines.Count -lt 2; $i++) {
      Start-Sleep -Milliseconds 250
      if ($proc.HasExited) { $script:probeError = '크롬이 바로 종료됨'; return 'error' }
      if (Test-Path -LiteralPath $portFile) { $lines = @(Get-Content -LiteralPath $portFile -ErrorAction SilentlyContinue) }
    }
    if ($lines.Count -lt 2) { $script:probeError = '10초 안에 디버깅 포트가 열리지 않음'; return 'timeout' }
    $list = Invoke-RestMethod "http://127.0.0.1:$($lines[0])/json/list" -TimeoutSec 5
    $page = $list | ForEach-Object { $_ } | Where-Object { $_.type -eq 'page' } | Select-Object -First 1   # 5.1은 JSON 배열을 한 덩어리로 돌려준다
    if (-not $page) { $script:probeError = '시험용 탭을 찾지 못함'; return 'error' }
    $none = [Threading.CancellationToken]::None
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    if (-not ($ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $none).Wait(5000) -and $ws.State -eq 'Open')) { return 'blocked' }
    $msg = [Text.Encoding]::UTF8.GetBytes('{"id":1,"method":"Runtime.evaluate","params":{"expression":"1+1"}}')
    $ws.SendAsync([ArraySegment[byte]]::new($msg), 'Text', $true, $none).Wait(5000) | Out-Null
    $buf = New-Object byte[] 4096
    $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $none)
    if ($r.Wait(5000) -and [Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count) -match '"value":2') { return 'ok' }
    return 'blocked'
  } catch [AggregateException] { return 'blocked' }
  catch { $script:probeError = $_.Exception.Message; return 'error' }
  finally {
    if ($ws) { $ws.Dispose() }
    if ($proc) { & taskkill /T /F /PID $proc.Id 2>$null | Out-Null; $proc.WaitForExit(5000) | Out-Null }
    for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $tmp); $i++) {
      Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
      if (Test-Path -LiteralPath $tmp) { Start-Sleep -Milliseconds 300 }
    }
  }
}
# 평소 크롬에서 원격 디버깅을 켜 두면 기본 프로필 폴더에 DevToolsActivePort 가 생기고 그 포트가 열려 있다
function RemoteDebugOn {
  $f = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\DevToolsActivePort'
  $port = if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -TotalCount 1 -ErrorAction SilentlyContinue }
  if (-not $port) { return $false }
  $c = New-Object Net.Sockets.TcpClient
  try { $c.ConnectAsync('127.0.0.1', [int]$port).Wait(1000) -and $c.Connected } catch { $false } finally { $c.Dispose() }
}
function BrowserNeeds {
  Report '확인' 'Playwright 브라우저 도구' '에이전트가 자기 도구 목록으로 확인한다(SKILL.md 2단계)'
  # 개발자 도구를 막는 정책이 걸리면 확장도 탭에 붙지 못한다. 클라우드 관리 정책은 레지스트리에 없어 개발자 도구를 열어 본다
  $blocked = $false; $rdOff = $false
  foreach ($k in 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKCU:\SOFTWARE\Policies\Google\Chrome') {
    $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    if ($p -and ("$($p.DeveloperToolsAvailability)" -eq '2' -or "$($p.DeveloperToolsDisabled)" -eq '1')) { $blocked = $true }
    if ($p -and "$($p.RemoteDebuggingAllowed)" -eq '0') { $rdOff = $true }
  }
  if ($blocked) { Report '확인' 'Chrome 개발자 도구' 'PC 관리 정책이 막고 있어 브라우저 제어 확장은 붙지 못한다. Playwright를 쓴다' }
  # 로그인된 크롬 이어 쓰기(크롬 144 이상의 원격 디버깅 자동 연결)를 이 PC 정책이 허용하는지 직접 시험한다
  $chrome = @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ } |
    ForEach-Object { Join-Path $_ 'Google\Chrome\Application\chrome.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  $ver = if ($chrome) { (Get-Item -LiteralPath $chrome).VersionInfo.ProductVersion }
  $major = if ($ver -match '^(\d+)\.') { [int]$Matches[1] } else { 0 }
  $item = "로그인된 크롬 이어 쓰기(선택, Chrome $ver)"
  if (-not $chrome) { Report '확인' '로그인된 크롬 이어 쓰기(선택)' '미확인(Chrome을 찾지 못함). Playwright를 쓴다' }
  elseif ($major -lt 144) { Report '확인' $item '미확인(자동 연결은 144 이상만 된다). Playwright를 쓴다' }
  elseif ($blocked -or $rdOff) { Report '확인' $item '정책 차단. 이 PC는 Playwright만 사용' }
  else {
    $script:probeError = '원인 모름'
    switch (RemoteDebugProbe $chrome) {
      'ok' {
        if (RemoteDebugOn) { Report 'OK' $item '사용 가능. 평소 크롬의 원격 디버깅이 이미 켜져 있다' }
        else { Report 'OK' $item '사용 가능. 쓸 때 사용자가 chrome://inspect/#remote-debugging 에서 켠다(SKILL.md 2단계)' }
      }
      'blocked' { Report '확인' $item '정책 차단. 이 PC는 Playwright만 사용' }
      default { Report '확인' $item "미확인(시험 실패: $script:probeError). Playwright를 쓴다" }
    }
  }
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
if (Get-Command npx -ErrorAction SilentlyContinue) { Report 'OK' 'Node.js(npx)' }
else { Report '없음' 'Node.js(npx)' '스킬 설치·갱신에 필요. https://nodejs.org' }
$web = 'neis-automation', 'k-edufine-automation', 'kyodetong-submit'
if ($targets | Where-Object { $_ -notin 'k-edufine-automation', 'kyodetong-submit', 'ealimi-points' }) {
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
    'ealimi-points' {
      Report '확인' 'Playwright 브라우저 도구' '에이전트가 자기 도구 목록으로 확인한다(school-work-setup SKILL.md 2단계). 로그인은 사용자가 Playwright 창에서 직접 한다'
    }
    'comcigan-timetable' {
      CheckModules @('playwright') ''
      $edge = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ } |
        ForEach-Object { Join-Path $_ 'Microsoft\Edge\Application\msedge.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
      if ($edge) { Report 'OK' 'Microsoft Edge' } else { Report '없음' 'Microsoft Edge' '화면 없는 Edge로 시간표를 읽는다. Edge를 설치한다' }
      if ($env:COMCI_SCHOOL -and $env:COMCI_TEACHER) { Report 'OK' '학교·교사 환경 변수(COMCI_SCHOOL·COMCI_TEACHER)' }
      else { Report '확인' '학교·교사 환경 변수' '자동 실행에 붙일 때만 필요. 수동 조회는 --school·--teacher 인자로 준다. 방금 등록했으면 새 터미널에서 다시 점검' }
    }
    'coolmessenger-automation' {
      $memo = Join-Path "$env:LOCALAPPDATA" 'CoolMessenger\Memo'
      if (Test-Path -LiteralPath $memo) { Report 'OK' '쿨메신저 클라이언트 메시지 DB' }
      else { Report '없음' '쿨메신저 클라이언트 메시지 DB' "$memo 없음. 쿨메신저(Gentoo)를 설치하고 한 번 로그인한다" }
    }
    'alimjang-automation' {
      CheckModules @('dbfread') ''
      CheckModules @('openpyxl') 'XLSX 첨부 내용 읽기에만 필요'
      # 평일 자동 정리(run_daily.ps1)가 부르는 에이전트 CLI. 수동 사용에는 필요 없다
      $agent = if ($env:ALIM_AGENT_CMD) { @($env:ALIM_AGENT_CMD -split '\s+' | Where-Object { $_ })[0] } else { 'claude' }
      if (Get-Command $agent -ErrorAction SilentlyContinue) { Report 'OK' "에이전트 CLI $agent (자동 정리용)" }
      else { Report '확인' "에이전트 CLI $agent" '평일 자동 정리에만 필요. 다른 에이전트는 ALIM_AGENT_CMD 로 지정' }
      # 권장 도구의 연결 후보만 확인한다. 실제 변환 가능 여부는 대표 첨부로 검증한다.
      $extractor = Join-Path $skillsRoot 'alimjang-automation\scripts\extract_attachments.py'
      if ($pyExe -and (Test-Path -LiteralPath $extractor)) {
        try {
          $raw = & $pyExe $extractor --check-tools 2>$null
          if ($LASTEXITCODE -ne 0) { throw '도구 점검 실행 실패' }
          $caps = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
          foreach ($fmt in 'hwpx', 'hwp') {
            $cap = $caps.$fmt
            if (-not $cap.state) { throw '도구 점검 결과 없음' }
            if ($cap.state -eq 'candidate') {
              Report '확인' "$($fmt.ToUpper()) 첨부 읽기: 연결 후보 $($cap.tool)" '예약 자동화에 쓰려면 대표 첨부로 변환 결과를 확인한다'
            } else {
              Report '확인' "$($fmt.ToUpper()) 첨부 읽기: 미설정 또는 설정 확인 필요" "$($cap.detail). 기본 조회·첨부 저장에는 필요 없음"
            }
          }
        } catch { Report '확인' '한글 첨부 도구' '자동 연결 점검 불가. 알림장 references/첨부-도구.md의 설정을 확인한다' }
      } else { Report '확인' '한글 첨부 도구' '기본 조회·첨부 저장에는 필요 없음. 사용할 형식의 읽기 도구만 선택한다' }
      $pdf = (Get-Command pdftotext -ErrorAction SilentlyContinue | Select-Object -First 1).Source
      if (-not $pdf -and $env:ProgramFiles) {
        $g = Join-Path $env:ProgramFiles 'Git\mingw64\bin\pdftotext.exe'
        if (Test-Path -LiteralPath $g) { $pdf = $g }
      }
      if ($pdf) { Report 'OK' "pdftotext ($pdf)" } else { Report '확인' 'pdftotext' '자동 PDF 첨부 추출에만 필요. Git for Windows 또는 poppler 설치' }
      if (Test-Path -LiteralPath '\\관리자\$ALIM$\ALIM.DBF') { Report 'OK' '알림장 서버 공유 폴더' }
      else { Report '확인' '알림장 서버 공유 폴더' '학교 내부망에서 서버 PC가 켜져 있을 때만 보인다. 교내에서 다시 확인' }
    }
  }
}

Write-Host ''
if ($script:missing) { Write-Host "빠진 것 $($script:missing)건."; exit 1 }
Write-Host '빠진 것 없음.'
exit 0
