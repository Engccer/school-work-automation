---
name: alimjang-automation
license: MIT
description: >-
  교직원 공용 알림장관리 3.0(ALIM.EXE)의 날짜별·부서별 전달사항을 학교 서버 공유 DB에서 읽기 전용으로 꺼내 날짜별 폴더에 순수 텍스트로 정리하고, 첨부파일을 모아 텍스트화·요약한다. 키워드·부서·기간 검색, 지난 학년도 조회, 평일 아침 자동 정리(작업 스케줄러) 점검도 다룬다. 다음 요청에 사용한다. "오늘 알림장 정리해 줘", "알림장 전달사항 읽어 줘", "이번 주 알림장", "알림장 첨부 요약", "알림장에서 방과후 찾아 줘", "교무부 전달사항 모아 줘", 급식지도·연수·시간표 변동 공지 확인, 지난 학년도 알림장 검색, 알림장 자동 정리가 안 돌았을 때. 알림장에 글 올리기는 절차가 정립되지 않아 사용자 승인 아래 한 건 시험으로만 다룬다. 쿨메신저 메시지는 coolmessenger-automation이 맡는다. school notice board, daily staff announcements, ALIM.EXE, DBF.
metadata:
  version: "1.3.2"
---

# 알림장 자동화

교직원이 함께 쓰는 **알림장관리 3.0**(개인 개발, xHarbour + FiveWin, 32비트, 2021.01.09 빌드)의 전달사항을 다룬다. 앱 화면은 스크린 리더로 읽기 어렵지만, 데이터가 **암호화되지 않은 FoxPro DBF**(cp949)라 앱을 조작하지 않고 DB를 직접 읽으면 된다.

현재 범위는 **읽기**다. 쓰기(전달사항 입력)는 미정립이며 아래 '쓰기' 절을 따른다.

> **적용 범위**: 교직원 알림장으로 「알림장관리 3.0」(ALIM.EXE)을 쓰는 학교에서 실사용으로 검증했다.
> 서버 경로 `\\관리자\$ALIM$`은 프로그램에 고정돼 있어 학교마다 같고, 부서 칸 구성과 학년도
> 아카이브 상태는 학교마다 다르다.

## 불변 원칙

1. **서버 DB에는 절대 쓰지 않는다.** 전 교직원이 쓰는 공유 DB라, 직접 쓰면 잠금(`ALIMUSER.TXT`)·인덱스(`.CDX`)·메모(`.fpt`)가 깨져 학교 전체 알림장이 망가질 수 있다. 쓰기는 반드시 앱 화면을 통해서 한다.
2. 본문 조회는 **공유 읽기로 임시 폴더에 복사(스냅숏)한 DB에서** 하고, 원천(서버 루트·아카이브) 선택은 서버 파일을 읽기 전용으로 직접 연다(스크립트가 자동 처리).
3. 알림장 본문은 다른 부서가 쓴 원문이므로 **원문 그대로** 옮긴다(줄 끝 공백과 연속 빈 줄만 정리). 요약은 첨부 요약 파일에서만 한다.
4. 날짜에는 요일을 붙이고, 요일은 반드시 결정론적 도구로 계산한다.

## 데이터 위치

