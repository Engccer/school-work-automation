# school-work-automation

한국 교사의 교육행정 시스템 업무를 코딩 에이전트(Claude Code 등)로 자동화하는 스킬 번들이다: 나이스(NEIS) 복무·성적·급여·증명, K-에듀파인 결재·기안, 교데통 데이터취합 제출, 교내 메신저 쿨메신저 회신·첨부 수합, 교직원 알림장(알림장관리 3.0) 전달사항 정리. 다섯 스킬 모두 저자가 실제 학교 행정업무에서 반복 사용하며 정립·검증했고, 화면마다 밟은 시행착오(지연 렌더링, 커스텀 드롭다운, 파일 첨부 우회 경로 등)가 그대로 축적돼 있다.

저자는 시각장애인 교사다. 각 스킬에는 스크린 리더 사용자 관점의 확인 절차(스크린샷 대신 JS 검증, 접근성이 나쁜 화면의 현실적 우회)가 함께 기록돼 있다.

## 스킬 구성

| 스킬 | 담당 영역 |
|---|---|
| **neis-automation** (나이스) | 업무포털 → 나이스 진입, EVPN 원격 접속, 근무상황·출장 신청(육아시간·연가·조퇴 등), 외부강의 신고·현황, 정기고사 일괄채점·문항 통계, 학기 시작 선행작업(성취기준·수행평가영역·반영비율), 동아리 이수시간·특기사항, 학교생활기록부 독서활동상황·교과 세특 화면 입력, 급여명세서 내려받기·CSV 검산, 재직증명서 등 교육제증명 발급(정부24), 나이스광장 질의등록, 상신함 결재 내역 추출 |
| **k-edufine-automation** (K-에듀파인) | 업무포털 → K-에듀파인 진입, 결재대기 공문 처리(과제카드·문서처리), 공문 본문·첨부 PC저장(ODT 텍스트 추출), 신규 기안 작성 → 수신자·결재경로 지정 → 결재올림(대외시행·내부결재), 문서등록대장 선례 조회, 완료 문서 공개구분 수정, 사용자지원서비스 질의등록 |
| **kyodetong-submit** (교데통) | 교데통(교육행정데이터통합관리) 데이터취합 접수 → 파일 첨부 → 임시저장 → 내부승인 결재 상신 또는 K-에듀파인 전자결재 연계기안 → 완료 확인, 제출취소·회수 |
| **coolmessenger-automation** (쿨메신저) | 교내 메신저 쿨메신저(CoolMessenger Gentoo)의 받은·보낸 메시지를 로컬 SQLite DB에서 직접 읽어 회신 수합·미회신자 파악, 받은 메시지 첨부파일 내려받기, 회신 창 채우기(발송은 사용자 확인 후). 브라우저가 아니라 PowerShell Win32 창 조작 |
| **alimjang-automation** (알림장) | 교직원 공용 알림장관리 3.0의 날짜별·부서별 전달사항을 학교 서버 공유 DB(FoxPro DBF)에서 읽기 전용으로 꺼내 날짜 폴더에 텍스트로 정리, 첨부 수집·텍스트 추출·요약, 키워드·부서·기간·지난 학년도 검색, 평일 아침 자동 정리(작업 스케줄러) |
| **school-work-setup** (설치 점검) | 위 다섯 스킬의 실행 요구사항(PowerShell 7·Python 패키지·인증서 프로그램·인증서 만료·JDK·`pdftotext`·브라우저 제어 확장 연결 등)을 읽기 전용으로 점검해 스킬마다 "바로 사용 가능 / 빠진 것"을 보고 |

K-에듀파인·쿨메신저·알림장 스크립트에는 실제 업무 시스템·앱을 건드리지 않는 시험이 각 스킬의 `scripts/tests/`에 들어 있다.

## 필요한 것

