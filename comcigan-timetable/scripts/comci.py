"""컴시간알리미(comci.net:4082/st)에서 학교 시간표를 읽어 내 수업과 변동을 정리한다.

컴시간알리미는 공식 API가 없고 데이터 응답이 암호화되어 있다(운영사의 자동 수집 방지 장치).
암호를 풀지 않고, 화면 없는 Edge(Playwright)로 사이트를 정상적으로 열어 학급별 표를 읽는다.

사용(스킬 루트에서):
  python scripts/comci.py                       # 오늘
  python scripts/comci.py --date 2026-11-18     # 특정 날짜(이번 주·다음 주만 조회 가능)
  python scripts/comci.py --week                # 해당 주 월~금 전부
  python scripts/comci.py --out "<폴더>"         # <날짜>(<요일>) 컴시간 시간표.txt 로 저장
  python scripts/comci.py --all-changes         # 학교 전체 변경 칸까지 나열

학교와 교사는 인자(--school·--region·--teacher)나 환경 변수(COMCI_SCHOOL·COMCI_REGION·COMCI_TEACHER)로 준다.

출력 줄: SAVED <경로> / SKIP <사유>. 종료 코드: 0 정상, 1 조회 실패, 2 입력 오류(학교·교사 미지정·날짜), 3 조회 범위 밖 날짜.
"""
from __future__ import annotations

import argparse
import datetime as dt
import csv
import io
import json
import os
import re
import sys
from pathlib import Path

WEEKDAYS = "월화수목금토일"
URL = "http://comci.net:4082/st"


# ---------- 순수 함수(시험 대상) ----------

def school_year(d: dt.date) -> int:
    return d.year if d.month >= 3 else d.year - 1


def label(d: dt.date) -> str:
    return f"{d.isoformat()}({WEEKDAYS[d.weekday()]})"


def mask_name(name: str) -> str:
    """컴시간알리미는 교사 이름 가운데를 가린다: 홍길동 -> 홍*동, 남궁민수 -> 남**수."""
    name = name.strip()
    if not name:
        raise ValueError("교사 이름이 비어 있습니다")
    if len(name) <= 2:
        return name[0] + "*"
    return name[0] + "*" * (len(name) - 2) + name[-1]


def parse_date(s: str, today: dt.date) -> dt.date:
    """'YYYY-MM-DD' 또는 'MM-DD'. MM-DD는 오늘과 가장 가까운 해로 붙인다(12월 말에 '01-04' -> 다음 해)."""
    s = s.strip()
    if re.fullmatch(r"\d{4}-\d{1,2}-\d{1,2}", s):
        y, m, d = map(int, s.split("-"))
        try:
            return dt.date(y, m, d)
        except ValueError:
            raise ValueError(f"없는 날짜입니다: {s}") from None
    if re.fullmatch(r"\d{1,2}-\d{1,2}", s):
        m, d = map(int, s.split("-"))
        cands = []
        for y in (today.year - 1, today.year, today.year + 1):
            try:
                cands.append(dt.date(y, m, d))
            except ValueError:   # 2월 29일 등
                pass
        if not cands:
            raise ValueError(f"없는 날짜입니다: {s}")
        return min(cands, key=lambda c: abs((c - today).days))
    raise ValueError(f"날짜 형식은 YYYY-MM-DD 또는 MM-DD입니다: {s}")


def read_text_any(path: Path) -> str:
    """UTF-8(BOM 포함)을 먼저, 안 되면 CP949로 읽는다. 둘 다 안 되면 UnicodeDecodeError."""
    raw = path.read_bytes()
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        return raw.decode("cp949")


