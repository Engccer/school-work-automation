# 메인 창 조직도(SysTreeView32) 열거·클릭 함수.
#
#   . "$PSScriptRoot\cm_tree.ps1"
#
# 쿨메신저는 32비트라 TVITEMW의 포인터가 4바이트다(pszText 오프셋 16, cchTextMax 20).
# pwsh(7)로 실행한다. Windows PowerShell 5.1은 [UIntPtr]4096 형변환에서 멈춘다.

. "$PSScriptRoot\cm_lib.ps1"

$TVM_EXPAND        = 0x1102
$TVM_GETITEMRECT   = 0x1104
$TVM_GETNEXTITEM   = 0x110A
$TVM_GETITEMW      = 0x113E
$TVM_ENSUREVISIBLE = 0x1114
$TVGN_ROOT = 0; $TVGN_NEXT = 1; $TVGN_CHILD = 4
$TVE_EXPAND = 2

function Get-CMTree {
    <# 메인 창의 조직도 트리 핸들. #>
    $main = Find-CMWindow -Title 'COOLMESSENGER'
    foreach ($c in [CM]::Kids([IntPtr]$main)) {
        if ([CM]::Cls($c) -eq 'SysTreeView32' -and [CM]::Txt($c) -eq '조직도') { return $c }
    }
    throw '조직도 트리를 찾지 못했습니다.'
}

function New-CMRemoteBuf {
    <# 대상 프로세스에 4KB 작업 버퍼를 잡는다. 앞 1KB는 구조체, 뒤는 글자용. #>
    $h = [CM]::OpenProcess(0x0438, $false, [uint32](Get-CMPid))
    if ($h -eq [IntPtr]::Zero) { throw '쿨메신저 프로세스를 열 수 없습니다.' }
    [pscustomobject]@{ Proc = $h; Addr = [CM]::VirtualAllocEx($h, [IntPtr]::Zero, [UIntPtr]4096, 0x3000, 4) }
}
function Remove-CMRemoteBuf($Buf) {
    [void][CM]::VirtualFreeEx($Buf.Proc, $Buf.Addr, [UIntPtr]0, 0x8000)
    [void][CM]::CloseHandle($Buf.Proc)
}

function Get-CMTreeItemText($Tree, $Item, $Buf) {
    $textAddr = [IntPtr]([int64]$Buf.Addr + 1024)
    $b = New-Object byte[] 40
    [BitConverter]::GetBytes([uint32]0x0001).CopyTo($b, 0)                      # TVIF_TEXT
    [BitConverter]::GetBytes([int32]$Item).CopyTo($b, 4)
    [BitConverter]::GetBytes([uint32]([int64]$textAddr)).CopyTo($b, 16)         # pszText(4바이트)
    [BitConverter]::GetBytes([int32]512).CopyTo($b, 20)                         # cchTextMax
    $w = [UIntPtr]::Zero
    [void][CM]::WriteProcessMemory($Buf.Proc, $Buf.Addr, $b, [UIntPtr]40, [ref]$w)
    [void][CM]::Msg($Tree, $TVM_GETITEMW, [IntPtr]::Zero, $Buf.Addr)
    $out = New-Object byte[] 1024; $r = [UIntPtr]::Zero
    [void][CM]::ReadProcessMemory($Buf.Proc, $textAddr, $out, [UIntPtr]1024, [ref]$r)
    $s = [Text.Encoding]::Unicode.GetString($out)
    $z = $s.IndexOf([char]0); if ($z -ge 0) { $s = $s.Substring(0, $z) }
    $s
}

