---
name: school-work-setup
license: MIT
description: >-
  school-work-automation 번들(나이스·K-에듀파인·교데통·쿨메신저·알림장 자동화 스킬 5종)의 설치와 실행 요구사항을 점검한다. 스킬마다 "바로 사용 가능 / 빠진 것"을 보고하고 빠진 것의 설치 방법을 안내한다. 쓰지 않을 스킬은 건너뛴다. 다음 요청에 사용한다. "학교 업무 자동화 스킬 설치됐는지 봐 줘", "나이스 자동화 쓸 준비 됐어?", "알림장 스킬 쓰려면 뭐가 필요해?", 설치 점검, 요구사항 확인, 환경 점검, 셋업. Check requirements and setup for the school-work-automation bundle: verify skills, runtimes, packages, certificate program, Playwright browser tools.
metadata:
  version: "1.0.0"
---

# 학교 업무 자동화 설치 점검

번들의 다섯 스킬이 이 컴퓨터에서 바로 돌 수 있는지 점검한다. 읽기만 하고 아무것도 설치하지 않는다. 설치는 사용자가 결과를 보고 고른다.

## 1. 쓸 스킬 고르기

사용자가 특정 업무만 말했으면 그 스킬만 점검한다("알림장만" → `alimjang-automation`). 말이 없으면 다섯 개 전부다.

| 업무 | 스킬 |
|---|---|
| 나이스 | `neis-automation` |
| K-에듀파인 | `k-edufine-automation` |
| 교데통 | `kyodetong-submit` |
| 쿨메신저 | `coolmessenger-automation` |
| 알림장 | `alimjang-automation` |

## 2. 점검 스크립트

스킬 루트에서 실행한다. 여러 개는 쉼표로 잇는다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_requirements.ps1 -Skill neis-automation,alimjang-automation
```

줄마다 `[OK]`·`[없음]`·`[확인]` 중 하나다. 종료 코드 0은 빠진 것 없음, 1은 있음, 2는 잘못된 스킬 이름이다.

`[확인]`은 두 가지다. 일부 기능(급여명세서 CSV, 알림장 평일 자동 정리)에만 필요한 항목은 사용자가 그 기능을 쓸 때만 설치를 안내한다. 스크립트가 판정할 수 없는 항목은 아래 절차로 마저 본다.

- **Playwright 브라우저 도구**(나이스·K-에듀파인·교데통): 에이전트에 Playwright 도구(`browser_navigate` 등)가 있는지 본다. 없으면 "빠진 것"으로 보고하고, 에이전트 설정에 MCP 서버 `npx @playwright/mcp@latest`를 등록하도록 안내한다. 브라우저 제어 확장은 사용자가 쓰겠다고 할 때만 점검한다. 탭 목록은 되는데 클릭·캡처가 `Cannot attach to this target`이면 그 크롬에서 메뉴 ⋮ → 도구 더보기 → 개발자 도구를 열어 보게 하고, "조직에서 이 페이지의 DevTools 사용을 차단했습니다"가 뜨면 그 크롬에서는 확장을 쓸 수 없다고 알린다.
- **교육행정 전자서명 인증서**: 기본 위치에 없으면 이동식 매체나 다른 경로에 두었는지 사용자에게 묻는다. 인증서 암호는 묻지도 입력하지도 않는다.
- **알림장 서버 공유 폴더**: 학교 내부망에서 서버 PC가 켜져 있을 때만 보인다. 교외에서 점검했으면 교내에서 다시 확인하라고 안내한다.

## 3. 보고

스킬마다 한 줄로 "바로 사용 가능" 또는 "빠진 것: …"을 적고, 빠진 것마다 스크립트가 낸 설치 방법을 붙인다. 업무포털 공통 항목(Playwright 도구·인증서 프로그램·인증서)이 빠졌으면 웹 세 스킬 모두에 해당한다고 한 번만 말한다. 설치는 사용자가 하겠다고 하면 그때 한다.
