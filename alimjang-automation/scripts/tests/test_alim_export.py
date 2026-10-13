"""alim_export.py 밀폐 시험. 서버·실제 DB를 건드리지 않는다.

가짜 dbfread(JSON 파일을 DBF처럼 읽음)를 임시 폴더에 만들고, `--src`로 가짜 DB 폴더를 주며,
PROJECT_ROOT·오늘 날짜·임시 폴더를 바꿔 끼운다.
실행(스킬 루트에서): python -m unittest discover -s scripts/tests -p "test_*.py"
"""
import contextlib
import datetime
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import types
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "alim_export.py"

FAKE_DBFREAD = '''
import datetime, json
class DBF:
    def __init__(self, path, encoding=None, char_decode_errors=None):
        self.path = path
    def __iter__(self):
        with open(self.path, encoding="utf-8") as f:
            rows = json.load(f)
        for r in rows:
            r = dict(r)
            if r.get("ALDATE"):
                r["ALDATE"] = datetime.date.fromisoformat(r["ALDATE"])
            yield r
'''


def row(date, bodies=None, atts=None):
    r = {"ALDATE": date, "ALJOGI": ""}
    for i in range(1, 21):
        r[f"ALME{i:02d}"] = (bodies or {}).get(i, "")
    for i in range(1, 6):
        f, dp = (atts or {}).get(i, ("", ""))
        r[f"ALHWP{i}"] = f
        r[f"ALID0{i}"] = dp
    return r


class AlimExportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="alimtest_"))
        fake = self.tmp / "fakemods"
        fake.mkdir()
        (fake / "dbfread.py").write_text(FAKE_DBFREAD, encoding="utf-8")
        self._saved_path = list(sys.path)
        self._saved_mod = sys.modules.pop("dbfread", None)
        sys.path.insert(0, str(fake))
        self._saved_tempdir = tempfile.tempdir
        tempfile.tempdir = str(self.tmp)
        self._saved_out = os.environ.get("ALIM_OUT_DIR")
        os.environ["ALIM_OUT_DIR"] = "{학년도} 업무/4. 교무/알림장"  # 기본값과 무관하게 시험

        spec = importlib.util.spec_from_file_location("alim_export_under_test", SCRIPT)
        self.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.m)
        self.root = self.tmp / "proj"
        self.root.mkdir()
        self.m.PROJECT_ROOT = self.root
        self.m.SERVER = str(self.tmp / "no-server")  # 실수로 서버 경로를 쓰면 실패하도록

        self.src = self.tmp / "db"
        self.src.mkdir()
        (self.src / "AGICHO.DBF").write_text(json.dumps([
            {"ALID": "4", "ALBU": "연구부"}, {"ALID": "7", "ALBU": "생활교육부"},
        ], ensure_ascii=False), encoding="utf-8")

    def tearDown(self):
        sys.path[:] = self._saved_path
        sys.modules.pop("dbfread", None)
        if self._saved_mod is not None:
            sys.modules["dbfread"] = self._saved_mod
        tempfile.tempdir = self._saved_tempdir
        if self._saved_out is None:
            os.environ.pop("ALIM_OUT_DIR", None)
        else:
            os.environ["ALIM_OUT_DIR"] = self._saved_out
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_rows(self, rows):
        (self.src / "ALIM.DBF").write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")

    def run_main(self, today, *args):
        real = datetime.date

        class FakeDate(real):
            @classmethod
            def today(cls):
                return cls(today.year, today.month, today.day)

        self.m.dt = types.SimpleNamespace(date=FakeDate, timedelta=datetime.timedelta)
        argv = ["alim_export.py", "--src", str(self.src), *args]
        buf = io.BytesIO()
        out = io.TextIOWrapper(buf, encoding="utf-8")  # --stdout 은 sys.stdout.buffer 에 쓴다
        saved = sys.argv
        sys.argv = argv
        try:
            with contextlib.redirect_stdout(out):
                self.m.main()
        finally:
            sys.argv = saved
            out.flush()
        return buf.getvalue().decode("utf-8")

    def alim(self, sy):
        return self.root / f"{sy} 업무" / "4. 교무" / "알림장"

    def test_date_export_goes_to_target_date_school_year(self):
        (self.src / "H02271.PDF").write_bytes(b"%PDF-fake")
        self.write_rows([row("2026-02-27", {4: "연구부 안내"}, {1: ("H02271.PDF", "4")})])
        self.run_main(datetime.date(2026, 3, 5), "--date", "2026-02-27")
        day = self.alim(2025) / "2026-02-27(금)"
        self.assertTrue((day / "2026-02-27(금) 알림장 전달사항.txt").is_file())
        self.assertTrue((day / "첨부1_연구부_H02271.PDF").is_file())
        self.assertFalse((self.root / "2026 업무").exists())

    def test_range_export_splits_by_each_date_school_year(self):
        self.write_rows([row("2026-02-27", {4: "가"}), row("2026-03-02", {4: "나"})])
        self.run_main(datetime.date(2026, 3, 5), "--from", "2026-02-27", "--to", "2026-03-02")
        self.assertTrue((self.alim(2025) / "2026-02-27(금)").is_dir())
        self.assertTrue((self.alim(2026) / "2026-03-02(월)").is_dir())

    def test_search_goes_to_run_date_school_year(self):
        self.write_rows([row("2026-02-27", {7: "방과후 운영"})])
        self.run_main(datetime.date(2026, 3, 5), "--search", "방과후",
                      "--from", "2026-02-20", "--to", "2026-03-04")
        hits = list((self.alim(2026) / "검색").glob("*.txt"))
        self.assertEqual(len(hits), 1)
        self.assertFalse((self.root / "2025 업무").exists())

    def test_dept_list_goes_to_run_date_school_year(self):
        self.write_rows([row("2026-02-27", {7: "상담 안내"})])
        self.run_main(datetime.date(2026, 3, 5), "--dept", "생활교육부", "--list",
                      "--from", "2026-02-20", "--to", "2026-03-04")
        self.assertEqual(len(list((self.alim(2026) / "검색").glob("*.txt"))), 1)
        self.assertFalse((self.root / "2025 업무").exists())

    def test_explicit_out_is_kept_for_search(self):
        self.write_rows([row("2026-02-27", {7: "방과후 운영"})])
        out = self.tmp / "out"
        self.run_main(datetime.date(2026, 3, 5), "--search", "방과후",
                      "--from", "2026-02-20", "--to", "2026-03-04", "--out", str(out))
        self.assertEqual(len(list((out / "검색").glob("*.txt"))), 1)
        self.assertFalse((self.root / "2026 업무").exists())

    def test_explicit_out_is_kept_for_date_export(self):
        self.write_rows([row("2026-02-27", {4: "가"})])
        out = self.tmp / "out"
        self.run_main(datetime.date(2026, 3, 5), "--date", "2026-02-27", "--out", str(out))
        self.assertTrue((out / "2026-02-27(금)").is_dir())
        self.assertFalse((self.root / "2025 업무").exists())

    def test_out_dir_env_absolute_with_school_year(self):
        self.write_rows([row("2026-02-27", {4: "가"})])
        os.environ["ALIM_OUT_DIR"] = str(self.tmp / "out" / "{학년도}")
        self.run_main(datetime.date(2026, 3, 5), "--date", "2026-02-27")
        self.assertTrue((self.tmp / "out" / "2025" / "2026-02-27(금)").is_dir())

    def test_default_out_without_env(self):
        self.write_rows([row("2026-03-02", {4: "가"})])
        os.environ.pop("ALIM_OUT_DIR", None)
        self.run_main(datetime.date(2026, 3, 5), "--date", "2026-03-02")
        base = self.root / self.m.DEFAULT_OUT.replace("{학년도}", "2026")
        self.assertTrue((base / "2026-03-02(월)").is_dir())

    def test_year_range_ends_on_last_day_of_february(self):
        self.write_rows([row("2028-02-29", {7: "윤일 방과후"}), row("2027-02-28", {7: "평년 방과후"})])
        for year, last in ((2027, "2028-02-29"), (2026, "2027-02-28")):
            with self.subTest(year=year):
                out = self.run_main(datetime.date(2026, 10, 8), "--year", str(year),
                                    "--search", "방과후", "--stdout")
                self.assertIn(f"{year}-03-01~{last}", out)
                self.assertIn("모두 1건입니다.", out)


if __name__ == "__main__":
    unittest.main()
