"""선택 도구 부재·사용자 지정 변환·부분 실패의 동작을 검증한다."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "extract_attachments.py"
spec = importlib.util.spec_from_file_location("extract", SCRIPT)
extract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extract)


class ExtractionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="alim_optional_")
        self.root = Path(self.tmp.name)
        self.src = self.root / "첨부 폴더"
        self.out = self.root / "출력 폴더"
        self.src.mkdir()
        self.out.mkdir()
        self.env = patch.dict(os.environ, {"ALIM_HWP_CMD": "", "ALIM_HWPX_CMD": ""})
        self.env.start()
        self.legacy = patch.multiple(extract, HWPX_EDIT=self.root/"absent.py", HWP2HWPX=self.root/"absent.bat")
        self.legacy.start()

    def tearDown(self):
        self.legacy.stop()
        self.env.stop()
        self.tmp.cleanup()

    def run_extract(self):
        output = io.StringIO()
        with patch.object(sys, "argv", [str(SCRIPT), str(self.src), str(self.out)]), contextlib.redirect_stdout(output):
            extract.main()
        return output.getvalue()

    def make_odt(self):
        p = self.src / "첨부2_안내.odt"
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("content.xml", '<root xmlns:t="urn:oasis:names:tc:opendocument:xmlns:text:1.0"><t:p>전달사항 본문</t:p></root>')
        return p

    def command(self, code):
        script = self.root / "도구 파일.py"
        script.write_text(code, encoding="utf-8")
        return json.dumps([sys.executable, str(script), "{input}", "{output}"])

    def test_missing_tools_keep_originals_and_process_other_formats(self):
        hwp = self.src / "첨부1_문서.hwp"
        hwpx = self.src / "첨부3_문서.hwpx"
        hwp.write_bytes(b"original-hwp")
        hwpx.write_bytes(b"original-hwpx")
        self.make_odt()
        with patch.object(extract.importlib, "import_module", side_effect=ImportError):
            output = self.run_extract()
        self.assertIn("SKIP 첨부1_", output)
        self.assertIn("SKIP 첨부3_", output)
        self.assertIn("OK 첨부2_", output)
        self.assertEqual(hwp.read_bytes(), b"original-hwp")
        self.assertEqual(hwpx.read_bytes(), b"original-hwpx")
        self.assertEqual(len(list(self.out.glob("*.md"))), 1)
        self.assertIn("전달사항", next(self.out.glob("*.md")).read_text(encoding="utf-8"))

    def test_custom_tool_receives_unicode_spaces_and_shell_characters_as_arguments(self):
        src = self.src / "첨부1_공백 & 괄호 (자료).hwp"
        src.write_text("원문 123", encoding="utf-8")
        os.environ["ALIM_HWP_CMD"] = self.command(
            "import sys\nfrom pathlib import Path\n"
            "Path(sys.argv[2]).write_text(Path(sys.argv[1]).read_text(encoding='utf-8'), encoding='utf-8')\n")
        output = self.run_extract()
        self.assertIn("WARN 첨부1_", output)
        self.assertEqual((self.out/(src.name+".md")).read_text(encoding="utf-8"), "원문 123")

    def test_failed_tool_removes_partial_output_and_continues(self):
        src = self.src / "첨부1_실패.hwp"
        src.write_bytes(b"original")
        self.make_odt()
        os.environ["ALIM_HWP_CMD"] = self.command(
            "import sys\nfrom pathlib import Path\n"
            "Path(sys.argv[2]).write_text('불완전한 내용', encoding='utf-8')\nsys.exit(7)\n")
        output = self.run_extract()
        self.assertIn("FAIL 첨부1_", output)
        self.assertIn("종료 코드 7", output)
        self.assertFalse((self.out/(src.name+".md")).exists())
        self.assertIn("OK 첨부2_", output)

    def test_empty_success_is_failure(self):
        src = self.src / "첨부1_빈문서.hwp"
        src.write_bytes(b"original")
        os.environ["ALIM_HWP_CMD"] = self.command(
            "import sys\nfrom pathlib import Path\nPath(sys.argv[2]).write_text('', encoding='utf-8')\n")
        self.assertIn("FAIL 첨부1_", self.run_extract())
        self.assertFalse((self.out/(src.name+".md")).exists())

    def test_invalid_custom_config_is_reported_without_fallback(self):
        src = self.src / "첨부1_설정.hwpx"
        src.write_bytes(b"original")
        os.environ["ALIM_HWPX_CMD"] = "not-json"
        self.assertIn("FAIL 첨부1_", self.run_extract())
        with patch.object(extract.importlib, "import_module", side_effect=ImportError):
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream):
                extract.check_tools()
        caps = json.loads(stream.getvalue())
        self.assertEqual(caps["hwpx"]["state"], "invalid")
        self.assertEqual(caps["hwp"]["state"], "missing")

    def test_stale_output_removed_when_tool_missing(self):
        src = self.src / "첨부1_과거.hwp"
        src.write_bytes(b"original")
        stale = self.out / (src.name+".md")
        stale.write_text("옛 본문", encoding="utf-8")
        self.assertIn("SKIP 첨부1_", self.run_extract())
        self.assertFalse(stale.exists())

    def test_hwpx_direct_engine_preserves_warnings(self):
        src = self.src / "첨부1_안내.hwpx"
        src.write_bytes(b"placeholder")
        from types import SimpleNamespace
        result = SimpleNamespace(markdown="본문과 표", warnings=["본문 이미지 1개", "숫자 누락 확인"])
        engine = SimpleNamespace(convert=lambda _: result)
        with patch.object(extract.importlib, "import_module", return_value=engine):
            output = self.run_extract()
        self.assertIn("WARN 첨부1_", output)
        self.assertIn("본문 이미지 1개 / 숫자 누락 확인", output)
        self.assertEqual((self.out/(src.name+".md")).read_text(encoding="utf-8"), "본문과 표")

    def test_real_hwpx_engine_without_skill(self):
        try:
            import hwpx_tomd
        except ImportError:
            self.skipTest("선택 엔진 미설치")
        src = self.src / "첨부1_표.hwpx"
        xml = '<hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph"><hp:p><hp:run><hp:t>알림장 본문 123</hp:t></hp:run></hp:p></hs:sec>'
        with zipfile.ZipFile(src, "w") as z:
            z.writestr("Contents/section0.xml", xml)
        output = self.run_extract()
        self.assertNotIn("FAIL", output)
        self.assertIn("알림장 본문 123", (self.out/(src.name+".md")).read_text(encoding="utf-8"))

    def test_cli_check_without_site_packages_needs_no_external_skill(self):
        env = {**os.environ, "HWPX_AUTOMATION_DIR": str(self.root/"absent")}
        r = subprocess.run([sys.executable, "-S", str(SCRIPT), "--check-tools"],
                           capture_output=True, encoding="utf-8", env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        caps = json.loads(r.stdout)
        self.assertEqual(caps["hwpx"]["state"], "missing")
        self.assertEqual(caps["hwp"]["state"], "missing")


if __name__ == "__main__":
    unittest.main()