def parse_memo(text: str) -> dict[str, list[tuple[int, str]]]:
    """정규 시간표 파일의 시간표 절을 읽는다.

    형식: '# …시간표' 머리 아래 요일 한 글자 줄, 그 밑에 '  <교시> <학년><반 두 자리>' 줄.
    '---' 또는 다음 '#' 머리에서 끝난다. 반환: {'월': [(3, '1-2'), …]}
    """
    out: dict[str, list[tuple[int, str]]] = {}
    inside = False
    day = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("#"):
            if inside:
                break
            inside = "시간표" in line
            continue
        if not inside:
            continue
        if line.startswith("---"):
            break
        if len(line) == 1 and line in WEEKDAYS[:5]:
            day = line
            out.setdefault(day, [])
            continue
        m = re.fullmatch(r"(\d{1,2})\s+(\d)(\d{2})", line)
        if m and day:
            out[day].append((int(m.group(1)), f"{m.group(2)}-{int(m.group(3))}"))
    return out


def day_column(header_row: list[str], d: dt.date) -> int | None:
    """표 머리 '월(16)' 가운데 날짜에 맞는 열 번호(교시 열 다음부터 1)."""
    want = f"{WEEKDAYS[d.weekday()]}({d.day})"
    for i, h in enumerate(header_row):
        if h.strip() == want:
            return i
    return None


def cell_parts(text: str) -> tuple[str, str, str]:
    """'영어\\n홍*동\\n영어실' -> (과목, 교사, 장소)."""
    parts = [p.strip() for p in text.split("\n") if p.strip()]
    return (parts[0] if parts else "", parts[1] if len(parts) > 1 else "",
            " ".join(parts[2:]) if len(parts) > 2 else "")


def analyze(tables: dict, d: dt.date, teacher_mask: str,
            regular: dict[str, list[tuple[int, str]]] | None) -> dict:
    """학급별 표(tables)에서 날짜 d의 내 수업·정규 대비 변동·학교 전체 변경 칸을 뽑는다.

    tables: {'1-1': [[{'t':..,'c':..}, …], …]} · 0행은 머리, 그 뒤 교시 행.
    """
    mine, changes, empty_classes, total_classes = [], [], 0, 0
    found_day = False
    grade_filled: dict[str, int] = {}     # 학년별 채워진 칸 수(학년 전체가 빈 날 판별)
    for cls, rows in tables.items():
        if not rows:
            continue
        col = day_column([c["t"] for c in rows[0]], d)
        if col is None:
            continue
        found_day = True
        total_classes += 1
        filled = 0
        for row in rows[1:]:
            per_txt = row[0]["t"]
            m = re.match(r"(\d+)", per_txt)
            if not m or col >= len(row):
                continue
            per = int(m.group(1))
            cell = row[col]
            subj, teacher, room = cell_parts(cell["t"])
            if subj:
                filled += 1
            changed = cell.get("c") == "변경"
            if teacher == teacher_mask:
                mine.append({"period": per, "class": cls, "subject": subj, "room": room, "changed": changed})
            if changed and subj:
                changes.append({"period": per, "class": cls, "subject": subj, "teacher": teacher})
        if filled == 0:
            empty_classes += 1
        g = cls.split("-")[0]
        grade_filled[g] = grade_filled.get(g, 0) + filled
    if not found_day:
        return {"found": False}
    mine.sort(key=lambda x: (x["period"], x["class"]))
    changes.sort(key=lambda x: (x["class"], x["period"]))
    all_empty = total_classes > 0 and empty_classes == total_classes
    empty_grades = [] if all_empty else sorted(g for g, n in grade_filled.items() if n == 0)
    result = {"found": True, "mine": mine, "changes": changes,
              "all_empty": all_empty, "empty_grades": empty_grades}
    if regular is not None:
        reg = set(regular.get(WEEKDAYS[d.weekday()], []))
        now = {(x["period"], x["class"]) for x in mine}
        removed = sorted(reg - now)
        result["added"] = sorted(now - reg)
        # 학년 전체가 빈 날(그 학년 고사일 등)에 빠진 수업은 따로 둔다.
        result["removed"] = [x for x in removed if x[1].split("-")[0] not in empty_grades]
        result["removed_blank"] = [x for x in removed if x[1].split("-")[0] in empty_grades]
    return result


