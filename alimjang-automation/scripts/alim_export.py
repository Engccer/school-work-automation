r"""알림장관리 3.0 공유 DB(\\관리자\$ALIM$)에서 전달사항을 읽기 전용으로 추출한다.

사용 예(스킬 루트에서)
  python scripts/alim_export.py                          # 오늘 전달사항 → <출력 루트>/<날짜>(<요일>)/ 에 저장 + 첨부 복사
  python scripts/alim_export.py --date 2026-09-29        # 특정 날짜
  python scripts/alim_export.py --from 2026-09-28 --to 2026-10-02   # 기간(날짜마다 폴더)
  python scripts/alim_export.py --search 방과후 --from 2026-03-01 --to 2026-09-30
  python scripts/alim_export.py --search 방과후 --year 2025        # 학년도 전체(지난 학년도면 아카이브 자동 선택)
  python scripts/alim_export.py --dept 교무부 --from 2026-03-01 --to 2026-09-30 --list

원칙: 서버 DB에는 절대 쓰지 않는다. 본문 조회는 공유 읽기로 임시 폴더에 복사(스냅숏)한 DB에서 하고,
원천(서버 루트·아카이브) 선택은 서버 파일을 읽기 전용으로 직접 연다.
"""
import argparse
import datetime as dt
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

try:
    from dbfread import DBF
except ImportError:
    sys.exit("dbfread가 없습니다. 'pip install dbfread' 후 다시 실행하세요.")

SERVER = r"\\관리자\$ALIM$"
PROJECT_ROOT = Path(__file__).resolve().parents[4]
# 출력 루트. ALIM_OUT_DIR 로 바꾼다. {학년도} 는 학년도 숫자로 바뀌고, 상대 경로는 PROJECT_ROOT 기준이다.
DEFAULT_OUT = "알림장/{학년도}"
WEEKDAY_KO = "월화수목금토일"
DEFAULT_KEYWORDS = [k.strip() for k in os.environ.get("ALIM_KEYWORDS", "").split(",") if k.strip()]
MY_DEPTS = [k.strip() for k in os.environ.get("ALIM_MY_DEPTS", "").split(",") if k.strip()]


def school_year(d: dt.date) -> int:
    return d.year if d.month >= 3 else d.year - 1


def label(d: dt.date) -> str:
    return f"{d.isoformat()}({WEEKDAY_KO[d.weekday()]})"


def default_out_root(d: dt.date) -> Path:
    tpl = os.environ.get("ALIM_OUT_DIR") or DEFAULT_OUT
    p = Path(os.path.expandvars(os.path.expanduser(tpl.replace("{학년도}", str(school_year(d))))))
    return p if p.is_absolute() else PROJECT_ROOT / p


def snapshot(src_dir: str) -> str:
    """전달사항·기초자료 테이블만 임시 폴더로 복사한다(서버 파일은 열기만 하고 쓰지 않는다).
    학생 명렬(MYUNG) 등 다른 테이블은 복사하지 않는다."""
    tmp = tempfile.mkdtemp(prefix="alim_")
    for name in os.listdir(src_dir):
        stem, ext = os.path.splitext(name.upper())
        if stem in ("ALIM", "AGICHO") and ext in (".DBF", ".FPT", ".CDX"):
            shutil.copyfile(os.path.join(src_dir, name), os.path.join(tmp, name))
    return tmp


def open_db(src_dir: str):
    tmp = snapshot(src_dir)
    try:
        depts = {}
        for r in DBF(os.path.join(tmp, "AGICHO.DBF"), encoding="cp949", char_decode_errors="replace"):
            if str(r["ALID"]).strip().isdigit() and r["ALBU"].strip():
                depts[int(r["ALID"])] = r["ALBU"].strip()
        rows = {}
        for r in DBF(os.path.join(tmp, "ALIM.DBF"), encoding="cp949", char_decode_errors="replace"):
            if r["ALDATE"]:
                rows[r["ALDATE"]] = r
        return depts, rows
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def count_filled(path: str) -> int:
    n = 0
    for r in DBF(path, encoding="cp949", char_decode_errors="replace"):
        if any((r[f"ALME{i:02d}"] or "").strip() for i in range(1, 21)):
            n += 1
    return n


