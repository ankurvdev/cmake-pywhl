cmake_minimum_required(VERSION 3.20)
project(nanobind_example_wrap VERSION 0.0.1)

find_package(Python3 REQUIRED COMPONENTS Interpreter Development.Module)

execute_process(
    COMMAND "${Python3_EXECUTABLE}" -m pip install --upgrade pip nanobind
    COMMAND_ERROR_IS_FATAL ANY
)
execute_process(
    COMMAND "${Python3_EXECUTABLE}" -c "import nanobind; print(nanobind.cmake_dir())"
    OUTPUT_VARIABLE NANOBIND_CMAKE_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)

list(APPEND CMAKE_PREFIX_PATH "${NANOBIND_CMAKE_DIR}")

# ---------------------------------------------------------------------------
# Download the upstream wjakob/nanobind_example source.
# We intentionally do NOT call add_subdirectory on it: the upstream
# CMakeLists.txt requires scikit-build, not cmake-pywhl.  We only need
# the C++ source file.
# ---------------------------------------------------------------------------
include(FetchContent)
FetchContent_Declare(nanobind_example_upstream
    GIT_REPOSITORY https://github.com/wjakob/nanobind_example.git
    GIT_TAG        master
    GIT_SHALLOW    TRUE
)
FetchContent_GetProperties(nanobind_example_upstream)
if(NOT nanobind_example_upstream_POPULATED)
    FetchContent_Populate(nanobind_example_upstream)
endif()

add_subdirectory(${nanobind_example_upstream_SOURCE_DIR} nanobind_example)

find_package(PyWhl CONFIG REQUIRED)
add_pywhl_module(nanobind_example
    TARGETS nanobind_example_ext
    SCRIPTS
        ${nanobind_example_upstream_SOURCE_DIR}/src/nanobind_example
        ${CMAKE_CURRENT_SOURCE_DIR}/scripts/example.py
)

add_pywhl_package(nanobind_example
    VERSION "${PROJECT_VERSION}"
    MODULES nanobind_example
    LICENSE_FILE
        "${nanobind_example_upstream_SOURCE_DIR}/LICENSE"
)

add_custom_target(all_whl DEPENDS nanobind_example)
