#!/usr/bin/env python3
import sys
import shutil
from pathlib import Path

script_dir = Path(__file__).parent
out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("PyWhlConfig.cmake")

shutil.copy(script_dir / "src" / "PyWhlConfig.cmake", out_path)

with out_path.open("a", encoding="utf-8") as out:
    out.write("set(PYWHL_CONTENTS_PYWHL_PY [====[\n")
    out.write((script_dir / "src" / "pywhl.py").read_text(encoding="utf-8"))
    out.write("]====])\n")
    out.write("set(PYWHL_CONTENTS_EDITABLE_FINDER_PY [====[\n")
    out.write((script_dir / "src" / "editable_finder.py").read_text(encoding="utf-8"))
    out.write("]====])\n")
    out.write("PyWhl_Init()\n")
