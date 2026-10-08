# 쿨메신저(CoolMessenger Gentoo) UI 자동화 공용 라이브러리
#
#   . "$PSScriptRoot\cm_lib.ps1"
#
# 쿨메신저는 32비트 MFC 셸 + CEF(크롬) 뷰 구조다. 목록·버튼·대화상자는
# 전부 네이티브 Win32라 메시지로 다룰 수 있고, 본문 에디터만 CEF다.

Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class CM {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW")]
    public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr res);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte scan,uint flags,IntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,IntPtr e);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  // 가려진 창도 찍힌다(플래그 2 = PW_RENDERFULLCONTENT). CopyFromScreen은 맨 앞 창만 찍힌다.
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a,bool i,uint pid);
  [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr p,IntPtr a,UIntPtr s,uint t,uint pr);
  [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr p,IntPtr a,UIntPtr s,uint t);
  [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr p,IntPtr a,byte[] b,UIntPtr s,out UIntPtr w);
  [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr p,IntPtr a,byte[] b,UIntPtr s,out UIntPtr r);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT  { public int L, T, R, B; }
  public static string Cls(IntPtr h){var s=new StringBuilder(256);GetClassName(h,s,256);return s.ToString();}
  public static string Txt(IntPtr h){var s=new StringBuilder(1024);GetWindowTextW(h,s,1024);return s.ToString();}
  public static List<IntPtr> Kids(IntPtr p){var l=new List<IntPtr>();EnumChildWindows(p,(h,x)=>{l.Add(h);return true;},IntPtr.Zero);return l;}
  public static List<IntPtr> Tops(uint pid){var l=new List<IntPtr>();EnumWindows((h,x)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid)l.Add(h);return true;},IntPtr.Zero);return l;}
  // SendMessage는 상대 앱이 모달을 띄우면 영영 안 돌아온다. 항상 타임아웃판을 쓴다.
  public static IntPtr Msg(IntPtr h,uint m,IntPtr w,IntPtr l){ IntPtr r; SendMessageTimeout(h,m,w,l,0x0002,5000,out r); return r; }
}
"@

# ------------------------------------------------------------------ 기본 조회
function Get-CMPid { (Get-Process CoolMessenger -ErrorAction Stop).Id }

function Find-CMWindow {
    <# 제목으로 쿨메신저 최상위 창을 찾는다. #>
    param([string]$TitlePattern, [string]$Class = '#32770')
    foreach ($t in [CM]::Tops([uint32](Get-CMPid))) {
        if ([CM]::Cls($t) -eq $Class -and [CM]::Txt($t) -match $TitlePattern) { return $t }
    }
    return [IntPtr]::Zero
}

function Open-CMArchive {
    <#  메시지 관리함(받은 메시지 전체)을 연다.

        주의: 새 메시지가 오면 제목이 'N개의 안읽은 메시지'인 **수신 알림 창**이
        저절로 열리는데, 생김새가 관리함과 같아서 헷갈린다. 그 창은 방금 온
        메시지만 담고 있어 목록이 몇 건뿐이고, 시간이 지나면 그마저 빠진다.
        전체 이력과 지난 첨부를 다루려면 그 창을 닫고 메인 창의
        [메시지관리함 열기](Ctrl+B)로 진짜 관리함(제목 '메시지 관리함')을 열어야 한다.
        관리함은 늦게 뜰 때가 있어 제목을 최대 $TimeoutSec초 폴링하고, 못 찾으면 오류를 낸다. #>
    param([int]$TimeoutSec = 20)
    $archive = Find-CMWindow -TitlePattern '^메시지 관리함$'
    if ($archive -ne [IntPtr]::Zero) { return $archive }

    # 수신 알림 창이 떠 있으면 닫는다(관리함과 목록이 다르다).
    $popup = Find-CMWindow -TitlePattern '안읽은 메시지'
    if ($popup -ne [IntPtr]::Zero) {
        $null = Set-CMActive -Hwnd $popup
        $btn = Find-CMControl -Parent $popup -Class 'Button' -TextLike '닫기*'
        if ($btn -ne [IntPtr]::Zero) { [void][CM]::Msg($btn, 0x00F5, [IntPtr]0, [IntPtr]0); Start-Sleep -Seconds 2 }
    }
    $main = Find-CMWindow -TitlePattern '^COOLMESSENGER$'
    if ($main -eq [IntPtr]::Zero) { throw '쿨메신저 메인 창을 찾지 못했습니다.' }
    $null = Set-CMActive -Hwnd $main
    $open = Find-CMControl -Parent $main -Class 'Button' -TextLike '메시지관리함 열기*'
    [void][CM]::Msg($open, 0x00F5, [IntPtr]0, [IntPtr]0)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        Start-Sleep -Milliseconds 500
        $archive = Find-CMWindow -TitlePattern '^메시지 관리함$'
        if ($archive -ne [IntPtr]::Zero) { return $archive }
    } while ((Get-Date) -lt $deadline)
    throw "메시지 관리함이 ${TimeoutSec}초 안에 열리지 않았습니다."
}