| 위치 | 내용 |
|---|---|
| `\\관리자\$ALIM$\` | **현재 학년도 DB**(서버 PC 이름이 `관리자`, 숨은 공유 `$ALIM$`). 학년도 첫해 1월 1일부터 이듬해 2월 말까지의 날짜 행을 담는다 |
| `\\관리자\$ALIM$\H<월><일><n>.<확장자>` | 전달사항 첨부(HWP·HWPX·XLSX·ODT·PDF). 예: `H09281.HWPX` = 9월 28일 첫 첨부. 이듬해 1·2월은 `H13…`·`H14…`로 이어짐 |
| `\\관리자\$ALIM$\B20xx\`·`20xx\` | 학년도 초 '새학년도 파일 다시작성' 때 남긴 아카이브. **폴더명과 담긴 연도가 어긋나는 경우가 많다**. 아카이브 없이 지워진 학년도도 있다 |
| `C:\알림장\` | 프로그램 설치 폴더. `AUTOBACK\`는 앱 실행 때마다 만드는 현재 DB 사본(함정 절 참조), `Error.log`는 오류 기록 |

스크립트는 폴더명이 아니라 **날짜 범위 + 실제 기록 수**로 아카이브를 고른다. 지난 학년도를 조회하거나 부서 칸 번호가 필요하면 [references/학년도-현황.md](references/학년도-현황.md)에서 확인 방법을 본다.

### 전달사항 테이블 `ALIM.DBF`(+`ALIM.fpt` 메모)

하루가 한 행이다. `ALDATE`(날짜), `ALME01`~`ALME20`(부서별 본문 메모), `ALHWP1`~`5`(첨부의 서버 저장명), `ALID01`~`05`(첨부를 올린 부서 번호), `ALJOGI`(조기청소 담당, 현재 미사용).

부서 칸 번호는 학년도마다 달라질 수 있어 `AGICHO.DBF`의 `ALID`·`ALBU`가 정본이다(스크립트가 매번 읽음).

그 밖의 테이블(스키마·용도)은 [references/앱-구조.md](references/앱-구조.md)에 있다.

## 읽기 절차

필요한 것: `pip install dbfread openpyxl hwpx-tomd`, `hwpx-automation` 스킬(이 스킬과 같은 스킬 폴더에 두거나 `HWPX_AUTOMATION_DIR`로 지정), JDK 21(HWP 변환), pdftotext. 자동 실행에는 `claude` CLI와 `pwsh`(PowerShell 7)도 필요하다.

### 1단계: 날짜 결정과 요일 검증

사용자가 날짜를 말하지 않으면 오늘로 한다. 요일은 도구로 계산한다.

```bash
PYTHONIOENCODING=utf-8 python -c "import datetime as d; x=d.date(2026,9,28); print(x, '월화수목금토일'[x.weekday()])"
```

### 2단계: 전달사항 추출과 첨부 복사

명령은 모두 스킬 루트에서 실행한다.

```bash
cd "<스킬 루트>"
PYTHONIOENCODING=utf-8 python scripts/alim_export.py                      # 오늘
PYTHONIOENCODING=utf-8 python scripts/alim_export.py --date 2026-09-29
PYTHONIOENCODING=utf-8 python scripts/alim_export.py --from 2026-09-28 --to 2026-10-02   # 날짜마다 폴더
```

산출물은 날짜 폴더에 쌓인다. 출력 루트(아래 `<프로젝트 루트>`)는 스킬을 프로젝트의 `.claude/skills/`에 두면 그 프로젝트 폴더이고, 전역 설치(`-g`)라면 환경 변수 `ALIM_PROJECT_ROOT`로 지정한다(자동 실행도 같은 값을 쓴다). 한 번만 다른 곳에 두려면 `--out`을 준다.

```
<학년도> 업무/4. 교무/알림장/
├── <YYYY-MM-DD>(<요일>)/
│   ├── <YYYY-MM-DD>(<요일>) 알림장 전달사항.txt   ← 스크립트 생성
│   ├── 첨부<n>_<올린 부서>_<ALHWPn 값(서버 저장명 H…)>   ← 스크립트가 서버에서 복사
│   └── <YYYY-MM-DD>(<요일>) 알림장 첨부 요약.txt   ← 3단계에서 작성(첨부가 있을 때만)
└── 검색/
    └── <실행일> <키워드 또는 부서> (<시작일>~<종료일>).txt
