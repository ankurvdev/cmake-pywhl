include_guard()

define_property(
    GLOBAL PROPERTY PYWHL_MODULE_MANIFESTS INHERITED
    BRIEF_DOCS "PYWHL Module Manifests"
    FULL_DOCS "This property is used to track PYWHL modules available for packaging")

define_property(
    GLOBAL PROPERTY PYWHL_TARGET_DEPENDENCIES INHERITED
    BRIEF_DOCS "PYWHL Package Target dependencies"
    FULL_DOCS "This property is used to track the target dependencies of PYWHL packages")

function(add_pywhl_module name)
    cmake_parse_arguments("args" "" "EXCLUDE_REGEX" "DATA_FILES;SCRIPTS;TARGETS" ${ARGN})
    
    set(data_files ${args_DATA_FILES})
    set(target_libs)
    set(target_bins)

    foreach (tgt ${args_TARGETS})
        get_target_property(type ${tgt} TYPE)
        set(lib_targets STATIC_LIBRARY SHARED_LIBRARY MODULE_LIBRARY)
        if ("${type}" IN_LIST lib_targets)
            list(APPEND target_libs $<TARGET_FILE:${tgt}>)
        elseif("${type}" STREQUAL "EXECUTABLE")
            list(APPEND target_bins $<TARGET_FILE:${tgt}>)
        else()
            # For all other target types, we just collect additional files
        endif()
        list(APPEND data_files $<TARGET_PROPERTY:${tgt},PYWHL_ADDITIONAL_FILES>)
    endforeach()

    string(JOIN "\n" contents_package_ini
        "[DEFAULT]"
        "SRC_ROOT=${CMAKE_CURRENT_SOURCE_DIR}"
        "NAME=${name}"
        "DATA=${data_files}"
        "SCRIPTS=${args_SCRIPTS}"
        "TARGETS=${args_TARGETS}"
        "TARGET_LIBS=${target_libs}"
        "TARGET_BINS=${target_bins}"
        "EXCLUDE_REGEX=${args_EXCLUDE_REGEX}"
    )

    # Prefix with $<CONFIG> so multi-config generators (e.g. Visual Studio)
    # get a distinct output file per configuration. The content embeds
    # $<TARGET_FILE:...>, which differs per config; without a per-config
    # output name cmake errors with "Evaluation file to be written multiple
    # times with different content".
    set(manifest_file "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>_${name}.ini")
    file(GENERATE OUTPUT "${manifest_file}" CONTENT "${contents_package_ini}")

    set_property(GLOBAL APPEND PROPERTY PYWHL_MODULE_MANIFESTS "${name}:${manifest_file}")
    foreach (tgt ${args_TARGETS})
        set_property(GLOBAL APPEND PROPERTY PYWHL_TARGET_DEPENDENCIES "${name}:${tgt}")
    endforeach()
endfunction()

function(_pywhl_generate_whl_name)
    cmake_parse_arguments("args" 
        "" 
        "OUTPUT_VAR;DISTRIBUTION;VERSION;BUILD;" 
        "" ${ARGN})
    # The wheel filename is {distribution}-{version}(-{build tag})?-{python tag}-{abi tag}-{platform tag}.whl.
    # PIP-PYWHLs are both dogmatic about version string formats,
    # but accept sem-ver 2 compliant version-strings.
    # The PYWHL filename, however, needs to encode all `-` as `_` in the version-string.

    string(REPLACE "-" "_" version "${args_VERSION}")
    if (NOT DEFINED args_DISTRIBUTION)
        message(FATAL_ERROR "add_pywhl_package: DISTRIBUTION not specified")
    endif()
    if (NOT DEFINED args_BUILD)
        set(build "")
    else()
        set(build "-${args_BUILD}")
    endif()
    set(build_tag   "")
    set(python_tag  "cp${Python3_VERSION_MAJOR}${Python3_VERSION_MINOR}")
    string(REPLACE "." "" python_tag "${python_tag}")
    set(abi_tag     "abi3")
    if (WIN32)
        set(platform_tag "win_amd64")
    elseif(APPLE)
        set(platform_tag "macosx_11_0_${CMAKE_SYSTEM_PROCESSOR}")
    elseif(UNIX)
        set(platform_tag "linux_${CMAKE_SYSTEM_PROCESSOR}")
    else()
        message(FATAL_ERROR "add_pywhl_package: Unsupported platform for wheel: ${CMAKE_SYSTEM_NAME}")
    endif()
    set(extension whl)

    set(whl_name "${args_DISTRIBUTION}-${version}${build}-${python_tag}-${abi_tag}-${platform_tag}.${extension}")
    set(${args_OUTPUT_VAR} "${whl_name}" PARENT_SCOPE)
endfunction()

