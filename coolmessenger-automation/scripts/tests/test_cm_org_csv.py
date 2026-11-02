# -*- coding: utf-8 -*-
"""cm_org_csv.py 시험. 가짜 이름·가짜 TSV·가짜 DB fixture만 쓴다.
실제 쿨메신저 DB와 조직도는 건드리지 않는다.

    python -m unittest discover -s scripts/tests
"""
import csv, io, os, shutil, sqlite3, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(os.path.dirname(HERE), "cm_org_csv.py")
sys.path.insert(0, os.path.dirname(HERE))
import cm_org_csv  # noqa: E402

FAKE_TSV = [
    "학교\t교장 교감",                                   # 그룹
    "학교 > 교장 교감\t(가나다 101 교장)",
    "학교 > 교무부\t(라마바(1-2) 111 교무부장)111",     # 꼬리가 내선과 같으면 뺀다
    "학교 > 교과 > 영어\t(라마바(1-2) 111 교무부장)111",  # 같은 사람, 다른 그룹
    "학교 > 상담\t(사아자 (음악))",                      # 내선 없이 담당만
    "학교 > 상담\t(차카타 777동아리)상태 문구",      # 내선 바로 뒤에 한글
    "학교 > 상담\t(sysop)",                             # 계정만 있는 항목
    "학교 > 상담\t(파하가 333)",                        # 담당 없이 내선만
]


class SplitAndParse(unittest.TestCase):
    def test_split_label_matches_nested_parentheses(self):
        self.assertEqual(cm_org_csv.split_label("(라마바(1-2) 111 교무부장)111"),
                         ("라마바(1-2) 111 교무부장", "111"))
        self.assertEqual(cm_org_csv.split_label("(하나둘 (영어))"), ("하나둘 (영어)", ""))
        self.assertEqual(cm_org_csv.split_label("교무부"), (None, None))

    def test_parse_inner_variants(self):
        cases = {
            "가나다(1-2) 111 기획": ("가나다", "1-2", "111", "기획"),
            "가나다 101": ("가나다", "", "101", ""),
            "사아자 (음악)": ("사아자", "", "", "음악"),
            "차카타 333 기획 월,수": ("차카타", "", "333", "기획 월,수"),
            # 내선 숫자 바로 뒤에 한글이 붙어도 내선으로 본다(예전에 놓친 경우)
            "파하가 777동아리": ("파하가", "", "777", "동아리"),
            "나다라(3-4) 555": ("나다라", "3-4", "555", ""),
            "sysop": None,
        }
        for raw, want in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(cm_org_csv.parse_inner(raw), want)


class ParseTree(unittest.TestCase):
    def setUp(self):
        self.people, self.warnings = cm_org_csv.parse_tree(FAKE_TSV)
        self.by_name = {p["이름"]: p for p in self.people}

    def test_people_in_tree_order_and_groups_skipped(self):
        self.assertEqual([p["이름"] for p in self.people],
                         ["가나다", "라마바", "사아자", "차카타", "파하가"])

    def test_merged_paths_and_tail_dropped_when_equal_to_ext(self):
        p = self.by_name["라마바"]
        self.assertEqual((p["학년-반"], p["내선번호"], p["담당"]), ("1-2", "111", "교무부장"))
        self.assertEqual(p["소속"], ["교무부", "교과 > 영어"])
        self.assertEqual(p["상태 메시지"], "")

    def test_ext_missing_and_status_kept(self):
        self.assertEqual(self.by_name["사아자"]["내선번호"], "")
        self.assertEqual(self.by_name["사아자"]["담당"], "음악")
        p = self.by_name["차카타"]
        self.assertEqual((p["내선번호"], p["담당"], p["상태 메시지"]), ("777", "동아리", "상태 문구"))

    def test_account_only_row_skipped(self):
        self.assertNotIn("sysop", self.by_name)

    def test_conflicting_values_warn_and_keep_first(self):
        tsv = FAKE_TSV + ["학교 > 교무부\t(가나다 102 교장)"]
        people, warnings = cm_org_csv.parse_tree(tsv)
        self.assertEqual(people[0]["내선번호"], "101")
        self.assertTrue(any("가나다" in w for w in warnings))


class WriteAndDb(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="cmorg_test_")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_csv_has_bom_header_and_six_columns(self):
        people, _ = cm_org_csv.parse_tree(FAKE_TSV)
        out = os.path.join(self.root, "org.csv")
        cm_org_csv.write_csv(people, out)
        with open(out, "rb") as f:
            self.assertEqual(f.read(3), b"\xef\xbb\xbf")
        with io.open(out, encoding="utf-8-sig", newline="") as f:
            rows = list(csv.reader(f))
        self.assertEqual(rows[0], cm_org_csv.COLS)
        self.assertTrue(all(len(r) == 6 for r in rows))
        self.assertEqual(len(rows) - 1, 5)

    def make_members_db(self):
        path = os.path.join(self.root, "members.udb")
        con = sqlite3.connect(path)
        con.execute("create table tbl_member (K_MemberID INTEGER PRIMARY KEY, MemberID TEXT, MemberName TEXT)")
        rows = ["가나다 101 교장", "라마바(1-2) 999 교무부장", "사아자 (음악)", "마바사 444 행정",
                "sysop"]
        for i, name in enumerate(rows, 1):
            con.execute("insert into tbl_member values (?,?,?)", (i, "id%d" % i, name))
        con.commit()
        con.close()
        return path

    def test_db_cross_check_reports_without_changing_people(self):
        people, _ = cm_org_csv.parse_tree(FAKE_TSV)
        before = [dict(p) for p in people]
        members = cm_org_csv.read_db_members(self.make_members_db())
        report = cm_org_csv.check_db(people, members)
        self.assertEqual(people, before)
        text = "\n".join(report)
        self.assertIn("내선 다름: 라마바", text)
        self.assertIn("명단에 없음: 차카타", text)
        self.assertIn("명단에 없음: 파하가", text)
        self.assertIn("명단에만 있음", text)
        self.assertIn("마바사", text)
        self.assertNotIn("sysop", text)

    def test_cli_writes_csv_from_tsv(self):
        tsv = os.path.join(self.root, "tree.tsv")
        with io.open(tsv, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(FAKE_TSV) + "\n")
        out = os.path.join(self.root, "out.csv")
        r = subprocess.run([sys.executable, SCRIPT, tsv, "--out", out],
                           capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(r.returncode, 0, r.stderr)
        with io.open(out, encoding="utf-8-sig", newline="") as f:
            self.assertEqual(len(list(csv.reader(f))) - 1, 5)


if __name__ == "__main__":
    unittest.main()