function Get-CMTreeItemRect($Tree, $Item, $Buf) {
    <# 트리 클라이언트 좌표. 화면 밖 항목은 음수가 나오므로 ENSUREVISIBLE 뒤에 다시 읽는다. #>
    $b = New-Object byte[] 16
    [BitConverter]::GetBytes([int32]$Item).CopyTo($b, 0)
    $w = [UIntPtr]::Zero
    [void][CM]::WriteProcessMemory($Buf.Proc, $Buf.Addr, $b, [UIntPtr]16, [ref]$w)
    if ([CM]::Msg($Tree, $TVM_GETITEMRECT, [IntPtr]1, $Buf.Addr) -eq [IntPtr]::Zero) { return $null }
    $out = New-Object byte[] 16; $r = [UIntPtr]::Zero
    [void][CM]::ReadProcessMemory($Buf.Proc, $Buf.Addr, $out, [UIntPtr]16, [ref]$r)
    [pscustomobject]@{
        L = [BitConverter]::ToInt32($out, 0); T = [BitConverter]::ToInt32($out, 4)
        R = [BitConverter]::ToInt32($out, 8); B = [BitConverter]::ToInt32($out, 12)
    }
}

function Get-CMTreeItems($Tree, $Buf, [int]$Max = 4000) {
    <# 트리를 펼치며 (H, Text, D)를 모은다. 한 사람이 여러 부서에 중복해 나온다. #>
    $items = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]
    $root = [CM]::Msg($Tree, $TVM_GETNEXTITEM, [IntPtr]$TVGN_ROOT, [IntPtr]::Zero)
    if ($root -eq [IntPtr]::Zero) { return $items }
    $stack.Push([pscustomobject]@{ H = $root; D = 0 })
    while ($stack.Count -gt 0 -and $items.Count -lt $Max) {
        $cur = $stack.Pop(); $h = $cur.H
        while ($h -ne [IntPtr]::Zero -and $items.Count -lt $Max) {
            $items.Add([pscustomobject]@{ H = $h; Text = (Get-CMTreeItemText $Tree $h $Buf); D = $cur.D })
            [void][CM]::Msg($Tree, $TVM_EXPAND, [IntPtr]$TVE_EXPAND, $h)
            Start-Sleep -Milliseconds 5
            $child = [CM]::Msg($Tree, $TVM_GETNEXTITEM, [IntPtr]$TVGN_CHILD, $h)
            if ($child -ne [IntPtr]::Zero) { $stack.Push([pscustomobject]@{ H = $child; D = $cur.D + 1 }) }
            $h = [CM]::Msg($Tree, $TVM_GETNEXTITEM, [IntPtr]$TVGN_NEXT, $h)
        }
    }
    $items
}

function Find-CMPerson {
    <# 이름이 들어간 트리 항목을 찾는다. 계정 글자가 둘 이상이면 동명이인이므로 막는다. #>
    param($Tree, $Buf, [Parameter(Mandatory = $true)][string]$Name)
    $hit = @(Get-CMTreeItems $Tree $Buf | Where-Object { $_.Text -like "*$Name*" })
    if ($hit.Count -eq 0) { throw "$Name 을(를) 조직도에서 찾지 못했습니다." }
    $accounts = @($hit | ForEach-Object { $_.Text } | Sort-Object -Unique)
    if ($accounts.Count -ne 1) { throw "이름이 여러 계정에 걸립니다: $($accounts -join ' / ')" }
    [pscustomobject]@{ Item = $hit[0].H; Account = $accounts[0]; Count = $hit.Count }
}

function Invoke-CMTreeDoubleClick {
    <# 트리 항목을 보이게 한 뒤 실제 더블클릭. down/up 쌍을 80ms 간격으로 두 번 보낸다. #>
    param($Tree, $Item, $Buf)
    [void][CM]::Msg($Tree, $TVM_ENSUREVISIBLE, [IntPtr]::Zero, $Item)
    Start-Sleep -Milliseconds 250
    $r = Get-CMTreeItemRect $Tree $Item $Buf
    if (-not $r) { throw '항목 좌표를 구하지 못했습니다.' }
    $pt = New-Object CM+POINT
    $pt.X = [int](($r.L + $r.R) / 2); $pt.Y = [int](($r.T + $r.B) / 2)
    [void][CM]::ClientToScreen([IntPtr]$Tree, [ref]$pt)
    if ([CM]::WindowFromPoint($pt) -ne [IntPtr]$Tree) { throw '클릭 좌표가 조직도 위가 아닙니다.' }
    [void][CM]::SetCursorPos($pt.X, $pt.Y); Start-Sleep -Milliseconds 150
    foreach ($i in 1, 2) {
        [CM]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
        [CM]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 80
    }
}