function(add_pywhl_package targetName)
    set(build_dir "${CMAKE_CURRENT_BINARY_DIR}")

    cmake_parse_arguments("args" 
        "" 
        "whl_file_OUTVAR;EDITABLE_TARGET;VERSION;LICENSE_FILE;METADATA_FILE;ENTRY_POINTS_FILE" 
        "MODULES" ${ARGN})

    if (NOT DEFINED args_EDITABLE_TARGET)
        set(args_EDITABLE_TARGET "${targetName}_dev_whl")
    endif()

    if (NOT DEFINED args_VERSION)
        set(args_VERSION "0.0.1")
        message(WARNING "add_pywhl_package: version not specified. Using VERSION=0.0.1")
    endif()

    if (NOT DEFINED args_LICENSE_FILE AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
        set(args_LICENSE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
    endif()

    if (NOT EXISTS "${args_LICENSE_FILE}")
        message(FATAL_ERROR "License file not found: ${args_LICENSE_FILE}")
    endif()

    if (NOT DEFINED args_METADATA_FILE AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/METADATA")
        set(args_METADATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/METADATA")
    endif()

    if (NOT DEFINED args_METADATA_FILE)
        message(WARNING "Metadata file not found for pywhl package: ${targetName}. Please create one at ${CMAKE_CURRENT_SOURCE_DIR}/METADATA")
    endif()

    if (NOT DEFINED args_ENTRY_POINTS_FILE AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/entry_points.txt")
        set(args_ENTRY_POINTS_FILE "${CMAKE_CURRENT_SOURCE_DIR}/entry_points.txt")
    endif()

    find_package(Python3 REQUIRED COMPONENTS Interpreter Development.Module)
    find_package(Python3 QUIET COMPONENTS Development.SABIModule)

    get_property(allmanifests GLOBAL PROPERTY PYWHL_MODULE_MANIFESTS)
    get_property(alltargets GLOBAL PROPERTY PYWHL_TARGET_DEPENDENCIES)

    set(manifest_files)
    set(targets)

    foreach(modname ${args_MODULES})
        set(modmanifest "NOTFOUND")
        set(modtargets "")
        foreach(manifest ${allmanifests})
            # Split on the FIRST ":" only. The manifest path contains a Windows
            # drive-letter colon (e.g. C:/...), so splitting on every colon would
            # truncate the path to the drive letter. (pkgname never has a colon.)
            string(FIND "${manifest}" ":" _pywhl_colon)
            string(SUBSTRING "${manifest}" 0 ${_pywhl_colon} pkgname2)
            math(EXPR _pywhl_after "${_pywhl_colon} + 1")
            string(SUBSTRING "${manifest}" ${_pywhl_after} -1 manifestfile)
            if ("${modname}" STREQUAL "${pkgname2}")
                set(modmanifest "${manifestfile}")
            endif()
        endforeach()
        foreach(tgt ${alltargets})
            string(REPLACE ":" ";" info ${tgt})
            list(GET info 0 pkgname2)
            list(GET info 1 tgts)
            if ("${modname}" STREQUAL "${pkgname2}")
                set(modtargets "${tgts}")
            endif()
        endforeach()
        if ("${modmanifest}" STREQUAL "NOTFOUND")
            message(FATAL_ERROR "add_pywhl_package: pywhl module ${modname} not found for package ${targetName}")
        endif()
        list(APPEND manifest_files "${modmanifest}")
        list(APPEND targets ${modtargets})
    endforeach()
    set(pyexttgt "")
    foreach (tgt ${targets})
        get_target_property(type ${tgt} TYPE)
        set(lib_targets STATIC_LIBRARY SHARED_LIBRARY MODULE_LIBRARY)
        if ("${type}" STREQUAL "MODULE_LIBRARY")
            set(pyexttgt ${tgt})
        endif()
    endforeach()

    _pywhl_generate_whl_name(DISTRIBUTION ${targetName} VERSION ${args_VERSION} OUTPUT_VAR whl_name)
    set(whl_file "${build_dir}/${whl_name}")
    message(STATUS "Setting Wheel: ${whl_file}")

    string(JOIN "\n" build_ini
        "[DEFAULT]"
        "NAME=${targetName}"
        "SRC_ROOT=${CMAKE_CURRENT_SOURCE_DIR}"
        "VERSION=${args_VERSION}"
        "LICENSE_FILE=${args_LICENSE_FILE}"
        "BUILD_DIR=${build_dir}"
        "MODULE_MANIFESTS=${manifest_files}"
    )
    if(DEFINED args_METADATA_FILE)
        set(build_ini "${build_ini}\nMETADATA_FILE=${args_METADATA_FILE}")
    endif()
    if(DEFINED args_ENTRY_POINTS_FILE)
        set(build_ini "${build_ini}\nENTRY_POINTS_FILE=${args_ENTRY_POINTS_FILE}")
    endif()

    set(manifest_file "${build_dir}/$<CONFIG>_${targetName}_build.ini")
    file(GENERATE OUTPUT "${manifest_file}" CONTENT "${build_ini}")
    set(editable_depfile "${manifest_file}.editable.d")
    set(package_depfile "${manifest_file}.package.d")

    add_custom_command(
        COMMAND "${Python3_EXECUTABLE}" "${PYWHL_SCRIPT_FILE_PATH}" --verbose
            --package  "${whl_file}"
            --manifest "${manifest_file}"
            --dep-file "${package_depfile}"
            --work-dir "${build_dir}"
        OUTPUT "${whl_file}"
        DEPENDS "${PYWHL_SCRIPT_FILE_PATH}" "${manifest_file}" ${args_METADATA_FILE} ${args_ENTRY_POINTS_FILE}
        DEPFILE "${package_depfile}"
    )

    add_custom_command(
        COMMAND "${Python3_EXECUTABLE}" "${PYWHL_SCRIPT_FILE_PATH}" --verbose
            --install --editable --force-reinstall
            --manifest "${manifest_file}"
            --dep-file "${editable_depfile}"
            --work-dir "${build_dir}"
        DEPENDS "${PYWHL_SCRIPT_FILE_PATH}" "${manifest_file}" ${args_METADATA_FILE} ${args_ENTRY_POINTS_FILE}
        DEPFILE "${editable_depfile}"
        OUTPUT  "${editable_depfile}"
    )

    add_custom_target(${args_EDITABLE_TARGET} ALL
        DEPENDS
            ${editable_depfile}
            "${PYWHL_SCRIPT_FILE_PATH}" "${manifest_file}" ${args_METADATA_FILE} ${args_ENTRY_POINTS_FILE}
    )
    add_custom_target(${targetName}
        DEPENDS 
            "${whl_file}"
    )

    set_target_properties(${args_EDITABLE_TARGET} PROPERTIES whl_file "${whl_file}")

    get_property(dependencies GLOBAL PROPERTY PYWHL_TARGET_DEPENDENCIES)
    foreach(pkgname ${args_MODULES})
        foreach(dependency ${dependencies})
            string(REPLACE ":" ";" dependencyinfo ${dependency})
            list(GET dependencyinfo 1 deptarget)
            list(GET dependencyinfo 0 pkgname2)
            if ("${pkgname}" STREQUAL "${pkgname2}")
                add_dependencies(${targetName}           ${deptarget})
                add_dependencies(${args_EDITABLE_TARGET} ${deptarget})
            endif()
       endforeach()
    endforeach()
    if (NOT TARGET all_whl)
        add_custom_target(all_whl)
    endif()
    add_dependencies(all_whl ${targetName})
    add_dependencies(all_whl ${args_EDITABLE_TARGET})
    if (DEFINED args_WHL_FILE_OUTVAR)
        set(${args_WHL_FILE_OUTVAR} "${whl_file}" PARENT_SCOPE)
    endif()
endfunction()

set(PYWHL_CMAKE_DIR "${CMAKE_CURRENT_LIST_DIR}")

macro(PyWhl_Init)
    if (NOT DEFINED PYWHL_SCRIPT_FILE_PATH AND (EXISTS ${PYWHL_CMAKE_DIR}/pywhl.py))
        if (NOT EXISTS "${PYWHL_CMAKE_DIR}/editable_finder.py")
            message(FATAL_ERROR "Cannot find ${PYWHL_CMAKE_DIR}/editable_finder.py")
        endif()
        set(PYWHL_SCRIPT_FILE_PATH ${PYWHL_CMAKE_DIR}/pywhl.py)
    endif()
    if (NOT DEFINED PYWHL_SCRIPT_FILE_PATH AND (DEFINED PYWHL_CONTENTS_PYWHL_PY))
        set(PYWHL_SCRIPT_FILE_PATH ${CMAKE_CURRENT_BINARY_DIR}/pywhl.py)
        if (NOT DEFINED PYWHL_CONTENTS_EDITABLE_FINDER_PY)
            message(FATAL_ERROR "Unable to generate ${CMAKE_CURRENT_BINARY_DIR}/editable_finder.py")
        endif()
        file(GENERATE OUTPUT "${PYWHL_SCRIPT_FILE_PATH}" CONTENT "${PYWHL_CONTENTS_PYWHL_PY}")
        file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/editable_finder.py" CONTENT "${PYWHL_CONTENTS_EDITABLE_FINDER_PY}")
    endif()
endmacro()

PyWhl_Init()

set(PYWHL_CONTENTS_PYWHL_PY [====[
"""
PEP 517 A build-system independent format for source trees: https://peps.python.org/pep-0517/#build-backend-api
PEP 660 (Editable Installs): https://peps.python.org/pep-0660/#prepare-metadata-for-build-editable

Helper script for the CMake Module to generate wheels from CMake Projects
"""

import argparse
import configparser
import hashlib
import logging
import os
import platform
import re
import shutil
import site
import string
import sys
import zipfile
from collections.abc import Generator
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn

logging.basicConfig(format="%(asctime)s %(name)s [%(levelname)s] - %(message)s", level=logging.DEBUG)
log = logging.getLogger(__name__)


class CMakeBuildWheelError(RuntimeError):
    pass


class ModuleInfo:
    def __init__(self) -> None:
        self.file: Path = Path()
        self.name: str = ""
        self.src_root: Path = Path()
        self.data: dict[Path, Path] = {}
        self.scripts: dict[Path, Path] = {}
        self.targets: list[str] = []
        self.target_libs: list[Path] = []
        self.target_bins: list[Path] = []
        self.exclude_regex: re.Pattern[str] | None = None


@dataclass
class BuildInfo:
    file: Path
    name: str
    version: str
    src_root: Path
    license_file: Path
    modules: list[ModuleInfo]
    entry_points_file: Path | None = None
    metadata_template_file: Path | None = None


@dataclass
class Args:
    manifest: Path = Path()
    work_dir: Path = Path()
    dep_file: Path = Path()

    package: Path | None = None
    install: bool = False
    editable: bool = False
    force_reinstall: bool = False
    verbose: bool = False
    debug: bool = False
    quiet: bool = False


def parse_manifest(manifest: Path) -> BuildInfo:
    def read_config(fname: Path) -> dict[str, str]:
        try:
            with fname.open() as file:
                configreader = configparser.ConfigParser()
                configreader.read_file(file, fname.as_posix())
        except OSError as err:
            raise CMakeBuildWheelError(f"Failed to read manifest file: {fname.as_posix()}") from err

        return dict(configreader["DEFAULT"].items())

    build_info = read_config(manifest)

    def splitpaths(paths: str) -> list[Path]:
        return [Path(val) for val in filter(len, filter(None, paths.split(";")))]

    def splitstr(paths: str) -> list[str]:
        return list(filter(len, filter(None, paths.split(";"))))

    def create_source_dest_paths(paths: list[str]) -> dict[Path, Path]:
        return {Path(src): Path(dst or Path(src).name) for path in paths for src, dst in [([*path.split("@"), ""])[:2]]}

    def parse_manifest(manifest: Path) -> ModuleInfo:
        modconfig = read_config(manifest)
        modinfo = ModuleInfo()
        modinfo.file = manifest
        modinfo.name = modconfig["name"]
        modinfo.src_root = Path(modconfig["src_root"])
        modinfo.data = create_source_dest_paths(splitstr(modconfig["data"]))
        modinfo.scripts = create_source_dest_paths(splitstr(modconfig["scripts"]))
        modinfo.target_libs = splitpaths(modconfig["target_libs"])
        modinfo.target_bins = splitpaths(modconfig["target_bins"])
        if modconfig.get("entry_points", "") != "":
            raise ValueError("`entry_points` not implemented/supported")
        # modinfo.entry_points = {}  # Not implemented.
        if (exclude_regex := modconfig.get("exclude_regex", "")) != "":
            modinfo.exclude_regex = re.compile(exclude_regex)

        return modinfo

    def path_or_none(val: str | None) -> Path | None:
        return None if val is None else Path(val)

    return BuildInfo(
        src_root=Path(build_info["src_root"]),
        file=manifest,
        name=build_info["name"],
        version=build_info["version"],
        license_file=Path(build_info["license_file"]),
        metadata_template_file=path_or_none(build_info.get("metadata_file")),
        entry_points_file=path_or_none(build_info.get("entry_points_file")),
        modules=[parse_manifest(file) for file in splitpaths(build_info["module_manifests"])],
    )


class CMakeBuildWheel:
    _instance: "CMakeBuildWheel | None" = None

    @classmethod
    def instance(cls) -> "CMakeBuildWheel":
        if cls._instance is None:
            raise CMakeBuildWheelError("Need manifest file to initialize")
        return cls._instance

    def __init__(self, args: Args):
        CMakeBuildWheel._instance = self
        self.work_dir: Path = args.work_dir
        tagpyversion = f"cp{sys.version_info.major}{sys.version_info.minor}"
        self.tag: str = f"{tagpyversion}-{tagpyversion}-{sys.platform}_{platform.machine()}"
        self.dependencies: set[Path] = {Path(__file__), Path(__file__).parent / "BuildWheel.cmake"}
        self.whl_file_name: Path | None = None

        # The manifests here are generated by BuildWheel.cmake corresponding to add_wheel_package calls
        # def load_manifest(self, manifest: Path) -> None:
        self.build_info: BuildInfo = parse_manifest(args.manifest)
        self.dependencies.update(mod.file for mod in self.build_info.modules)
        self.dependencies.add(self.build_info.file)
        self.dependencies.add(self.build_info.license_file)
        if self.build_info.metadata_template_file:
            self.dependencies.add(self.build_info.metadata_template_file)
        if self.build_info.entry_points_file:
            self.dependencies.add(self.build_info.entry_points_file)

    def _script_path_mapping(self, mod: ModuleInfo, script_path: Path) -> dict[str, str]:
        script_root = mod.src_root / script_path
        if not script_root.exists():
            raise CMakeBuildWheelError(f"Script {script_root.as_posix()} not found")
        mapping: dict[str, str] = {}
        if script_root.is_dir():
            if (script_root / "__init__.py").exists():
                mapping[mod.name] = script_root.as_posix()
            else:
                for subpath in script_root.rglob("*.py"):
                    mapping[f"{mod.name}.{subpath.stem}"] = subpath.as_posix()
        elif script_root.suffix == ".py":
            mapping[f"{mod.name}.{script_root.stem}"] = script_root.as_posix()
            if script_path.name == "__init__.py":
                mapping[mod.name] = script_path.absolute().as_posix()
        return mapping

    def _build_editable_mapping(self) -> dict[str, str]:
        if not self.build_info.modules:
            raise ValueError("Empty self.build_info.modules")
        mapping: dict[str, str] = {}
        for mod in self.build_info.modules:
            for script_path in mod.scripts:
                mapping.update(self._script_path_mapping(mod, script_path))
            for target_lib in mod.target_libs:
                for libname in [
                    target_lib.stem,
                    re.sub(r".abi[0-9\.]+", "", target_lib.stem),
                    re.sub(r"^lib", "", target_lib.stem),
                ]:
                    mapping[libname] = target_lib.as_posix()
                    mapping[mod.name + "." + libname] = target_lib.as_posix()
            for target_bin in mod.target_bins:
                mapping[target_bin.stem] = target_bin.as_posix()
                mapping[mod.name + "." + target_bin.stem] = target_bin.as_posix()
            for data_path in mod.data:
                mapping[data_path.name] = data_path.as_posix()
        return mapping

    def _generate_editable_finder(self, name: str) -> str:
        """Create a string containing the code for the MetaPathFinder and PathEntryFinder."""
        mapping = self._build_editable_mapping()
        namespaces: dict[str, str] = {}
        tmpl = (Path(__file__).parent / "editable_finder.py").read_text()
        tmpl = tmpl.replace(
            "MAPPING: dict[str, str] = {}  # TEMPLATE-SUBSTITUTION-MARKER",
            f"MAPPING: dict[str, str] = {mapping!r}",
        )
        tmpl = tmpl.replace(
            "NAMESPACES: dict[str, str] = {}  # TEMPLATE-SUBSTITUTION-MARKER",
            f"NAMESPACES: dict[str, str] = {namespaces!r}",
        )
        return tmpl.replace(
            'PATH_PLACEHOLDER: str = ".__path_hook__"  # TEMPLATE-SUBSTITUTION-MARKER',
            f'PATH_PLACEHOLDER: str = {name!r} + ".__path_hook__"',
        )

    def get_requires_for_build_sdist(self, _config_settings: dict[str, object] | None = None) -> list[str]:
        return []  # No dependencies for building with this file as the build backend

    def get_requires_for_build_wheel(self, _config_settings: dict[str, object] | None = None) -> list[str]:
        return []  # No dependencies for building with this file as the build backend

    def prepare_metadata_for_build_wheel(
        self,
        _metadata_directory: str | None = None,
        _config_settings: dict[str, object] | None = None,
    ) -> NoReturn:
        raise CMakeBuildWheelError("prepare_metadata_for_build_wheel Unsupported")

    def _recurse_path(
        self,
        mod: ModuleInfo,
        src_root: Path,
        fpath: Path,
        dest: Path,
        add_to_dependencies: bool = False,
    ) -> Generator[tuple[Path, Path], None, None]:
        if not fpath.exists() and (src_root / fpath).exists():
            fpath = src_root / fpath
        if not fpath.exists():
            raise CMakeBuildWheelError(f"File {fpath.as_posix()} or {(src_root / fpath).as_posix()} not found")

        if mod.exclude_regex and mod.exclude_regex.match(fpath.as_posix()):
            log.info(f"excluding {fpath}")
            return

        if fpath.is_dir():
            for subpath in os.scandir(fpath.as_posix()):
                if subpath.name == "__pycache__":
                    continue
                yield from self._recurse_path(
                    mod,
                    src_root,
                    Path(subpath.path),
                    dest / subpath.name,
                    add_to_dependencies=add_to_dependencies,
                )
        else:
            yield fpath, dest
            if add_to_dependencies:
                self.dependencies.add(fpath)

    def _foreach_wheel_file_item(self) -> Generator[tuple[Path, Path], None, None]:
        for mod in self.build_info.modules:
            log.info(f"Adding package {mod.name}")
            dest_root = Path(f"{mod.name}")
            for fpath, dest in mod.data.items():
                log.info(f"Adding package {mod.name} data {fpath.as_posix()} => {dest.as_posix()}")
                # There's could be too many files in data directory.
                # Skip adding them to dependency file list to avoid needles blaoting
                # Just add the root directory
                self.dependencies.add(fpath)
                for fpath1, dest1 in self._recurse_path(mod, mod.src_root, fpath, dest_root / dest):
                    yield fpath1, dest1
            for fpath, dest in mod.scripts.items():
                dest_path = dest_root / dest if dest_root.name != dest.name else dest_root
                log.info(f"Adding package {mod.name} script {fpath.as_posix()} => {dest_path.as_posix()}")
                for fpath1, dest1 in self._recurse_path(mod, mod.src_root, fpath, dest_path, add_to_dependencies=True):
                    yield fpath1, dest1
            for fpath in mod.target_libs:
                log.info(f"Adding package {mod.name} target_lib {fpath.as_posix()}")
                self.dependencies.add(fpath)
                for fpath1, dest1 in self._recurse_path(mod, mod.src_root, fpath, dest_root / fpath.name):
                    yield fpath1, dest1
            for fpath in mod.target_bins:
                log.info(f"Adding package {mod.name} target_bins {fpath.as_posix()}")
                self.dependencies.add(fpath)
                for fpath1, dest1 in self._recurse_path(mod, mod.src_root, fpath, dest_root / fpath.name):
                    yield fpath1, dest1

    def _generate_wheel_content(
        self,
        editable: bool = False,
    ) -> Generator[tuple[Path, Path | None, str | None], None, None]:
        """
        Generates (dest path, source path, content) tuples for a binary distribution (wheel).
        as per
        PEP 660 (Editable Installs) https://peps.python.org/pep-0660/#prepare-metadata-for-build-editable
        PEP 427 (Wheel) https://peps.python.org/pep-0427/#the-dist-info-directory
        See https://packaging.python.org/en/latest/specifications/binary-distribution-format/#file-contents

        """
        metadata_template = (
            self.build_info.metadata_template_file.read_text(encoding="utf-8")
            if self.build_info.metadata_template_file
            else "Metadata-Version: 2.1\nName: ${name}\nVersion: ${version}\nSummary: Wheel for ${name}"
        )
        records: list[tuple[str, str, str]] = []  # path, hash, size
        dist_info = Path(f"{self.build_info.name}-{self.build_info.version}.dist-info")

        def add_to_record(
            fpath: Path,
            src_file: Path | None,
            contents: str | None,
        ) -> tuple[Path, Path | None, str | None]:
            if src_file is not None:
                log.debug(f"Adding {src_file} => {fpath.as_posix()}")
                records.append(
                    (fpath.as_posix(), hashlib.sha256(src_file.read_bytes()).hexdigest(), str(src_file.stat().st_size)),
                )
            else:
                log.debug(f"Adding {fpath.as_posix()}")
                if contents is None:
                    raise ValueError(f"Cannot add empty file {fpath}")
                sha256sum = hashlib.sha256(contents.encode("utf-8")).hexdigest()
                records.append((fpath.as_posix(), sha256sum, str(len(contents))))
            return (fpath, src_file, contents)

        if re.search("^Version: .*", metadata_template, re.MULTILINE) is None:
            metadata_template = "Version: ${version}\n" + metadata_template
        else:
            metadata_template = re.sub(
                "^Version: .*",
                f"Version: {self.build_info.version}",
                metadata_template,
                flags=re.MULTILINE,
            )
        dist_info = Path(f"{self.build_info.name}-{self.build_info.version}.dist-info")
        template_info = self.__dict__ | self.build_info.__dict__
        yield add_to_record(
            dist_info / "METADATA",
            None,
            string.Template(metadata_template).substitute(template_info),
        )

        yield add_to_record(
            dist_info / "WHEEL",
            None,
            string.Template("Wheel-Version: 1.0\nRoot-Is-Purelib: false\nTag: ${tag}").substitute(template_info),
        )

        if self.build_info.license_file:
            yield add_to_record(dist_info / "LICENSE", None, self.build_info.license_file.read_text(encoding="utf-8"))
        package_names = [mod.name for mod in self.build_info.modules]
        yield add_to_record(dist_info / "top_level.txt", None, "\n".join(package_names) + "\n")

        if self.build_info.entry_points_file:
            yield add_to_record(dist_info / "entry_points.txt", self.build_info.entry_points_file, None)

        if editable:
            yield add_to_record(
                dist_info / "direct_url.json",
                None,
                string.Template('{"dir_info": {"editable": true}, "url": "file://${src_root}"}').substitute(
                    template_info,
                ),
            )

            editable_finder_module_name = f"__editable__{self.build_info.name}_finder"
            yield add_to_record(
                Path(f"__editable__{self.build_info.name}-{self.build_info.version}.pth"),
                None,
                string.Template(
                    "import ${editable_finder_module_name}; ${editable_finder_module_name}.install()",
                ).substitute(
                    {**template_info, "editable_finder_module_name": editable_finder_module_name},
                ),
            )
            yield add_to_record(
                Path(editable_finder_module_name + ".py"),
                None,
                self._generate_editable_finder(self.build_info.name),
            )
        else:
            for fpath, dest in self._foreach_wheel_file_item():
                yield add_to_record(dest, fpath, None)

        records.append(((dist_info / "RECORD").as_posix(), "", ""))
        record_contents = "\n".join([",".join(record) for record in records])
        yield (dist_info / "RECORD", None, record_contents)

    def prepare_metadata_for_build_editable(
        self,
        _metadata_directory: str | None = None,
        _config_settings: dict[str, object] | None = None,
    ) -> NoReturn:
        raise CMakeBuildWheelError("prepare_metadata_for_build_editable Untested")

    def build_editable(
        self,
        _out_dir: str,
        _config_settings: dict[str, object] | None = None,
        _metadata_directory: str | None = None,
    ) -> NoReturn:
        """
        Generates an editable wheel as per https://peps.python.org/pep-0660/#build-editable
        """
        raise CMakeBuildWheelError("build_editable Untested")

    def _build_editable_at(self, out_dir: Path, _force_reinstall: bool) -> None:
        for fpath, src_file, contents in self._generate_wheel_content(editable=True):
            fabspath = out_dir / fpath
            fabspath.parent.mkdir(parents=True, exist_ok=True)
            if src_file is not None:
                _ = shutil.copyfile(src_file, fabspath)
            elif contents is not None:
                if not fabspath.exists() or fabspath.read_text(encoding="utf-8") != contents:
                    _ = fabspath.write_text(contents, encoding="utf-8")
            else:
                raise ValueError(f"Neither file nor contents found for {fpath.as_posix()}")

    def build_sdist(
        self,
        _out_dir: str,
        _config_settings: dict[str, object] | None = None,
    ) -> str:
        raise CMakeBuildWheelError("Python source distribution ('sdist') Unsupported")

    def build_wheel(
        self,
        out_dir: Path,
        _config_settings: dict[str, object] | None = None,
        _metadata_directory: str | None = None,
    ) -> Path:
        whl_file = Path(out_dir) / (
            self.whl_file_name or f"{self.build_info.name}-{self.build_info.version}-{self.tag}.whl"
        )
        with zipfile.ZipFile(whl_file, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=0) as archive:
            for fpath, src_file, contents in self._generate_wheel_content():
                if src_file is not None:
                    archive.write(src_file, fpath)
                elif contents is not None:
                    archive.writestr(fpath.as_posix(), contents.encode("utf-8"))
                else:
                    raise ValueError(f"Neither file nor contents found for {fpath.as_posix()}")
        log.info(f"Finished Creating {whl_file.as_posix()}")
        return whl_file

    def install(self, editable: bool, force_reinstall: bool = False) -> None:
        if editable:
            # The first one in site.getsitemodules() is the directory for the venv if we are in a venv
            site_package_path = Path(site.getsitepackages()[0])
            self._build_editable_at(Path(site_package_path), force_reinstall)
        else:
            raise CMakeBuildWheelError("Python install ('install') Unsupported")

    def generate_depfile(self, depfile: Path, output: Path) -> None:
        contents = f"{output.as_posix()}: " + " ".join(fpath.as_posix() for fpath in self.dependencies)
        if depfile.exists() and depfile.read_text() == contents:
            return
        _ = depfile.write_text(contents, encoding="utf-8")

    @classmethod
    def main(cls) -> None:
        parser = argparse.ArgumentParser()
        _ = parser.add_argument("--manifest", type=Path, default=None, required=True, help="Manifest file")
        _ = parser.add_argument("--work-dir", type=Path, default=Path(), required=True, help="Working directory")
        _ = parser.add_argument("--package", type=Path, default=None, help="Build wheel")
        _ = parser.add_argument("--dep-file", type=Path, default=None, help="Emit Dependency File")
        _ = parser.add_argument("--install", action="store_true", help="Install in the python environment")
        _ = parser.add_argument("--editable", action="store_true", help="Editable install")
        _ = parser.add_argument("--force-reinstall", action="store_true", help="Editable install")
        _ = parser.add_argument("--verbose", action="store_true", help="Verbose")
        _ = parser.add_argument("--debug", action="store_true", help="LogLevel Debug")
        args = parser.parse_args(namespace=Args())

        args.verbose = args.verbose or os.environ.get("VERBOSE", "") not in ["0", ""]
        args.debug = args.debug or os.environ.get("PYWHL_DEBUG", "") not in ["0", ""]
        log.setLevel(logging.DEBUG if args.debug else (logging.INFO if args.verbose else logging.WARNING))
        instance = CMakeBuildWheel(args)

        if args.install:
            instance.install(args.editable, args.force_reinstall)
            if args.dep_file:
                instance.generate_depfile(args.dep_file, args.dep_file)
        if args.package:
            instance.whl_file_name = Path(args.package.name)
            whl_file: Path = instance.build_wheel(args.package.parent, None, None)
            if whl_file.as_posix() != args.package.as_posix():
                raise CMakeBuildWheelError(
                    f"Unexpected output file: {whl_file.as_posix()} != {args.package.as_posix()}",
                )
            if args.dep_file:
                instance.generate_depfile(args.dep_file, whl_file)


# The following functions are required by
# PEP 517 A build-system independent format for source trees
# https://peps.python.org/pep-0517/#build-backend-api
# The current file can be used as a build backend from a pyproject.toml file


def get_requires_for_build_wheel(
    config_settings: dict[str, object] | None = None,
) -> list[str]:
    return CMakeBuildWheel.instance().get_requires_for_build_wheel(config_settings)


def get_requires_for_build_sdist(
    config_settings: dict[str, object] | None = None,
) -> list[str]:
    return CMakeBuildWheel.instance().get_requires_for_build_sdist(config_settings)


def build_wheel(
    wheel_directory: str,
    config_settings: dict[str, object] | None = None,
    metadata_directory: str | None = None,
) -> str:
    return CMakeBuildWheel.instance().build_wheel(Path(wheel_directory), config_settings, metadata_directory).as_posix()


def build_sdist(
    sdist_directory: str,
    config_settings: dict[str, object] | None = None,
) -> str:
    return CMakeBuildWheel.instance().build_sdist(sdist_directory, config_settings)


def prepare_metadata_for_build_wheel(
    metadata_directory: str,
    config_settings: dict[str, object] | None = None,
) -> str:
    return CMakeBuildWheel.instance().prepare_metadata_for_build_wheel(metadata_directory, config_settings)


def build_editable(
    wheel_directory: str,
    config_settings: dict[str, object] | None = None,
    metadata_directory: str | None = None,
) -> str:
    return CMakeBuildWheel.instance().build_editable(wheel_directory, config_settings, metadata_directory)


def prepare_metadata_for_build_editable(
    metadata_directory: str,
    config_settings: dict[str, object] | None = None,
) -> str:
    return CMakeBuildWheel.instance().prepare_metadata_for_build_editable(metadata_directory, config_settings)


if __name__ == "__main__":
    CMakeBuildWheel.main()
]====])
set(PYWHL_CONTENTS_EDITABLE_FINDER_PY [====[
# This is adapted from setuptools finder code
# It helps the python environment locate modules and namespaces when in editable mode
# where these python files arent installed in the site-packages directory but are located
# in their original location inside the sources directory
# This file is imported via the companion .pth file which is always sourced into the python env
# Sourcing this file also adds __editable_<name> into the sys.modules list

import importlib.abc
import sys
from collections.abc import Sequence
from importlib.machinery import ModuleSpec, PathFinder
from importlib.machinery import all_suffixes as module_suffixes
from importlib.util import spec_from_file_location
from itertools import chain
from pathlib import Path
from types import ModuleType
from typing import override

MAPPING: dict[str, str] = {}  # TEMPLATE-SUBSTITUTION-MARKER
NAMESPACES: dict[str, str] = {}  # TEMPLATE-SUBSTITUTION-MARKER
PATH_PLACEHOLDER: str = ".__path_hook__"  # TEMPLATE-SUBSTITUTION-MARKER


class PyWhlEditableNamespaceFinder(importlib.abc.PathEntryFinder):
    def _paths(self, fullname: str) -> list[str]:
        # Ensure __path__ is not empty for the spec to be considered a namespace.
        return [NAMESPACES.get(fullname) or MAPPING.get(fullname) or PATH_PLACEHOLDER]

    @override
    def find_spec(self, fullname: str, target: ModuleType | None = None) -> ModuleSpec | None:
        if fullname in NAMESPACES:
            spec = ModuleSpec(fullname, None, is_package=True)
            spec.submodule_search_locations = self._paths(fullname)
            return spec
        return None

    def find_module(self, _fullname: str) -> None:
        return None


class PyWhlEditableFinder(importlib.abc.MetaPathFinder):  # MetaPathFinder
    @override
    def find_spec(
        self,
        fullname: str,
        _path: Sequence[str] | None = None,
        _target: ModuleType | None = None,
        _cache: bool = True,
    ) -> ModuleSpec | None:
        extra_path: list[str] = []

        # Top-level packages and modules (we know these exist in the FS)
        if fullname in MAPPING:
            pkg_path = MAPPING[fullname]
            return self._find_spec(fullname, Path(pkg_path))

        # Handle immediate children modules (required for namespaces to work)
        # To avoid problems with case sensitivity in the file system we delegate
        # to the importlib.machinery implementation.
        parent, _, _child = fullname.rpartition(".")
        if parent and parent in MAPPING:
            return PathFinder.find_spec(fullname, path=[*MAPPING[parent], *extra_path])

        # Other levels of nesting should be handled automatically by importlib
        # using the parent path.
        return None

    def _find_spec(self, fullname: str, candidate_path: Path) -> ModuleSpec | None:
        init = candidate_path / "__init__.py"
        candidates = (candidate_path.with_suffix(x) for x in module_suffixes())
        for candidate in chain([init], candidates):
            if candidate.exists():
                return spec_from_file_location(fullname, candidate)
        return None

    @staticmethod
    def path_hook(path: str) -> PyWhlEditableNamespaceFinder:
        if path == PATH_PLACEHOLDER:
            return PyWhlEditableNamespaceFinder()
        raise ImportError


def install() -> None:
    if not any(isinstance(finder, PyWhlEditableFinder) for finder in sys.meta_path):
        sys.meta_path.append(PyWhlEditableFinder())

    if not any(hook == PyWhlEditableFinder.path_hook for hook in sys.path_hooks):
        # PathEntryFinder is needed to create NamespaceSpec without private APIS
        sys.path_hooks.append(PyWhlEditableFinder.path_hook)

    if PATH_PLACEHOLDER not in sys.path:
        sys.path.append(PATH_PLACEHOLDER)  # Used just to trigger the path hook
]====])
PyWhl_Init()
