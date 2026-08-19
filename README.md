# school-work-automation

한국 교사의 3대 교육행정 시스템 업무를 코딩 에이전트(Claude Code 등)로 자동화하는 스킬 번들이다: 나이스(NEIS) 복무·성적·외부활동, K-에듀파인 결재·기안, 교데통 데이터취합 제출. 세 스킬 모두 저자가 실제 학교 행정업무에서 반복 사용하며 정립·검증했고, 화면마다 밟은 시행착오(지연 렌더링, 커스텀 드롭다운, 파일 첨부 우회 경로 등)가 그대로 축적돼 있다.

저자는 시각장애인 교사다. 각 스킬에는 스크린 리더 사용자 관점의 확인 절차(스크린샷 대신 JS 검증, 접근성이 나쁜 화면의 현실적 우회)가 함께 기록돼 있다.

## 스킬 구성

| 스킬 | 담당 영역 |
|---|---|
| **나이스-업무자동화** | 업무포털 → 나이스 진입, 근무상황·출장 신청(육아시간·연가 등), 외부강의 신고·현황, 정기고사 일괄채점·문항 통계, 동아리 이수시간·특기사항, 상신함 결재 내역 추출 |
| **K-에듀파인-업무자동화** | 업무포털 → K-에듀파인 진입, 결재대기 공문 처리(과제카드·문서처리), 공문 본문·첨부 PC저장, 신규 기안 작성 → 수신자·결재경로 지정 → 결재올림 |
| **교데통-제출** | 교데통(교육행정데이터통합관리) 데이터취합 접수 → 파일 첨부 → 임시저장 → 내부승인 결재 상신 → 완료 확인 |

## 필요한 것

- **코딩 에이전트 CLI**: Claude Code 등 스킬(SKILL.md)을 인식하는 에이전트.
- **Claude in Chrome** 브라우저 확장(MCP): 세 스킬 모두 브라우저 자동화의 기반이다.
- **Windows + PowerShell 7**: K-에듀파인의 결재·기안 문서 창은 브라우저가 아니라 네이티브 앱(임베디드 IE)이라, 동봉된 PowerShell MSHTML 브리지 스크립트로 제어한다(Windows 전용). 나이스·교데통 스킬은 브라우저 조작만 쓴다.
- **교육행정 전자서명 인증서**: 로그인은 항상 사용자가 직접 수행한다(아래 안전 원칙).

## 적용 범위

서울특별시교육청 환경(`sen.eduptl.kr` · `sen.neis.go.kr` · `klef.sen.go.kr` · `sen.edmgr.kr`)에서 검증했다. 4세대 나이스·K-에듀파인·교데통은 전국 공통 시스템이고 시도별 서브도메인과 세부 화면만 다르므로, 타 시도에서는 도메인을 바꿔 절차 골격을 그대로 적용하되 좌표·화면 차이를 확인하며 진행한다.

## 안전 원칙

세 스킬이 공통으로 지키는 경계다.

- **인증서 비밀번호·자격증명 입력은 절대 자동화하지 않는다.** 로그인은 사용자(교사 본인)가 직접 한다.
- **비가역 조작(상신·문서처리·제출·발송)은 사용자 승인 후에만** 실행한다. 자동화는 폼 채우기·검증까지이고, 확정 버튼 앞에서 요약해 확인받는다.
- **성적·공문 등 민감 화면의 스크린샷을 파일로 저장하지 않는다.**
- **스킬 문서에 개인·학교 식별 정보를 기록하지 않는다.** 교사·학생 이름, 학교명, 문서번호, 계정 등은 일반화해서 갱신한다.

## 설치

```bash
npx skills add Engccer/school-work-automation -g
```

`npx`는 Node.js에 포함돼 있다. 개별 스킬만 쓰고 싶으면 설치 후 필요 없는 스킬 폴더를 지워도 서로 의존하지 않는다(K-에듀파인 스킬이 나이스 스킬의 로그인 단계를 참조하는 문서 링크만 있다).

## 비용

전부 무료·오픈소스(MIT)다. 클라우드 API 과금이 없고, 필요한 것은 코딩 에이전트 자체의 사용 비용뿐이다.

## License

MIT (c) 2026 Engccer

---

## English

**school-work-automation** is a skill bundle that automates the three core administrative systems used by teachers in Korean public schools with a coding agent (Claude Code and similar): **NEIS** (attendance/leave requests, exam grading and item statistics, external-lecture reports, club records), **K-EduFine** (approving incoming official documents, saving document bodies/attachments, drafting and submitting new official documents), and **Kyodetong** (the education-data collection platform: receive, attach, save, and submit through internal approval).

All three skills were built and repeatedly field-tested by the author, a blind teacher, in real school work. They encode hard-won workarounds for these legacy systems: delayed dialog rendering, custom DIV dropdowns that reject `form_input`, calendar-only date fields, iframe file uploaders that need a `DataTransfer` bridge, and an MSHTML PowerShell bridge for K-EduFine's embedded-IE native document windows.

**Requirements:** a coding agent CLI that recognizes skills, the Claude in Chrome browser extension (MCP), Windows + PowerShell 7 (for K-EduFine's native document windows; the NEIS and Kyodetong skills are browser-only), and a Korean education digital certificate — login is always performed by the user, never automated.

**Scope:** verified against the Seoul Metropolitan Office of Education environment (`sen.*` domains). The systems are nationwide; other provinces differ only in subdomains and screen details.

**Safety principles:** credentials are never automated; irreversible actions (submit, approve, dispatch) run only after explicit user confirmation; screenshots of sensitive screens are never saved to disk; skill updates never record personal or school-identifying information.

**Install:**

```bash
npx skills add Engccer/school-work-automation -g
```

**License:** MIT (c) 2026 Engccer
