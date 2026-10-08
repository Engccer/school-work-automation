#Requires -Version 7.0
<#
  capture.ps1 의 판정 함수 시험. 실제 창은 건드리지 않는다(스크립트를 점-소싱해 함수만 불러온다).
  사용: pwsh -NoProfile -File scripts\tests\test_capture.ps1   (종료 코드 0 = 통과, 2 = 가드 없음으로 중단)
#>
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot '..\capture.ps1'
$src = Get-Content -LiteralPath $target -Raw -Encoding UTF8

# 점-소싱 가드가 함수 정의를 뺀 첫 최상위 문장이 아니면(주석 처리·조건 안·본문 뒤) 점-소싱이 실제 창을 건드리므로 중단한다
$guard = "if (`$MyInvocation.InvocationName -eq '.') { return }"
$tree = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$null)
$first = @($tree.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })[0]
if (-not $first -or $first.Extent.Text -cne $guard) { "ABORT: 점-소싱 가드가 첫 최상위 문장이 아니다"; exit 2 }

Add-Type -AssemblyName System.Drawing
. $target

$fail = 0
function Check($name, $cond) {
  if ($cond) { "PASS $name" } else { "FAIL $name"; $script:fail++ }
}
function New-Bmp($w, $h, $color) {
  $b = New-Object System.Drawing.Bitmap($w, $h)
  $gr = [System.Drawing.Graphics]::FromImage($b)
  $gr.Clear($color); $gr.Dispose()
  return $b
}

# 빈 화면 판정: 표본 픽셀이 모두 같은 색이면 빈 화면
$black = New-Bmp 200 150 ([System.Drawing.Color]::Black)
$gray  = New-Bmp 200 150 ([System.Drawing.Color]::FromArgb(255, 240, 240, 240))
$white = New-Bmp 200 150 ([System.Drawing.Color]::White)
$drawn = New-Bmp 200 150 ([System.Drawing.Color]::FromArgb(255, 240, 240, 240))
$gr = [System.Drawing.Graphics]::FromImage($drawn)
$gr.FillRectangle([System.Drawing.Brushes]::Navy, 0, 0, 200, 40)   # 제목줄처럼 위쪽을 칠한다
$gr.Dispose()
$corner = New-Bmp 200 150 ([System.Drawing.Color]::FromArgb(255, 240, 240, 240))
$gr = [System.Drawing.Graphics]::FromImage($corner)
$gr.FillRectangle([System.Drawing.Brushes]::Navy, 100, 60, 100, 90)  # 오른쪽 아래만 칠한다(가로 표본도 봐야 잡힌다)
$gr.Dispose()
$alpha = New-Bmp 200 150 ([System.Drawing.Color]::FromArgb(255, 0, 0, 0))
$alpha.SetPixel(23, 17, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))  # 알파만 다른 검정

Check 'black is blank' (Test-BlankBitmap $black)
Check 'gray is blank' (Test-BlankBitmap $gray)
Check 'white is blank' (Test-BlankBitmap $white)
Check 'drawn is not blank' (-not (Test-BlankBitmap $drawn))
Check 'corner drawing is not blank' (-not (Test-BlankBitmap $corner))
Check 'alpha-only difference is still blank' (Test-BlankBitmap $alpha)

# 저장 경로: -Out 이 비면 <TEMP>\kedufine-capture\<시각>.png, 폴더를 만든다
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("kedu-cap-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$savedTemp = $env:TEMP
try {
  $now = [datetime]'2026-10-08 13:05:09.123'
  $p = Resolve-CaptureOut -Out '' -TempRoot $root -Now $now
  Check 'default path under kedufine-capture' ($p -eq (Join-Path $root 'kedufine-capture\20261008-130509-123.png'))
  Check 'default folder created' (Test-Path -LiteralPath (Join-Path $root 'kedufine-capture') -PathType Container)
  $given = Join-Path $root 'x\shot.png'
  Check 'given path unchanged' ((Resolve-CaptureOut -Out $given -TempRoot $root -Now $now) -eq $given)
  $env:TEMP = $root   # -TempRoot 를 주지 않으면 %TEMP% 를 쓴다
  $d = Resolve-CaptureOut -Out '' -Now $now
  Check 'default root is %TEMP%' ($d -eq (Join-Path $root 'kedufine-capture\20261008-130509-123.png'))
} finally {
  $env:TEMP = $savedTemp
  Remove-Item -LiteralPath $root -Recurse -Force
}

# 배선: 본문은 실제 창을 캡처하므로 실행하지 않고, 판정·저장 경로를 정하는 본문 줄이 글자 그대로 있는지 본다
$lines = $src -split "`r?`n" | ForEach-Object { $_.Trim() }
function Test-Line($l) { @($lines | Where-Object { $_ -ceq $l }).Count -eq 1 }
Check 'main stores blank verdict' (Test-Line 'if ($ok) { $blank = Test-BlankBitmap $bmp }')
Check 'main falls back on blank' (Test-Line 'if (-not $ok -or $blank) {')
Check 'main passes user -Out to Resolve-CaptureOut' (Test-Line '$Out = Resolve-CaptureOut -Out $Out')
$iResolve = $src.IndexOf('$Out = Resolve-CaptureOut -Out $Out'); $iSave = $src.IndexOf('$bmp.Save($Out,')
Check 'resolve happens before Save($Out' ($iResolve -ge 0 -and $iSave -gt $iResolve)
$iVerdict = $src.IndexOf('$blank = Test-BlankBitmap $bmp'); $iFall = $src.IndexOf('if (-not $ok -or $blank) {')
Check 'verdict comes before fallback' ($iVerdict -ge 0 -and $iFall -gt $iVerdict)
Check 'blank assigned only twice (init, verdict)' (@($lines | Where-Object { $_ -match '\$blank\s*=' }).Count -eq 2)
Check 'fallback copies the screen' (@($lines | Where-Object { $_ -like '*.CopyFromScreen(*' }).Count -eq 1)

if ($fail) { "FAILED $fail"; exit 1 } else { "ALL PASS"; exit 0 }
