# -*- coding: utf-8 -*-
"""
쿨메신저 로컬 DB에서 메시지를 뽑아 CSV/JSON으로 내보낸다.

쿨메신저는 주고받은 메시지를 암호화 없는 SQLite에 그대로 보관한다.
  %LOCALAPPDATA%\\CoolMessenger\\Memo\\<사용자명>.udb
앱이 파일을 잠그고 있으므로 공유 읽기로 복사한 뒤 연다. 앱을 조작하지
않으므로 가장 안전하고 빠른 경로이며, 화면 목록과 달리 전체 이력이 남는다.

사용 예
  python cm_export.py --since 2026-09-21 --out 회신.csv
  python cm_export.py --sent --since 2026-09-01 --format json
  python cm_export.py --since 2026-09-21 --contains 체크리스트 --full
"""
import argparse, csv, glob, io, json, os, shutil, sqlite3, sys, tempfile

DB_DIR = os.path.join(os.environ.get("LOCALAPPDATA", ""), "CoolMessenger", "Memo")


def find_db():
    hits = [p for p in glob.glob(os.path.join(DB_DIR, "*.udb"))]
    if not hits:
        sys.exit("쿨메신저 DB를 찾지 못했습니다: %s" % DB_DIR)
    return max(hits, key=os.path.getsize)


def copy_db(src, tmp):
    """앱이 잠근 파일이라 FileShare.ReadWrite 상당의 공유 읽기로 tmp 폴더에 복사한다.

    WAL 모드라 -wal / -shm 까지 같이 가져와야 최근 메시지가 보인다.
    """
    base = os.path.basename(src)
    for suffix in ("", "-wal", "-shm"):
        p = src + suffix
        if not os.path.exists(p):
            continue
        with open(p, "rb") as f, open(os.path.join(tmp, base + suffix), "wb") as o:
            shutil.copyfileobj(f, o)
    return os.path.join(tmp, base)


def parse_attachments(file_path):
    """FilePath 필드는 |건수|크기;크기;|보낸사람쪽폴더|파일명|플래그| 꼴이고,
    첨부가 여러 개면 (폴더|파일명|플래그) 세 칸이 건수만큼 반복된다."""
    if not file_path:
        return []
    fields = file_path.split("|")[1:-1]      # 양끝 구분자 하나씩만 벗긴다
    return [name for name in fields[3::3] if name]


def strip_quote(text, quote_mark):
    """회신에 따라붙은 원문 인용을 잘라 내고 실제로 쓴 부분만 남긴다.

    인용 머리글은 '<보낸사람>님이 보낸글 >> <일시>' 한 줄이므로, 표시가
    나온 지점이 아니라 그 줄의 처음에서 잘라야 이름이 남지 않는다.
    """
    if not text or not quote_mark:
        return text or ""
    i = text.find(quote_mark)
    if i < 0:
        return text
    line_start = text.rfind("\n", 0, i) + 1      # 없으면 0
    return text[:line_start]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sent", action="store_true", help="보낸메시지(기본은 받은메시지)")
    ap.add_argument("--since", help="YYYY-MM-DD 또는 'YYYY/MM/DD HH:MM'")
    ap.add_argument("--contains", help="제목이나 본문(인용문 포함)에 이 문구가 들어간 것만")
    ap.add_argument("--from", dest="sender", help="상대 이름에 이 문구가 들어간 것만(받은메시지는 보낸사람, --sent면 받는사람)")
    ap.add_argument("--quote-mark", default="님이 보낸글",
                    help="인용 시작 표시. 이 앞부분만 '회신내용'으로 담는다")
    ap.add_argument("--full", action="store_true", help="인용문까지 통째로 담기")
    ap.add_argument("--format", choices=["csv", "json"], default="csv")
    ap.add_argument("--out", help="출력 파일(생략 시 표준출력)")
    a = ap.parse_args()

    table, who, datecol = (("tbl_send", "Receiver", "SendDate") if a.sent
                           else ("tbl_recv", "Sender", "ReceiveDate"))

    since = (a.since or "").replace("-", "/")
    sql = "select %s as Who, %s as When_, Title, FilePath, MessageText from %s" % (who, datecol, table)
    args = []
    if since:
        sql += " where %s >= ?" % datecol
        args.append(since)
    sql += " order by %s" % datecol

    src = find_db()
    # 사본은 교직원 메시지 전체라 실패해도 남기지 않는다.
    tmp = tempfile.mkdtemp(prefix="cm_")
    try:
        con = sqlite3.connect(copy_db(src, tmp))
        cur = None
        try:
            con.row_factory = sqlite3.Row
            rows = []
            cur = con.execute(sql, args)
            for r in cur:
                text = r["MessageText"] or ""
                if a.contains and a.contains not in text and a.contains not in (r["Title"] or ""):
                    continue
                if a.sender and a.sender not in (r["Who"] or ""):
                    continue
                rows.append({
                    "상대": r["Who"],
                    "일시": r["When_"],
                    "제목": r["Title"],
                    "첨부": "; ".join(parse_attachments(r["FilePath"])),
                    "내용": (text if a.full else strip_quote(text, a.quote_mark)).strip(),
                })
        finally:
            # 커서가 남아 있으면 Windows에서 사본 파일이 잠겨 지워지지 않는다.
            if cur is not None:
                cur.close()
            con.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        if os.path.exists(tmp):
            sys.stderr.write("경고: DB 사본을 지우지 못했습니다. 직접 지우세요: %s\n" % tmp)

    if a.format == "json":
        out = json.dumps(rows, ensure_ascii=False, indent=2)
        if a.out:
            io.open(a.out, "w", encoding="utf-8").write(out)
        else:
            io.open(sys.stdout.fileno(), "w", encoding="utf-8", closefd=False).write(out)
    else:
        cols = ["상대", "일시", "제목", "첨부", "내용"]
        # 한글이 터미널에서 깨지므로 파일 출력을 기본으로 삼는 편이 낫다(BOM = 엑셀 호환).
        f = (io.open(a.out, "w", encoding="utf-8-sig", newline="") if a.out
             else io.open(sys.stdout.fileno(), "w", encoding="utf-8", newline="", closefd=False))
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
        if a.out:
            f.close()

    sys.stderr.write("%d건\n" % len(rows))


if __name__ == "__main__":
    main()
