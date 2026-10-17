#Requires -Version 7.0
<#
  close_win.ps1 의 창 선택 함수 시험. 창 목록은 가짜 배열이고, 실제 창에 WM_CLOSE 를 보내지 않는다.
  사용: pwsh -NoProfile -File scripts\tests\test_close_win.ps1   (종료 코드 0 = 통과, 2 = 가드 없음으로 중단)
#>
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot '..\close_win.ps1'
$src = Get-Content -LiteralPath $target -Raw -Encoding UTF8

# 점-소싱 가드가 함수 정의를 뺀 첫 최상위 문장이 아니면(주석 처리·조건 안·본문 뒤) 점-소싱이 실제 창을 건드리므로 중단한다
$guard = "if (`$MyInvocation.InvocationName -eq '.') { return }"
$tree = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$null)
$first = @($tree.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })[0]
if (-not $first -or $first.Extent.Text -cne $guard) { "ABORT: 점-소싱 가드가 첫 최상위 문장이 아니다"; exit 2 }

. $target

$fail = 0
function Check($name, $cond) {
  if ($cond) { "PASS $name" } else { "FAIL $name"; $script:fail++ }
}

$titles = @(
  '파일저장 | 업무관리시스템 -- 웹 페이지 대화 상자',
  '-- 웹 페이지 대화 상자',
  'HCLTAPP_KYUL_',
  '문서저장 -- 웹 페이지 대화 상자'
)

$part = @(Select-WindowIndex -Titles $titles -TitleLike '-- 웹 페이지 대화 상자')
Check 'partial matches three' (($part -join ',') -eq '0,1,3')

# 점-소싱한 스크립트의 [switch]$Exact 와 겹치지 않게 변수 이름을 따로 쓴다
$exactHits = @(Select-WindowIndex -Titles $titles -TitleLike '-- 웹 페이지 대화 상자' -Exact)
Check 'exact matches only the bare title' (($exactHits -join ',') -eq '1')

$none = @(Select-WindowIndex -Titles $titles -TitleLike '웹 페이지' -Exact)
Check 'exact with partial text matches none' ($none.Count -eq 0)

$case = @(Select-WindowIndex -Titles @('hcltapp_kyul_', 'HCLTAPP_KYUL_') -TitleLike 'HCLTAPP_KYUL_' -Exact)
Check 'exact is case-sensitive' (($case -join ',') -eq '1')

$wild = @(Select-WindowIndex -Titles @('a[1]', 'a1') -TitleLike 'a[1]' -Exact)
Check 'exact treats brackets literally' (($wild -join ',') -eq '0')

# 배선: 본문은 실제 창을 건드리므로 실행하지 않고, 후보를 고르는 본문 줄이 글자 그대로 있는지 본다
# (제목 목록 [CloseW]::T, 사용자가 준 -TitleLike, -Exact 를 그대로 넘겨야 한다)
$wire = '$c = @(Select-WindowIndex -Titles ([CloseW]::T.ToArray()) -TitleLike $TitleLike -Exact:$Exact)'
$lines = $src -split "`r?`n" | ForEach-Object { $_.Trim() }
Check 'main selects with T, $TitleLike and -Exact:$Exact' (@($lines | Where-Object { $_ -ceq $wire }).Count -eq 1)
Check 'main closes a selected candidate' (@($lines | Where-Object { $_ -ceq '$h = [CloseW]::H[$c[$Index]]' }).Count -eq 1)
Check 'target handle assigned once' (@($lines | Where-Object { $_ -match '^\$h\s*=' }).Count -eq 1)

if ($fail) { "FAILED $fail"; exit 1 } else { "ALL PASS"; exit 0 }
