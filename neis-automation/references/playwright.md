# Playwright · 업무포털 웹 업무의 기본 브라우저

업무포털을 거치는 웹 업무(나이스·K-에듀파인·교데통) 공통. 세 스킬이 이 파일 하나를 참조한다.

## 경로 고르기

**Playwright MCP 서버**(`@playwright/mcp`)가 띄우는 크롬은 인증서 창이 정상으로
뜨고 SSO도 이어진다. 확장 연결이 필요 없고 크롬 프로필의 계정 관리 정책도 받지 않으므로 이것이 기본이다.
별도 크롬 인스턴스라 업무포털 로그인은 그 창에서 새로 한다. 도구가 없으면 사용자에게 에이전트 설정에
Playwright MCP 서버(`npx @playwright/mcp@latest`) 등록을 요청한다.

브라우저 제어 확장(Claude in Chrome에서 검증)은 사용자가 원할 때만 쓴다. 확장에서 주소 이동·탭 목록은 되는데 **클릭·스크린샷·
페이지 JS 실행이 모든 탭에서 `Cannot attach to this target`**이면 대개 크롬 관리 정책이 개발자 도구를
막아 확장이 붙지 못하는 것이다. 크롬 메뉴 ⋮ → 도구 더보기 → 개발자 도구를 열어 "조직에서 이 페이지의
DevTools 사용을 차단했습니다"가 뜨면 확정이다. 탭·크롬 재시작으로는 풀리지 않으니 바로 Playwright로
돌아온다. 다른 크롬 프로필로 바꿔도 PC 단위 정책이면 그대로 막힌다. → 사례

다른 길이 막히는 이유:

- **에이전트 앱의 내장 브라우저**: 인증서 프로그램을 인식하지 못한다
  ("인증서 로그인용 프로그램 설치가 필요합니다" 알림).
- **데스크톱 제어**(computer use): 브라우저는 읽기 전용 등급이라 클릭·타이핑이 막힌다.

## 공통 절차