def calendar_note(rows: list[dict], d: dt.date) -> str:
    for r in rows:
        if r.get("날짜") == d.isoformat():
            parts = [r.get("주요 일정", ""), r.get("비고", "")]
            return ", ".join(p for p in parts if p)
    return ""


def render(d: dt.date, res: dict, *, teacher: str, school: str, modified: str,
           fetched: dt.datetime, note: str, all_changes: bool) -> str:
    L = [f"{label(d)} 컴시간 시간표",
         f"출처: 컴시간알리미 {school} (시간표 수정일 {modified or '확인 못 함'}), 조회 {label(fetched.date())} {fetched:%H:%M}"]
    if note:
        L.append(f"학사일정: {note}")
    L.append("")
    L.append(f"1. {teacher} 선생님 수업")
    if res["all_empty"]:
        L.append("그날은 전 학급 시간표가 비어 있습니다(휴업일·고사일 등).")
    else:
        for g in res.get("empty_grades", []):
            L.append(f"{g}학년은 전 학급 시간표가 비어 있습니다(고사일·현장체험학습 등).")
        if not res["mine"]:
            L.append("수업이 없습니다.")
    for x in res["mine"]:
        room = f", {x['room']}" if x["room"] else ""
        mark = " (변경)" if x["changed"] else ""
        L.append(f"{x['period']}교시 {x['class']} {x['subject']}{room}{mark}")
    L.append("")
    L.append("2. 정규 시간표와 다른 점")
    if res["all_empty"]:
        L.append("수업이 없는 날이라 비교하지 않았습니다.")
    elif "added" not in res:
        L.append("정규 시간표 파일을 읽지 못해 비교하지 않았습니다.")
    else:
        fmt = lambda xs: ", ".join(f"{p}교시 {c}" for p, c in xs) or "없음"
        blank = res.get("removed_blank", [])
        if not res["added"] and not res["removed"]:
            if not blank:
                L.append("정규 시간표와 같습니다.")
        else:
            L.append(f"새로 생긴 수업: {fmt(res['added'])}")
            L.append(f"빠진 수업: {fmt(res['removed'])}")
        if blank:
            grades = "·".join(res.get("empty_grades", []))
            L.append(f"{grades}학년 시간표가 비어 없어진 수업: {fmt(blank)}")
    L.append("")
    L.append("3. 학교 전체 변경")
    if not res["changes"]:
        L.append("변경 칸이 없습니다.")
    else:
        by_grade: dict[str, int] = {}
        for x in res["changes"]:
            g = x["class"].split("-")[0]
            by_grade[g] = by_grade.get(g, 0) + 1
        L.append(f"변경 칸 {len(res['changes'])}개(" +
                 ", ".join(f"{g}학년 {n}개" for g, n in sorted(by_grade.items())) + ")")
        if all_changes:
            for x in res["changes"]:
                L.append(f"{x['class']} {x['period']}교시 {x['subject']} {x['teacher']}")
    return "\n".join(L) + "\n"


# ---------- 조회(브라우저) ----------

def week_option(options: list[tuple[str, str]], d: dt.date) -> str | None:
    """'26-11-16 ~ 26-11-21' 꼴 선택지 가운데 d가 든 주의 value."""
    for value, text in options:
        m = re.findall(r"(\d{2})-(\d{2})-(\d{2})", text)
        if len(m) == 2:
            a = dt.date(2000 + int(m[0][0]), int(m[0][1]), int(m[0][2]))
            b = dt.date(2000 + int(m[1][0]), int(m[1][1]), int(m[1][2]))
            if a <= d <= b:
                return value
    return None


# 학급 c의 표가 뜨고, 그 표 머리에 원하는 주의 날짜 칸(예: '월(30)')이 있을 때 참.
# 주(#nal)를 바꾼 직후 지난주 표가 남아 있어도 통과하지 않게 날짜까지 본다.
READY_JS = r"""([c, want])=>{
  const [g, b] = c.split('-');
  const re = new RegExp('제\\s*'+g+'\\s*학년\\s*'+b+'\\s*반\\s*시간표');
  const tbs=[...document.querySelectorAll('table')].filter(t=>re.test(t.innerText) && t.rows.length>3);
  const t=tbs[tbs.length-1]; if(!t) return false;
  return [...t.rows].some(r=>[...r.cells].some(td=>td.innerText.trim()===want));
}"""


