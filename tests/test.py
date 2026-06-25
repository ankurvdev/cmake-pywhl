"""
Integration test for cmake-pywhl.

Each subdirectory of tests/ that contains a CMakeLists.txt is a test case.
Each test folder must provide:

  CMakeLists.txt                          — cmake project with an `all_whl` target
  tests/whl_install_test.py               — functional test run in both venvs
  tests/whl_install_files.txt             — glob patterns expected in runtime-venv site-packages
  tests/inplace_install_patterns.txt      — glob patterns expected in build-venv site-packages
  tests/inplace_file_changed_test.py               — run right after source_change.patch (pre-rebuild)
  tests/inplace_file_changed_post_rebuild_test.py  — run after cmake rebuild following source_change.patch
  tests/inplace_file_add_test.py                   — run after cmake rebuild following file_add.patch
  patches/source_change.patch             — modifies local source files (e.g. Python scripts)
  patches/upstream_source_change.patch    — optional: patch applied to the FetchContent source repo
  patches/upstream_source_var.txt         — cmake variable name that holds the FetchContent source path
  patches/file_add.patch                  — adds a new .py file + updates CMakeLists.txt
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Sequence

TESTS_DIR = Path(__file__).parent
REPO_ROOT = TESTS_DIR.parent


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------


def _run(
    cmd: Sequence[str | Path],
    *,
    cwd: Path | str | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(c) for c in cmd],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed: {' '.join(str(c) for c in cmd)}\n"
            f"--- stdout ---\n{result.stdout}\n"
            f"--- stderr ---\n{result.stderr}",
        )
    return result


def _make_venv(path: Path) -> None:
    _run([sys.executable, "-m", "venv", path])


def _venv_python(venv: Path) -> Path:
    if sys.platform == "win32":
        return venv / "Scripts" / "python.exe"
    return venv / "bin" / "python"


def _site_packages(venv: Path) -> Path:
    result = _run(
        [_venv_python(venv), "-c", "import site; print(site.getsitepackages()[0])"],
    )
    return Path(result.stdout.strip())


def _editable_files(sp: Path) -> list[Path]:
    return list(sp.glob("__editable__*.pth")) + list(sp.glob("__editable__*_finder.py"))


def _mtimes(files: list[Path]) -> dict[Path, float]:
    return {f: f.stat().st_mtime for f in files if f.exists()}


def _cmake_env(build_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("CMAKE_FETCHCONTENT_BASE_DIR", str(build_dir / "_fetchcontent"))
    return env


def _find_fetchcontent_patch_dir(build_dir: Path, patch_file: Path) -> Path | None:
    """Return the FetchContent source dir where patch_file applies cleanly, or None."""
    base = Path(_cmake_env(build_dir)["CMAKE_FETCHCONTENT_BASE_DIR"])
    for src_dir in sorted(base.glob("*-src")):
        if not src_dir.is_dir():
            continue
        result = subprocess.run(
            ["git", "apply", "--check", "--whitespace=nowarn", str(patch_file)],
            cwd=src_dir,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0:
            return src_dir
    return None


# ---------------------------------------------------------------------------
# Build-phase helpers
# ---------------------------------------------------------------------------


def _cmake_configure(
    source_dir: Path,
    build_dir: Path,
    python: Path,
    cmake_prefix: Path,
) -> None:
    env = _cmake_env(build_dir)
    _run(
        [
            "cmake", source_dir,
            "-B", build_dir,
            f"-DPython3_EXECUTABLE={python}",
            f"-DCMAKE_PREFIX_PATH={cmake_prefix}",
            f"-DFETCHCONTENT_BASE_DIR={env['CMAKE_FETCHCONTENT_BASE_DIR']}",
        ],
        env=env,
    )


def _cmake_build(build_dir: Path, target: str | None = None) -> None:
    cmd: list[str | Path] = ["cmake", "--build", build_dir]
    if target:
        cmd += ["--target", target]
    _run(cmd, env=_cmake_env(build_dir))


def _setup_build(
    source_copy: Path,
    folder_name: str,
    build_dir: Path,
    build_venv: Path,
) -> tuple[Path, list[Path], list[Path]]:
    """Configure cmake, build extension + editable install + wheels.

    Returns (build_site_packages, editable_files, whl_files).
    """
    folder_copy = source_copy / "tests" / folder_name
    _make_venv(build_venv)
    build_python = _venv_python(build_venv)

    _cmake_configure(folder_copy, build_dir, build_python, cmake_prefix=source_copy)
    _cmake_build(build_dir)              # extension + editable install (ALL targets)
    _cmake_build(build_dir, "all_whl")   # generate .whl files

    build_sp = _site_packages(build_venv)
    editable = _editable_files(build_sp)
    whls = list(build_dir.rglob("*.whl"))
    return build_sp, editable, whls


# ---------------------------------------------------------------------------
# Pattern-check helpers
# ---------------------------------------------------------------------------


def _assert_patterns_present(sp: Path, patterns_file: Path, *, label: str) -> list[str]:
    """Check every pattern in patterns_file exists under sp. Returns the patterns."""
    if not patterns_file.exists():
        return []
    patterns = [
        ln.strip()
        for ln in patterns_file.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    ]
    for pattern in patterns:
        if not list(sp.glob(pattern)):
            pytest.fail(f"[{label}] Expected pattern not found in {sp}: {pattern!r}")
    return patterns


def _assert_patterns_absent(sp: Path, patterns: list[str], *, label: str) -> None:
    for pattern in patterns:
        if list(sp.glob(pattern)):
            pytest.fail(
                f"[{label}] Pattern {pattern!r} should NOT be present in {sp}"
                " (editable install redirects to source instead of copying files)",
            )


# ---------------------------------------------------------------------------
# Patch-phase helpers
# ---------------------------------------------------------------------------


@dataclass
class _TestCtx:
    source_copy: Path
    build_dir: Path
    build_python: Path
    patches_dir: Path
    test_scripts: Path
    editable_files: list[Path]


def _apply_patch(patch_file: Path, repo_root: Path) -> None:
    _run(["git", "apply", "--whitespace=nowarn", patch_file], cwd=repo_root)


def _test_source_change(ctx: _TestCtx) -> None:
    """Apply source_change.patch, verify two-stage rebuild behaviour.

    Pre-rebuild  — Python changes are visible immediately; C++ is not yet recompiled.
    Post-rebuild — C++ changes are visible; editable install files are NOT regenerated
                   (cmake correctly detects them as up-to-date).
    """
    patch = ctx.patches_dir / "source_change.patch"
    if not patch.exists():
        return

    _apply_patch(patch, ctx.source_copy)

    # Apply upstream patch (e.g. C++ change) to the FetchContent source repo if present
    upstream_patch = ctx.patches_dir / "upstream_source_change.patch"
    if upstream_patch.exists():
        upstream_src = _find_fetchcontent_patch_dir(ctx.build_dir, upstream_patch)
        if upstream_src:
            _run(["git", "apply", "--whitespace=nowarn", upstream_patch], cwd=upstream_src)

    # Pre-rebuild: Python change visible, C++ unchanged
    pre_test = ctx.test_scripts / "inplace_file_changed_test.py"
    if pre_test.exists():
        _run([ctx.build_python, pre_test])

    # Rebuild: recompiles C++ but must NOT touch the editable install files
    ts_before = _mtimes(ctx.editable_files)
    _cmake_build(ctx.build_dir)
    ts_after = _mtimes(ctx.editable_files)

    for f in ctx.editable_files:
        if ts_before.get(f) != ts_after.get(f):
            pytest.fail(
                f"Editable install file {f.name} was unexpectedly regenerated after a "
                "source-only change (cmake should have considered it up-to-date)",
            )

    # Post-rebuild: C++ change now visible
    post_test = ctx.test_scripts / "inplace_file_changed_post_rebuild_test.py"
    if post_test.exists():
        _run([ctx.build_python, post_test])


def _test_file_add(ctx: _TestCtx) -> None:
    """Apply file_add.patch, rebuild, verify editable was regenerated, run add test."""
    patch = ctx.patches_dir / "file_add.patch"
    if not patch.exists():
        return

    _apply_patch(patch, ctx.source_copy)

    ts_before = _mtimes(ctx.editable_files)
    _cmake_build(ctx.build_dir)
    ts_after = _mtimes(ctx.editable_files)

    if not any(ts_before.get(f) != ts_after.get(f) for f in ctx.editable_files):
        pytest.fail(
            "Expected editable install files to be regenerated after adding a new "
            "Python file (finder mapping must be updated)",
        )

    add_test = ctx.test_scripts / "inplace_file_add_test.py"
    if add_test.exists():
        _run([ctx.build_python, add_test])


# ---------------------------------------------------------------------------
# Parametrize over every folder that has a CMakeLists.txt
# ---------------------------------------------------------------------------


def _test_folder_names() -> list[str]:
    return [
        d.name
        for d in TESTS_DIR.iterdir()
        if d.is_dir()
        and not d.name.startswith(("_", "."))
        and (d / "CMakeLists.txt").exists()
    ]


@pytest.fixture(params=_test_folder_names())
def folder_name(request: pytest.FixtureRequest) -> str:
    return request.param  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# Main integration test
# ---------------------------------------------------------------------------


def test_cmake_pywhl(folder_name: str, tmp_path: Path) -> None:
    folder = TESTS_DIR / folder_name
    test_scripts = folder / "tests"
    patches_dir = folder / "patches"

    source_copy = tmp_path / "source"
    build_dir = tmp_path / "build"
    build_venv = tmp_path / "build_venv"
    runtime_venv = tmp_path / "runtime_venv"
    build_dir.mkdir()

    shutil.copytree(
        REPO_ROOT,
        source_copy,
        ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc", "PyWhlConfig.cmake"),
    )
    _run(["bash", source_copy / "build.sh", source_copy / "PyWhlConfig.cmake"], cwd=source_copy)

    # 1. cmake configure + build
    build_sp, editable, whl_files = _setup_build(source_copy, folder_name, build_dir, build_venv)
    build_python = _venv_python(build_venv)

    if not editable:
        pytest.fail("No editable install files (*.pth / *_finder.py) found in build venv")
    if not whl_files:
        pytest.fail("No .whl files found in build directory after cmake build")

    # 2. Install wheels into runtime venv
    _make_venv(runtime_venv)
    runtime_python = _venv_python(runtime_venv)
    _run([runtime_python, "-m", "pip", "install", "--no-index", *whl_files])
    runtime_sp = _site_packages(runtime_venv)

    # 3. Verify file presence
    whl_patterns = _assert_patterns_present(
        runtime_sp, test_scripts / "whl_install_files.txt", label="runtime-venv",
    )
    _assert_patterns_present(
        build_sp, test_scripts / "inplace_install_patterns.txt", label="build-venv",
    )

    # 4. Editable install: whl files must NOT be directly in build venv
    _assert_patterns_absent(build_sp, whl_patterns, label="build-venv editable check")

    # 5. Functional test in build venv (via editable install)
    whl_install_test = test_scripts / "whl_install_test.py"
    if whl_install_test.exists():
        _run([build_python, whl_install_test])

    ctx = _TestCtx(
        source_copy=source_copy,
        build_dir=build_dir,
        build_python=build_python,
        patches_dir=patches_dir,
        test_scripts=test_scripts,
        editable_files=editable,
    )

    # 6. Source-change patch: visible immediately, no editable regeneration on rebuild
    _test_source_change(ctx)

    # 7. File-add patch: editable must be regenerated on rebuild
    _test_file_add(ctx)

    # 8. Delete build venv + source to prove wheel is self-contained
    shutil.rmtree(build_venv)
    shutil.rmtree(source_copy / "tests" / folder_name)

    # 9. Functional test in runtime venv (standalone wheel install)
    if whl_install_test.exists():
        _run([runtime_python, whl_install_test])
