# -*- coding: utf-8 -*-
"""cm_org_chart.ps1이 쓴 조직도 TSV를 내선번호·소속 포함 CSV(UTF-8 BOM)로 바꾼다.

    python scripts/cm_org_csv.py <tree.tsv> --out <저장 파일.csv> [--check-db]

열: 이름, 학년-반, 내선번호, 담당, 소속(조직도 경로), 상태 메시지
  - 소속은 사람이 나온 모든 그룹 경로를 " / "로 이은 것이다(예: "교무부 / 교과 > 영어").
  - 상태 메시지는 항목 꼬리 글자다. 내선 숫자를 그대로 반복한 꼬리는 비운다.
  - 이름이 한글로 시작하지 않는 항목(계정만 있는 것)은 사람이 아니므로 뺀다.

--check-db: 쿨메신저 DB의 tbl_member(구성원 명단)를 읽기 전용 사본으로 열어
  이름별 내선·담당을 대조해 보고한다. 파일 내용은 바꾸지 않는다.
  명단에는 조직도에서 빠진 과거 구성원이 섞여 있어 목록에 넣지 않고 "명단에만 있음"으로만 적는다.

시험: python -m unittest discover -s scripts/tests
"""
import argparse, csv, io, os, re, shutil, sqlite3, sys, tempfile
from contextlib import closing

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# 내선은 2~4자리 숫자이고, 뒤에 숫자가 이어지지 않아야 한다.
# 숫자 뒤에 한글이 바로 붙어도 내선으로 본다(예: "777동아리").
EXT_RE = re.compile(r"^(\d{2,4})(?!\d)\s*(.*)$")
NAME_RE = re.compile(r"^([가-힣]+)(?:\((\d-\d)\))?\s*(.*)$")
COLS = ["이름", "학년-반", "내선번호", "담당", "소속(조직도 경로)", "상태 메시지"]


def split_label(label):
    """'(이름 …)꼬리'에서 (안쪽 글자, 꼬리)를 낸다. 괄호는 깊이로 짝을 맞춘다.
    사람 노드가 아니면 (None, None)."""
    if not label.startswith("("):
        return None, None
    depth = 0
    for i, ch in enumerate(label):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return label[1:i], label[i + 1:].strip()
    return None, None


def parse_inner(inner):
    """'이름(학년-반) 내선 담당' 꼴을 (이름, 학년-반, 내선, 담당)으로 나눈다.
    이름이 한글로 시작하지 않으면 None(계정 등 사람이 아닌 항목)."""
    m = NAME_RE.match(inner.strip())
    if not m:
        return None
    name, cls, rest = m.group(1), m.group(2) or "", m.group(3).strip()
    e = EXT_RE.match(rest)
    if e:
        return name, cls, e.group(1), e.group(2).strip()
    if rest.startswith("(") and rest.endswith(")"):      # 내선 없이 담당만: "이름 (담당)"
        return name, cls, "", rest[1:-1].strip()
    return name, cls, "", rest


def parse_tree(lines):
    """TSV 줄들에서 사람별 정보를 모은다.
    반환: (사람 dict들을 조직도 등장 순서로 담은 list, 경고 list)"""
    people, order, warnings = {}, [], []
    for line in lines:
        if not line.strip() or "\t" not in line:
            continue
        path, label = line.split("\t", 1)
        inner, tail = split_label(label)
        if inner is None:
            continue                                     # 그룹 노드
        parsed = parse_inner(inner)
        if parsed is None:
            continue                                     # 계정 등 사람이 아닌 항목
        name, cls, ext, duty = parsed
        parts = [p for p in path.split(" > ")[1:] if p]  # 최상위(학교 이름) 제외
        where = " > ".join(parts)
        if name not in people:
            people[name] = {"이름": name, "학년-반": cls, "내선번호": ext,
                            "담당": duty, "소속": [], "상태 메시지": tail}
            order.append(name)
        p = people[name]
        if (p["학년-반"], p["내선번호"], p["담당"]) != (cls, ext, duty):
            # 같은 사람이 여러 그룹에 나올 때 내선·담당이 다르면 빈 칸만 채우고 알린다
            warnings.append("같은 이름의 값이 다릅니다: %s" % name)
            p["학년-반"] = p["학년-반"] or cls
            p["내선번호"] = p["내선번호"] or ext
            p["담당"] = p["담당"] or duty
        if not p["상태 메시지"] and tail:
            p["상태 메시지"] = tail
        if where and where not in p["소속"]:
            p["소속"].append(where)
    for name in order:
        p = people[name]
        if p["상태 메시지"] == p["내선번호"]:          # 내선 숫자의 반복은 중복이라 뺀다
            p["상태 메시지"] = ""
    return [people[n] for n in order], warnings