- **코딩 에이전트 CLI**: Claude Code 등 스킬(SKILL.md)을 인식하는 에이전트.
- **브라우저 제어 확장**(Claude in Chrome에서 검증): 나이스·K-에듀파인·교데통 세 스킬의 기반이다. 페이지 JS 실행, 접근성 트리 읽기, 좌표 클릭, 화면 캡처, 파일 업로드를 할 수 있어야 한다. 쿨메신저·알림장 스킬은 브라우저를 쓰지 않는다.
- **Windows + PowerShell 7**: K-에듀파인의 결재·기안 문서 창은 브라우저가 아니라 네이티브 앱(임베디드 IE)이라, 동봉된 PowerShell MSHTML 브리지 스크립트로 제어한다. 쿨메신저 스킬도 Win32 메시지·마우스 클릭으로 창을 조작하고, 알림장 스킬은 학교 서버 공유 폴더(UNC)와 작업 스케줄러를 쓴다(셋 다 Windows 전용). 나이스·교데통 스킬은 브라우저 조작만 쓴다.
- **Python 3**: 나이스 급여명세서 CSV 변환(`openpyxl`), 쿨메신저 DB 내보내기(표준 라이브러리만), 알림장 DB 읽기(`dbfread`)와 첨부 추출에 쓴다. 알림장 첨부 추출은 [hwpx-automation](https://github.com/Engccer/hwpx-automation) 스킬(`hwpx-tomd`, HWP 변환에 JDK 21)과 `pdftotext`도 필요하다.
- **교육행정 전자서명 인증서**: 로그인은 항상 사용자가 직접 수행한다(아래 안전 원칙).

## 적용 범위

서울특별시교육청 환경(`sen.eduptl.kr` · `sen.neis.go.kr` · `klef.sen.go.kr` · `sen.edmgr.kr` · `evpn.sen.go.kr`)에서 검증했다. 4세대 나이스·K-에듀파인·교데통은 전국 공통 시스템이고 시도별 서브도메인과 세부 화면만 다르므로, 타 시도에서는 도메인을 바꿔 절차 골격을 그대로 적용하되 좌표·화면 차이를 확인하며 진행한다. 쿨메신저는 학교가 도입한 메신저 제품이라 교육청과 무관하며, Gentoo 버전 클라이언트에서 검증했다. 알림장관리 3.0도 학교가 쓰는 교내 프로그램이라 교육청과 무관하다.

## 안전 원칙

다섯 스킬이 공통으로 지키는 경계다.

- **인증서 비밀번호·자격증명 입력은 절대 자동화하지 않는다.** 로그인은 사용자(교사 본인)가 직접 한다.
- **공유 서버 DB(알림장)에는 직접 쓰지 않는다.** 읽기는 임시 사본에서 하고, 쓰기는 앱 화면으로만 한다.
- **비가역 조작(상신·문서처리·제출·메시지 발송)은 사용자 승인 후에만** 실행한다. 자동화는 폼 채우기·검증까지이고, 확정 버튼 앞에서 요약해 확인받는다.
- **성적·공문 등 민감 화면의 스크린샷을 파일로 저장하지 않는다.**
- **스킬 문서에 개인·학교 식별 정보를 기록하지 않는다.** 교사·학생 이름, 학교명, 문서번호, 계정 등은 일반화해서 갱신한다.

## 설치

```bash
npx skills add Engccer/school-work-automation -g
```

설치 뒤 에이전트에게 "학교 업무 자동화 스킬 쓸 준비 됐는지 봐 줘"라고 하면 school-work-setup이 요구사항을 점검한다. `npx`는 Node.js에 포함돼 있다. 개별 스킬만 쓰고 싶으면 설치 후 필요 없는 스킬 폴더를 지워도 서로 의존하지 않는다(K-에듀파인·교데통 스킬이 나이스 스킬의 로그인 단계를 참조하고, 교데통 전자결재 연계기안은 K-에듀파인 스킬 문서를 참조한다). 알림장 스킬의 첨부 추출은 별도 저장소의 hwpx-automation 스킬을 같은 스킬 폴더에 설치해 쓴다.

```bash
npx skills add Engccer/hwpx-automation -g
```

## 비용

전부 무료·오픈소스(MIT)다. 클라우드 API 과금이 없고, 필요한 것은 코딩 에이전트 자체의 사용 비용뿐이다.

## License

MIT (c) 2026 Engccer

---

## English

**school-work-automation** is a skill bundle that automates the administrative systems used by teachers in Korean public schools with a coding agent (Claude Code and similar): **NEIS** (attendance/leave requests, exam grading and item statistics, external-lecture reports, club, reading, and subject-comment records, payslip download with CSV reconciliation, employment certificates via Gov24), **K-EduFine** (approving incoming official documents, saving document bodies/attachments, drafting and submitting new official documents for external dispatch or internal approval, changing the public-disclosure status of completed documents), **Kyodetong** (the education-data collection platform: receive, attach, save, and submit through internal approval or K-EduFine e-approval), **CoolMessenger** (the in-school messenger: read replies straight from its local SQLite store, download attachments from received messages, and pre-fill replies; sending is left to the user), and **Alimjang** (the staff notice-board program "알림장관리 3.0": read daily department announcements read-only from the school server's FoxPro DBF share, collect and summarize attachments, search past years, and run a weekday-morning digest via Task Scheduler).

All five skills were built and repeatedly field-tested by the author, a blind teacher, in real school work. They encode hard-won workarounds for these legacy systems: delayed dialog rendering, custom DIV dropdowns that reject direct form-value setting, calendar-only date fields, iframe file uploaders that need a `DataTransfer` bridge, and an MSHTML PowerShell bridge for K-EduFine's embedded-IE native document windows.

**Requirements:** a coding agent CLI that recognizes skills, a browser-control extension for the three web systems (verified with Claude in Chrome), Windows + PowerShell 7 (K-EduFine's native document windows and CoolMessenger's Win32 windows; the NEIS and Kyodetong skills are browser-only), Python 3 for the helper scripts, and a Korean education digital certificate — login is always performed by the user, never automated.

**Scope:** verified against the Seoul Metropolitan Office of Education environment (`sen.*` domains). The systems are nationwide; other provinces differ only in subdomains and screen details. CoolMessenger is a school-licensed product independent of the education office (verified on the Gentoo client), as is the Alimjang notice-board program.

**Safety principles:** credentials are never automated; irreversible actions (submit, approve, dispatch) run only after explicit user confirmation; screenshots of sensitive screens are never saved to disk; skill updates never record personal or school-identifying information.

**Install:**

```bash
npx skills add Engccer/school-work-automation -g
```

After installing, the **school-work-setup** skill checks the requirements read-only and reports, per skill, what is ready and what is missing.

**License:** MIT (c) 2026 Engccer