function Get-CMSendNotice {
    <#  [보내기] 뒤 안내 문구. 클릭은 5~15초 늦게 반영될 때가 있어 창이 닫혔는지로
        발송을 단정하지 않는다. 창이 남았다고 다시 누르면 중복 발송이 된다. #>
    param([IntPtr]$Compose, [string]$Name)
    $check = "발송 여부는 'python scripts/cm_export.py --sent --since <보낸 시각>'으로 tbl_send를 조회해 확인하세요."
    if ([CM]::IsWindow($Compose)) { "회신 창이 아직 열려 있습니다($Name). [보내기]를 다시 누르지 말고 먼저 $check" }
    else                          { "회신 창 닫힘($Name). $check" }
}

function Find-CMControl {
    param([IntPtr]$Parent, [string]$Class, [string]$TextLike)
    foreach ($c in [CM]::Kids($Parent)) {
        if ($Class -and [CM]::Cls($c) -ne $Class) { continue }
        if ($TextLike) { if ([CM]::Txt($c) -like $TextLike) { return $c } } else { return $c }
    }
    return [IntPtr]::Zero
}

function Get-CMShownSender {
    <# 미리보기 창에 실제로 떠 있는 메시지의 보낸사람. 선택 행과 다를 수 있어 매번 확인한다. #>
    param([IntPtr]$MsgWin)
    foreach ($c in [CM]::Kids($MsgWin)) {
        if ([CM]::Txt($c) -match '^보낸사람\s*:\s*(.+)$') { return $Matches[1].Trim() }
    }
    return ''
}

# ------------------------------------------------------------------ 창 활성화
function Set-CMActive {
    <#  SetForegroundWindow는 포그라운드 잠금 때문에 그냥은 실패한다.
        ALT를 눌렀다 떼면 시스템이 사용자 조작으로 간주해 통과된다.
        실제 마우스 클릭을 쓰려면 이 활성화가 선행되어야 한다. #>
    param([IntPtr]$Hwnd, [int]$Tries = 3)
    for ($i = 0; $i -lt $Tries; $i++) {
        if ([CM]::IsIconic($Hwnd)) { [void][CM]::ShowWindow($Hwnd, 9) }
        [CM]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)
        [void][CM]::SetForegroundWindow($Hwnd)
        [CM]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 500
        if ([CM]::GetForegroundWindow() -eq $Hwnd) { return $true }
    }
    return $false
}

function Invoke-CMClick {
    param([int]$X, [int]$Y, [switch]$Right)
    [void][CM]::SetCursorPos($X, $Y); Start-Sleep -Milliseconds 250
    if ($Right) { [CM]::mouse_event(0x0008,0,0,0,[IntPtr]::Zero); [CM]::mouse_event(0x0010,0,0,0,[IntPtr]::Zero) }
    else        { [CM]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero); [CM]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero) }
    Start-Sleep -Milliseconds 400
}

