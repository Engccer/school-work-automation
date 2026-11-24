"""comci.py 순수 함수 시험. 가짜 표만 쓰고 네트워크에 닿지 않는다.

  python -m unittest discover -s scripts/tests   (스킬 루트에서)
"""
import datetime as dt
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import comci  # noqa: E402

MEMO = """# 2026학년도 2학기 홍길동 시간표

월
  3 102
  4 302
수
  1 301
  4 101
---

# 다른 메모
시간표와 무관한 내용
"""


def cell(t, c="내용"):
    return {"t": t, "c": c}


def table(mon, wed):
    """월(16)·수(18) 두 열만 있는 가짜 학급 표. mon/wed: {교시: (글자, 클래스)}"""
    rows = [[cell("교시", "교시"), cell("월(16)", "제목"), cell("수(18)", "제목")]]
    for per in range(1, 8):
        m = mon.get(per, ("", "내용"))
        w = wed.get(per, ("", "변경"))
        rows.append([cell(f"{per}(09:00)", "교시"), cell(*m), cell(*w)])
    return rows


TABLES = {
    "1-1": table({1: ("국어\n이*수", "내용")}, {1: ("영어\n홍*동", "변경"), 2: ("음악\n박*호", "변경")}),
    "1-2": table({3: ("영어\n홍*동", "내용")}, {1: ("정보\n최*진\n정보실", "변경")}),
    "3-2": table({4: ("영어\n홍*동\n영어실", "내용")}, {1: ("수학\n이*수", "내용")}),
}
MON = dt.date(2026, 11, 16)
WED = dt.date(2026, 11, 18)


