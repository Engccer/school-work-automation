r"""알림장 날짜 폴더의 첨부(첨부*)를 형식별로 텍스트(.md)로 뽑는다. 원본 폴더에는 아무것도 쓰지 않는다.

사용(스킬 루트에서): python scripts/extract_attachments.py "<알림장 날짜 폴더>" "<출력 폴더>"
출력: <출력 폴더>/<첨부 파일명>.md, 그리고 결과 요약 한 줄씩(OK/WARN/FAIL)을 표준출력으로.

형식별 방법
  HWPX  hwpx-automation(HWPX_AUTOMATION_DIR 또는 같은 스킬 폴더)의 hwpx_edit.py --to-md
  HWP   hwpx-automation 의 convert/hwp2hwpx.bat(JDK 21)로 HWPX 변환 후 위와 같이
  ODT   content.xml 의 문단·표를 직접 파싱
  PDF   pdftotext -layout -enc UTF-8 (PATH 의 pdftotext, 없으면 Git for Windows 동봉본)
  XLSX  openpyxl 로 시트별 셀 값
  기타(XLS 등)  추출 불가로 표시
"""
import os
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# hwpx-automation 위치: 환경 변수, 없으면 이 스킬과 같은 스킬 폴더
HWPX_DIR = Path(os.environ.get("HWPX_AUTOMATION_DIR") or Path(__file__).resolve().parents[2] / "hwpx-automation")
HWPX_EDIT = HWPX_DIR / "hwpx_edit.py"
HWP2HWPX = HWPX_DIR / "convert" / "hwp2hwpx.bat"
PDFTOTEXT_CANDIDATES = [shutil.which("pdftotext"), r"C:\Program Files\Git\mingw64\bin\pdftotext.exe"]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, env={**os.environ, "PYTHONIOENCODING": "utf-8"})
    dec = lambda b: b.decode("utf-8", "replace") if b else ""
    return r.returncode, dec(r.stdout), dec(r.stderr)


def hwpx_to_md(src: Path, out: Path):
    code, so, se = run([sys.executable, str(HWPX_EDIT), str(src), "--to-md", "-o", str(out)])
    if code != 0 or not out.exists():
        raise RuntimeError((se or so).strip()[-300:])
    m = re.search(r"이미지 (\d+)개", se + so)
    return f"본문 이미지 {m.group(1)}개(이미지 속 글자는 추출 안 됨)" if m else ""


def hwp_to_md(src: Path, out: Path, work: Path):
    tmp_hwp = work / "_in.hwp"
    tmp_hwpx = work / "_in.hwpx"
    try:
        shutil.copyfile(src, tmp_hwp)
        code, so, se = run(["cmd", "/c", str(HWP2HWPX), str(tmp_hwp), str(tmp_hwpx)])
        if not tmp_hwpx.exists():
            raise RuntimeError("HWP→HWPX 변환 실패: " + (se or so).strip()[-300:])
        return hwpx_to_md(tmp_hwpx, out)
    finally:
        tmp_hwp.unlink(missing_ok=True)
        tmp_hwpx.unlink(missing_ok=True)


def odt_to_md(src: Path, out: Path):
    ns = {"text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
          "table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0"}
    T = "{%s}" % ns["text"]
    TB = "{%s}" % ns["table"]
    root = ET.fromstring(zipfile.ZipFile(src).read("content.xml"))

    def text_of(el):
        parts = [el.text or ""]
        for ch in el:
            if ch.tag == T + "s":
                parts.append(" " * int(ch.get(T + "c", "1")))
            elif ch.tag in (T + "tab",):
                parts.append("\t")
            elif ch.tag == T + "line-break":
                parts.append("\n")
            else:
                parts.append(text_of(ch))
            parts.append(ch.tail or "")
        return "".join(parts)

    lines = []

    def walk(el):
        for ch in el:
            if ch.tag in (T + "p", T + "h"):
                s = text_of(ch).strip()
                if s:
                    lines.append(s)
            elif ch.tag == TB + "table":
                for row in ch.iter(TB + "table-row"):
                    cells = [" ".join(text_of(p).strip() for p in c.iter(T + "p")).strip()
                             for c in row.findall(TB + "table-cell")]
                    if any(cells):
                        lines.append("| " + " | ".join(cells) + " |")
            else:
                walk(ch)

    walk(root)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return ""


def pdf_to_md(src: Path, out: Path):
    exe = next((p for p in PDFTOTEXT_CANDIDATES if p and Path(p).exists()), None)
    if not exe:
        raise RuntimeError("pdftotext 없음")
    code, so, se = run([exe, "-layout", "-enc", "UTF-8", str(src), str(out)])
    if code != 0 or not out.exists():
        raise RuntimeError(se.strip()[-300:])
    if len(out.read_text(encoding="utf-8", errors="replace").strip()) < 20:
        return "텍스트 레이어가 거의 없음(스캔 PDF일 수 있음, Read 도구로 직접 확인 필요)"
    return ""


def xlsx_to_md(src: Path, out: Path):
    import openpyxl
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    lines = []
    for ws in wb.worksheets:
        lines.append(f"## 시트: {ws.title}")
        for row in ws.iter_rows(values_only=True):
            vals = ["" if v is None else str(v).strip() for v in row]
            if any(vals):
                while vals and not vals[-1]:
                    vals.pop()
                lines.append("| " + " | ".join(vals) + " |")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return ""


def main():
    if len(sys.argv) != 3:
        sys.exit('사용: python scripts/extract_attachments.py "<알림장 날짜 폴더>" "<출력 폴더>"')
    folder, outdir = Path(sys.argv[1]), Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in folder.glob("첨부*") if p.is_file())
    if not files:
        print("NONE 첨부 없음")
        return
    for src in files:
        out = outdir / (src.name + ".md")
        out.unlink(missing_ok=True)  # 지난 실행의 결과로 성공을 오판하지 않게
        ext = src.suffix.lower()
        try:
            if ext == ".hwpx":
                note = hwpx_to_md(src, out)
            elif ext == ".hwp":
                note = hwp_to_md(src, out, outdir)
            elif ext == ".odt":
                note = odt_to_md(src, out)
            elif ext == ".pdf":
                note = pdf_to_md(src, out)
            elif ext == ".xlsx":
                note = xlsx_to_md(src, out)
            else:
                print(f"FAIL {src.name} 지원하지 않는 형식({ext})")
                continue
            size = len(out.read_text(encoding="utf-8", errors="replace"))
            print(f"{'WARN' if note else 'OK'} {src.name} -> {out} ({size}자){' ' + note if note else ''}")
        except Exception as e:
            print(f"FAIL {src.name} {e}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
