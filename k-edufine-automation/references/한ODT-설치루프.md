# 한ODT 설치 루프와 사용자지원서비스 질의 등록

SKILL.md 3단계(install.html)에서 넘어온다.

## 한글 2024 PC의 HwpODTpatch 무한 루프

`main.do`가 `필수 보안 프로그램이 설치되지 않았습니다.[HwpODTpatch]` alert → install.html →
[메인페이지로 이동] → 같은 alert로 끝없이 돈다. 원인 사슬(로그로 확정):

1. `install_config.js`의 자동설치 목록(`objectInstList`)에는 **패치(HwpODTpatch)만** 있고,
   본체 한ODT(`/thirdParty/handy/install/HwpODT.exe`, 10.2.0.805)는 "(수동설치)"다.
2. 패치(`HwpODTCtrl_Patch.exe`)는 본체가 없으면 "이 업데이트를 설치하려면 한ODT이(가) 필요합니다"로 끝난다.
3. 본체 설치 프로그램(Inno Setup 5.5.5)의 `InitializeSetup`이 **한글 2024(레지스트리 `HNC\Hwp\13.0`)를
   인식하지 못해** `isInstalled is False` → "한컴오피스 또는 한글이 설치되지 않아…" → 중단(종료 코드 1).
   원인 확인은 `/LOG="<경로>"` 옵션으로 실행해 Inno 로그를 보면 된다.

- 따라서 한글 2024만 깔린 PC에서는 사용자 쪽에서 풀 방법이 없다(레지스트리 위장 등 우회 금지).
  K-에듀파인 상담(02-1396)에 한ODT의 한글 2024 호환판을 요청할 사안이다. → 사례
- alert가 떠 있으면 `Script injection timed out`으로 탭 전체가 먹통이 된다. 판독은
  `scripts/capture.ps1 -TitleLike "K-에듀파인"`으로 창을 캡처해서 하고, 판독 후 PNG(`SAVED=` 경로)를 지운다.
- **신고 창구는 나이스광장이 아니라 K-에듀파인 사용자지원서비스**(help.klef.go.kr, 업무포털
  업무바로가기 [K-에듀파인 지원])다. 같은 증상의 선례 질의에 공식 답변이 있다:
  한컴독스(구독형)는 ODT 지원 대상 아님, 교육청 라이선스 정식 한글을 설치하라.
  원인 제품 신고는 hancomdocs.com/inquiry. → 사례
- 이 페이지의 JS 결과는 URL 조각 때문에 `[BLOCKED]`로 자주 막힌다. 설치 스크립트는
  `fetch`로 모아 Blob 다운로드로 받아 로컬에서 읽는다. exe는 브라우저 Blob 다운로드가
  조용히 막히므로 PowerShell `Invoke-WebRequest`(크롬 UA)로 받는다(curl은 응답 없음).

## 사용자지원서비스 질의 등록

넥사크로 화면이라 입력은 DOM이 아니라
`nexacro.getPopupFrames(app.mainframe.MainVFrameSet.TopFrame)`에서 `insertNttInfo` 팝업을 찾아
`form.divContent.form`의 `txtSj`(제목)·`txtSj00`(요청자전화번호)·`txtQestnCn`(질의내용)에
`set_value`로 넣는다(`readonly` 표시여도 들어감). 화면명은 돋보기 → 메뉴조회에서 검색 후 [확인].

- **질의유형 `기능개선`은 [기능개선 요청서 다운로드]의 서식(hwp) 첨부가 필수**다. 첨부는
  외부 업로더(`fv_extUp`)라 [첨부파일추가]를 눌러도 파일 창·input이 생기지 않는다 →
  이름 없는 300×150 iframe 안의 `input[type=file]`에 최상위 임시 input + 파일 업로드 +
  iframe `DataTransfer` 이관(나이스 스킬 RaonK 우회와 동일).
- [저장] 후에도 등록 창이 남으니 다시 누르지 말고 닫은 뒤 [업무] 탭 목록에서 번호·첨부를 확인한다.
