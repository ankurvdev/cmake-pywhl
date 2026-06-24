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
