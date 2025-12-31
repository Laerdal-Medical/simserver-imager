# Windows packaging: deployment, installer setup, and post-build steps

# Target Windows 10, in line with Qt requirements
add_definitions(-DWINVER=0x0A00 -D_WIN32_WINNT=0x0A00 -DNTDDI_VERION=0x0A000000)

# Strip debug symbols in release mode
if(CMAKE_STRIP AND CMAKE_BUILD_TYPE MATCHES "^(Release|RelWithDebInfo|MinSizeRel)$")
  add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND "${CMAKE_STRIP}" "$<TARGET_FILE:${PROJECT_NAME}>"
    COMMENT "Stripping $<TARGET_FILE_NAME:${PROJECT_NAME}>"
    VERBATIM)
endif()

# Optional code signing
if (IMAGER_SIGNED_APP)
    # Determine build architecture
    if (CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(arch x64)
    else ()
        set(arch x86)
    endif ()

    # Find signtool from Windows 10 SDK
    if (NOT SIGNTOOL)
        set(win10_kit_versions)
        set(regkey "HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows Kits\\Installed Roots")
        set(regval "KitsRoot10")
        get_filename_component(w10_kits_path "[${regkey};${regval}]" ABSOLUTE CACHE)
        if (w10_kits_path)
            message(WARNING "Found Windows 10 kits path: ${w10_kits_path}")
            file(GLOB w10_kit_versions "${w10_kits_path}/bin/10.*")
            list(REVERSE w10_kit_versions)
        endif ()
        unset(w10_kits_path CACHE)
        if (w10_kit_versions)
            find_program(SIGNTOOL
                NAMES signtool
                PATHS ${w10_kit_versions}
                PATH_SUFFIXES ${arch} bin/${arch} bin
                NO_DEFAULT_PATH
            )
        endif ()
    endif ()

    if (NOT SIGNTOOL)
        message(FATAL_ERROR "Unable to locate signtool.exe used for code signing")
    endif()
    add_definitions(-DSIGNTOOL="${SIGNTOOL}")

    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND "${SIGNTOOL}" sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 /a
                "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.exe")

    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND "${SIGNTOOL}" sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 /a
                "${CMAKE_BINARY_DIR}/laerdal-imager-callback-relay.exe")
endif()

# windeployqt
find_program(WINDEPLOYQT "windeployqt.exe" PATHS "${Qt6_ROOT}/bin")
if (NOT WINDEPLOYQT)
    message(FATAL_ERROR "Unable to locate windeployqt.exe")
endif()

file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/deploy")

add_custom_command(TARGET ${PROJECT_NAME}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.exe"
        "${CMAKE_SOURCE_DIR}/../license.txt"
        "${CMAKE_SOURCE_DIR}/windows/laerdal-imager-cli.cmd"
        "${CMAKE_BINARY_DIR}/laerdal-imager-callback-relay.exe"
        "${CMAKE_BINARY_DIR}/deploy")

add_custom_command(TARGET ${PROJECT_NAME}
    POST_BUILD
    COMMAND "${WINDEPLOYQT}" --no-translations --no-widgets --skip-plugin-types qmltooling --exclude-plugins qtiff,qwebp,qgif --no-quickcontrols2fusion --no-quickcontrols2fusionstyleimpl --no-quickcontrols2universal --no-quickcontrols2universalstyleimpl --no-quickcontrols2imagine --no-quickcontrols2imaginestyleimpl --no-quickcontrols2fluentwinui3styleimpl --no-quickcontrols2windowsstyleimpl --verbose 2 --qmldir "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/deploy/${PROJECT_NAME}.exe")

# Copy MSYS2/MinGW runtime DLLs that libcurl depends on (Brotli, IDN, and their dependencies)
# These are needed because libcurl is built with brotli and IDN support using MSYS2 libraries
# Note: MINGW64_ROOT typically points to Qt's MinGW, but Brotli/IDN may be from MSYS2

# Allow explicit MSYS2 root override, otherwise try to detect it
if(NOT DEFINED MSYS2_MINGW64_ROOT)
    # Try environment variable first
    if(DEFINED ENV{MSYSTEM_PREFIX})
        set(MSYS2_MINGW64_ROOT "$ENV{MSYSTEM_PREFIX}")
    # Then try common paths
    elseif(EXISTS "D:/a/_temp/msys64/mingw64")
        set(MSYS2_MINGW64_ROOT "D:/a/_temp/msys64/mingw64")  # GitHub Actions
    elseif(EXISTS "C:/msys64/mingw64")
        set(MSYS2_MINGW64_ROOT "C:/msys64/mingw64")  # Default MSYS2
    endif()
endif()