TABLE_JS = r"""()=>{
  const tbs=[...document.querySelectorAll('table')].filter(t=>/\d\s*학년\s*\d+\s*반\s*시간표/.test(t.innerText) && t.rows.length>3);
  const t=tbs[tbs.length-1]; if(!t) return null;
  const rows=[...t.rows].map(r=>[...r.cells].map(td=>({t:td.innerText, c:td.className})));
  const i=rows.findIndex(r=>r.length && r[0].t.trim()==='교시');
  return i<0? null : rows.slice(i);
}"""


def fetch(d: dt.date, school: str, school_full: str, region: str, timeout_ms: int = 30000) -> tuple[dict, str]:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge")
        try:
            pg = browser.new_page()
            pg.set_default_timeout(timeout_ms)
            pg.goto(URL, wait_until="networkidle")
            pg.fill("#sc", school)
            pg.click("input[value='검색']")
            pg.wait_for_timeout(2000)
            # 같은 이름 학교가 여러 지역에 있을 수 있어 지역과 학교명이 모두 맞는 행의 링크를 고른다.
            rows = pg.locator("tr", has_text=region) if region else pg
            link = rows.locator("a", has_text=school_full).first
            link.click()
            pg.wait_for_selector("#nal option", state="attached")
            pg.wait_for_timeout(2000)
            opts = pg.eval_on_selector_all("#nal option", "els=>els.map(e=>[e.value,e.text])")
            val = week_option([tuple(o) for o in opts], d)
            if val is None:
                raise LookupError("조회 가능한 주: " + " / ".join(t for _, t in opts))
            if pg.eval_on_selector("#nal", "e=>e.value") != val:
                pg.select_option("#nal", val)
                pg.wait_for_timeout(2000)
            want = f"{WEEKDAYS[d.weekday()]}({d.day})"    # 그 주 표가 맞는지 확인할 머리 칸
            classes = [v for v in pg.eval_on_selector_all("#ba option", "els=>els.map(e=>e.value)") if v]
            if not classes:
                raise RuntimeError("학급 선택지(#ba)가 비어 있습니다")
            tables = {}
            for cls in classes:
                pg.select_option("#ba", cls)
                pg.wait_for_function(READY_JS, arg=[cls, want])
                pg.wait_for_timeout(300)
                tables[cls] = pg.evaluate(TABLE_JS)
            body = pg.inner_text("body")
            m = re.search(r"수정일\s*:\s*([\d\- :]+)", body)
            return tables, (m.group(1).strip() if m else "")
        finally:
            browser.close()


