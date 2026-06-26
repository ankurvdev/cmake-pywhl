# cmake-pywhl

A CMake module for building Python wheels directly from CMake projects. It integrates compiled C/C++ extensions (via nanobind, pybind11, ctypes, etc.) and pure Python source files into PEP 427-compliant wheel archives, with full support for PEP 660 editable installs.

## Requirements

- CMake 3.20+
- Python 3.12+


### 2. Integrate into your CMakeLists.txt

```cmake
nanobind_add_module(_myext src/_myext.cpp)

# Declare a pywhl module (maps to a top-level Python package)
add_pywhl_module(mypackage
    TARGETS _myext
    SCRIPTS mypackage          # directory or individual .py files
)

# Create wheel and editable-install targets
add_pywhl_package(mypackage
    VERSION "${PROJECT_VERSION}"
    MODULES mypackage
    LICENSE_FILE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE"
    METADATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/METADATA"
)
```

### 3. Build

```bash
cmake -B build -DCMAKE_MODULE_PATH=/path/to/pywhl
cmake --build build          # builds editable install (ALL target)
cmake --build build --target mypackage   # builds the .whl file
```

The editable install target (`mypackage_dev_whl`) runs as part of `ALL` and installs import hooks into the active Python environment via a `.pth` file. The wheel target (`mypackage`) produces a distributable `.whl` archive.

## API Reference

### `add_pywhl_module(name ...)`

Registers a Python module (package directory) that will be included in a wheel.

| Parameter | Description |
|-----------|-------------|
| `TARGETS target1 ...` | CMake targets (compiled libraries or executables) whose output files are bundled |
| `SCRIPTS file_or_dir ...` | Python source files or directories; a directory with `__init__.py` is treated as a package |
| `DATA_FILES file ...` | Arbitrary data files to bundle |
| `EXCLUDE_REGEX pattern` | Regex pattern to exclude matching paths |

Scripts and data files can use `src@dest` syntax to rename items inside the wheel: `mymodule/config.ini@config.ini`.

### `add_pywhl_package(targetName ...)`

Creates two CMake targets: a wheel-build target (`targetName`) and an editable-install target (default: `targetName_dev_whl`, runs as `ALL`).

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MODULES mod1 ...` | required | List of module names registered with `add_pywhl_module` |
| `VERSION x.y.z` | `0.0.1` | Wheel version |
| `LICENSE_FILE path` | `./LICENSE` | License file (required) |
| `METADATA_FILE path` | `./METADATA` | Package metadata template (Python `string.Template` syntax with `${name}`, `${version}`) |
| `ENTRY_POINTS_FILE path` | `./entry_points.txt` | Console scripts / entry points |
| `EDITABLE_TARGET name` | `targetName_dev_whl` | Override the editable target name |
| `whl_file_OUTVAR var` | — | CMake variable to receive the output wheel path |


## METADATA template

The `METADATA` file is a Python `string.Template` supporting `${name}` and `${version}` substitutions:

```
Metadata-Version: 2.1
Name: ${name}
Version: ${version}
Summary: My package
Author: Your Name
License: MIT
```

## entry_points.txt

Standard INI format accepted by pip:

```ini
[console_scripts]
my-tool = mypackage.cli:main
```

## Project layout example

```
myproject/
├── CMakeLists.txt
├── LICENSE
├── METADATA
├── entry_points.txt          # optional
├── src/
│   └── _myext.cpp            # C++ nanobind extension
└── mypackage/
    ├── __init__.py           # imports from _myext
    └── helpers.py
```

## License

MIT — see [LICENSE](LICENSE).
