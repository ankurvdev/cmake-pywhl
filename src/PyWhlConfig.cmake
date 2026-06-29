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
    cmake_parse_arguments("args" "" "EXCLUDE_REGEX" "DATA;SCRIPTS;TARGETS" ${ARGN})
    
    set(data_files ${args_DATA})
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