def source_for(d: dt.date) -> str:
    """날짜를 담은 DB 폴더. 서버 루트(현재 학년도)를 먼저 보고, 없으면 하위 아카이브 중
    그 날짜 범위를 덮으면서 실제 기록이 가장 많은 폴더를 고른다.
    아카이브 폴더명(B2018 등)은 담긴 연도와 어긋나는 경우가 많아 이름으로 고르지 않는다."""
    if not os.path.exists(os.path.join(SERVER, "ALIM.DBF")):
        sys.exit(f"DB를 찾을 수 없습니다: {SERVER} (서버 PC '관리자'가 꺼졌을 수 있음. --src 로 사본 지정 가능)")
    cands = [SERVER] + [os.path.join(SERVER, x) for x in sorted(os.listdir(SERVER))
                        if os.path.isdir(os.path.join(SERVER, x))]
    best, best_n = None, -1
    for c in cands:
        p = os.path.join(c, "ALIM.DBF")
        if not os.path.exists(p):
            continue
        t = DBF(p, encoding="cp949", char_decode_errors="replace")
        recs = [r["ALDATE"] for r in t if r["ALDATE"]]
        if not recs or not (recs[0] <= d <= recs[-1]):
            continue
        if c == SERVER:
            return c
        n = count_filled(p)
        if n > best_n:
            best, best_n = c, n
    if best is None or best_n == 0:
        sys.exit(f"{d} 을(를) 담은 알림장 기록이 서버에 없습니다(새학년도 파일 다시작성으로 지워진 학년도일 수 있음).")
    return best