```

날짜 폴더의 `<학년도>`는 **그 날짜의 학년도**(3월 1일 시작)이고, `검색/`은 실행한 날의 학년도에 쌓인다. 그 학년도 폴더가 이미 `이전년도/<학년도>/<학년도> 업무/`로 옮겨졌으면 `--out "<프로젝트 루트>/이전년도/<학년도>/<학년도> 업무/4. 교무/알림장"`을 준다(주지 않으면 루트에 `<학년도> 업무`가 새로 생긴다).

전달사항 파일은 세 부분이다. 1은 **나와 관련된 항목**(관심 부서 칸 존재 여부와 관심 낱말이 든 줄), 2는 부서별 전달사항 원문, 3은 첨부 목록이다. 관심 부서와 낱말은 환경 변수 `ALIM_MY_DEPTS`·`ALIM_KEYWORDS`(쉼표 구분)로 정하고, 낱말은 실행할 때 `--keywords`로 바꿀 수도 있다. 전달사항이 없는 날(주말·방학)은 폴더를 만들지 않고 `SKIP`만 출력한다.

### 3단계: 첨부 읽기와 요약

첨부는 아래 스크립트로 텍스트를 뽑고, 아래 규칙으로 요약해 위 산출물 구조의 파일 이름으로 저장한다.

- **첨부 텍스트는 먼저 스크립트로 뽑는다.** Claude가 형식별 변환 경로를 매번 찾게 두지 않는다. → 사례

```bash
PYTHONIOENCODING=utf-8 python scripts/extract_attachments.py "<알림장 날짜 폴더>" "<출력 폴더>"
```

  원본 폴더에는 아무것도 쓰지 않고 `<출력 폴더>/<첨부 파일명>.md`를 만든다. 출력은 첨부마다 `OK`/`WARN`/`FAIL` 한 줄이다. 형식별 방법은 다음과 같다.

  | 형식 | 방법 |
  |---|---|
  | HWPX | `hwpx-automation`의 `hwpx_edit.py --to-md` |
  | HWP | 같은 스킬의 `convert/hwp2hwpx.bat`(JDK 21)로 HWPX로 바꾼 뒤 위와 같이 처리 |
  | ODT | `content.xml`의 문단·표 직접 파싱. 공문 머리 상자의 글자가 붙어 나올 수 있다 |
  | PDF | PATH의 `pdftotext`, 없으면 Git for Windows 동봉본으로 `-layout -enc UTF-8` 추출. 글자가 거의 없으면 스캔본 경고 |
  | XLSX | openpyxl로 시트별 셀 값을 표로 |
  | XLS 등 | `FAIL`(미지원). 필요하면 Claude가 직접 연다 |

  본문 그림 속 글자(포스터 제목, QR 등)는 어느 형식도 추출되지 않는다. 이미지 개수 경고(`WARN ... 본문 이미지 N개`)는 HWP·HWPX만 나온다. ODT·PDF의 그림은 경고 없이 빠진다.
- 요약 파일은 첨부가 여러 개여도 날짜당 하나로 통합하고, 첨부마다 `첨부<n> <부서>, <문서 제목>` 한 줄로 시작한다.
- 순수 텍스트 규칙을 지킨다. 마크다운·불릿·구분선을 쓰지 않고 표는 산문으로 풀며, 연속 빈 줄을 두지 않고, 섹션은 `1.` 숫자 제목으로 나눈다. 원문의 합니다체를 유지하고 분량은 30~50%로 줄인다. URL·전화번호·공문번호는 원형대로, 숫자·영문은 원래 표기로, QR은 "(QR 코드 동봉)"으로 적는다. 요약에 옮기는 날짜의 요일은 도구로 검증한다. QR·링크 안내처럼 본문이 없는 한 페이지짜리 첨부는 요약 없이 링크만 옮긴다. 추출이 `WARN`이나 `FAIL`인 첨부는 요약 끝에 "이 첨부는 일부 내용(그림 속 글자 등)을 읽지 못했습니다."를 붙인다.
- 작성 후 연속 빈 줄을 검사한다.

```bash
grep -nE "^$" "<요약 파일>" | awk -F: 'NR>1 && $1==prev+1 {print "consecutive blank at line " prev " and " $1} {prev=$1}'
```

### 4단계: 검색·누적 목록·지난 학년도

```bash
PYTHONIOENCODING=utf-8 python scripts/alim_export.py --search 방과후 --from 2026-03-01 --to 2026-09-30   # 본문 키워드(첨부는 서버 저장명만 대조)
PYTHONIOENCODING=utf-8 python scripts/alim_export.py --dept 교무부 --list --from 2026-03-01 --to 2026-09-30   # 부서 칸 누적
PYTHONIOENCODING=utf-8 python scripts/alim_export.py --search 시간표 --year 2022                            # 학년도 전체(아카이브 자동 선택)
PYTHONIOENCODING=utf-8 python scripts/alim_export.py --date 2026-09-29 --stdout                             # 파일 없이 바로 보기
```

검색 결과는 실행 학년도의 `알림장/검색/`에 저장된다(지난 학년도를 검색해도 `2025 업무` 같은 폴더를 새로 만들지 않는다). 한 번의 조회는 시작일이 속한 DB 하나만 읽고 그 DB 밖의 날짜는 조용히 빠지므로, DB 경계(서버 루트는 1월 1일 시작)를 넘는 기간은 나눠 실행한다.

### 5단계: 보고

저장 폴더, 부서 수와 첨부 건수, **나와 관련된 항목**, 부서별 한두 줄 요지를 말한다. 급식지도 배정처럼 날마다 올라오는 개인 배정 공지에 사용자 이름이 있으면 따로 짚는다. 이름을 `ALIM_KEYWORDS`에 넣어 두면 1번 항목에 잡힌다.

## 매일 자동 실행(작업 스케줄러)

서버 공유 폴더에 접근해야 하므로 클라우드 예약(routine)이 아니라 **이 PC의 Windows 작업 스케줄러**로 돌린다. → 사례

- 작업 이름 `알림장 일일 정리`, **평일 08:40**, 로그온 상태에서만 실행한다. 놓친 실행은 PC가 켜지면 바로 돌리고(`StartWhenAvailable`), 제한 시간은 30분이다.
- 등록 명령(스킬 루트 경로를 넣는다. 사용자 계정·로그온 상태 실행이 기본값이다):

  ```powershell
  $a = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -File "<스킬 루트>\scripts\run_daily.ps1"'
  $t = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 08:40
  $s = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
  Register-ScheduledTask -TaskName '알림장 일일 정리' -Action $a -Trigger $t -Settings $s
  ```
- 실행 파일은 `scripts/run_daily.ps1`이고 **`pwsh`(PowerShell 7)로 돌린다.** 스크립트가 BOM 없는 UTF-8이라 Windows PowerShell 5.1로 돌리면 한글 경로가 깨진다.
- 흐름은 서버 접근 확인 → `alim_export.py --date 오늘` → 첨부가 있고 요약 파일이 없으면 `extract_attachments.py`로 `%LOCALAPPDATA%\알림장-자동화\extract\<날짜>\`에 텍스트 추출(14일 지난 추출본은 자동 삭제) → `claude -p`가 **추출된 .md만 읽어** 요약 작성 순이다. 요약 규칙은 프롬프트에 직접 들어 있고, `claude -p`에는 Read·Write·Edit·`Bash(python/grep/awk)`만 허용한다.
- 이미 요약 파일이 있으면 claude를 부르지 않는다(재실행해도 무해). 다시 쓰게 하려면 `-Force`를 붙이고, 지난 날짜는 `-Date 2026-09-22`로 돌린다.
- 로그는 `%LOCALAPPDATA%\알림장-자동화\log\<날짜>.log`에 남는다. 종료 코드는 0 정상, 1 서버 접근 불가, 2 요약 미생성, 3 `alim_export.py` 실패(원인은 로그의 `export:` 줄)다.
- 점검은 `Get-ScheduledTaskInfo -TaskName '알림장 일일 정리'`(LastTaskResult·NextRunTime)로 하고, 수동 실행은 `Start-ScheduledTask`로 한다. 해제는 `Unregister-ScheduledTask -TaskName '알림장 일일 정리'`이다.
- **이 PC에서 알림장 앱이 실행 중일 필요는 없다.** 스크립트는 앱을 거치지 않고 서버 공유 폴더의 DB 파일을 직접 읽는다. 필요한 조건은 서버 PC `관리자`가 켜져 있고 이 PC가 로그온돼 있으며 출력할 프로젝트 폴더에 접근할 수 있는 것이다.

## 쓰기(미정립)

아직 실제로 시험 입력한 적이 없다. 아래는 2026-09-28 조사로 확인한 사실이며 절차가 아니다. 쓰기를 처음 할 때는 사용자 승인을 받고, 사용자가 부서 암호를 직접 넣게 한 뒤 한 건만 시험하고, 결과를 DB 재조회로 검증한 다음 이 절을 절차로 고쳐 쓴다.

- 날짜별 입력 화면은 제목 없는 대화상자(`#32770`)다. 주요 컨트롤은 달력 `DRCALEND`(id 4001), [입ㆍ수정](201), [파일첨부](301), [자료검색](205), [닫기](210), 본문 표시란 `Edit`(id 2001), 연·월 콤보(5001·5002), 숨은 [보 관](6001)·[취 소](6002), [첨부1~5](9001~9005)이다. 일반 Win32 컨트롤이라 `WM_GETTEXT`로 본문이 읽히고 `WM_SETTEXT`·`WM_COMMAND`도 통할 가능성이 높다(미검증).
- 부서 칸 입력은 **부서별 암호**가 필요하다(`AGICHO.DBF`의 `ALPA`에 난독화 저장. 풀거나 우회하지 않는다).
- 동시 편집 잠금이 있다. 누가 편집 중이면 "다른 사용자가 있습니다. 잠시 후 보관하시오."가 뜬다. 편집자 이름은 `ALIMUSER.TXT`(전달사항)·`MEETUSER.TXT`(부장회의)에 남는다.
- 첨부는 서버에 `H<월><일><n>.<확장자>`로 복사되고, `ALHWPn`에 파일명이, `ALIDn`에 올린 부서 번호가 기록된다.
- 창 조작 공통 기법(ALT를 눌렀다 떼며 `SetForegroundWindow`, 버튼은 `BM_CLICK`을 먼저 보내고 변화가 없으면 `WM_COMMAND`+컨트롤 ID(모달 대화상자는 `BM_CLICK`이 무시된 실측이 있어 바로 `WM_COMMAND`), `SendMessageTimeout`, `PrintWindow` 캡처)은 `coolmessenger-automation`·`k-edufine-automation` 스킬의 스크립트를 재사용한다.

