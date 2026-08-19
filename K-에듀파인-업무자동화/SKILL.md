---
name: K-에듀파인-업무자동화
license: MIT
description: >-
  서울 업무포털(sen.eduptl.kr)에서 K-에듀파인(klef.sen.go.kr) 진입 → 결재대기 확인·접수 공문 처리 → 신규 기안 작성·상신까지의 자동화 워크플로우. 목록·진입은 Claude in Chrome, 결재/기안 문서 창(WXSClient)과 그 파생 대화상자는 임베디드 IE라 PowerShell MSHTML 브리지로 제어하고, 팝업 내부는 실제 마우스 클릭으로 조작한다. 트리거: (1) K-에듀파인 업무 자동화 요청 (2) 결재대기 문서 확인·공문 처리 요청 (3) 접수 공문 본문·첨부파일 PC저장 요청 (4) 공문 기안·결재올림(상신) 요청 — "공문 올려 줘", "기안해 줘", "결재 올려 줘" (5) 결재 문서 내부 탭 이동·필드 판독·버튼 조작 (6) K-에듀파인 메뉴 진입이 필요한 작업의 진입 단계
---

# K-에듀파인 업무 자동화 (업무포털 → K-에듀파인 → 결재대기·기안)

## 개요

서울특별시교육청 업무포털을 거쳐 K-에듀파인에 진입해, 들어온 공문을 처리하고(결재대기)
새 공문을 만들어 올리는(기안) 자동화 워크플로우. **도구가 세 갈래**다.

- **목록·진입**: Claude in Chrome MCP (브라우저)
- **문서 창 내부 판독·필드 입력**: PowerShell MSHTML 브리지
  - `scripts/kyul_dom.ps1` — 결재 문서 창 전용(`Get-Process WXSClient` + 제목 완전일치)
  - `scripts/mshtml_dom.ps1` — **제목 부분일치 범용판.** 기안 창과 모든 파생 대화상자는
    이걸 쓴다. 대화상자는 클래스가 `Internet Explorer_TridentDlgFrame` 이고 제목이 달라
    `kyul_dom.ps1` 로는 못 잡는다
- **팝업 내부 조작**: **실제 마우스 클릭** (`scripts/click_screen.ps1`)
  — 수신자지정·결재경로설정 같은 선택 팝업은 스크립트로 상태를 못 바꾼다. 10단계 참조

보조 스크립트:

| 스크립트 | 용도 |
|---|---|
| `scripts/click_screen.ps1` | 창을 앞으로 올리고 **창 기준 상대좌표**에 실제 마우스 클릭 |
| `scripts/capture.ps1` | 창을 PNG 로 캡처(PrintWindow → CopyFromScreen 폴백). 좌표는 이 이미지 좌표 = `click_screen.ps1` 의 `-X/-Y` |
| `scripts/dlg.ps1` | 네이티브 대화상자(#32770) 자식 컨트롤 덤프 / `WM_COMMAND` 로 버튼 클릭 |
| `scripts/close_win.ps1` | 제목 부분일치 창에 `WM_CLOSE` (`-List` 로 먼저 확인) |
| `scripts/pick_file.ps1` | 표준 "열기" 대화상자에 경로 입력 후 [열기] |

주소:

- 업무포털: `https://sen.eduptl.kr/bpm_man_mn00_001.do` (진입·로그인은
  [나이스-업무자동화](../나이스-업무자동화/SKILL.md) 스킬의 1~3단계와 동일)
- K-에듀파인: `https://klef.sen.go.kr/keris_ui/main.do` (업무포털에서 SSO로 진입)

> **적용 범위**: 서울특별시교육청 환경(`sen.*` 도메인)에서 실사용으로 검증했다. 타 시도는
> 업무포털 도메인과 세부 화면이 다를 수 있으나, K-에듀파인 결재·기안 구조(WXSClient·MSHTML)는
> 전국 공통 계열이라 절차 골격은 그대로 적용된다.

**자동화 경계 (v2에서 정정)**: 결재 문서 창은 브라우저 탭이 아니라 네이티브 Windows 창
(`WXSClient.exe`, 제목 `HCLTAPP_KYUL_`)이라 **브라우저 MCP 도구로는 닿지 않는다**. 그러나
그 창의 내부 렌더러가 **임베디드 IE(MSHTML)** 이므로, PowerShell에서 DOM을 직접 잡아
읽기·클릭·필드 조작을 할 수 있다. v1에 적힌 "제어 불가"는 틀린 기록이었다 → 6단계 참조.

**단, 되돌릴 수 없는 조작은 자동 실행하지 않는다.** 문서처리(`fncProcessDoc`)와
결재올림(`fncSanctn`)은 confirm 한 번으로 확정된다. 사용자 승인을 받고 실행하거나
사용자에게 핸드오프한다.

**주입 스크립트가 모달을 띄우면 PowerShell 이 통째로 멈춘다 (가장 자주 밟는 함정).**
`mshtml_dom.ps1` 은 `<script>` 엘리먼트를 `appendChild` 로 주입한다. 그 스크립트가
**동기적으로** `alert` / `showModalDialog` 를 띄우면 `appendChild` 가 반환되지 않아
호출이 120초 타임아웃까지 매달린다. 모달을 띄울 수 있는 호출
(`fncAdd`, `fncSanctn`, `savetmpr`, `btnAttAdd.click()`, `fncProcessDoc` …)은
**반드시 `setTimeout(...)` 으로 감싸** 비동기로 실행한다.

```javascript
window.__r = "scheduled";
setTimeout(function () { try { fncAdd(); } catch (e) {} }, 250);   // ← 이렇게
```

## 워크플로우

### 1단계: 업무포털 로그인 (나이스 스킬과 공통)

업무포털 접속·인증서 로그인 핸드오프·공지 팝업 닫기는 나이스-업무자동화 스킬 1~3단계와
동일하다. 인증서 비밀번호 입력은 자동화 금지 — 사용자가 직접 로그인한다.

### 2단계: [K-에듀파인] 클릭 → 새 탭 진입

- 업무포털 메인 상단 메뉴에서 **[K-에듀파인]** 텍스트 클릭 (1568px 폭 기준 약 (407, 68)).
- 새 탭이 같은 탭 그룹에 생성된다 (`klef.sen.go.kr/keris_ui/main.do`).
  클릭 후 `wait 3초` → `tabs_context_mcp`로 새 탭 ID 확보.
- **시행착오**: 사용자 개입 직후 등 일부 상황에서 `navigate`로 klef 직접 이동이 권한
  분류기에 거부될 수 있다. 이때는 navigate를 반복하지 말고 **포털 화면의 [K-에듀파인]
  메뉴를 다시 클릭**하는 방식(페이지 내 클릭)으로 우회한다.

### 3단계: 보안 프로그램 안내 페이지(install.html) 처리

- 첫 진입 시 "PC 보안 프로그램 설치 통합안내"(install.html)로 리다이렉트될 수 있다.
  필요 프로그램(VeraPort, Ksign, MarkAny WebDRM 등)이 모두 **설치됨**이면 설치할 것은 없다.
- **시행착오**: 이 페이지에서 외부 광고 팝업이 뜨면서 탭이 `about:blank#blocked` 상태로
  고착되는 경우가 있다. 스크린샷 타임아웃·흰 화면이 반복되면 그 탭을 `tabs_close_mcp`로
  닫고, 포털 탭에서 [K-에듀파인]을 다시 클릭해 새 탭으로 재진입한다.

### 4단계: 결재대기 목록 조회

- 메뉴 경로: **문서관리 > 결재 > 결재대기**. 목록 조회까지는 브라우저 안에서 동작한다.
- 목록에는 문서 제목·기안 부서·긴급 여부·첨부 건수가 표시된다.
- **빠른 확인 대안**: 업무포털 메인의 "K-에듀파인 문서함" 위젯(결재대기 탭)으로도
  대기 건수를 확인할 수 있다. 처리 후 0건 검증에도 이 위젯이 유용하다.

### 5단계: 문서 열기 (브라우저 → 네이티브 창)

- 문서 제목 링크의 onclick은 `doCallClientApp(...)` (인자 4개). 클릭하면 결재 앱
  (`WXSClient.exe`, 창 제목 `HCLTAPP_KYUL_`)이 브라우저 밖 네이티브 창으로 실행된다.
- **클릭 후 브라우저 화면에는 아무 변화가 없는 것이 정상**이다. 새 탭도 안 생기고
  `window.open`도 호출되지 않는다(후킹해도 안 잡힌다). 실패로 오판해 반복 클릭하지 말 것 —
  **누른 횟수만큼 창이 중복 생성**된다.
- 좌표 클릭이 안 먹은 것처럼 보여도 실제로는 열렸을 수 있다. 창 존재 확인은 이것 하나로:
  ```powershell
  Get-Process WXSClient | Select-Object Id, StartTime, MainWindowTitle
  ```
  `Get-Process | Where MainWindowTitle -ne ""` 류의 일반 목록에는 **안 잡힐 때가 있다**
  (창 제목이 비어 보이는 시점 존재). UI Automation 최상위 열거도 가상 데스크톱 전환 시
  창을 놓친다. 프로세스명으로 직접 조회하는 것이 가장 확실하다.
- 중복 창이 떴으면 사용자에게 알리고 정리한다(임의로 닫지 말 것 — 저장 안 된 변경 위험).

### 6단계: 결재 문서 창 내부 제어 (MSHTML 브리지)

`scripts/kyul_dom.ps1` 사용. 반드시 **STA** 로 실행한다.

```bash
pwsh -STA -NoProfile -ExecutionPolicy Bypass -File scripts/kyul_dom.ps1 \
     -JsFile <주입할js> [-Var __r] [-WaitMs 1500] [-Index 0]
```

동작 원리: 창의 자식 중 클래스명 `Internet Explorer_Server` 를 찾아
`WM_HTML_GETOBJECT` 를 보내고, `oleacc!ObjectFromLresult` 로 `IHTMLDocument2` 를 얻는다.
그 다음은 일반 웹페이지와 똑같이 다루면 된다.

주입 JS 규칙:

- 결과는 `window.__r` 에 **문자열로** 담는다(객체는 회수 시 빈 값이 된다).
- 비동기(setTimeout, 탭 전환 후 상태 확인 등)면 완료 시점에 `__r` 에 대입하고
  `-WaitMs` 를 넉넉히 준다.
- `execScript` 는 이 문서 모드에 **없다**. 스크립트는 `<script>` 엘리먼트 주입으로 실행된다
  (`kyul_dom.ps1` 이 알아서 처리).

확인된 화면 요소 (결재 문서 창, 접수문서 기준):

| 요소 | id | 용도 |
|------|----|------|
| 결재정보 탭 | `property` (LI) | 활성 시 `class="Lcurrent"` |
| 본문 탭 | `maindoc1` (LI) | 각 LI 안의 `A` 를 `.click()` |
| 문서처리 | `processdoc` (A) | `fncProcessDoc()` — **비가역** |
| 결재올림 | `sanctndoc` (A) | **비가역** |
| 결재경로지정 | `btnApprProperty` (A) | |
| 공람지정 | `btnCnrsAppn` (A) | |
| 첨부 PC저장 | `btnAttSave` (A) | 첨부 전용. 본문 저장은 창 우상단 아이콘 → 7단계 |
| 본문 PC저장 | 우상단 `A.utilBtnAll` (img alt `PC저장(새창열기)`) | `fncSavePC()` → 7단계 |
| 첨부 파일 목록 | `HSFileBox` (DIV) + `HSAttach1` (OBJECT) | 건수는 `D$('HSAttach1').getFilesCount()` |
| 수정저장 / 임시저장 | `saveupdate` / `savecnslt` | |
| 편철(단위과제·관리과제) | `untkID` / `mngtkID` (hidden) | 미지정 시 빈 값 |
| 과제카드 선택 / 초기화 | `aChooseTkcrd` / `aCancelTkcrd` (A) | 결재정보 탭에 있음. 전역 `fncTkcrdChoisePop` |
| 기록물 형태 | `registSe` (SELECT) | 1=일반문서 2=도면류 3=사진,필름류 4=녹음,동영상류 5=카드류 |
| 제목 | `Sj` (INPUT) | |
| 대국민공개 | `othbcLmtt1/2/3` (radio) | 전체공개 / 부분공개 / 비공개 |

**탭 전환은 실증됨** — `document.getElementById('maindoc1').getElementsByTagName('A')[0].click()`
로 본문 탭 전환, `property` 로 복귀가 정상 동작한다. 즉 스크립트 클릭이 앱 UI에 그대로 먹는다.

**편철(v2 미해결 → v3 해소)**: 편철은 **과제카드(단위과제)** 지정이고 값은 `untkID` 에
들어간다. v2 는 "지정 UI 가 결재정보 탭에 없다"고 적었으나 **오독이었다.** 결재정보 탭에
`aChooseTkcrd`(과제카드선택) / `aCancelTkcrd`(과제카드선택취소) 앵커가 있고 전역
`fncTkcrdChoisePop` 이 팝업을 연다. `fncProcessDoc()` 을 부를 필요가 없다.
(`fncProcessDoc` 이 confirm 한 번으로 확정되는 비가역 동작이라는 v2 기록은 그대로 유효 —
승인 없이 호출 금지.)

### 7단계: 본문·첨부 PC저장

접수 공문 원본을 파일로 받아 두는 작업. **창이 4겹**으로 이어진다.

```
HCLTAPP_KYUL_ (#32770, MSHTML)          ← 결재 문서 창
  └ "파일저장 | 업무관리시스템 -- 웹 페이지 대화 상자"   (TridentDlgFrame, MSHTML)
      └ "문서저장 -- 웹 페이지 대화 상자"                (TridentDlgFrame, MSHTML)
          └ "폴더 찾아보기"                             (#32770, 네이티브 — MSHTML 아님)
```

앞의 셋은 `mshtml_dom.ps1` 로 제어된다. **문제는 마지막 폴더 선택 창**인데, 정면으로
상대하지 말고 아래 "정석"으로 우회한다.

**호출 사슬 (읽어서 확인한 것)**

- 우상단 아이콘 `fncSavePC()` → `docSave('doccrdMain')`
- `docSave` 분기
  - `rInfo.draftsrc == '4'` (비전자접수문서): 첨부 동반 여부를 confirm 으로 물음
  - **`applId == '5010'` (접수대기 문서)**: `alert("열람권한이 없습니다.\n접수처리 후
    저장하시기 바랍니다.")` 후 return. **접수처리 전에는 저장 자체가 막힌다.**
    저장 실패 시 이 분기부터 의심할 것 (정상 결재대기 문서는 `applId 2010`)
  - 그 외: 모달 팝업 `retrieveDocListBdtStre.do` 로 넘김
- 파일저장 대화상자 → `fncVerify()` → `bdtStreAt=='Y'` 면 `fncMultiVerify()`
- 문서저장 모달의 **`init()`** (약 23KB)이 실제 저장을 수행

**파일저장 대화상자 옵션 id**

| id | 뜻 | 기본 |
|----|----|------|
| `hwpsave` / `attsave` / `sisave` / `hoxsave` | 본문 / 첨부파일 / 시행문 / 문서정보 | 앞 둘만 체크 |
| `HWPDISTSAVE01` / `HWPDISTSAVE02` | 비배포(ODT) / 배포(PDF) | 01 |
| `CHOSAVE03` / `CHOSAVE02` / `CHOSAVE04` | 파일명 규칙 3종 | 03 |

**정석: 폴더 선택 창을 띄우지 말고 경로를 소스에 박아 넣는다**

`init()` 안의 `FileManager.selectFolderEx(...)` 호출부만 경로 리터럴로 바꿔 재정의한다.
ActiveX 객체(`FileManager`)에 메서드를 덮어쓰는 것은 실패하므로 **함수 소스 치환**이 답이다.

```javascript
// 문서저장 모달에 주입
(function () {
  var src = init.toString();
  var re = /FileManager\.selectFolderEx\([^)]*\)/;      // 호출은 정확히 1곳
  if (!re.test(src)) { window.__r = "NO MATCH"; return; }
  var patched = src.replace(re, '"C:\\\\some\\\\ascii\\\\path"');
  window.__patchedInit = eval("(" + patched + ")");
  try { pMsg.innerHTML = ""; } catch (e) {}                // 진행 메시지 비우기
  window.__r = "PATCH ok";
  setTimeout(function () { window.__patchedInit(); }, 400);
})();
```

- `init()` 은 인자가 없고 전역 `obj`(USERID·APPRIDLIST·fileGbn·saveChoice·hwpChoice 등)와
  `pMsg` 를 쓴다. eval 로 만든 사본도 전역 스코프라 그대로 동작한다.
- 결과 확인은 `pMsg.innerHTML` — 저장된 전체 경로와 `...... ok`, 끝에
  "결재문서들을 모두 저장하였습니다." 가 찍힌다.
- **저장 경로는 ASCII 임시 폴더로 받고 PowerShell 로 최종 위치에 옮긴다.** 한글·공백이
  섞인 클라우드 드라이브 경로를 ActiveX `CopyFile` 에 직접 주는 위험을 피한다.
- 끝나면 `fncClose()` 를 문서저장 → 파일저장 순으로 주입해 정리한다(앞의 것만 닫아도
  대개 함께 닫힌다).

**첨부 유무는 미리 확인한다**: `D$('HSAttach1').getFilesCount()`. 0 이면 `HSFileBox` 의
`tbody` 도 비어 있고 OBJECT 의 `AttachCount` 파라미터도 0 이다. 첨부가 없으면
"첨부도 받아 달라"는 요청에 대해 0건임을 근거와 함께 보고한다.

**저장한 PDF는 텍스트가 안 뽑힌다**: 글꼴에 유니코드 매핑이 없어 추출 결과가 깨진다
(스크린 리더로도 못 읽는다). 본문 텍스트가 필요하면 **렌더링해서 읽고 텍스트본을 따로
만들어 함께 저장**한다.

```bash
python -c "import fitz; d=fitz.open(PDF); d[0].get_pixmap(dpi=170).save('p1.png')"
# → 이미지로 읽어 .txt 로 옮겨 적고, 임시 PNG 는 삭제
```

### 8단계: 과제카드 지정 → 문서처리 (접수 처리)

**비가역.** 사용자의 명시적 승인 없이 실행하지 않는다. 순서는 결재정보 탭 → 과제카드 →
보안·공개 확인 → 문서처리 → 네이티브 확인창.

**8-1. 결재정보 탭으로**

```javascript
document.getElementById('property').getElementsByTagName('A')[0].click();
```

**8-2. 과제카드 지정 — 팝업이 Nexacro다**

`fncChooseTkcrd()` → `showModalDialog(retrieveTaskChoiseUntkCard.do)` → 실제 화면은
`taskChoiseTaskNexacroRP.do`. 창 제목은 "K-에듀파인 -- 웹 페이지 대화 상자"(MSHTML).
**목록이 DOM 에 없다** — TR/A 를 긁으면 0건이 나온다. Nexacro 객체로 접근한다.

```javascript
var f = nexacro.getApplication().mainframe.QuickViewFrame.form.Tab00.Tabpage1.form;
var ds = f.divTkcrd.form.grdAList.getBindDataset();     // f.dsAList 로는 접근 불가
// 컬럼: tkcrdId, tkcrdNm, taskId, dcryPrsrvPdSeNm(보존기간), chk
for (var r = 0; r < ds.getRowCount(); r++) ds.setColumn(r, "chk", 0);
ds.setColumn(target, "chk", 1);        // ★ 확인 버튼은 chk==1 인 행을 찾는다
ds.set_rowposition(target);
f.divAuth.form.btnAuthC01.click();     // 확인 (btnAuthC02 도 동일 동작)
```

- **`currentrow` 를 맞춰 놓는 것만으로는 안 된다.** 확인 핸들러가
  `dsAList.findRowExpr("chk==1")` 로 찾고, 없으면 "단위과제카드를 선택하세요" 로 되돌린다.
- 컴포넌트 트리: `divSearch.form.edtTaskNm`(검색어), `divAuth.form.btnAuthS01`(조회) /
  `btnAuthC01`(확인), `divTkcrd.form.grdAList`(단위과제카드),
  `divTkcrdMang.form.grdBList`(관리과제카드), `divActPlan.form.grdActPlan`(활동계획).
- 관리과제카드는 필수가 아니다(체크된 것이 있으면 함께 넘어갈 뿐).

**8-3. 지정 결과는 INPUT 이 아니라 HOX XML 에 들어간다**

```javascript
get_text(domHox1, '/hox/docInfo/taskInfo/taskCard/cardID');    // 실제 저장 위치
get_text(domHox1, '/hox/docInfo/taskInfo/taskCard/cardName');
```

**`untkID`·`mngtkID` hidden 은 빈 채로 남는다.** 이 값만 보고 "과제카드가 안 붙었다"고
판단하면 오판이다(v2 표의 설명 보강). 화면 표시는 `#dvTkcrdEdit` 행의 `#taskInfo` span.

**8-4. 보안·공개 확인**

결재정보 탭의 `othbcLmtt1/2/3`(공개·부분공개·비공개)이 원 문서 값으로 이미 설정돼 있다.
**공개 문서면 공개제한근거 `othbcAt1~8`(1~8호)은 전부 `disabled`** — 체크할 수 없고
할 필요도 없다. 비공개·부분공개일 때만 활성화된다. 기존 설정은 그대로 두는 것이 기본이다.

**8-5. 문서처리**

`fncProcessDoc()` → "문서처리 | 업무관리시스템 -- 웹 페이지 대화 상자"(MSHTML).

- 이 대화상자에도 대국민공개여부·관계법령 1~8호·공개제한기간·게시판 필드가 **존재하지만
  평소에는 숨겨져 있다**(`offsetParent === null`). 공문게시를 지정할 때만 노출된다.
  `checked=false` 만 보고 "체크가 빠졌다"고 오판하지 말고 **`offsetParent` 로 노출 여부를
  먼저 확인**할 것.
- 실제로 보이는 것은 처리구분(`docprocess` 가 기본 선택됨)·의견작성·의견첨부뿐이다.
- 확인 = `fncVerify()` (앵커 `#aSubmit`).

**8-6. 네이티브 확인창 처리**

`fncVerify()` 뒤에 클래스 `#32770`, 제목 **"웹 페이지 메시지"** 창이 뜬다. MSHTML 이 아니라
Win32 메시지박스다.

- 문구는 자식 `Static`(보통 `id=65535`)에서 읽는다. 확인 문구: "문서를 결재하시겠습니까 ?"
- **버튼 컨트롤 ID 가 창마다 다르다.** confirm 은 확인=1·취소=2 였는데,
  뒤이어 뜨는 결과 alert("정상적으로 처리되었습니다.")은 **확인 버튼이 id=2** 였다.
  넘겨짚지 말고 매번 컨트롤을 덤프해 확인한 뒤 `PostMessage(hwnd, WM_COMMAND, id, 0)` 를 보낸다.
- 처리가 끝나면 **결재 창(WXSClient)이 스스로 닫힌다.** 창이 사라진 것은 정상 완료 신호다.

### 9단계: 처리 결과 검증 (브라우저로 복귀)

- 결재대기 목록을 재조회해 **0건**, 상단 카운터가 `결재(긴급) 0(0)` · `문서진행 0` 인지 본다.
  업무포털 메인의 K-에듀파인 문서함 위젯을 새로고침해도 된다.
- 확정 검증은 **문서관리 > 문서함 > 문서등록대장**에서 해당 문서 상태가 `종료` 인지 확인한다.
- 작업이 길어질 것 같으면 시작 전에 K-에듀파인 좌상단 타이머 옆 **[연장]** 을 눌러 둔다
  (약 (218, 40), 1568px 폭 기준). 60분으로 리셋된다.

### 10단계: 기안 (신규 공문 작성 → 결재올림)

들어온 공문을 처리하는 1~9단계와 별개로, **새 공문을 만들어 올리는** 흐름이다.

**핵심 원칙 두 가지 (v4에서 값비싸게 배움)**

1. **본 창의 폼 필드는 스크립트로, 팝업 내부는 마우스로.**
   기안 창 본 문서의 INPUT·radio·checkbox 는 `.click()` / 값 대입이 잘 먹는다.
   그러나 **수신자지정·결재경로설정 팝업은 안 먹는다.** 이 팝업들은 jQuery 이벤트와
   전역 상태(`selectedID`, `Capi` 캐시)에 의존해서, `checked = true` 도 `.click()` 도
   `$().trigger('click')` 도 내부 상태를 제대로 갱신하지 못한다. 억지로 밀어붙이면
   상태가 꼬이고 **세션까지 죽는다**(실제로 죽었다 → 아래 "세션" 항목).
   → 팝업은 `capture.ps1` 로 보고 `click_screen.ps1` 로 실제 클릭한다.
2. **모달을 띄우는 호출은 `setTimeout` 으로 감싼다.** (개요의 함정 항목)

#### 10-1. 서식 열기

문서관리 > 기안 > **공용서식** → 서식명 클릭. 표준 서식 목록(16종):
`일반기안문 서식(결재4인,협조4인)` 이 표준이다.

- 결재대기와 같은 `WXSClient.exe` 네이티브 창이 뜨지만 **창 제목이 `HCLTAPP_KYUL_` 이
  아니라 서식명**(`일반기안문 서식(결재4인,협조4인)_`)이다.
  → `kyul_dom.ps1`(제목 완전일치)로는 못 잡는다. `mshtml_dom.ps1 -TitleLike "일반기안문 서식"` 사용.
- 클릭 후 화면 무변화가 정상. 확인은 `Get-Process WXSClient`. 반복 클릭 시 창 중복 생성.

#### 10-2. 기안 창 요소

| 요소 | id | 비고 |
|---|---|---|
| 결재올림 | `sanctn` (A) | **비가역** |
| 결재경로(지정) | `reportcours` / `btnApprProperty` | |
| 임시저장 | `savetmpr` / `savecnslt` | |
| 수정저장 | `saveupdate` | |
| 서식변경 | `changeformat` | |
| 탭 | `property`(결재정보) / `maindoc1`(본문) / `maindoc2`(시행문) | 안의 `A` 를 `.click()` |
| 하위 탭 | `id-tabarea01`(결재경로·시행정보) / `02`(공람) / `04`(지식공유) / `05`(관리정보) | |
| 제목 | `Sj` (INPUT) | `onchange="input_changed(this)"` |
| 수신자지정 / 변경 | `btnRcverAppn` / `btnRcverDispAppn` | |
| 과제카드 선택 / 취소 | `aChooseTkcrd` / `aCancelTkcrd` | 8-2 와 동일(Nexacro) |
| 대국민공개 | `othbcLmtt1/2/3` (공개/부분공개/비공개) | |
| 공개제한근거 | `othbcAt1`~`othbcAt8` | 부분공개·비공개일 때만 활성 |
| 첨부 파일추가/삭제/PC저장 | `btnAttAdd` / `btnAttDelete` / `btnAttSave` | |
| 첨부 목록 / 개수 | `HSFileBox` (DIV) / `HSAttach1.getFilesCount()` | |
| 긴급 | `emrgncy` (checkbox) | |
| 본문 편집기 | iframe `editor1` 안 OBJECT `editor1` | 한글(HWP) ActiveX |

#### 10-3. 제목·본문 — 본문은 한글 ActiveX 필드다

본문 편집기는 HTML 이 아니라 **HWP ActiveX 컨트롤**이다. 서식에 이름 붙은 필드가 있고
`PutFieldText` / `GetFieldText` 로 읽고 쓴다.

```javascript
var ed = document.getElementById("editor1").contentWindow.document.getElementById("editor1");
ed.GetFieldList(1, 0);          // 필드 목록 (구분자 {{0}})
ed.PutFieldText("본문", text);   // 줄바꿈은 \r\n
ed.GetFieldText("수신");
```

일반기안문 서식의 필드: `머리표어 로고 발신기관명 심볼 수신 경유 결재제목 본문 꼬리표어
관인 발신명의 관인생략 수신처캡션 수신처 직위.1~4 서명.1~4 협조직위.1~4 협조.1~4
문서번호 시행일자 접수번호 접수일자 우편번호 주소 홈페이지 전화 전송 이메일 공개여부`

- **제목**은 `Sj` INPUT 에 값을 넣고 `input_changed(sj)` 를 호출하면 `결재제목` 필드로
  자동 동기화된다. 본문 필드에 직접 쓸 필요 없다.
- `수신`·`발신명의`·`공개여부` 필드는 수신자지정·공개설정을 하면 **자동으로 채워진다.**
  직접 쓰지 말 것.
- 본문 탭으로 전환하지 않아도(`editor1` 이 `offsetParent === null` 이어도)
  `PutFieldText` 는 동작한다.

#### 10-4. 대국민공개 — 본 창 폼이라 스크립트 OK

```javascript
document.getElementById("othbcLmtt2").click();   // 부분공개
document.getElementById("othbcAt6").click();     // 6호(개인정보)
```

기본값이 **비공개(`othbcLmtt3`)** 다. 개인정보가 든 복무·인사 문서는 `부분공개 + 6호`.
설정하면 HWP `공개여부` 필드가 `부분공개(6)` 로 바뀌는 것으로 검증한다.

#### 10-5. 수신자지정 (`btnRcverAppn`) — 마우스로

팝업 제목 `수신자지정 -- 웹 페이지 대화 상자`. 일반 HTML(Nexacro 아님).

- **기본 활성 탭이 `공용그룹`** 이다. 먼저 **조직도** 탭을 누른다.
- 왼쪽 트리에서 체크한 다음 **가운데 `>>` 버튼으로 오른쪽 "수신자" 패널에 옮겨야 한다.**
  체크만 하고 [확인]을 누르면 **수신자 0 으로 조용히 반영되지 않는다** — 오류도 안 뜬다.
  (이걸 몰라서 두 번 헛돌았다.)
- 조직명 검색은 `orgnztNm` INPUT 에 **값만 대입**하고(안전) [조회]는 마우스 클릭.
- 확인 = `fncVerifyChoose()`.

창 기준 좌표(창 836×669 기준): 조직도 탭 `(59,123)` · 조직명 [조회] `(357,182)` ·
검색결과 첫 행 체크박스 `(49,255)` · `>>` `(419,308)` · [확인] `(789,84)`

반영되면 본 창에서 이렇게 보인다.

```
수신 = 서울특별시교육감(○○담당관)     ← 교육감 + 괄호 안 담당 부서
발신명의 = ○○중학교장                       (자동)
시행종류 = 대외시행 [v]자동발송              (자동 — 아래 참조)
```

**자동발송 — 수신자를 지정하면 기본으로 켜진다 (확인 완료)**

대외시행 공문은 `자동발송` 에 체크돼 있어야 **결재 완료와 동시에 수신 기관으로 발송**된다.
체크되지 않았으면 결재 완료 후 발송함에서 직접 발송해야 한다(행정실 안내).

- **판별은 HOX XML 로 한다**: `domHox1.xml` 안의 **`<sendMethod>auto</sendMethod>`**
  → 자동발송 켜짐. 과제카드가 `untkID` 가 아니라 HOX 에 저장되던 것과 같은 패턴이다.
- **`recpInfo` 의 innerText 로 판별하면 안 된다.** 기안 화면에서 `시행종류 대외시행 자동발송`
  으로 읽히는 것은 체크박스 **라벨**이라 체크 여부를 알려주지 않고, 조회(읽기 전용) 화면에서는
  체크박스가 아예 렌더링되지 않아 `시행종류 대외시행` 으로만 보인다.
- **`autoSnding_senderName` · `autoSnding_enforceType` · `autoSndingHiddenInfo` hidden 이
  비어 있는 것은 정상**이다. 이건 자동발송 상세 설정용 임시 필드이지 켜짐/꺼짐 플래그가 아니다.
- `senderID` · `enforceDate` 는 **최종 결재 시점에 시스템이 채운다.** 결재 전 문서에서
  비어 있다고 자동발송이 꺼진 것으로 오판하지 말 것.
- **사후 검증**: 문서등록대장 > 해당 문서 > **발송정보** 탭에서 수신처 상태가
  `수신` → `접수` → `완료` 로 찍히고, `수신` 시각이 **최종 결재 시각과 같으면** 자동발송이다
  (수동 발송이면 발송함에서 처리한 만큼 시차가 난다).
- **수신자 지정 직후 `sendMethod` 를 한 번 찍어 두고, 결재올림 직전에 다시 확인한다**
  (10-10 의 사전 확인 스니펫에 포함돼 있다). 기본으로 켜지긴 하지만 "켜져 있겠지"로
  넘어가면 안 되는 항목이다 — 꺼진 채 결재가 끝나면 공문이 안 나간 줄도 모르고 지나간다.

#### 10-6. 결재경로지정 (`btnApprProperty`) — 마우스로

팝업 제목 `결재경로설정 -- 웹 페이지 대화 상자`.

- 오른쪽 사용자 목록은 **iframe `reportOrgList`** 안에 있다(본 문서에서 TR 을 긁으면 0건).
  라디오: `id` = 사용자 ID, `name="partSelRadio"`.
- `fncAdd()` 는 라디오 체크가 아니라 **전역 `selectedID`** 와
  `Capi.getUser(selectedID, searchDept).user` 를 본다. 스크립트로 체크만 하면
  `"선택된 사용자 정보가 없습니다."` alert 이 뜬다. → **행을 마우스로 클릭**.
- 행 클릭 → **`∨∨`(`fncAdd`)** 로 아래 그리드에 추가. 확인 = `fncVerify()`.
- **연속 클릭 금지**: 행 선택이 반영되기 전에 `∨∨` 를 누르면 직전 선택이 다시 추가돼
  `"결재선에 동일한 사용자가 존재합니다."` 가 뜬다. 한 번에 하나씩, 캡처로 확인하며 진행.
- **그리드는 역순 표시**(맨 위가 마지막 결재자). 순서 조정은 우측 `∧`/`∨`.
- **처리방법은 위치에 따라 자동 재배정된다** — 순번 1=`기안`, 중간=`검토`, 마지막=`결재`.
  드롭다운을 직접 건드릴 필요 없이 **순서만 맞추면 된다.**
  (사람을 추가하면 기안자 행이 `전결` → `기안` 으로 저절로 바뀐다.)

창 기준 좌표(창 1016×699 기준): 사용자 목록 행 1/2/3 `(430, 250/276/301)` ·
`∨∨` 추가 `(590,450)` · `∧∧` 제거 `(632,450)` · 순서 `∨`/`∧` `(916,504)`/`(958,504)` ·
그리드 행 `(250, 577/613/649)` · [확인] `(952,84)` · [닫기] `(988,46)`

#### 10-7. 과제카드

8-2 와 완전히 동일(Nexacro, `chk==1` 인 행을 찾는다). 지정 결과는 `untkID` 가 아니라
HOX XML `/hox/docInfo/taskInfo/taskCard/cardName` 으로 검증한다.

#### 10-8. 첨부 (`btnAttAdd`)

표준 "열기" 대화상자(`#32770`, 제목 `열기`)가 뜬다.
**7단계의 "폴더 찾아보기" 와 달리 파일 이름 편집란이 활성이라 그대로 조작할 수 있다.**

- 파일 이름 편집란: `class=Edit`, **`id=1148`** (ComboBoxEx32 안에 중첩)
- `WM_SETTEXT`(0x000C) 로 **전체 경로를 따옴표로 감싸** 넣는다(공백·괄호 대비)
- [열기] = `PostMessage(dlg, WM_COMMAND, 1, 0)`, [취소] = id 2
- **`GetWindowText` 로는 검증이 안 된다** — 크로스 프로세스 Edit 은 빈 문자열을 돌려준다.
  실제 검증은 `document.getElementById('HSAttach1').getFilesCount()`.
- → `scripts/pick_file.ps1` 이 위 절차를 담고 있다.

**첨부 공개여부 라디오는 기본 미선택이다.** `HSFileBox` 안의
`name="modiAttachOthbcSe1"` (`open` / `not_open`) 중 하나를 명시적으로 고른다.
본문이 부분공개(6호)면 첨부도 `not_open`(비공개)이 일관된다.

#### 10-9. 임시저장 (`savetmpr`)

긴 작업 중간에 **반드시** 해 둔다(세션이 죽어도 임시저장함에 남는다).

- `임시저장 -- 웹 페이지 대화 상자` → 문서명이 제목으로 **자동 입력**됨 → [저장] `(589,84)`
- → 네이티브 `웹 페이지 메시지` "정상적으로 처리되었습니다." → 확인(id=2)

#### 10-10. 결재올림 (`sanctn`) — 비가역, 사용자 승인 후

**결재올림 전 필수 확인 (하나로 끝낸다).** 아래를 주입해 전부 통과하는지 본다.
대외시행인데 `sendMethod` 가 `auto` 가 아니면 자동발송이 꺼진 것이므로,
사용자에게 알리고 **자동발송을 켜거나**(수신자 지정을 다시 하거나 체크박스를 마우스로 클릭)
**결재 완료 후 발송함에서 직접 발송**할 것임을 합의한 뒤 올린다.

```javascript
(function () {
  var out = [], ed = document.getElementById("editor1").contentWindow.document.getElementById("editor1");
  ["수신", "결재제목", "본문", "발신명의", "공개여부"].forEach(function (n) {
    out.push(n + " = " + String(ed.GetFieldText(n)).replace(/\r\n/g, " / "));
  });
  out.push("제목입력란 = " + document.getElementById("Sj").value);
  out.push("과제카드 = " + get_text(domHox1, "/hox/docInfo/taskInfo/taskCard/cardName"));
  out.push("첨부 = " + document.getElementById("HSAttach1").getFilesCount() + "건");
  var x = domHox1.xml;
  out.push("시행종류 = " + (/<enforceType>([^<]*)</.exec(x) || [, "-"])[1]);
  out.push("발송방식 = " + (/<sendMethod>([^<]*)</.exec(x) || [, "-"])[1] + "   ← auto 여야 자동발송");
  window.__r = out.join("\n");
})();
```

기대값: `시행종류 = enforcetype_external` · **`발송방식 = auto`** ·
첨부 건수 일치 · 과제카드·수신·제목이 의도대로. 첨부 공개여부(`modiAttachOthbcSe1`)도
미선택이 아닌지 함께 본다(10-8).

`문서처리 | 업무관리시스템 -- 웹 페이지 대화 상자` 가 뜬다.

- 확인할 것: 처리구분 `결재` / 대국민공개여부 / 공개제한부분 / 직원열람제한 / 공문게시
  (부분공개·비공개면 공문게시 불가) / 의견작성
- **직원열람제한 기본값은 `설정안함`** 이다. 문서등록대장 > 문서정보의 `직원열람제한: 영구`
  표시는 설정값이 아니라 기본 렌더링이므로 그것에 맞추려 하지 말 것(사용자 확인 완료).
- **대화상자가 스크롤되어 [확인] 버튼 좌표가 바뀐다.** 누르기 직전에 반드시 재캡처할 것.
  (스크롤 전 `(706,127)`, 스크롤 후 `(697,90)`)
- [확인] → 네이티브 `웹 페이지 메시지` "정상적으로 처리되었습니다. / 결재완료후 …" →
  확인 **id=2** → **`WXSClient` 창이 자동 종료**된다(정상 완료 신호).

**검증**: 상단 카운터 `문서진행` +1 (좌측 ↻ 로 새로고침) → 문서관리 > 결재 > 문서진행에서
`진행상태 = 진행 (다음 결재자 이름)` 확인.

**상신 후 목록을 정리하는 단계는 없다.** 자동발송이면 상신 → 결재 완료 → 자동발송으로
끝난다. 발송함에서 직접 발송할 일도, 임시저장·진행 목록을 손으로 비울 일도 없다.

#### 10-11. 선례 맞추기 — 먼저 문서등록대장을 본다

같은 계열 공문을 전에 보냈다면 **문서관리 > 문서함 > 문서등록대장**에서 그 문서를 찾아
설정을 그대로 따르는 것이 가장 안전하다. 제목 검색 + 등록일자 범위를 넓히고, 행 체크 후
상단 [문서정보] / [결재경로] 탭을 본다. 여기서 얻는 것:

- 수신 표기 전문(예: `서울특별시교육감(○○담당관)`)
- 시행종류(대외시행/내부결재), 대국민공개여부(예: `부분공개(6)`), 과제카드
- 결재경로 전체(처리방법·직위·처리자)

#### 10-12. 자동저장 복원 — 절반만 복원된다

세션이 끊겨 창을 닫았다가 같은 서식을 다시 열면 **HWP 본문(제목·본문 필드)은 자동
복원**되지만, 결재정보 폼(`Sj` INPUT · 공개여부 라디오 · 과제카드 · 첨부)은 **초기 상태**다.
HWP 필드에 값이 보인다고 폼도 채워진 걸로 착각하지 말고 양쪽 다 검증한다.

## 기술 노트 (시행착오)

- **화면 구조**: Nexacro 셸 + iframe 다층 구조(websocket 브리지, 업무화면 iframe,
  OZ 뷰어 iframe). DOM 조회 시 iframe을 재귀 탐색해야 한다.
- **javascript_tool 비동기 결과**: async IIFE/Promise 반환값은 `{}`로 직렬화된다.
  결과를 `window` 변수에 저장해 두고, 별도 호출에서 `JSON.stringify`로 동기 조회할 것.
- **출력 차단**: 함수 소스나 URL 전체를 반환하면 세션 토큰 감지로 출력이
  "[BLOCKED: Cookie/query string data]"로 대체된다. 경로·불리언·식별자만 정규식으로
  추출해 반환하면 통과한다.
- **네이티브 창 판별법**: `window.open('', '창이름')`으로 이름 조회 시 새 빈 팝업이
  생기면 그 이름의 브라우저 창은 존재하지 않는 것 — 클라이언트 앱 창이라는 방증이다.
- **"네이티브 창 = 제어 불가"로 단정하지 말 것**: 국내 행정 시스템의 클라이언트 앱은
  임베디드 IE 셸인 경우가 많다. 창 클래스가 `#32770` 이고 자식에
  `Shell Embedding > Shell DocObject View > Internet Explorer_Server` 가 보이면
  MSHTML 브리지로 완전 제어할 수 있다. 확인 순서:
  1. `Get-Process <앱명> | Select MainWindowHandle, MainWindowTitle`
  2. UI Automation 으로 컨트롤 트리 덤프 → `Internet Explorer_Server` 리프 확인
  3. `kyul_dom.ps1` 로 DOM 획득 → `document.title` 이 읽히면 성공
- **COM 은 STA 필수**: MTA(PowerShell 7 기본)에서 `ObjectFromLresult` 후 속성 접근이
  조용히 빈 값으로 나온다. `pwsh -STA` 로 별도 실행할 것.
- **COM late binding**: `$doc.title` 직접 접근은 빈 값이 나올 수 있다.
  `$obj.GetType().InvokeMember(name, GetProperty, ...)` 로 명시 호출하면 정상 동작한다.
- **브라우저 쪽 조사 팁**: 목록 화면에서 `doCallClientApp` 을 감싸 호출 인자·예외를
  기록해두면 클릭이 실제로 발동했는지 확인할 수 있다. 함수는 정상 실행되고
  `undefined` 를 반환하며, 네이티브 창은 그 뒤에 뜬다.
- **결재대기 그리드는 iframe 안**이라 `find` 도구가 못 찾는다("해당 텍스트 없음"으로
  실패한다). 행 클릭은 스크린샷 좌표로, 행 내용 추출은 `javascript_tool` 에서
  iframe 을 재귀 순회하며 `tr.innerText` 를 긁는 방식으로 한다.

### Win32 / PowerShell 함정 (v3에서 값비싸게 배운 것)

- **크로스 프로세스로 `WM_USER` 계열 메시지에 문자열 포인터를 보내지 말 것.**
  `BFFM_SETSELECTION`(WM_USER+103)에 경로 문자열을 실어 `SendMessageW` 로 보냈더니
  **결재 창(WXSClient)이 통째로 죽었다.** 시스템이 마샬링해 주는 것은 `WM_SETTEXT` 같은
  **알려진 메시지뿐**이고, 사용자 정의 메시지의 포인터는 남의 주소 공간에서 쓰레기가 된다.
  다른 프로세스 창을 다룰 때 안전한 것: `WM_SETTEXT`, `BM_CLICK`,
  `WM_COMMAND`(wParam=컨트롤ID, lParam=HWND), `WM_CHAR`.
- **"폴더 찾아보기"의 경로 편집란(`id=14148`)은 `WS_DISABLED` 다.** 트리 선택을 비추기만
  하는 필드라 `WM_SETTEXT` · `WM_CHAR` · 실제 클릭 후 Ctrl+V **전부 무효**다. 스타일을
  먼저 확인할 것(`GetWindowLong(GWL_STYLE) & 0x08000000`). 이 창은 이기려 하지 말고
  7단계의 소스 치환으로 **아예 띄우지 않는 것**이 정답이다.
- **PowerShell 은 별칭이 함수보다 우선한다.** 헬퍼를 `SP`/`GP`/`CM` 처럼 두 글자로
  지으면 각각 `Set-ItemProperty`/`Get-ItemProperty`/… 로 잡혀서, COM 속성 설정이
  "경로를 찾을 수 없습니다" 같은 엉뚱한 오류로 실패한다. 게다가 이 오류는 **비종료
  오류라 함수가 성공한 것처럼 계속 진행**한다. `Get-DomProp` 처럼 동사-명사로 지을 것.
- **P/Invoke 는 `EntryPoint=` 를 명시한다.** 같은 API 를 시그니처만 바꿔 여러 번 선언할 때
  메서드 이름만 바꾸면 "Unable to find an entry point named 'SendMessageP'" 가 난다.
  `[DllImport("user32.dll", EntryPoint="SendMessageW")]` 처럼 붙여야 한다.
- **`$PID` 는 읽기 전용 자동 변수다.** `GetWindowThreadProcessId(h, [ref]$pid)` 는
  "Cannot overwrite variable PID" 로 실패한다. `$procId` 등 다른 이름을 쓸 것.
- **대화상자 닫기는 좌표 클릭보다 메시지가 확실하다.**
  `PostMessage(dlg, WM_COMMAND, IDCANCEL(=2), 0)` 로 "폴더 찾아보기"가 깔끔히 닫혔다.
  네이티브 메시지박스(`#32770`)에는 이 방법을 쓴다.
- **다만 MSHTML 대화상자 안의 HTML 버튼·행은 실제 마우스 클릭이 답이다** (v4 정정).
  `SetForegroundWindow` + `SetCursorPos` + `mouse_event` 조합은 **정상 동작한다**
  (`scripts/click_screen.ps1`). v3 에서 "포그라운드 락 때문에 조용히 실패"라고 적은 것은
  대상이 네이티브 컨트롤이었던 특수 사례였다. 좌표는 `capture.ps1` 이미지 좌표를
  그대로 `-X/-Y` 에 넣으면 된다(창 좌상단 기준).
- **캡처는 PrintWindow 우선, 안 되면 화면 복사.**
  `Internet Explorer_TridentDlgFrame` 대화상자는 `PrintWindow(PW_RENDERFULLCONTENT=2)` 로
  **다른 창에 가려져도** 깨끗이 찍힌다. 반대로 `WXSClient` 본 창(`#32770`)은 PrintWindow 가
  **빈 회색 화면**을 주므로 `CopyFromScreen` 폴백이 필요하다(= 가려지면 겹쳐 찍힌다).
  `capture.ps1` 이 빈 화면을 감지해 자동 폴백한다.
- **`Add-Type -ReferencedAssemblies` 를 쓰면 기본 어셈블리 참조가 사라진다.**
  `-ReferencedAssemblies System.Drawing` 만 붙였다가 `List<>` 를 못 찾아 컴파일이 깨졌다.
  C# 쪽에서 Drawing 타입을 안 쓰면 아예 붙이지 말 것.
- **창이 사라졌다고 곧바로 타임아웃으로 단정하지 말 것.** 저장 대화상자가 없어졌을 때는
  (1) 내가 보낸 잘못된 메시지로 앱이 죽었거나 (2) 부모 모달이 `fncClose()` 되며 함께
  닫힌 경우가 많다. `Get-Process WXSClient` 로 **앱 생존부터** 확인한다.

## 일반 원칙

- 여러 조작은 `browser_batch`로 묶어 실행. 클릭 전 최신 스크린샷으로 좌표 확인.
- 인증서 비밀번호·개인 자격증명 입력은 절대 자동화하지 않는다.
- 업무포털 세션 타이머(60분) 유의. 작업 시작 전 좌상단 **[연장]** 을 눌러 둔다.
- **세션이 죽으면 창이 줄줄이 뜬다 — 당황하지 말고 순서대로 정리한다.**
  팝업 내부를 스크립트로 험하게 다루다 서버 세션이 끊긴 사례가 있다. 증상:
  별도 `IEFrame` 창에 "요청하신 서비스가 정상적으로 처리되지 않았습니다 / 사용자 정보를
  불러오지 못하였습니다", 제목이 빈 `-- 웹 페이지 대화 상자`, 이어서 `스크립트 오류`,
  브라우저 탭에는 "접속이 종료되었습니다".
  1. `close_win.ps1 -List` 로 확인 후 군더더기 창을 `WM_CLOSE` 로 모두 닫는다
  2. **브라우저 탭에서 알림 [확인]을 누르면 SSO 로 세션이 되살아나는 경우가 있다**
     (재로그인 불필요 — 실제로 타이머가 40:00 으로 리셋되며 복구됐다)
  3. 문서 창의 입력값은 클라이언트 메모리에 남아 있지만 서버 호출은 전부 실패하므로,
     임시저장도 안 된다. 창을 닫고 10-12 의 자동저장 복원을 전제로 다시 만든다
- 공문·결재 문서 내용이 담긴 스크린샷은 파일로 저장하지 않는다(`save_to_disk` 금지).
- **비가역 조작은 승인 후**: 문서처리·결재올림·삭제·회수는 사용자에게 확인을 받고
  실행하거나 핸드오프한다. 조사 목적이라면 클릭 대신 핸들러 소스를 읽어 판단한다
  (팝업만 여는지, 곧바로 서버 확정인지).
- DOM 조사 결과를 출력할 때 세션 토큰·계정 ID·부서코드가 섞이지 않게 필요한 필드만 뽑는다.
- **이 스킬 문서는 외부 공개를 전제로 한다.** 갱신 시 개인·학교 식별 정보(교사·학생 이름,
  학교명, 문서번호, 기관·계정 실명 등)를 기록하지 않고 일반화해서 쓴다.

## 변경 이력

- v4.1 (2026-08-12): **자동발송 판별법 확립.** 대외시행 공문은 `자동발송` 체크 여부에 따라
  결재 완료와 동시에 발송되느냐, 발송함에서 직접 발송해야 하느냐가 갈린다. 판별은
  **HOX XML `<sendMethod>auto</sendMethod>`** 로 한다 — `recpInfo` innerText 의
  "대외시행 자동발송"은 **체크박스 라벨**이라 상태를 알려주지 않고, 조회 화면에서는 체크박스가
  렌더링되지 않아 "대외시행"만 보인다. `autoSnding_*` hidden 이 비어 있는 것도 무관하다.
  **수신자를 지정하면 자동발송이 기본으로 켜진다**는 것을 이번 문서와 3월 발송 완료 문서의
  `sendMethod` 대조로 확인. 사후 검증은 발송정보 탭의 `수신` 시각 = 최종 결재 시각.
  **10-10 에 "결재올림 전 필수 확인" 스니펫을 넣어** 수신·제목·본문·과제카드·첨부와 함께
  `enforceType`·`sendMethod` 를 한 번에 찍도록 했다(이번에 자동발송을 확인하지 않고 상신해
  사후에 되짚은 것이 계기).
- v4 (2026-08-12): **기안(신규 공문 작성 → 결재올림) 전 과정 정립** — 대외시행 공문 1건을
  실제로 작성해 상신하고 `문서진행 = 진행(다음 결재자)` 까지 확인(10단계 신설).
  기안 창은 결재 창과 같은 `WXSClient` 지만 **창 제목이 서식명**이라 `kyul_dom.ps1` 로는
  못 잡고 `mshtml_dom.ps1` 을 써야 한다는 점, 본문이 **한글(HWP) ActiveX 필드**라
  `PutFieldText("본문", …)` 로 쓰고 제목은 `Sj` + `input_changed()` 로 동기화된다는 점을 기록.
  **가장 큰 교훈: 선택 팝업(수신자지정·결재경로설정) 내부는 스크립트로 조작할 수 없다** —
  `fncAdd()` 가 라디오 체크가 아니라 전역 `selectedID` 와 `Capi` 캐시를 보기 때문이고,
  억지로 밀어붙이다 **세션이 서버에서 끊겼다.** 실제 마우스 클릭(`click_screen.ps1`)과
  창 캡처(`capture.ps1`)로 전환해 한 번에 통과. 수신자는 체크만으로는 안 되고 **`>>` 로
  오른쪽 패널에 옮겨야** 반영되며(오류 없이 조용히 실패), 결재경로 그리드는 **역순 표시**에
  **처리방법이 위치 따라 자동 재배정**된다는 점, 연속 클릭 시 중복 추가 경고가 뜬다는 점을 수록.
  첨부는 표준 "열기" 대화상자의 `Edit id=1148` 에 `WM_SETTEXT` + `WM_COMMAND(1)` 로 성공
  (검증은 `getFilesCount()` — `GetWindowText` 는 크로스 프로세스라 빈 값).
  **주입 스크립트가 동기적으로 모달을 띄우면 `appendChild` 가 막혀 PowerShell 이 멈춘다**는
  함정과 `setTimeout` 래핑 규칙을 개요에 명시. 세션 사망 시 복구 절차, 자동저장이 HWP 본문만
  복원하고 결재정보 폼은 초기화된다는 점, 선례를 문서등록대장에서 확보하는 방법도 추가.
  스크립트 5종 신설: `click_screen.ps1` · `capture.ps1` · `dlg.ps1` · `close_win.ps1` ·
  `pick_file.ps1`. v3 의 "좌표 클릭은 포그라운드 락으로 실패"는 **부분 정정**(MSHTML 대화상자
  내부에는 실제 마우스 클릭이 정상 동작).
- v3.1 (2026-08-12): **과제카드 지정 → 문서처리(접수) 전 과정 정립**(접수 공문 1건 실제
  처리, 문서등록대장 상태 `종료` 확인). 과제카드 팝업이 **Nexacro** 라 DOM 에 목록이 없고
  `nexacro.getApplication()...Tabpage1.form` 으로 접근해야 한다는 점, 확인 버튼이
  `currentrow` 가 아니라 **`chk==1`** 인 행을 찾는다는 점, 지정 결과가 INPUT 이 아니라
  **HOX XML**(`/hox/docInfo/taskInfo/taskCard/cardID`)에 들어가고 `untkID` 는 빈 채로
  남는다는 점을 기록. 문서처리 대화상자의 공개·보안 필드는 공문게시 지정 시에만 노출되므로
  `checked` 가 아니라 `offsetParent` 로 판단해야 한다는 함정, 네이티브 "웹 페이지 메시지"
  확인창의 **버튼 컨트롤 ID 가 창마다 다르다**는 점(confirm 확인=1, 결과 alert 확인=2)을 추가.
  처리 완료 시 결재 창이 자동 종료된다는 것과 세션 [연장] 버튼 위치도 수록.
- v3 (2026-08-12): **본문·첨부 PC저장 정립**(접수 공문 1건 실제 저장). 호출 사슬
  `fncSavePC → docSave → fncVerify → fncMultiVerify → init()` 과 파일저장 대화상자
  옵션 id 표 작성. 결재 창에서 파생되는 대화상자도 MSHTML 이지만 제목·클래스가 달라
  제목 부분일치로 찾는 범용 브리지 `scripts/mshtml_dom.ps1` 를 추가. **폴더 선택 창은
  경로 편집란이 `WS_DISABLED` 라 자동 입력이 불가능**함을 확인하고, `init()` 소스의
  `FileManager.selectFolderEx(...)` 호출부를 경로 리터럴로 치환해 eval 재정의하는
  우회법을 정립(ActiveX 메서드 덮어쓰기는 불가). `applId == '5010'` 접수대기 문서는
  접수처리 전 저장이 막힌다는 분기 확인. 저장된 PDF 의 텍스트 레이어가 깨져 있어
  스크린 리더로 못 읽으므로 렌더링 후 텍스트본을 함께 만든다는 원칙 추가.
  v2 의 "과제카드 지정 UI 없음"은 **오독으로 확인**되어 정정(`aChooseTkcrd`).
  시행착오: 크로스 프로세스 `WM_USER` + 문자열 포인터로 앱 사망, PowerShell 별칭이
  함수보다 우선해 COM 설정이 조용히 실패, P/Invoke `EntryPoint` 누락, `$PID` 읽기 전용,
  폴더 대화상자는 좌표 클릭 대신 `WM_COMMAND`/`IDCANCEL`, 결재대기 그리드가 iframe
  안이라 `find` 도구 실패.
- v2 (2026-08-10): **자동화 경계 정정.** 결재 문서 창(`WXSClient.exe`) 내부가 임베디드
  IE(MSHTML)임을 확인하고, `WM_HTML_GETOBJECT` + `ObjectFromLresult` 로 DOM을 획득하는
  `scripts/kyul_dom.ps1` 브리지를 정립. 문서 제목·전 필드 판독, `<script>` 주입 실행,
  탭 전환 클릭(본문 ↔ 결재정보)까지 실증. 결재 화면 요소 id 표 작성. 편철 = 과제카드
  (`untkID`)이며 지정 UI가 결재정보 탭에 없다는 점, `fncProcessDoc` 이 confirm 한 번으로
  확정되는 비가역 동작이라는 점 확인(미실행). 시행착오: `execScript` 부재,
  MTA에서 COM 속성 조용한 실패(STA 필요), late binding 은 `InvokeMember` 필요,
  UIA 최상위 열거가 가상 데스크톱 전환 시 창 누락, 문서 열기 클릭 반복으로 창 중복 생성.
- v1 (2026-07-06): 업무포털 → K-에듀파인 진입 → 결재대기 확인 → 문서 열기(클라이언트 앱
  핸드오프) → 처리 후 0건 검증까지 실제 결재 1건 처리로 정립. 시행착오: install.html
  리다이렉트·광고 팝업 탭 고착, navigate 거부 우회, 한컴 클라이언트 앱 경계 판별,
  javascript_tool 비동기·출력 차단 대응.
  (v1의 "네이티브 창이라 제어 불가" 판단은 v2에서 **오류로 확인**되어 정정됨.)
