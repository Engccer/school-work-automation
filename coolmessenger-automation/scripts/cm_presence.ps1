<#
    조직도에서 사람의 접속 상태 아이콘 번호를 읽어, 기준이 되는 사람(보통 본인)과 비교한다.
    읽기 전용이다(트리 노드를 펼치기만 한다).

      pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/cm_presence.ps1 -Name 홍길동 -Self 본인이름

    조직도 글자에는 상태가 나오지 않는다. 아이콘 번호만 단서이고, 번호가 뜻하는 상태는
    다 확인하지 못했다(SKILL.md 「접속 상태 확인」). 본인은 지금 PC를 쓰고 있으니 접속 중이 확실하므로
    본인과 같은 번호면 '접속 중', 다르면 '다른 상태'로만 판정한다.
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Self
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cm_tree.ps1"

$tree = Get-CMTree
$buf = New-CMRemoteBuf
try {
    $items = Get-CMTreeItems $tree $buf
    function Get-One([string]$n) {
        $hit = @($items | Where-Object { $_.Text -like "*$n*" })
        if ($hit.Count -eq 0) { throw "$n 을(를) 조직도에서 찾지 못했습니다." }
        $acc = @($hit | ForEach-Object { $_.Text } | Sort-Object -Unique)
        if ($acc.Count -ne 1) { throw "이름이 여러 계정에 걸립니다: $($acc -join ' / ')" }
        [pscustomobject]@{ Account = $acc[0]; Image = (Get-CMTreeItemImage $tree $hit[0].H $buf) }
    }
    $p = Get-One $Name
    Write-Output "대상: $($p.Account) 아이콘=$($p.Image)"
    if ($Self) {
        $s = Get-One $Self
        Write-Output "기준: $($s.Account) 아이콘=$($s.Image)"
        if ($p.Image -eq $s.Image) { Write-Output '판정: 기준과 같음(접속 중으로 봄)' }
        else { Write-Output '판정: 기준과 다름(오프라인·자리비움 등 다른 상태, 번호 뜻은 미확정)' }
    }
} finally { Remove-CMRemoteBuf $buf }
