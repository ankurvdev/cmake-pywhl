# The following functions are required by
# PEP 517 A build-system independent format for source trees
# https://peps.python.org/pep-0517/#build-backend-api
# The current file can be used as a build backend from a pyproject.toml file
import shutil
import subprocess
import sys
from pathlib import Path


def prepare_metadata_for_build_wheel(
    _metadata_directory: str | None = None,
    _config_settings: dict[str, object] | None = None,
) -> str | None:
    return None
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
    wheel_directory: str,
    _config_settings: dict[str, object] | None = None,
    _metadata_directory: str | None = None,
) -> str:
    if _config_settings and len(_config_settings.items()) != 0:
        raise ValueError(f"Dont know how to handle configs = {_config_settings!r}")
    if _metadata_directory:
        raise ValueError(f"metadata directory {_metadata_directory!r} not supported")
    _ = subprocess.check_call(
        [
            shutil.which("cmake") or "cmake",
            "-B",
            wheel_directory,
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
            wheel_directory,
            "--target",
            "all_whl",
        ],
    )
    return next(Path(wheel_directory).glob("*-abi3-*.whl")).relative_to(wheel_directory).as_posix()


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
    raise NotImplementedError(
        "Editable builds not supported by the build backend. Use the cmake module PyWhlConfig.cmake directly",
    )


#
#    if _config_settings and len(_config_settings.items()) != 0:
#        raise ValueError(f"Dont know how to handle configs = {_config_settings!r}")
#    if _metadata_directory:
#        raise ValueError(f"metadata directory {_metadata_directory!r} not supported")
#    _ = subprocess.check_call(
#        [
#            shutil.which("cmake") or "cmake",
#            "-B",
#            wheel_directory,
#            "-S",
#            ".",
#            f"-DPython3_EXECUTABLE={sys.executable}",
#            f"-DPyWhl_DIR={Path(__file__).parent.as_posix()}",
#        ],
#    )
#
#    _ = subprocess.check_call(
#        [
#            shutil.which("cmake") or "cmake",
#            "--build",
#            wheel_directory,
#            "--target",
#            "all_editable_whl",
#        ],
#    )
#    return next(Path(wheel_directory).glob("*-0.editable-py3-none-any.whl")).relative_to(wheel_directory).as_posix()


def prepare_metadata_for_build_editable(
    _metadata_directory: str,
    _config_settings: dict[str, object] | None = None,
) -> str:
    raise NotImplementedError(
        "Editable builds not supported by the build backend. Use the cmake module PyWhlConfig.cmake directly",
    )