def resolve(tpl: str, d: dt.date) -> Path:
    p = Path(os.path.expandvars(os.path.expanduser(tpl.replace("{학년도}", str(school_year(d))))))
    return p if p.is_absolute() else Path.cwd() / p


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--date", help="YYYY-MM-DD 또는 MM-DD(기본 오늘)")
    ap.add_argument("--week", action="store_true", help="그 주 월~금 전부")
    ap.add_argument("--out", help="저장 폴더(없으면 화면 출력)")
    env = os.environ.get
    ap.add_argument("--teacher", default=env("COMCI_TEACHER", ""), help="교사 이름(환경 변수 COMCI_TEACHER)")
    ap.add_argument("--school", default=env("COMCI_SCHOOL", ""), help="학교 검색어(COMCI_SCHOOL)")
    ap.add_argument("--school-full", default=env("COMCI_SCHOOL_FULL", ""), help="검색 결과의 학교 이름(COMCI_SCHOOL_FULL, 기본은 검색어)")
    ap.add_argument("--region", default=env("COMCI_REGION", ""), help="같은 이름 학교를 가를 지역(COMCI_REGION)")
    ap.add_argument("--memo", default=env("COMCI_MEMO", ""), help="정규 시간표가 든 텍스트 파일(COMCI_MEMO, {학년도} 치환)")
    ap.add_argument("--calendar", default=env("COMCI_CALENDAR", ""), help="학사일정 CSV(COMCI_CALENDAR, {학년도} 치환)")
    ap.add_argument("--all-changes", action="store_true", help="학교 전체 변경 칸을 모두 나열")
    ap.add_argument("--dump", help="학급별 원자료를 JSON으로 저장(점검용)")
    ap.add_argument("--from-json", help="조회 대신 --dump로 저장한 JSON을 읽음(점검용)")
    a = ap.parse_args(argv)

    today = dt.date.today()
    try:
        d = parse_date(a.date, today) if a.date else today
    except ValueError as e:
        print(f"ERROR 입력 오류: {e}", file=sys.stderr)
        return 2
    days = [d - dt.timedelta(days=d.weekday()) + dt.timedelta(days=i) for i in range(5)] if a.week else [d]
    if not a.week and d.weekday() >= 5:
        print(f"SKIP {label(d)} (주말)")
        return 0

    if not a.teacher.strip() or not (a.school.strip() or a.from_json):
        print("ERROR 학교(--school 또는 COMCI_SCHOOL)와 교사 이름(--teacher 또는 COMCI_TEACHER)을 지정하세요.", file=sys.stderr)
        return 2
    try:
        mask = mask_name(a.teacher)
    except ValueError as e:
        print(f"ERROR 입력 오류: {e}", file=sys.stderr)
        return 2
    a.school_full = a.school_full or a.school
    memo_path = resolve(a.memo, d) if a.memo else None
    regular = None
    if memo_path and memo_path.is_file():
        try:
            regular = parse_memo(read_text_any(memo_path))
        except (OSError, UnicodeDecodeError) as e:
            print(f"WARN 정규 시간표 파일을 읽지 못해 정규 시간표 비교를 건너뜀: {memo_path}: {e}", file=sys.stderr)
    cal_path = resolve(a.calendar, d) if a.calendar else None
    cal_rows = []
    if cal_path and cal_path.is_file():
        try:
            cal_rows = list(csv.DictReader(io.StringIO(read_text_any(cal_path), newline="")))
        except (OSError, UnicodeDecodeError, csv.Error) as e:
            print(f"WARN 학사일정을 읽지 못함: {cal_path}: {e}", file=sys.stderr)

    fetched = dt.datetime.now()
    try:
        if a.from_json:
            blob = json.loads(Path(a.from_json).read_text(encoding="utf-8"))
            tables, modified = blob["tables"], blob.get("modified", "")
        else:
            tables, modified = fetch(days[0], a.school, a.school_full, a.region)
    except LookupError as e:
        print(f"ERROR {label(d)} 조회 범위 밖: {e}", file=sys.stderr)
        return 3
    except Exception as e:  # 네트워크·사이트 구조 변경 등
        print(f"ERROR 컴시간알리미 조회 실패: {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    if a.dump:
        Path(a.dump).write_text(json.dumps({"modified": modified, "tables": tables}, ensure_ascii=False), encoding="utf-8")

    texts = []
    for day in days:
        res = analyze(tables, day, mask, regular)
        if not res["found"]:
            texts.append((day, f"{label(day)} 컴시간 시간표\n그날 열을 찾지 못했습니다.\n"))
            continue
        texts.append((day, render(day, res, teacher=a.teacher, school=a.school_full, modified=modified,
                                  fetched=fetched, note=calendar_note(cal_rows, day), all_changes=a.all_changes)))

    if a.out:
        out = Path(a.out)
        out.mkdir(parents=True, exist_ok=True)
        for day, t in texts:
            p = out / f"{label(day)} 컴시간 시간표.txt"
            p.write_text(t, encoding="utf-8")
            print(f"SAVED {p}")
    else:
        sys.stdout.write("\n".join(t for _, t in texts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