## 함정

- **서버 PC `관리자`가 꺼져 있으면 모든 조회가 실패한다**(오류 로그에 `DOS Error 2 ... \\관리자\$ALIM$\ALIM.fpt` 실측). 급하면 `--src 'C:\알림장\AUTOBACK'`(bash에서는 작은따옴표 필수)으로 이 PC의 사본을 읽되, 앱을 마지막으로 켠 시점까지의 자료라는 점을 알린다. 이 폴더는 앱을 켤 때만 갱신되고, 첨부(`H…` 파일)가 없으면 `MISSING`이 뜬다.
- 앱 하위 메뉴는 오너드로 방식이라 `GetMenuString`이 빈 문자열을 돌려준다. 메뉴 구성은 실행 파일 문자열에서 복원했다(references 참조).
- 오류 로그와 실행 파일의 한글은 cp949다. 로그에 서버 경로가 `\\������\$ALIM$`처럼 깨져 보이면 바이트를 cp949로 디코드한다(`\xb0\xfc\xb8\xae\xc0\xda` = 관리자).
- 한글 출력을 터미널로 흘리면 깨지니 `PYTHONIOENCODING=utf-8` 또는 UTF-8 파일로 쓴다. `--stdout`을 `head`로 자르면 `BrokenPipeError`가 나지만 무해하다.
- `ALME` 칸 수(20)보다 부서 수가 적으면 남는 칸은 비어 있다.

