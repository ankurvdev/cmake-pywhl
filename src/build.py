# The following functions are required by
# PEP 517 A build-system independent format for source trees
# https://peps.python.org/pep-0517/#build-backend-api
# The current file can be used as a build backend from a pyproject.toml file
from pathlib import Path
import shutil
import subprocess
import sys


def prepare_metadata_for_build_wheel(
    _metadata_directory: str | None = None,
    _config_settings: dict[str, object] | None = None,
) -> str:
    pass
    # raise NotImplementedError(
    #    f"prepare_metadata_for_build_editable(metadata_directory={_metadata_directory!r}, "
    #    f"config_settings={_config_settings!r})",
    # )


def get_requires_for_build_wheel(
    _config_settings: dict[str, object] | None = None,
) -> list[str]:
    # cmake + ninja + stubgen/mypy
    return ["cmake", "ninja"]  # No dependencies for building with this file as the build backend


def get_requires_for_build_sdist(
    _config_settings: dict[str, object] | None = None,
) -> list[str]:
    return []  # No dependencies for building with this file as the build backend


def build_wheel(
    _wheel_directory: str,
    _config_settings: dict[str, object] | None = None,
    _metadata_directory: str | None = None,
) -> str:
    raise NotImplementedError(
        f"build_wheel(_wheel_directory={_wheel_directory!r}, config_settings={_config_settings!r}, "
        f"metadata_directory={_metadata_directory!r})",
    )
    _ = subprocess.check_call(
        [
            shutil.which("cmake") or "cmake",
            "--build",
            ".",
            "--target",
            "all_whl",
        ],
    )


def build_sdist(
    _sdist_directory: str,
    _config_settings: dict[str, object] | None = None,
) -> str:
    raise NotImplementedError(f"build_sdist(sdist_directory={_sdist_directory}, config_settings={_config_settings!r})")


def build_editable(
    _wheel_directory: str,
    _config_settings: dict[str, object] | None = None,
    _metadata_directory: str | None = None,
) -> str:

    _ = subprocess.check_call(
        [
            shutil.which("cmake") or "cmake",
            "-B",
            _wheel_directory,
            "-S",
            ".",
            f"-DPython3_EXECUTABLE={sys.executable}",
            f"-DPyWhl_DIR={Path(__file__).parent.as_posix()}",
        ],
    )

    _ = subprocess.check_call(
        [
            shutil.which("cmake") or "cmake",
            "--build",
            _wheel_directory,
            "--target",
            "all_dev_whl",
        ],
    )
    return _wheel_directory


def prepare_metadata_for_build_editable(
    _metadata_directory: str,
    _config_settings: dict[str, object] | None = None,
) -> str:
    pass