set(MSYS2_DLLS
    # Brotli (compression used by HTTP)
    "libbrotlidec.dll"
    "libbrotlicommon.dll"
    # IDN (internationalized domain names)
    "libidn2-0.dll"
    # libidn2 dependencies
    "libunistring-5.dll"
    "libiconv-2.dll"
    # libintl (gettext) - dependency of libidn2
    "libintl-8.dll"
)

# Build list of DLL search paths (checked at build time, not configure time)
set(DLL_SEARCH_PATHS "")
if(MSYS2_MINGW64_ROOT)
    list(APPEND DLL_SEARCH_PATHS "${MSYS2_MINGW64_ROOT}/bin")
endif()
if(MINGW64_ROOT)
    list(APPEND DLL_SEARCH_PATHS "${MINGW64_ROOT}/bin")
endif()

if(DLL_SEARCH_PATHS)
    # Create a CMake script that will run at build time to copy DLLs
    set(COPY_DLLS_SCRIPT "${CMAKE_BINARY_DIR}/copy_msys2_dlls.cmake")
    file(WRITE ${COPY_DLLS_SCRIPT} "# Auto-generated script to copy MSYS2 DLLs\n")
    file(APPEND ${COPY_DLLS_SCRIPT} "set(DLLS ${MSYS2_DLLS})\n")
    file(APPEND ${COPY_DLLS_SCRIPT} "set(SEARCH_PATHS \"${DLL_SEARCH_PATHS}\")\n")
    file(APPEND ${COPY_DLLS_SCRIPT} "set(DEPLOY_DIR \"${CMAKE_BINARY_DIR}/deploy\")\n")
    file(APPEND ${COPY_DLLS_SCRIPT} [[
foreach(dll ${DLLS})
    set(FOUND FALSE)
    foreach(search_path ${SEARCH_PATHS})
        if(EXISTS "${search_path}/${dll}" AND NOT FOUND)
            message(STATUS "Copying ${dll} from ${search_path}")
            file(COPY "${search_path}/${dll}" DESTINATION "${DEPLOY_DIR}")
            set(FOUND TRUE)
        endif()
    endforeach()
    if(NOT FOUND)
        message(WARNING "DLL not found: ${dll}")
    endif()
endforeach()
]])

    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -P "${COPY_DLLS_SCRIPT}"
        COMMENT "Copying MSYS2 runtime DLLs to deploy directory")
else()
    message(WARNING "No MSYS2/MinGW paths found - Brotli and IDN DLLs will not be copied")
endif()

# NSIS or Inno Setup configuration
option(ENABLE_INNO_INSTALLER "Build Inno Setup installer instead of NSIS" OFF)

if(ENABLE_INNO_INSTALLER)
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/installer")
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/windows/laerdal-simserver-imager.iss.in"
        "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.iss"
        @ONLY)

    find_program(INNO_COMPILER NAMES iscc ISCC "iscc.exe" PATHS
        "C:/Program Files (x86)/Inno Setup 6"
        "C:/Program Files/Inno Setup 6"
        DOC "Path to Inno Setup compiler")

    if(INNO_COMPILER)
        if(IMAGER_SIGNED_APP)
            add_custom_target(inno_installer
                COMMAND "${INNO_COMPILER}" "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.iss" "/DSIGNING_ENABLED" "/Ssign=${SIGNTOOL} sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 /a $p"
                DEPENDS ${PROJECT_NAME}
                COMMENT "Building Inno Setup installer"
                VERBATIM)
        else()
            add_custom_target(inno_installer
                COMMAND "${INNO_COMPILER}" "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.iss"
                DEPENDS ${PROJECT_NAME}
                COMMENT "Building Inno Setup installer"
                VERBATIM)
        endif()
        message(STATUS "Added 'inno_installer' target to build the Inno Setup installer")
    else()
        message(WARNING "Inno Setup compiler not found. Install Inno Setup from https://jrsoftware.org/isinfo.php")
    endif()
else()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/windows/laerdal-simserver-imager.nsi.in")
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/windows/laerdal-simserver-imager.nsi.in"
            "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.nsi"
            @ONLY)
    else()
        message(STATUS "NSIS template not found; skipping NSIS installer configuration")
    endif()
endif()

# Resource file generation (contains version info)
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/laerdal-simserver-imager.rc.in"
    "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.rc"
    @ONLY)

# Manifest generation and copying
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/laerdal-simserver-imager.manifest.in"
    "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.manifest"
    @ONLY)

add_custom_command(TARGET ${PROJECT_NAME}
    PRE_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.manifest"
        "${CMAKE_CURRENT_SOURCE_DIR}/windows/laerdal-simserver-imager.manifest"
    DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/laerdal-simserver-imager.manifest"
    COMMENT "Copying generated manifest for resource compilation")