## 상태

**v1.3.2**(2026-10-14: 스냅숏을 `ALIM`·`AGICHO` 테이블로 한정해 학생 명렬이 임시 폴더에 복사되지 않게 하고 정리를 `finally`로, `--keywords` 공백·빈 값 정리, 서버 꺼짐 안내, 첨부 파일명 금지 문자 치환, 추출 스크립트의 인코딩·임시 파일·지난 결과 오판 수정, `ALIM_PROJECT_ROOT` 환경 변수, 작업 스케줄러 등록 명령 추가). v1.3.0(2026-10-08 스킬 감사: 경위·실측은 [references/cases.md](references/cases.md), 학년도별 현황은 `references/학년도-현황.md`로 옮김. 날짜 폴더를 그 날짜의 학년도에 두고, `run_daily.ps1`이 `alim_export.py` 실패를 종료 코드 3으로 알리며, `--year` 끝날을 2월 말일로, 자동 요약의 '읽지 못했습니다' 조건을 WARN·FAIL로 고침). v1.2(2026-09-28)에서 읽기 절차 정립, 평일 08:40 자동 실행 등록, 첨부 추출 스크립트 도입. 쓰기는 미정립이다. → 사례

스크립트를 고치면 스킬 루트에서 `PYTHONIOENCODING=utf-8 python -m unittest discover -s scripts/tests -p "test_*.py"`와 `pwsh -NoProfile -File scripts/tests/test_run_daily.ps1`을 돌린다(가짜 DB·가짜 명령으로 돌아 서버·작업 스케줄러·claude에 닿지 않는다).
