---
name: k-edufine-automation
license: MIT
description: >-
  서울 업무포털을 거쳐 K-에듀파인(klef.sen.go.kr)의 공문 업무를 자동화한다. 목록은 Claude in Chrome으로, 결재·기안 문서 창(WXSClient)은 PowerShell MSHTML 브리지와 실제 마우스 클릭으로 다룬다. 다음 요청에 사용한다. (1) 결재대기 공문 확인·판독, 접수 공문 본문·첨부 PC저장, 과제카드 지정·문서처리(접수) (2) 새 공문 기안·결재올림(상신): 내부결재, 대외시행 자동발송, 겸직허가 신청 등. "공문 올려 줘", "기안해 줘", "결재 올려 줘" (3) 문서등록대장에서 선례·발송 정보 찾기 (4) 기록물관리 점검 등에 따른 완료 문서 대국민공개여부(공개구분) 수정 (5) HwpODTpatch 보안 프로그램 설치 alert 반복, K-에듀파인 사용자지원서비스 질의. 교데통 자료 제출(전자결재 연계기안 포함)은 kyodetong-submit, 나이스 복무·출장 상신은 neis-automation이 맡는다. K-Edufine, official document, e-approval, drafting, document registry, WXSClient, MSHTML.
metadata:
  version: "5.3.1"
---

# K-에듀파인 업무 자동화 (업무포털 → K-에듀파인 → 결재대기·기안)

## 개요

서울특별시교육청 업무포털을 거쳐 K-에듀파인에 진입해, 들어온 공문을 처리하고(결재대기)
새 공문을 만들어 올리는(기안) 자동화 워크플로우. **도구가 세 갈래**다.

- **목록·진입**: Claude in Chrome MCP (브라우저). 확장이 모든 탭에서 `Cannot attach to this target`으로
  붙지 않으면 Playwright 크롬으로 바꾼다 → 스킬 `neis-automation`의
  [references/playwright-폴백.md](../neis-automation/references/playwright-폴백.md)
  (2단계의 [K-에듀파인] 새 탭 진입도 그 파일의 절차 2. 5단계 문서 열기로 WXSClient가 뜨는지는 미확인)
- **문서 창 내부 판독·필드 입력**: PowerShell MSHTML 브리지(6단계)
  - `scripts/kyul_dom.ps1` — 결재 문서 창 전용(`Get-Process WXSClient` + 제목 완전일치)
  - `scripts/mshtml_dom.ps1` — **제목 부분일치 범용판.** 기안 창과 모든 MSHTML 대화상자는
    제목이 달라 `kyul_dom.ps1` 로는 못 잡으므로 이걸 쓴다
- **팝업 내부 조작**: **실제 마우스 클릭** (`scripts/click_screen.ps1`)
  — 수신자지정·결재경로설정 같은 선택 팝업은 스크립트로 상태를 못 바꾼다(기안 10단계)

창은 두 종류로 부른다. **MSHTML 대화상자**는 `Internet Explorer_TridentDlgFrame` 클래스에
제목이 `… -- 웹 페이지 대화 상자` 인 팝업(파일저장·문서저장·과제카드·결재경로·임시저장 등)이고
`mshtml_dom.ps1` 로 DOM 을 다룬다. **Win32 메시지 창**은 클래스 `#32770` 의 표준 창
("웹 페이지 메시지" confirm·alert, "열기", "폴더 찾아보기")이고 `dlg.ps1` 로 컨트롤을 덤프하고 누른다.
결재 문서 주 창(`HCLTAPP_KYUL_`)도 클래스가 `#32770` 이므로 창은 클래스가 아니라 제목으로 가른다.

보조 스크립트:

