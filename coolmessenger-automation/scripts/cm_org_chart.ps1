# 메인 창 조직도 트리를 깊이 우선으로 펼쳐 "상위 경로<TAB>항목 글자" TSV로 저장한다.
#
#   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/cm_org_chart.ps1 -Out <tree.tsv> [-Launch]
#
# 행 하나가 트리 항목 하나다. 경로는 최상위(루트)를 뺀 상위 그룹들을 " > "로 잇는다.
# 그룹 노드도 행으로 나오고(글자가 "("로 시작하지 않는다), 사람 노드는 "(이름 …)꼬리" 꼴이다.
# 해석은 cm_org_csv.py가 맡는다.
#
# -Launch: 쿨메신저가 꺼져 있으면 기본 설치 경로에서 띄우고 조직도가 뜰 때까지 기다린다(최대 40초).
# 로그인 창이 뜨면 사용자가 직접 로그인한 뒤 다시 실행한다.
#
# 트리 펼치기는 노드를 열 뿐 메시지를 보내거나 바꾸지 않는다.

param(
    [Parameter(Mandatory = $true)][string]$Out,
    [switch]$Launch,
    [string]$AppPath = 'C:\Program Files (x86)\CoolMessenger Gentoo\CoolMessenger.exe'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cm_tree.ps1"

$outDir = Split-Path -Parent ([IO.Path]::GetFullPath($Out))
if (-not (Test-Path -LiteralPath $outDir)) { throw "저장 폴더가 없습니다: $outDir" }

if (-not (Get-Process CoolMessenger -ErrorAction SilentlyContinue)) {
    if (-not $Launch) { throw '쿨메신저가 꺼져 있습니다. 먼저 켜거나 -Launch를 주세요.' }
    if (-not (Test-Path -LiteralPath $AppPath)) { throw "쿨메신저 실행 파일을 찾지 못했습니다: $AppPath" }
    Start-Process -FilePath $AppPath
}

# 메인 창과 조직도 트리가 뜰 때까지 기다린다. 시작 직후에는 트리가 늦게 나타난다.
$tree = $null
$deadline = (Get-Date).AddSeconds(40)
while ((Get-Date) -lt $deadline -and -not $tree) {
    try { $tree = Get-CMTree } catch { Start-Sleep -Seconds 1 }
}
if (-not $tree) { throw '조직도 트리를 찾지 못했습니다. 로그인 창이 떠 있는지 확인하세요.' }

$buf = New-CMRemoteBuf
$rows = New-Object System.Collections.Generic.List[string]

function Add-CMTreeRows($Tree, $Buf, $Parent, [string[]]$Path, $Rows) {
    # 형제를 한 줄로 돌며 각 항목을 펼친 뒤 바로 자식 쪽으로 내려간다(깊이 우선).
    # 형제 체인을 먼저 다 읽고 나중에 자식을 훑으면 순서가 뒤섞여 소속 경로가 틀어진다.
    $h = [CM]::Msg($Tree, $TVM_GETNEXTITEM, [IntPtr]$TVGN_CHILD, $Parent)
    while ($h -ne [IntPtr]::Zero) {
        $text = Get-CMTreeItemText $Tree $h $Buf
        $Rows.Add(("{0}`t{1}" -f ($Path -join ' > '), $text))
        [void][CM]::Msg($Tree, $TVM_EXPAND, [IntPtr]2, $h)
        Start-Sleep -Milliseconds 5
        Add-CMTreeRows $Tree $Buf $h ($Path + @($text)) $Rows
        $h = [CM]::Msg($Tree, $TVM_GETNEXTITEM, [IntPtr]$TVGN_NEXT, $h)
    }
}

try {
    $root = [CM]::Msg($tree, $TVM_GETNEXTITEM, [IntPtr]$TVGN_ROOT, [IntPtr]::Zero)
    if ($root -eq [IntPtr]::Zero) { throw '조직도 최상위 항목이 없습니다.' }
    $rootText = Get-CMTreeItemText $tree $root $buf
    [void][CM]::Msg($tree, $TVM_EXPAND, [IntPtr]2, $root)
    Start-Sleep -Milliseconds 50
    Add-CMTreeRows $tree $buf $root @($rootText) $rows
    [IO.File]::WriteAllLines($Out, [string[]]$rows, [Text.UTF8Encoding]::new($false))
    Write-Output "rows=$($rows.Count) out=$Out"
} finally {
    Remove-CMRemoteBuf $buf
}