def read_db_members(db_path):
    """DB 사본(tbl_member)을 읽어 {이름: (내선, 담당)}을 낸다. 사본 경로만 받는다."""
    members = {}
    with closing(sqlite3.connect(db_path)) as con:
        for (full,) in con.execute("select MemberName from tbl_member"):
            parsed = parse_inner(full or "")
            if parsed is None:
                continue
            name, _cls, ext, duty = parsed
            members.setdefault(name, (ext, duty))
    return members


def check_db(people, members):
    """조직도와 명단을 이름으로 맞춰 어긋난 곳을 보고한다. 목록은 바꾸지 않는다."""
    report = []
    tree_names = {p["이름"]: p for p in people}
    for name, p in tree_names.items():
        if name not in members:
            report.append("명단에 없음: %s" % name)
            continue
        ext, duty = members[name]
        if ext != p["내선번호"]:
            report.append("내선 다름: %s 조직도=%r 명단=%r" % (name, p["내선번호"], ext))
        d1, d2 = duty.strip("() "), p["담당"].strip("() ")
        if d1 and d2 and d1 != d2:
            report.append("담당 다름: %s 조직도=%r 명단=%r" % (name, p["담당"], duty))
    only_db = sorted(set(members) - set(tree_names))
    if only_db:
        report.append("명단에만 있음(조직도에 없음, 목록에서 뺌): %s" % ", ".join(only_db))
    return report


def write_csv(people, out_path):
    with io.open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(COLS)
        for p in people:
            w.writerow([p["이름"], p["학년-반"], p["내선번호"], p["담당"],
                        " / ".join(p["소속"]), p["상태 메시지"]])


def main(argv=None):
    ap = argparse.ArgumentParser(description="조직도 TSV → 내선번호 포함 CSV")
    ap.add_argument("tsv", help="cm_org_chart.ps1이 만든 TSV")
    ap.add_argument("--out", required=True, help="저장할 CSV 경로")
    ap.add_argument("--check-db", action="store_true", help="쿨메신저 명단 DB와 대조(읽기 전용)")
    a = ap.parse_args(argv)

    with io.open(a.tsv, encoding="utf-8") as f:
        people, warnings = parse_tree([l.rstrip("\r\n") for l in f])
    write_csv(people, a.out)

    print("인원 %d명 -> %s" % (len(people), a.out))
    no_ext = [p["이름"] for p in people if not p["내선번호"]]
    if no_ext:
        print("내선 번호 없음: %s" % ", ".join(no_ext))
    for w in warnings:
        print("경고:", w)

    if a.check_db:
        import cm_export
        tmp = tempfile.mkdtemp(prefix="cm_org_")
        try:
            snap = cm_export.copy_db(cm_export.find_db(), tmp)
            members = read_db_members(snap)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        report = check_db(people, members)
        print("명단 대조: %d명" % len(members))
        for r in report:
            print("  ", r)
        if not report:
            print("   어긋난 곳 없음")
    return 0


if __name__ == "__main__":
    # 파이프로 받을 때도 한글이 깨지지 않도록 출력 인코딩을 UTF-8로 고정한다.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