먼저 [접속 환경 확인](../SKILL.md#접속-환경-확인)을 따른다.

쓰는 도구: `browser_navigate`·`browser_run_code_unsafe`·`browser_evaluate`·`browser_take_screenshot`·
`browser_tabs`·`browser_click`·`browser_handle_dialog`·`browser_file_upload`·`browser_snapshot`·`browser_find`.

1. **로그인**: `browser_navigate` → 확인한 교육청 업무포털 로그인 주소(서울 예: `https://sen.eduptl.kr/bpm_lgn_lg00_001.do`). 공지 팝업은 그대로 두고
   `browser_click`(target `button:has-text("교육행정 전자서명 인증서 로그인")`)으로 인증서 창을 띄운 뒤,
   **사용자에게 "새로 뜬 크롬 창에서 인증서 암호를 입력해 달라"고 요청**한다(암호 입력은 자동화 금지).
   로그인 확인은 `browser_evaluate`로 `document.title === '업무포털 메인'`.
   **클릭이 `element is visible, enabled` 뒤 시간 초과로 끝나면** 보안 프로그램 로딩 오버레이
   (`.isloading-overlay`)가 버튼을 덮고 있는 것이다. 새로고침한 뒤 `run_code`에서 1.5초 간격으로
   그 요소의 `display`가 `none`이 될 때까지 기다렸다가 `#btnLgn`을 누른다. → 사례
   **오버레이가 "보안프로그램이 로딩중입니다"에서 계속 풀리지 않으면 크롬의 로컬 네트워크 접근 허용 창을 의심한다.**
   업무포털이 PC의 보안 프로그램(`127.0.0.1`)에 연결하려 할 때 크롬이 주소창 아래에 허용 여부를 묻는데,
   이 창은 페이지 밖 브라우저 UI라 스냅숏·스크린샷·클릭 어디에도 잡히지 않는다. 새 Playwright 크롬에서
   처음 진입할 때마다 뜰 수 있으니 **로그인 요청 전에 사용자에게 "크롬 창에 접근 허용을 묻는 창이 뜨면
   [허용]을 눌러 달라"고 함께 안내**한다. 허용한 뒤에는 오버레이가 풀려 `#btnLgn` 클릭이 통했다. 같은 차단을 CDP
   `Browser.grantPermissions`로 우회한 사례는 K-에듀파인 쪽에만 있고(K-에듀파인 스킬 `references/공문검색-수집.md`),
   업무포털 로그인 화면에서는 아직 시험하지 않았다. → 사례
2. **업무 시스템 진입**: 상단 메뉴([나이스]·[K-에듀파인]·[교데통])는 새 탭으로 열리므로
   `browser_run_code_unsafe`에서 이벤트 대기와 클릭을 함께 건다.
   ```js
   async (page) => {
     const [p] = await Promise.all([
       page.context().waitForEvent('page', {timeout: 20000}),
       page.locator('a', {hasText: '[나이스]'}).first().click({force: true}),
     ]);
     await p.waitForLoadState('domcontentloaded'); await p.waitForTimeout(6000);
     await p.setViewportSize({width: 1600, height: 950});
     return await p.title();
   }
   ```
   이어서 `browser_tabs`(`select`, 새 탭 index)로 작업 탭을 옮긴다.
   새 탭 대기가 시간 초과되면 업무포털 공지 팝업이 메뉴를 덮고 있는 경우다. 팝업을 닫고 스크린샷으로
   메뉴 위치를 다시 잡아 좌표 클릭과 `waitForEvent('page')`를 함께 건다.
3. **화면 보기**: `browser_take_screenshot`(`scale: "css"`)이나 `run_code` 안의 `page.screenshot`.
   **저장 위치는 작업 폴더의 `.playwright-mcp/`만 허용된다**(스크래치 경로는 거부). 스크린샷 css 좌표가
   곧 클릭 좌표다.
4. **조작**: `run_code`의 `page.mouse.click(x,y)`·`dblclick`과 `page.evaluate`가 가장 잘 듣는다.
   커스텀 DIV 버튼·드롭다운도 실제 마우스 이벤트라 좌표 클릭이 통한다. 동작과 대기·스크린샷을 한
   `run_code`에 묶으면 왕복이 준다. 확인 창처럼 위치가 옮겨지는 요소는 `page.evaluate`로
   `.cl-text` 등의 `getBoundingClientRect()` 중심을 구해 그 좌표를 누른다(환산 비율 불필요).
5. **텍스트 입력**: 칸을 더블클릭 → `document.activeElement.tagName`이 `TEXTAREA`/`INPUT`인지 확인 →
   `page.keyboard.insertText(원고)` → `activeElement.value === 원고` 대조. 한글이 한 번에 정확히 들어가
   CDP 타이핑의 글자 깨짐이 없다.
6. **브라우저 대화상자(alert·confirm)**: `run_code` 안에서 뜬 대화상자는 처리하지 않으면 자동으로
   닫힌다(confirm은 취소로). 확인이 필요한 confirm은 `page.once('dialog', d => d.accept())`를 클릭 전에
   걸거나, 개별 도구 호출이면 `browser_handle_dialog`로 답한다.
7. **파일 첨부**: 페이지에 `input[type=file]`이 미리 있으면 `setInputFiles`로 바로 넣는다. iframe 안
   업로더도 `page.frameLocator('iframe[src*="..."]').locator('input[type=file]').setInputFiles(경로)`로
   닿으므로 브라우저 제어 확장에서 쓰던 임시 input·`DataTransfer` 다리가 필요 없다(미실측, 처음 쓸 때 화면
   표시로 검증).
   **파일 선택 창**: 버튼을 눌러야 창이 뜨는 업로더(나이스 일괄파일업로드 등)는 다르다. 창이 뜨는
   순간 **MCP가 그것을 가로채 `[File chooser]` 대기 상태**로 바꾼다. `run_code` 안에서
   `waitForEvent('filechooser')` + `setFiles`를 걸어도 효과가 없고, `run_code`는 그 자리에서 결과를
   돌려주지만 **남은 코드는 뒤에서 계속 돈다**. 이 상태에서는 `browser_evaluate`도 거부된다.
   그러니 여러 파일을 반복문 하나로 올리지 않는다. → 사례
   1. 창을 띄우는 클릭까지만 한 `run_code`에 넣는다.
   2. `browser_file_upload`로 파일 **하나**를 넣는다.
   3. 별도 호출로 미리보기를 대조하고 저장한다. 다음 파일은 1부터 되풀이한다.
   잘못 뜬 창은 `browser_file_upload`를 경로 없이 불러 취소한다.
   **다운로드**: 클릭 전에 `page.waitForEvent('download')`를 걸고 `download.saveAs(경로)`로 옮긴다.
   `saveAs`를 해도 `.playwright-mcp/`에 `download-*.확장자` 사본이 하나 더 남는다(8번 정리 대상).
   `run_code`에서는 `require`를 쓸 수 없어 로컬 파일을 읽지 못한다. 대조할 기대값은 코드 안에 넣거나
   대조 자체를 스크립트 밖(Python 등)에서 한다.
   **저장은 한 `run_code`로 끝까지 묶을 수 있다**: `.cl-text`가 `저장`인 요소 중심 클릭 →
   `저장하시겠습니까` 문구가 보일 때까지 1초 간격 대기 → `확인` 중심 클릭 → `완료` 문구 대기 →
   알림 `확인` → [조회] 재실행 → `document.body.innerText`에서 그 행의 Byte·본문 확인.
   교과 세특·과목별독서활동에서 이 묶음 그대로 통했다.
8. **정리**: `.playwright-mcp/`에는 학생·교직원 이름과 개인정보가 찍힌 스크린샷·화면 스냅숏(`page-*.yml`)·
   콘솔 로그·다운로드 사본이 쌓인다. 작업 폴더가 동기화 폴더 안이면 그대로 동기화되므로
   **작업이 끝나면 폴더째 지운다**(드라이브의 `desktop.ini`는 남겨도 된다). Playwright 크롬 창은 업무포털 세션이 살아 있으니 사용자에게
   닫아도 된다고 알린다.

## 업무 파일의 도구 이름 바꿔 읽기

스킬 본문과 업무 파일의 도구 이름은 확장 기준이다. Playwright 경로에서는 아래처럼 바꿔 읽는다.
Playwright로 끝까지 검증한 업무는 교과 세특·과목별독서활동·수행평가 일괄업로드이고, 나머지는 처음 쓸 때 화면으로 확인한다.

| 업무 파일의 표현 | Playwright |
|---|---|
| 주소 이동 | `browser_navigate` |
| 스크린샷, 확대 캡처 | `browser_take_screenshot`(`scale: "css"`), 확대는 같은 도구에 `target`(요소 ref·선택자)을 준다 |
| 좌표 클릭·더블클릭·드래그, 키 입력, `type` | `run_code`의 `page.mouse.*`·`page.keyboard.press`·`page.keyboard.insertText` |
| 페이지 JS 실행 | `browser_evaluate` 또는 `run_code`의 `page.evaluate` |
| 요소 찾기 | `browser_find`(문구로 ref를 찾는다) |
| 접근성 트리 읽기의 ref | `browser_snapshot`의 ref 또는 `page.locator(...)`(iframe 안은 `frameLocator`로 닿는다) |
| 폼 값 설정 | `browser_fill_form`·`browser_select_option`(DIV 드롭다운에는 둘 다 안 통한다) |
| 탭 목록 조회, 새 탭 ID | `browser_tabs` |
| 일괄 실행 | `run_code` 하나에 묶는다 |
| 파일 업로드, 임시 input 다리 | `setInputFiles`, 파일 선택 창이면 `browser_file_upload`(공통 절차 7) |
| 창 크기 조정 | `page.setViewportSize` |
| 페이지 텍스트 추출 | `page.evaluate(() => document.body.innerText)` |

스크린샷이 css 픽셀이라 「좌표 환산」의 비율은 1이다. 키 이름은 Playwright 표기로 바꾼다(`ctrl+a` →
`Control+A`, `Return` → `Enter`). 업무 파일의 JS 조각은 문장 그대로라 `browser_evaluate`에는
`() => { ... }`로 감싸 넘기고, Promise를 기다려 주므로 결과를 `window` 변수에 담아 두는 우회는 필요 없다.

## 미확인 영역

- **K-에듀파인 결재·기안 문서 창**(`WXSClient.exe`)은 브라우저가 `doCallClientApp`으로 띄우는 네이티브
  앱이다. Playwright 크롬에서 눌렀을 때 외부 프로그램 실행 확인 창이 뜨는지, 창이 정상으로 뜨는지는
  아직 모른다. 창이 뜬 뒤의 MSHTML 브리지·실제 마우스 클릭 절차는 브라우저와 무관하게 같다.
- **PC 단위 관리 정책**: 개인 계정 프로필에서도 확장이 막힌 PC에서 Playwright는 나이스까지 열렸다.
  그 PC의 정책 종류는 확인하지 못했으니, Playwright 크롬이 뜨지 않거나 조작이 거부되면 사용자에게 알린다.
