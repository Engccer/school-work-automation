"""나이스 급여명세서 xlsx -> CSV (구분,항목,금액,계산근거) + 검산."""
import csv, re, sys, warnings
import openpyxl

warnings.filterwarnings("ignore")
src, dst = sys.argv[1], sys.argv[2]
ws = openpyxl.load_workbook(src, data_only=True).active
rows = [[(c.column, c.value) for c in r if c.value not in (None, "")] for r in ws.iter_rows()]

ym = name = None
for r in rows:
    for _, v in r:
        m = re.search(r"급여지급년월\s*(\d{4})\s*년\s*(\d{2})\s*월\s*성명\s*(\S+)", str(v))
        if m and not ym:
            ym, name = f"{m[1]}-{m[2]}", m[3]

# 세부내역 헤더(급여내역/세금내역/공제내역) 구간
hi = next(i for i, r in enumerate(rows) if {"급여내역", "세금내역", "공제내역"} <= {v for _, v in r})
starts = sorted((col, v) for col, v in rows[hi] if v in ("급여내역", "세금내역", "공제내역"))
zone = lambda col: [z for s, z in starts if s <= col][-1]
items = {"급여내역": [], "세금내역": [], "공제내역": []}
totals, net = {}, None
for r in rows[hi + 1:]:
    labels = [(c, v) for c, v in r if isinstance(v, str)]
    if any(v == "실수령액" for _, v in labels):
        net = int(next(v for _, v in r if isinstance(v, (int, float))))
        break
    buf = {}
    for c, v in r:
        buf.setdefault(zone(c), []).append(v)
    for z, vals in buf.items():
        lab = next((v for v in vals if isinstance(v, str)), None)
        amt = next((v for v in vals if isinstance(v, (int, float))), None)
        if lab is None or amt is None:
            continue
        if lab.endswith("총액"):
            totals[lab] = int(amt)
        else:
            items[z].append((lab, int(amt)))

basis = {}
for r in rows:
    labs = [v for _, v in r if isinstance(v, str)]
    if len(labs) >= 2 and ("[당월]" in labs[-1] or "기준연도" in labs[-1]):
        basis.setdefault(labs[0], " ".join(labs[-1].split()))

out = [["급여지급년월", ym], ["성명", name], [], ["구분", "항목", "금액", "계산근거"]]
for z, g in (("급여내역", "급여"), ("세금내역", "세금"), ("공제내역", "공제")):
    out += [[g, lab, amt, basis.get(lab, "")] for lab, amt in items[z]]
for k in ("급여총액", "세금총액", "공제총액"):
    out.append(["합계", k, totals[k], ""])
out.append(["합계", "실수령액", net, ""])
with open(dst, "w", newline="", encoding="utf-8-sig") as f:
    csv.writer(f).writerows(out)

s = {z: sum(a for _, a in items[z]) for z in items}
checks = [
    ("급여 합계", s["급여내역"], totals["급여총액"]),
    ("세금 합계", s["세금내역"], totals["세금총액"]),
    ("공제 합계", s["공제내역"], totals["공제총액"]),
    ("실수령액", totals["급여총액"] - totals["세금총액"] - totals["공제총액"], net),
]
ok = True
for n, a, b in checks:
    print(f"{n}: {a} vs {b} {'OK' if a == b else 'MISMATCH'}")
    ok &= a == b
print("ym", ym, "| basis", sum(1 for z in items for l, _ in items[z] if l in basis))
sys.exit(0 if ok else 1)