| 스크립트 | 용도 |
|---|---|
| `scripts/click_screen.ps1` | 창을 앞으로 올리고 **창 기준 상대좌표**에 실제 마우스 클릭 |
| `scripts/capture.ps1` | 창을 PNG 로 캡처(PrintWindow → CopyFromScreen 폴백). `-Out` 을 생략하면 `%TEMP%\kedufine-capture\<시각>.png` 에 저장하고 `SAVED=` 로 경로를 출력한다(`-Out` 을 주면 그 폴더가 미리 있어야 한다). 좌표는 이 이미지 좌표 = `click_screen.ps1` 의 `-X/-Y` |
| `scripts/dlg.ps1` | Win32 메시지 창(#32770) 자식 컨트롤 덤프 / `-Click <id>` 로 `WM_COMMAND` 버튼 클릭 |
| `scripts/close_win.ps1` | 제목 부분일치(`-Exact` 면 완전일치) 창에 `WM_CLOSE` (`-List` 로 먼저 확인, `-Index` 로 고름) |
| `scripts/pick_file.ps1` | WXSClient 의 표준 "열기" 대화상자에 경로 입력 후 [열기] |

주소:

- 업무포털: `https://sen.eduptl.kr/bpm_man_mn00_001.do` (진입·로그인은
  [neis-automation](../neis-automation/SKILL.md) 스킬의 1~3단계와 동일)
- K-에듀파인: `https://klef.sen.go.kr/keris_ui/main.do` (업무포털에서 SSO로 진입)

**원격(외부망) 접속**: K-에듀파인은 **EVPN 연결 없이는 HTTP 응답 자체가 없다**(미연결이면
타임아웃). 자택 등 학교 외부에서는 [neis-automation](../neis-automation/SKILL.md) 스킬의
「원격(외부망) 접속 — EVPN」 절차(evpn.sen.go.kr → 웹 로그인 → AXGATE 클라이언트 로그인)로
터널을 먼저 연결할 것. 터널은 중간에 끊길 수 있으므로, 원격 작업 중 응답이 사라지면 EVPN
재연결부터 확인한다. → 사례

> **적용 범위**: 서울특별시교육청 환경(`sen.*` 도메인)에서 실사용으로 검증했다. 타 시도는
> 업무포털 도메인과 세부 화면이 다를 수 있으나, K-에듀파인 결재·기안 구조(WXSClient·MSHTML)는
> 전국 공통 계열이라 절차 골격은 그대로 적용된다.

**자동화 경계**: 결재 문서 창은 브라우저 탭이 아니라 네이티브 Windows 창
(`WXSClient.exe`, 제목 `HCLTAPP_KYUL_`)이라 **브라우저 MCP 도구로는 닿지 않는다**. 그러나
그 창의 내부 렌더러가 **임베디드 IE(MSHTML)** 이므로, PowerShell에서 DOM을 직접 잡아
읽기·클릭·필드 조작을 할 수 있다 → 6단계.

**되돌릴 수 없는 조작은 사용자 승인 후에만 실행한다**: 문서처리(`fncProcessDoc`)·
결재올림(`fncSanctn`)·완료 문서 공개구분 한건수정 저장(`fncCreate`)·삭제·회수.
문서처리와 결재올림은 confirm 한 번으로 확정되고, 공개구분 수정은 되돌리기가 없고 변경
이력이 남는다. 승인을 받고 실행하거나 사용자에게 핸드오프한다. 조사 목적이라면 클릭 대신
핸들러 소스를 읽어 판단한다(팝업만 여는지, 곧바로 서버 확정인지).

## 상황별 참고 문서

| 이럴 때 | 읽을 문서 |
|---|---|
| 결재대기 문서를 열어 판독·본문/첨부 PC저장·과제카드 지정·문서처리(접수)를 할 때 | [references/접수처리.md](references/접수처리.md) (결재 문서 창 요소, 7~9단계, Win32 메시지 창 버튼 id 8-6) |
| 새 공문을 기안·결재올림하거나, 문서등록대장에서 선례를 찾을 때 | [references/기안.md](references/기안.md) (10단계, 10-1~10-12). 과제카드 지정(8-2)·Win32 메시지 창 버튼(8-6)은 접수처리.md 를 함께 본다 |
| 완료 문서의 대국민공개여부를 바꿔 달라는 요청(기록물관리 점검 등)을 받았을 때 | [references/공개구분수정.md](references/공개구분수정.md) (10-13). 문서등록대장 조회는 기안.md 10-11, Win32 메시지 창 버튼은 접수처리.md 8-6 |
| `main.do`에서 `[HwpODTpatch]` 필수 보안 프로그램 alert가 되풀이되거나, K-에듀파인 사용자지원서비스에 질의를 등록할 때 | [references/한ODT-설치루프.md](references/한ODT-설치루프.md) |
| 스크립트를 고치거나 새로 짤 때, 스크립트가 P/Invoke·COM 오류나 빈 값·빈 캡처를 내거나 대상 앱이 죽었을 때 | [references/기술노트.md](references/기술노트.md) |
| 규칙이 생긴 경위·날짜·변경 이력이 궁금할 때 | [references/cases.md](references/cases.md) |
| 결재권자·부서 편제가 필요할 때 | 기관별 결재선(결재권자 실명·부서 편제)은 로컬 파일로 관리한다(예: `references/결재선-<학년도>.md`) |

## 워크플로우

### 1단계: 업무포털 로그인 (나이스 스킬과 공통)

업무포털 접속·인증서 로그인 핸드오프·공지 팝업 닫기는 neis-automation 스킬 1~3단계와
동일하다. 인증서 비밀번호 입력은 자동화 금지 — 사용자가 직접 로그인한다.

### 2단계: [K-에듀파인] 클릭 → 새 탭 진입

- 업무포털 메인 상단 메뉴에서 **[K-에듀파인]** 텍스트 클릭.
- 새 탭이 같은 탭 그룹에 생성된다 (`klef.sen.go.kr/keris_ui/main.do`).
  클릭 후 `wait 3~5초` → `tabs_context_mcp`로 새 탭 ID 확보(제목이 `K-에듀파인`인지 확인).
- **⚠ 메뉴 좌표를 외워 쓰지 말고 매번 `zoom` 으로 확인한다.** 창 폭에 따라
  `[K-에듀파인]` 이 **두 줄로 줄바꿈**되어(`[K-` / `에듀파인]`) 텍스트 중심이 크게
  내려가고, 옛 좌표를 누르면 바로 왼쪽의 **[나이스]가 열린다**(새 탭 제목이
  `4세대 나이스 시스템`). 잘못 열렸으면 그 탭을 `tabs_close_mcp` 로 닫고 아랫줄
  (`에듀파인]`)을 눌러 다시 진입한다. → 사례
- 사용자 개입 직후 등 일부 상황에서 `navigate`로 klef 직접 이동이 권한 분류기에 거부될 수
  있다. 이때는 navigate를 반복하지 말고 **포털 화면의 [K-에듀파인] 메뉴를 다시 클릭**하는
  방식(페이지 내 클릭)으로 우회한다.
- **작업이 길어질 것 같으면 시작 전에 K-에듀파인 좌상단 타이머 옆 [연장]** 을 `zoom` 으로
  찾아 누른다. 60분으로 리셋된다. 업무포털 탭의 세션 타이머(우측 상단
  "NN:NN후에 로그아웃됩니다")는 별개다.

### 3단계: 보안 프로그램 안내 페이지(install.html) 처리

- 첫 진입 시 "PC 보안 프로그램 설치 통합안내"(install.html)로 리다이렉트될 수 있다.
  필요 프로그램(VeraPort, Ksign, MarkAny WebDRM 등)이 모두 **설치됨**이면 설치할 것은 없다.
- 이 페이지에서 외부 광고 팝업이 뜨면서 탭이 `about:blank#blocked` 상태로 고착되는 경우가
  있다. 스크린샷 타임아웃·흰 화면이 반복되면 그 탭을 `tabs_close_mcp`로 닫고, 포털 탭에서
  [K-에듀파인]을 다시 클릭해 새 탭으로 재진입한다.
- `[HwpODTpatch]` alert 무한 루프와 사용자지원서비스 질의 등록 → [references/한ODT-설치루프.md](references/한ODT-설치루프.md)

### 4단계: 결재대기 목록 조회

- 메뉴 경로: **문서관리 > 결재 > 결재대기**. 목록 조회까지는 브라우저 안에서 동작한다.
- 목록에는 문서 제목·기안 부서·긴급 여부·첨부 건수가 표시된다.
- **빠른 확인 대안**: 업무포털 메인의 "K-에듀파인 문서함" 위젯(결재대기 탭)으로도
  대기 건수를 확인할 수 있다. 처리 후 0건 검증에도 이 위젯이 유용하다.
- **결재대기 그리드는 iframe 안**이라 `find` 도구가 못 찾는다("해당 텍스트 없음"으로
  실패한다). 행 클릭은 스크린샷 좌표로, 행 내용 추출은 `javascript_tool` 에서
  iframe 을 재귀 순회하며 `tr.innerText` 를 긁는 방식으로 한다.

### 5단계: 문서 열기 (브라우저 → 네이티브 창)

- 문서 제목 링크의 onclick은 `doCallClientApp(...)` (인자 4개). 클릭하면 결재 앱
  (`WXSClient.exe`, 창 제목 `HCLTAPP_KYUL_`)이 브라우저 밖 네이티브 창으로 실행된다.
- **클릭 후 브라우저 화면에는 아무 변화가 없는 것이 정상**이다. 새 탭도 안 생기고
  `window.open`도 호출되지 않는다(후킹해도 안 잡힌다). 실패로 오판해 반복 클릭하지 말 것 —
  **누른 횟수만큼 창이 중복 생성**된다. 열렸는지는 아래 "창 확인"으로 본다.

#### 창 확인

창 유무를 잘못 판단하면 반복 클릭 → 창 중복으로 이어지므로 아래 방법만 쓴다.

- **주 창(결재·기안 문서 창)**: `PowerShell` 도구로 프로세스명을 직접 조회한다.
  ```powershell
  Get-Process WXSClient | Select-Object Id, StartTime, MainWindowTitle
  ```
  `Bash` 도구에서 `powershell.exe -Command "Get-Process WXSClient ..."` 를 부르면 창이 실제로
  떠 있어도 **exit 1 로 실패**해 빈 결과와 구분이 안 된다. `Get-Process | Where MainWindowTitle -ne ""`
  류의 일반 목록에는 **안 잡힐 때가 있고**(창 제목이 비어 보이는 시점 존재), UI Automation
  최상위 열거도 가상 데스크톱 전환 시 창을 놓친다. 같은 이유로 `kyul_dom.ps1` 이 "창 없음"을
  내면 잠시 뒤 재시도하고, 문서를 다시 열지 않는다.
- **MSHTML 대화상자와 Win32 메시지 창**: 프로세스의 주 창이 아니라서 `Get-Process ...
  MainWindowTitle` 로는 "안 떴다"고 오판하게 된다. `close_win.ps1 -List`(클래스명 포함) 또는
  `mshtml_dom.ps1 -ListOnly`(IE 보유 여부 포함)로 확인한다.
- **창이 사라졌다고 곧바로 타임아웃으로 단정하지 말 것.** 저장 대화상자가 없어졌을 때는
  (1) 내가 보낸 잘못된 메시지로 앱이 죽었거나 (2) 부모 모달이 `fncClose()` 되며 함께
  닫힌 경우가 많다. `Get-Process WXSClient` 로 **앱 생존부터** 확인한다.
- 중복 창이 떴으면 사용자에게 알리고 정리한다(임의로 닫지 말 것 — 저장 안 된 변경 위험).

### 6단계: 결재 문서 창 내부 제어 (MSHTML 브리지)

`scripts/kyul_dom.ps1`(결재 창)·`scripts/mshtml_dom.ps1 -TitleLike <제목 일부>`(기안 창과
MSHTML 대화상자)를 `PowerShell` 도구로 실행한다. 반드시 **STA** 로 실행한다(STA가 아니면
COM 속성이 조용히 빈 값으로 나온다).

```powershell
pwsh -STA -NoProfile -ExecutionPolicy Bypass -File scripts/kyul_dom.ps1 -JsFile <주입할js> [-Var __r] [-WaitMs 1500] [-Index 0]
pwsh -STA -NoProfile -ExecutionPolicy Bypass -File scripts/mshtml_dom.ps1 -TitleLike "파일저장" -JsFile <주입할js> [-WaitMs 1500]
```

동작 원리: 창의 자식 중 클래스명 `Internet Explorer_Server` 를 찾아
`WM_HTML_GETOBJECT` 를 보내고, `oleacc!ObjectFromLresult` 로 `IHTMLDocument2` 를 얻는다.
그 다음은 일반 웹페이지와 똑같이 다루면 된다.

주입 JS 규칙(결재 창·기안 창·MSHTML 대화상자 공통):

- 결과는 `window.__r` 에 **문자열로** 담는다(객체는 회수 시 빈 값이 된다).
- **주입 스크립트에는 항상 `try/catch` + `__r` 대입을 넣는다.** 예외가 나면 `__r` 이
  미설정이라 PowerShell 이 **아무것도 출력하지 않고** 끝나서, "창을 못 찾았나 /
  타임아웃인가 / 스크립트가 깨졌나" 를 구분할 수 없다. 빈 출력을 받으면 먼저
  `typeof <함수>`·`location.pathname` 정도만 찍는 진단 스크립트를 보내 대상 창이
  맞는지부터 확인한다.
- **모달을 띄울 수 있는 호출은 반드시 `setTimeout(...)` 으로 감싼다(가장 자주 밟는 함정).**
  브리지는 `<script>` 엘리먼트를 `appendChild` 로 주입하므로, 그 스크립트가 **동기적으로**
  `alert` / `showModalDialog` 를 띄우면 `appendChild` 가 반환되지 않아 호출이 120초
  타임아웃까지 매달린다. 해당 호출: `fncAdd`, `fncSanctn`, `savetmpr`, `btnAttAdd.click()`,
  `fncProcessDoc`, `fncSavePC`, `fncVerify`, `fncCreate` …
  ```javascript
  window.__r = "scheduled";
  setTimeout(function () { try { fncAdd(); } catch (e) {} }, 250);   // ← 이렇게
  ```
- 비동기(setTimeout, 탭 전환 후 상태 확인 등)면 완료 시점에 `__r` 에 대입하고
  `-WaitMs` 를 넉넉히 준다.
- **JS 파일은 heredoc 말고 파일 쓰기 도구(Write)로 만든다.** `cat > x.js <<'EOF'` 로
  넣으면 도구 계층을 지나는 사이 **백슬래시가 한 겹 줄어든다**(`\\\\` → `\\`).
  정규식과 경로 리터럴이 조용히 달라져서, 스크립트는 멀쩡해 보이는데 eval 만 깨진다.
- **경로의 백슬래시는 리터럴로 쓰지 말고 `String.fromCharCode(92)` 로 조립한다.** 백슬래시가
  한 겹 줄어 `"C:\Users\..."` 가 되면 `\U`·`\u` 가 유니코드 이스케이프로 해석돼 eval 이
  `16진수가 필요합니다` 로 깨진다(접수처리 7단계의 경로 패치). → 사례
- `execScript` 는 이 문서 모드에 **없다**. 스크립트는 `<script>` 엘리먼트 주입으로 실행된다
  (브리지가 알아서 처리).

### 7단계 이후

- 7~9단계(본문·첨부 PC저장, 과제카드 지정 → 문서처리, 처리 결과 검증) → [references/접수처리.md](references/접수처리.md)
- 10단계(기안 → 결재올림, 선례 조회) → [references/기안.md](references/기안.md)
- 10-13(완료 문서 공개구분 수정) → [references/공개구분수정.md](references/공개구분수정.md)

## 브라우저 쪽 함정

- **화면 구조**: Nexacro 셸 + iframe 다층 구조(websocket 브리지, 업무화면 iframe,
  OZ 뷰어 iframe). DOM 조회 시 iframe을 재귀 탐색해야 한다.
- **javascript_tool 비동기 결과**: async IIFE/Promise 반환값은 `{}`로 직렬화된다.
  결과를 `window` 변수에 저장해 두고, 별도 호출에서 `JSON.stringify`로 동기 조회할 것.
- **출력 차단**: 함수 소스나 URL 전체를 반환하면 세션 토큰 감지로 출력이
  "[BLOCKED: Cookie/query string data]"로 대체된다. 경로·불리언·식별자만 정규식으로
  추출해 반환하면 통과한다.
- **사용자가 브라우저를 껐다 켜면 확장이 새 연결로 잡힌다.** 이전 연결은 목록에
  그대로 남아 있고 `select_browser` 도 성공하므로, 모르고 계속 쓰면 **탭이 만들어지고
  스크린샷도 찍히는데 사용자 화면에는 아무것도 안 보인다**("이 컴퓨터 브라우저에 안
  열렸어"). `list_connected_browsers` 의 `name` 은 **목록 순서 라벨이라 고정 식별자가
  아니다** — `Browser 1` 이 다른 창을 가리키게 된다. 판단 기준은 **`connectedAt` 이
  가장 큰 로컬(`isLocal:true`) 항목**. 사용자가 브라우저를 재시작했다고 하면 반드시
  목록부터 다시 뽑는다.

## 일반 원칙

- 여러 조작은 `browser_batch`로 묶어 실행. 클릭 전 최신 스크린샷으로 좌표 확인.
- 인증서 비밀번호·개인 자격증명 입력은 절대 자동화하지 않는다.
- **세션이 죽으면 창이 줄줄이 뜬다 — 당황하지 말고 순서대로 정리한다.**
  팝업 내부를 스크립트로 험하게 다루면 서버 세션이 끊길 수 있다(→ 사례). 증상:
  별도 `IEFrame` 창에 "요청하신 서비스가 정상적으로 처리되지 않았습니다 / 사용자 정보를
  불러오지 못하였습니다", 제목이 빈 `-- 웹 페이지 대화 상자`, 이어서 `스크립트 오류`,
  브라우저 탭에는 "접속이 종료되었습니다".
  1. 군더더기 창을 하나씩 닫는다: 같은 `-TitleLike`(제목이 정확히 정해지면 `-Exact`)로
     `close_win.ps1 -List` → `-Index` 로 하나 닫기 → 다시 `-List`. `-Index` 는 부를 때마다 창을 다시
     세어 매기는 순번이라, 처음 뽑은 목록의 순번으로 연달아 닫으면 엉뚱한 창이 닫힌다
  2. **브라우저 탭에서 알림 [확인]을 누르면 SSO 로 세션이 되살아나는 경우가 있다**
     (재로그인 불필요, 타이머가 리셋되며 복구된다)
  3. 문서 창의 입력값은 클라이언트 메모리에 남아 있지만 서버 호출은 전부 실패하므로,
     임시저장도 안 된다. 창을 닫고 기안 10-12 의 자동저장 복원을 전제로 다시 만든다
- **공문·결재 문서 내용이 담긴 화면은 영구 파일로 남기지 않는다.** 브라우저 스크린샷은
  `save_to_disk` 를 쓰지 않는다. `capture.ps1` 의 PNG 는 `%TEMP%` 아래 스크래치 폴더
  (`-Out` 을 생략하면 `%TEMP%\kedufine-capture`)에 두고 판독 직후 지운다.
- DOM 조사 결과를 출력할 때 세션 토큰·계정 ID·부서코드가 섞이지 않게 필요한 필드만 뽑는다.
- **이 스킬 문서는 외부 공개를 전제로 한다.** 갱신 시 개인·학교 식별 정보(교사·학생 이름,
  학교명, 문서번호, 기관·계정 실명 등)를 기록하지 않고 일반화해서 쓴다. 학교별 결재권자·부서
  편제는 학년도별 로컬 파일(`references/결재선-<학년도>.md`)로 관리하고 공개 저장소에 올리지 않는다.