# ------------------------------------------------------------------ 메시지 목록
# 대상이 32비트라 LVITEMW의 포인터는 4바이트다. 64비트 구조체를 그대로 쓰면 안 된다.
function Read-CMList {
    <# 메시지 리스트를 읽어 [보낸사람, 제목, 날짜/시간, 첨부파일] 행으로 돌려준다. #>
    param([IntPtr]$List, [int]$Cols = 4, [int]$Max = 200)
    $LVM_GETITEMCOUNT = 0x1004; $LVM_GETITEMTEXTW = 0x1073
    $count = [int][CM]::Msg($List, $LVM_GETITEMCOUNT, [IntPtr]0, [IntPtr]0)
    $hProc = [CM]::OpenProcess(0x0438, $false, [uint32](Get-CMPid))
    if ($hProc -eq [IntPtr]::Zero) { throw '쿨메신저 프로세스를 열 수 없습니다.' }
    $rem = [CM]::VirtualAllocEx($hProc, [IntPtr]::Zero, [UIntPtr]4096, 0x3000, 4)
    $textOff = 256
    $rows = @()
    for ($i = 0; $i -lt [Math]::Min($count, $Max); $i++) {
        $row = [ordered]@{ Index = $i }
        for ($j = 0; $j -lt $Cols; $j++) {
            $b = New-Object byte[] 64
            [BitConverter]::GetBytes([uint32]1).CopyTo($b, 0)                              # mask = LVIF_TEXT
            [BitConverter]::GetBytes([int32]$i).CopyTo($b, 4)                              # iItem
            [BitConverter]::GetBytes([int32]$j).CopyTo($b, 8)                              # iSubItem
            [BitConverter]::GetBytes([uint32]([int64]$rem + $textOff)).CopyTo($b, 20)      # pszText (32비트 포인터)
            [BitConverter]::GetBytes([int32]512).CopyTo($b, 24)                            # cchTextMax
            $w = [UIntPtr]::Zero
            [void][CM]::WriteProcessMemory($hProc, $rem, $b, [UIntPtr]64, [ref]$w)
            [void][CM]::Msg($List, $LVM_GETITEMTEXTW, [IntPtr]$i, $rem)
            $buf = New-Object byte[] 1024; $r = [UIntPtr]::Zero
            [void][CM]::ReadProcessMemory($hProc, [IntPtr]([int64]$rem + $textOff), $buf, [UIntPtr]1024, [ref]$r)
            $s = [System.Text.Encoding]::Unicode.GetString($buf)
            $z = $s.IndexOf([char]0); if ($z -ge 0) { $s = $s.Substring(0, $z) }
            $row["C$j"] = $s
        }
        $rows += [pscustomobject]$row
    }
    [void][CM]::VirtualFreeEx($hProc, $rem, [UIntPtr]0, 0x8000)
    [void][CM]::CloseHandle($hProc)
    return @{ Count = $count; Rows = $rows }
}