class PureTests(unittest.TestCase):
    def test_mask_name(self):
        self.assertEqual(comci.mask_name("홍길동"), "홍*동")
        self.assertEqual(comci.mask_name("남궁민수"), "남**수")
        self.assertEqual(comci.mask_name("이산"), "이*")

    def test_parse_memo_stops_at_rule(self):
        reg = comci.parse_memo(MEMO)
        self.assertEqual(reg, {"월": [(3, "1-2"), (4, "3-2")], "수": [(1, "3-1"), (4, "1-1")]})

    def test_parse_memo_without_section(self):
        self.assertEqual(comci.parse_memo("# 다른 메모\n월\n  3 102\n"), {})

    def test_day_column(self):
        self.assertEqual(comci.day_column(["교시", "월(16)", "수(18)"], WED), 2)
        self.assertIsNone(comci.day_column(["교시", "월(16)"], dt.date(2026, 11, 23)))

    def test_week_option(self):
        opts = [("1", "26-11-16 ~ 26-11-21"), ("2", "26-11-23 ~ 26-11-28")]
        self.assertEqual(comci.week_option(opts, dt.date(2026, 11, 25)), "2")
        self.assertIsNone(comci.week_option(opts, dt.date(2026, 12, 1)))

    def test_analyze_unchanged_day(self):
        res = comci.analyze(TABLES, MON, "홍*동", comci.parse_memo(MEMO))
        self.assertEqual([(x["period"], x["class"]) for x in res["mine"]], [(3, "1-2"), (4, "3-2")])
        self.assertEqual(res["mine"][1]["room"], "영어실")
        self.assertEqual(res["added"], [])
        self.assertEqual(res["removed"], [])
        self.assertEqual(res["changes"], [])

    def test_analyze_changed_day(self):
        res = comci.analyze(TABLES, WED, "홍*동", comci.parse_memo(MEMO))
        self.assertEqual(res["added"], [(1, "1-1")])
        self.assertEqual(res["removed"], [(1, "3-1"), (4, "1-1")])
        self.assertTrue(res["mine"][0]["changed"])
        self.assertEqual(len(res["changes"]), 3)       # 빈 변경 칸은 세지 않는다

    def test_analyze_missing_day(self):
        self.assertFalse(comci.analyze(TABLES, dt.date(2026, 11, 23), "홍*동", None)["found"])

    def test_all_empty_day(self):
        empty = {"1-1": table({}, {}), "1-2": table({}, {})}
        res = comci.analyze(empty, WED, "홍*동", comci.parse_memo(MEMO))
        self.assertTrue(res["all_empty"])
        text = comci.render(WED, res, teacher="홍길동", school="가상중학교", modified="",
                            fetched=dt.datetime(2026, 11, 16, 9, 0), note="재량휴업일", all_changes=False)
        self.assertIn("비어 있습니다", text)
        self.assertIn("비교하지 않았습니다", text)
        self.assertNotIn("빠진 수업", text)

    def test_render_has_weekdays_and_no_markdown(self):
        res = comci.analyze(TABLES, WED, "홍*동", comci.parse_memo(MEMO))
        text = comci.render(WED, res, teacher="홍길동", school="가상중학교", modified="2026-11-13 09:00:00",
                            fetched=dt.datetime(2026, 11, 16, 9, 5), note="", all_changes=True)
        self.assertTrue(text.startswith("2026-11-18(수) 컴시간 시간표"))
        self.assertIn("조회 2026-11-16(월) 09:05", text)
        self.assertIn("1교시 1-1 영어 (변경)", text)
        self.assertIn("빠진 수업: 1교시 3-1, 4교시 1-1", text)
        self.assertIn("변경 칸 3개(1학년 3개)", text)
        self.assertNotRegex(text, r"[*#]{2}|^- ")

    def test_calendar_note(self):
        rows = [{"날짜": "2026-11-19", "주요 일정": "대학수학능력시험(휴업일)", "비고": "휴일"}]
        self.assertEqual(comci.calendar_note(rows, dt.date(2026, 11, 19)), "대학수학능력시험(휴업일), 휴일")
        self.assertEqual(comci.calendar_note(rows, MON), "")

    def test_mask_name_empty(self):
        with self.assertRaises(ValueError):
            comci.mask_name("  ")

    def test_parse_date(self):
        today = dt.date(2026, 11, 24)
        self.assertEqual(comci.parse_date("2026-12-01", today), dt.date(2026, 12, 1))
        self.assertEqual(comci.parse_date("12-1", today), dt.date(2026, 12, 1))
        # 연말에 월-일만 넣으면 가까운 다음 해로
        self.assertEqual(comci.parse_date("01-04", dt.date(2026, 12, 29)), dt.date(2027, 1, 4))
        # 연초에 지난 12월을 넣으면 지난해로
        self.assertEqual(comci.parse_date("12-30", dt.date(2027, 1, 2)), dt.date(2026, 12, 30))
        for bad in ("2026-13-01", "13-40", "내일", "2026/12/01"):
            with self.assertRaises(ValueError):
                comci.parse_date(bad, today)

    def test_read_text_any_cp949(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / "memo.txt"
            f.write_bytes(MEMO.encode("cp949"))
            self.assertEqual(comci.parse_memo(comci.read_text_any(f))["월"], [(3, "1-2"), (4, "3-2")])

    def test_grade_empty_day(self):
        """3학년만 빈 날(3학년 고사일 등): 3학년 수업은 '빠진 수업'이 아니라 따로 적는다."""
        t = dict(TABLES)
        t["3-2"] = table({}, {})
        res = comci.analyze(t, MON, "홍*동", comci.parse_memo(MEMO))
        self.assertFalse(res["all_empty"])
        self.assertEqual(res["empty_grades"], ["3"])
        self.assertEqual(res["removed"], [])
        self.assertEqual(res["removed_blank"], [(4, "3-2")])
        text = comci.render(MON, res, teacher="홍길동", school="가상중학교", modified="",
                            fetched=dt.datetime(2026, 11, 16, 9, 0), note="", all_changes=False)
        self.assertIn("3학년은 전 학급 시간표가 비어 있습니다", text)
        self.assertIn("3학년 시간표가 비어 없어진 수업: 4교시 3-2", text)
        self.assertNotIn("빠진 수업:", text)
        self.assertNotIn("정규 시간표와 같습니다", text)


class CliTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(Path(comci.__file__)), *args],
                              capture_output=True, text=True, encoding="utf-8",
                              env={**__import__("os").environ, "PYTHONIOENCODING": "utf-8"})

    def test_from_json_saves_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "dump.json"
            src.write_text(json.dumps({"modified": "x", "tables": TABLES}, ensure_ascii=False), encoding="utf-8")
            memo = Path(tmp) / "memo.txt"
            memo.write_text(MEMO, encoding="utf-8")
            out = Path(tmp) / "out"
            r = self.run_cli("--from-json", str(src), "--date", "2026-11-18", "--teacher", "홍길동",
                             "--memo", str(memo), "--calendar", str(Path(tmp) / "none.csv"), "--out", str(out))
            self.assertEqual(r.returncode, 0, r.stderr)
            f = out / "2026-11-18(수) 컴시간 시간표.txt"
            self.assertIn("SAVED", r.stdout)
            self.assertIn("새로 생긴 수업: 1교시 1-1", f.read_text(encoding="utf-8"))

    def test_weekend_skips(self):
        r = self.run_cli("--date", "2026-11-21")
        self.assertEqual(r.returncode, 0)
        self.assertIn("SKIP 2026-11-21(토)", r.stdout)

    def test_bad_date_exit_2(self):
        r = self.run_cli("--date", "2026-02-30")
        self.assertEqual(r.returncode, 2)
        self.assertIn("ERROR 입력 오류", r.stderr)
        self.assertNotIn("Traceback", r.stderr)

    def test_unreadable_memo_warns_and_continues(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "dump.json"
            src.write_text(json.dumps({"modified": "x", "tables": TABLES}, ensure_ascii=False), encoding="utf-8")
            memo = Path(tmp) / "memo.txt"
            memo.write_bytes(b"\xff\xfe\x81\x81\xc8")     # UTF-8도 CP949도 아님
            r = self.run_cli("--from-json", str(src), "--date", "2026-11-18", "--teacher", "홍길동",
                             "--memo", str(memo), "--calendar", str(Path(tmp) / "none.csv"))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("WARN 정규 시간표", r.stderr)
            self.assertIn("읽지 못해 비교하지 않았습니다", r.stdout)

    def test_missing_school_or_teacher_exits_2(self):
        import os
        env = {k: v for k, v in os.environ.items() if not k.startswith("COMCI_")}
        r = subprocess.run([sys.executable, str(Path(comci.__file__)), "--date", "2026-11-18"],
                           capture_output=True, text=True, encoding="utf-8", env={**env, "PYTHONIOENCODING": "utf-8"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("COMCI_SCHOOL", r.stderr)


if __name__ == "__main__":
    unittest.main()
