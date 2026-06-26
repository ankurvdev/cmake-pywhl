
# The following functions are required by
# PEP 517 A build-system independent format for source trees
# https://peps.python.org/pep-0517/#build-backend-api
# The current file can be used as a build backend from a pyproject.toml file

def prepare_metadata_for_build_wheel(
        _metadata_directory: str | None = None,
        _config_settings: dict[str, object] | None = None,
    ) -> str:
    raise NotImplementedError("prepare_metadata_for_build_wheel Unsupported")


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
    #subprocess.run([
    #    "cmake",
    #    "--build", ".",
    #    "--target", "all_whl",
    #]
    raise NotImplementedError("build_wheel")


def build_sdist(
    sdist_directory: str,
    _config_settings: dict[str, object] | None = None,
) -> str:
    raise NotImplementedError("Python source distribution ('sdist') Unsupported")


def build_editable(
    wheel_directory: str,
    _config_settings: dict[str, object] | None = None,
    _metadata_directory: str | None = None,
) -> str:
    #subprocess.run([
    #    "cmake",
    #    "--build", ".",
    #    "--target", "all_dev_whl",
    #]
    raise NotImplementedError("build_editable Untested")


def prepare_metadata_for_build_editable(
    metadata_directory: str,
    _config_settings: dict[str, object] | None = None,
) -> str:
    raise NotImplementedError("prepare_metadata_for_build_editable Untested")

