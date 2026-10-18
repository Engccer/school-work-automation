# Playwright — 업무포털 웹 업무의 기본 브라우저

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

쓰는 도구: `browser_navigate`·`browser_run_code_unsafe`·`browser_evaluate`·`browser_take_screenshot`·
`browser_tabs`·`browser_click`·`browser_handle_dialog`·`browser_file_upload`·`browser_snapshot`·`browser_find`.

1. **로그인**: `browser_navigate` → `https://sen.eduptl.kr/bpm_lgn_lg00_001.do`. 공지 팝업은 그대로 두고
   `browser_click`(target `button:has-text("교육행정 전자서명 인증서 로그인")`)으로 인증서 창을 띄운 뒤,
   **사용자에게 "새로 뜬 크롬 창에서 인증서 암호를 입력해 달라"고 요청**한다(암호 입력은 자동화 금지).
   로그인 확인은 `browser_evaluate`로 `document.title === '업무포털 메인'`.
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
7. **파일 첨부**: 네이티브 "열기" 창을 띄우지 말고 `setInputFiles`로 input에 바로 넣는다. iframe 안
   업로더도 `page.frameLocator('iframe[src*="..."]').locator('input[type=file]').setInputFiles(경로)`로
   닿으므로 브라우저 제어 확장에서 쓰던 임시 input·`DataTransfer` 다리가 필요 없다(미실측, 처음 쓸 때 화면
   표시로 검증).
   **저장은 한 `run_code`로 끝까지 묶을 수 있다**: `.cl-text`가 `저장`인 요소 중심 클릭 →
   `저장하시겠습니까` 문구가 보일 때까지 1초 간격 대기 → `확인` 중심 클릭 → `완료` 문구 대기 →
   알림 `확인` → [조회] 재실행 → `document.body.innerText`에서 그 행의 Byte·본문 확인.
   교과 세특·과목별독서활동에서 이 묶음 그대로 통했다.
8. **정리**: `.playwright-mcp/`에는 학생·교직원 이름과 개인정보가 찍힌 스크린샷이 쌓인다.
   **작업이 끝나면 폴더째 지운다.** Playwright 크롬 창은 업무포털 세션이 살아 있으니 사용자에게
   닫아도 된다고 알린다.

## 업무 파일의 도구 이름 바꿔 읽기

스킬 본문과 업무 파일의 도구 이름은 확장 기준이다. Playwright 경로에서는 아래처럼 바꿔 읽는다.
Playwright로 끝까지 검증한 업무는 교과 세특·과목별독서활동이고, 나머지는 처음 쓸 때 화면으로 확인한다.

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
| 파일 업로드, 임시 input 다리 | `setInputFiles`(공통 절차 7) |
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