function Get-CMRowPoint {
    <# 목록 행의 화면 좌표. 행이 추가되면 인덱스가 밀리므로 클릭 직전에 다시 구한다. #>
    param([IntPtr]$List, [int]$Index)
    $LVM_GETITEMRECT = 0x100E
    $hProc = [CM]::OpenProcess(0x0438, $false, [uint32](Get-CMPid))
    $rem = [CM]::VirtualAllocEx($hProc, [IntPtr]::Zero, [UIntPtr]64, 0x3000, 4)
    $b = New-Object byte[] 16
    [BitConverter]::GetBytes([int32]0).CopyTo($b, 0)      # LVIR_BOUNDS
    $w = [UIntPtr]::Zero
    [void][CM]::WriteProcessMemory($hProc, $rem, $b, [UIntPtr]16, [ref]$w)
    [void][CM]::Msg($List, $LVM_GETITEMRECT, [IntPtr]$Index, $rem)
    $buf = New-Object byte[] 16; $r = [UIntPtr]::Zero
    [void][CM]::ReadProcessMemory($hProc, $rem, $buf, [UIntPtr]16, [ref]$r)
    [void][CM]::VirtualFreeEx($hProc, $rem, [UIntPtr]0, 0x8000)
    [void][CM]::CloseHandle($hProc)
    $p = New-Object CM+POINT
    $p.X = [BitConverter]::ToInt32($buf, 0) + 40
    $p.Y = [int](([BitConverter]::ToInt32($buf, 4) + [BitConverter]::ToInt32($buf, 12)) / 2)
    [void][CM]::ClientToScreen($List, [ref]$p)
    return $p
}

function Select-CMMessage {
    <#  목록에서 행을 실제 마우스로 눌러 미리보기까지 바꾼다.
        LVM_SETITEMSTATE로 선택만 바꾸면 선택 표시는 옮겨가도 미리보기는
        그대로라, 첨부 저장이 엉뚱한 메시지에 적용된다. 반드시 클릭해야 한다. #>
    param([IntPtr]$MsgWin, [IntPtr]$List, [string]$ExpectSender, [int]$Index, [int]$Tries = 4)
    for ($t = 1; $t -le $Tries; $t++) {
        $null = Set-CMActive -Hwnd $MsgWin
        $p = Get-CMRowPoint -List $List -Index $Index
        Invoke-CMClick -X $p.X -Y $p.Y
        Start-Sleep -Milliseconds 1200
        if ((Get-CMShownSender -MsgWin $MsgWin) -eq $ExpectSender) { return $true }
    }
    return $false
}

# ------------------------------------------------------------------ 대화상자
function Close-CMDialog {
    <#  모달 대화상자('파일 다운로드 중' 등)의 버튼은 BM_CLICK을 무시한다. 부모에 WM_COMMAND + 컨트롤 ID를 보내야 한다.
        ID는 창마다 달라 매번 GetDlgCtrlID로 읽는다(확인 1·2·5025 등 제각각). #>
    param([IntPtr]$Dialog, [string]$ButtonText)
    foreach ($c in [CM]::Kids($Dialog)) {
        if ([CM]::Cls($c) -eq 'Button' -and [CM]::Txt($c) -like "*$ButtonText*") {
            $id = [CM]::GetDlgCtrlID($c)
            [void][CM]::PostMessage($Dialog, 0x0111, [IntPtr]$id, $c)
            Start-Sleep -Seconds 2
            return -not [CM]::IsWindow($Dialog)
        }
    }
    return $false
}

function Wait-CMDownload {
    <#  '파일 다운로드 중' 창 처리.

        다운로드가 0 bytes에서 멈춘 채 창이 오류 없이 남을 때가 있다(57분 멈춘 적이 있다).
        조용히 실패하므로 저장 뒤에는 반드시 이 함수로 확인한다.
        STALLED면 메시지 관리함(제목 '메시지 관리함')에서 다시 시도한다. #>
    param([int]$TimeoutSec = 25)
    Start-Sleep -Milliseconds 1500      # 창이 뜨기 전에 확인하면 성공으로 오인한다
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $dlg = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $dlg = Find-CMWindow -TitlePattern '파일 다운로드 중'
        if ($dlg -eq [IntPtr]::Zero) { return 'OK' }     # 창이 없으면 이미 끝난 것
        Start-Sleep -Milliseconds 800
    }
    if ($dlg -ne [IntPtr]::Zero -and [CM]::IsWindow($dlg)) {
        [void](Close-CMDialog -Dialog $dlg -ButtonText '취소')
        return 'STALLED'
    }
    return 'OK'
}