def clean(text: str) -> str:
    lines = [ln.rstrip() for ln in (text or "").replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    out, blank = [], False
    for ln in lines:
        if not ln.strip():
            if not blank and out:
                out.append("")
            blank = True
        else:
            out.append(ln)
            blank = False
    while out and not out[-1]:
        out.pop()
    return "\n".join(out)


def entries(row, depts):
    """[(부서명, 본문)] — 비어 있는 칸 제외."""
    res = []
    for i in range(1, 21):
        body = clean(row[f"ALME{i:02d}"])
        if body.strip():
            res.append((depts.get(i, f"{i}번 칸"), body))
    return res


def attachments(row, depts):
    res = []
    for i in range(1, 6):
        f = row[f"ALHWP{i}"].strip()
        if f:
            aid = row[f"ALID0{i}"].strip()
            res.append((i, f, depts.get(int(aid), aid) if aid.isdigit() else aid))
    return res


def mentions(ents, keywords):
    hits = []
    for dept, body in ents:
        for ln in body.split("\n"):
            ks = [k for k in keywords if k in ln]
            if ks:
                hits.append((dept, ln.strip(), ks))
    return hits


def render_day(d, row, depts, keywords, src_dir):
    ents = entries(row, depts) if row else []
    atts = attachments(row, depts) if row else []
    out = [f"{label(d)} 알림장 전달사항", f"출처: 알림장관리 3.0 공유 DB ({src_dir})", ""]
    if not ents and not atts:
        out.append("이날은 입력된 전달사항이 없습니다.")
        return "\n".join(out) + "\n", atts
    out.append(f"부서 {len(ents)}곳, 첨부 {len(atts)}건입니다.")
    out.append("")
    out.append("1. 나와 관련된 항목")
    mine = [(dp, b) for dp, b in ents if dp in MY_DEPTS]
    hits = mentions(ents, keywords)
    if not MY_DEPTS and not keywords:
        out.append("관심 부서·낱말이 설정되지 않았습니다(ALIM_MY_DEPTS·ALIM_KEYWORDS 또는 --keywords).")
    elif not mine and not hits:
        out.append("해당 부서 칸과 관심 낱말이 들어간 줄이 없습니다.")
    for dp, _ in mine:
        out.append(f"{dp} 칸에 전달사항이 있습니다. 아래 본문을 확인하세요.")
    for dp, ln, ks in hits:
        out.append(f"{dp} 칸, 낱말 {', '.join(ks)}: {ln}")
    out.append("")
    out.append("2. 부서별 전달사항")
    for n, (dp, body) in enumerate(ents, 1):
        out.append("")
        out.append(f"2.{n} {dp}")
        out.append(body)
    out.append("")
    out.append("3. 첨부파일")
    if not atts:
        out.append("첨부파일이 없습니다.")
    for i, f, dp in atts:
        out.append(f"첨부{i}: {f} (올린 부서 {dp})")
    if row and row["ALJOGI"].strip():
        out += ["", f"조기청소: {row['ALJOGI'].strip()}"]
    return "\n".join(out) + "\n", atts


def daterange(a, b):
    while a <= b:
        yield a
        a += dt.timedelta(days=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date")
    ap.add_argument("--from", dest="dfrom")
    ap.add_argument("--to", dest="dto")
    ap.add_argument("--year", type=int, help="학년도 전체(3/1~이듬해 2월 말일)를 대상으로. 아카이브는 날짜로 자동 선택")
    ap.add_argument("--search", help="본문 키워드 검색(결과를 <출력 루트>/검색/ 에 저장)")
    ap.add_argument("--dept", help="부서 칸 이름으로 거르기(예: 교무부)")
    ap.add_argument("--list", action="store_true", help="부서별 누적 목록을 한 파일로(<출력 루트>/검색/)")
    ap.add_argument("--keywords", help="관련 항목 낱말, 쉼표 구분")
    ap.add_argument("--no-attach", action="store_true", help="첨부 복사 생략")
    ap.add_argument("--src", help=r"DB 폴더 직접 지정(예: C:\알림장\AUTOBACK, 서버가 꺼졌을 때)")
    ap.add_argument("--out", help="출력 루트(기본: 환경 변수 ALIM_OUT_DIR 또는 DEFAULT_OUT. {학년도}는 날짜별이면 그 날짜의, 검색이면 실행일의 학년도)")
    ap.add_argument("--stdout", action="store_true", help="파일 대신 표준출력(UTF-8)")
    a = ap.parse_args()

    today = dt.date.today()
    if a.year:
        d1, d2 = dt.date(a.year, 3, 1), dt.date(a.year + 1, 3, 1) - dt.timedelta(days=1)
    else:
        d1 = dt.date.fromisoformat(a.dfrom or a.date or today.isoformat())
        d2 = dt.date.fromisoformat(a.dto or a.date or a.dfrom or today.isoformat())
    keywords = [k.strip() for k in a.keywords.split(",") if k.strip()] if a.keywords else DEFAULT_KEYWORDS
    src = a.src or source_for(d1)
    if not os.path.exists(os.path.join(src, "ALIM.DBF")):
        sys.exit(f"DB를 찾을 수 없습니다: {src} (서버 PC '관리자'가 꺼졌을 수 있음)")
    depts, rows = open_db(src)
    if a.search or a.list:
        out_root = Path(a.out) if a.out else default_out_root(today)
        lines = []
        title = f"알림장 {'검색 ' + a.search if a.search else (a.dept or '전체') + ' 목록'} ({d1.isoformat()}~{d2.isoformat()})"
        lines += [title, f"출처: {src}", ""]
        n = 0
        for d in daterange(d1, d2):
            row = rows.get(d)
            if not row:
                continue
            for dp, body in entries(row, depts):
                if a.dept and dp != a.dept:
                    continue
                if a.search and a.search not in body:
                    continue
                n += 1
                lines += [f"{n}. {label(d)} {dp}", body, ""]
            if a.search:
                for i, f, dp in attachments(row, depts):
                    if a.search in f:
                        n += 1
                        lines += [f"{n}. {label(d)} 첨부 {f} ({dp})", ""]
        lines.insert(2, f"모두 {n}건입니다.")
        text = "\n".join(lines).rstrip() + "\n"
        if a.stdout:
            sys.stdout.buffer.write(text.encode("utf-8"))
            return
        (out_root / "검색").mkdir(parents=True, exist_ok=True)
        tag = a.search or (a.dept or "전체")
        p = out_root / "검색" / f"{today.isoformat()} {tag} ({d1.isoformat()}~{d2.isoformat()}).txt"
        p.write_text(text, encoding="utf-8")
        print(f"SAVED {p}  ({n}건)")
        return

    for d in daterange(d1, d2):
        row = rows.get(d)
        text, atts = render_day(d, row, depts, keywords, src)
        if a.stdout:
            sys.stdout.buffer.write((text + "\n").encode("utf-8"))
            continue
        if not row or (not entries(row, depts) and not atts):
            print(f"SKIP {label(d)} (전달사항 없음)")
            continue
        folder = (Path(a.out) if a.out else default_out_root(d)) / label(d)
        folder.mkdir(parents=True, exist_ok=True)
        p = folder / f"{label(d)} 알림장 전달사항.txt"
        p.write_text(text, encoding="utf-8")
        print(f"SAVED {p}")
        if a.no_attach:
            continue
        for i, f, dp in atts:
            s = os.path.join(src, f)
            t = folder / re.sub(r'[\\/:*?"<>|]', "_", f"첨부{i}_{dp}_{f}")
            if not os.path.exists(s):
                print(f"  MISSING {s}")
                continue
            if not t.exists() or t.stat().st_size != os.path.getsize(s):
                shutil.copyfile(s, t)
            print(f"  ATTACH {t.name} ({t.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
