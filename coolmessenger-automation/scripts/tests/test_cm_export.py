# -*- coding: utf-8 -*-
"""cm_export.py 시험. 가짜 DB fixture만 쓰고 실제 쿨메신저 DB는 건드리지 않는다.

    python -m unittest discover -s scripts/tests
"""
import os, shutil, sqlite3, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(os.path.dirname(HERE), "cm_export.py")
sys.path.insert(0, os.path.dirname(HERE))
import cm_export  # noqa: E402


class ParseAttachments(unittest.TestCase):
    def test_names_by_field_position(self):
        cases = {
            r"|1|1234|C:\Users\x\Desktop|a.hwp|0|": ["a.hwp"],
            # 경로 칸에 파일명이 붙어 있어도 경로를 이름으로 내지 않는다
            r"|1|1234|C:\Users\x\Desktop\a.hwp|a.hwp|0|": ["a.hwp"],
            # 크기 칸의 소수점을 이름으로 내지 않는다
            r"|1|12.5|C:\x|a.hwp|0|": ["a.hwp"],
            # 실제 DB 꼴: 크기 칸이 ;로 끝난다
            r"|1|1234;|C:\Users\x\Desktop|a.hwp|0|": ["a.hwp"],
            # 여러 건이면 (폴더|파일명|플래그)가 건수만큼 반복된다
            r"|2|10;20;|C:\d|a.hwp|0|C:\d|b 사진.jpg|0|": ["a.hwp", "b 사진.jpg"],
            r"|3|1;2;3;|C:\d|a.hwp|0|C:\e|b.pdf|0|C:\f|c.xlsx|0|": ["a.hwp", "b.pdf", "c.xlsx"],
            # 앞쪽 빈 칸이 있어도 양끝 구분자 하나씩만 벗긴다(플래그를 이름으로 내지 않는다)
            r"||10;|C:\d|a.hwp|0|": ["a.hwp"],
            "": [],
            None: [],
        }
        for raw, want in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(cm_export.parse_attachments(raw), want)


def make_db(path, corrupt=False):
    if corrupt:
        with open(path, "wb") as f:
            f.write(b"not a sqlite database" * 100)
        return
    con = sqlite3.connect(path)
    con.execute("pragma journal_mode=wal")
    con.execute("create table tbl_recv (Sender, Title, MessageText, ReceiveDate, FilePath, IsUnRead)")
    con.execute("create table tbl_send (Receiver, Title, MessageText, SendDate, FilePath)")
    con.execute("insert into tbl_recv values (?,?,?,?,?,?)",
                ("가나다(1학년부)", "회신", "1. 예\n가나다님이 보낸글 >> 2026/09/22\n원문",
                 "2026/09/22 10:00:00", r"|1|10;|C:\d|a.hwp|0|", 0))
    con.execute("insert into tbl_send values (?,?,?,?,?)",
                ("가나다(1학년부)", "안내", "본문", "2026/09/22 09:00:00", ""))
    con.commit()
    # WAL 파일이 남은 상태(앱이 열고 있는 상태)를 흉내 내려고 닫지 않고 둔다
    return con


class TempCopyRemoved(unittest.TestCase):
    """DB 사본(교직원 메시지 전체)을 %TEMP%에 남기지 않는다."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="cmtest_")
        self.local = os.path.join(self.root, "local")
        self.temp = os.path.join(self.root, "temp")
        self.memo = os.path.join(self.local, "CoolMessenger", "Memo")
        os.makedirs(self.memo)
        os.makedirs(self.temp)
        self.con = None

    def tearDown(self):
        if self.con:
            self.con.close()
        shutil.rmtree(self.root, ignore_errors=True)

    def run_export(self, *args):
        env = {
            "SYSTEMROOT": os.environ.get("SYSTEMROOT", ""),
            "LOCALAPPDATA": self.local,
            "TEMP": self.temp, "TMP": self.temp, "TMPDIR": self.temp,
            "PYTHONIOENCODING": "utf-8",
        }
        return subprocess.run([sys.executable, SCRIPT] + list(args), env=env,
                              capture_output=True, encoding="utf-8", errors="replace",
                              cwd=self.root)

    def test_success_leaves_no_copy(self):
        self.con = make_db(os.path.join(self.memo, "user.udb"))
        out = os.path.join(self.root, "out.csv")
        for extra in ([], ["--sent", "--format", "json"]):
            with self.subTest(extra=extra):
                p = self.run_export("--out", out, *extra)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertIn("1건", p.stderr)
                self.assertEqual(os.listdir(self.temp), [])

    def test_failure_leaves_no_copy(self):
        make_db(os.path.join(self.memo, "user.udb"), corrupt=True)
        p = self.run_export("--out", os.path.join(self.root, "out.csv"))
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(os.listdir(self.temp), [])

    def test_midloop_failure_leaves_no_copy(self):
        # 순회 도중 예외(뒤에 읽을 행이 남아 커서가 열린 채)에도 사본이 잠겨 남지 않는다
        self.con = make_db(os.path.join(self.memo, "user.udb"))
        self.con.execute("insert into tbl_recv values (?,?,?,?,?,?)",
                         ("가", "t", b"\x00blob", "2026/09/01 10:00:00", "", 0))
        self.con.commit()
        p = self.run_export("--contains", "x", "--out", os.path.join(self.root, "out.csv"))
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(os.listdir(self.temp), [])

    def test_copy_failure_leaves_no_copy(self):
        self.con = make_db(os.path.join(self.memo, "user.udb"))
        self.con.close(); self.con = None
        for suffix in ("-wal", "-shm"):
            p = os.path.join(self.memo, "user.udb" + suffix)
            if os.path.exists(p):
                os.remove(p)
        os.mkdir(os.path.join(self.memo, "user.udb-wal"))   # 복사 도중 실패하게 만든다
        p = self.run_export("--out", os.path.join(self.root, "out.csv"))
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(os.listdir(self.temp), [])


if __name__ == "__main__":
    unittest.main()
