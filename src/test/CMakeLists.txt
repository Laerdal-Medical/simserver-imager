# Test configuration for rpi-imager Uses Catch2 and CTest for testing

# Fetch Catch2 for testing
include(FetchContent)

FetchContent_Declare(
  Catch2
  GIT_REPOSITORY https://github.com/catchorg/Catch2.git
  GIT_TAG v3.5.2
  FIND_PACKAGE_ARGS NAMES Catch2)

FetchContent_MakeAvailable(Catch2)

# Include Catch2 CMake utilities for test discovery
list(APPEND CMAKE_MODULE_PATH ${catch2_SOURCE_DIR}/extras)
include(Catch)

# Add the customization generator test executable
add_executable(
  customization_generator_test
  ${CMAKE_CURRENT_SOURCE_DIR}/../customization_generator.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../customization_generator.cpp
  customization_generator_test.cpp)

# Link against Catch2 and Qt
target_link_libraries(customization_generator_test
                      PRIVATE Catch2::Catch2WithMain Qt6::Core Qt6::Network)

# Include parent directory for headers
target_include_directories(customization_generator_test
                           PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)

target_compile_features(customization_generator_test PRIVATE cxx_std_20)
target_compile_options(
  customization_generator_test PRIVATE -Wall -Wextra -Wpedantic
                                       $<$<CONFIG:Debug>:-g -O0>)

# Register with CTest for automatic test discovery
catch_discover_tests(customization_generator_test PROPERTIES LABELS "unit")

if(NOT BUILD_CLI_ONLY)
  add_executable(qml_utils_test qml_utils_test.cpp)
  target_link_libraries(qml_utils_test PRIVATE Catch2::Catch2
                        Qt6::Core Qt6::Qml Qt6::Gui)
  target_compile_definitions(
    qml_utils_test PRIVATE TEST_QML_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/..")
  target_compile_features(qml_utils_test PRIVATE cxx_std_20)
  target_compile_options(qml_utils_test PRIVATE -Wall -Wextra -Wpedantic
                                                $<$<CONFIG:Debug>:-g -O0>)
  catch_discover_tests(
    qml_utils_test PROPERTIES LABELS "unit" ENVIRONMENT
                               "QT_QPA_PLATFORM=offscreen")
endif()

add_executable(
  core_io_test
  core_io_test.cpp
  ../ringbuffer.cpp
  ../archiveentryiodevice.cpp
  ../archiveentryiodevice.h
  ../asynccachewriter.cpp
  ../systemmemorymanager.cpp)
if(WIN32)
  target_sources(core_io_test PRIVATE ../windows/acceleratedcryptographichash_cng.cpp)
  target_link_libraries(core_io_test PRIVATE bcrypt)
elseif(APPLE)
  target_sources(core_io_test PRIVATE ../mac/acceleratedcryptographichash_commoncrypto.cpp)
else()
  target_sources(core_io_test PRIVATE ../linux/acceleratedcryptographichash_gnutls.cpp)
  target_link_libraries(core_io_test PRIVATE GnuTLS::GnuTLS)
endif()
set_target_properties(core_io_test PROPERTIES AUTOMOC ON)
target_include_directories(core_io_test PRIVATE ..
                           ${LibArchive_INCLUDE_DIRS})
target_link_libraries(core_io_test PRIVATE Catch2::Catch2WithMain
                      Qt6::Core ${LibArchive_LIBRARIES})
target_compile_features(core_io_test PRIVATE cxx_std_20)
target_compile_options(core_io_test PRIVATE -Wall -Wextra -Wpedantic
                                             $<$<CONFIG:Debug>:-g -O0>)
catch_discover_tests(core_io_test PROPERTIES LABELS "unit" TIMEOUT 30)

add_executable(downloadonly_test downloadonly_test.cpp
               ../downloadonly.cpp ../curlnetworkconfig.cpp ../platformhelper.cpp
               ../urlfmt.cpp platformquirks_test_stubs.cpp)
set_target_properties(downloadonly_test PROPERTIES AUTOMOC ON)
target_compile_definitions(downloadonly_test PRIVATE CLI_ONLY_BUILD)
target_include_directories(downloadonly_test PRIVATE ..
                           ${CURL_INCLUDE_DIRS} ${LibArchive_INCLUDE_DIRS})
target_compile_features(downloadonly_test PRIVATE cxx_std_20)
target_link_libraries(downloadonly_test PRIVATE Catch2::Catch2WithMain
                      Qt6::Core Qt6::Network ${CURL_LIBRARIES} ${LibArchive_LIBRARIES})
catch_discover_tests(downloadonly_test PROPERTIES LABELS "unit")

# Also add a custom target for manual running
add_custom_target(
  test_customization_generator
  COMMAND customization_generator_test
  DEPENDS customization_generator_test
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  COMMENT "Running customization generator tests")

# Determine platform-specific file operations implementation for FAT partition
# test
if(WIN32)
  set(PLATFORM_FILE_OPS
      ${CMAKE_CURRENT_SOURCE_DIR}/../windows/file_operations_windows.h
      ${CMAKE_CURRENT_SOURCE_DIR}/../windows/file_operations_windows.cpp)
elseif(APPLE)
  set(PLATFORM_FILE_OPS
      ${CMAKE_CURRENT_SOURCE_DIR}/../mac/file_operations_macos.h
      ${CMAKE_CURRENT_SOURCE_DIR}/../mac/file_operations_macos.cpp
      ${CMAKE_CURRENT_SOURCE_DIR}/../mac/macfile.h
      ${CMAKE_CURRENT_SOURCE_DIR}/../mac/macfile.cpp)
else()
  set(PLATFORM_FILE_OPS
      ${CMAKE_CURRENT_SOURCE_DIR}/../linux/file_operations_linux.h
      ${CMAKE_CURRENT_SOURCE_DIR}/../linux/file_operations_linux.cpp)
endif()

add_executable(
  disk_formatter_test
  ${CMAKE_CURRENT_SOURCE_DIR}/../disk_formatter.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../disk_formatter.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../file_operations.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../file_operations.cpp
  ${PLATFORM_FILE_OPS}
  ${CMAKE_CURRENT_SOURCE_DIR}/../disk_formatter_test.cpp)
set_target_properties(disk_formatter_test PROPERTIES AUTOMOC ON)
target_link_libraries(disk_formatter_test PRIVATE Catch2::Catch2WithMain
                                                  Qt6::Core)
target_include_directories(disk_formatter_test
                           PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_compile_features(disk_formatter_test PRIVATE cxx_std_20)
target_compile_options(disk_formatter_test PRIVATE -Wall -Wextra -Wpedantic
                                                   $<$<CONFIG:Debug>:-g -O0>)
if(APPLE)
  target_link_libraries(
    disk_formatter_test
    PRIVATE "-framework Security" "-framework DiskArbitration"
            "-framework CoreFoundation")
endif()
catch_discover_tests(disk_formatter_test PROPERTIES LABELS "unit")

# Add the FAT partition test executable (manual test against real filesystem)
add_executable(
  fat_partition_test
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapper.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapper.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapperpartition.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapperpartition.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapperblockcacheentry.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapperblockcacheentry.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapperfatpartition.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../devicewrapperfatpartition.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../file_operations.h
  ${CMAKE_CURRENT_SOURCE_DIR}/../file_operations.cpp
  ${PLATFORM_FILE_OPS}
  ${CMAKE_CURRENT_SOURCE_DIR}/../fat_partition_test.cpp)

# Enable Qt MOC for Q_OBJECT classes
set_target_properties(fat_partition_test PROPERTIES AUTOMOC ON)

# Link Catch2 and Qt libraries
target_link_libraries(fat_partition_test PRIVATE Catch2::Catch2WithMain
                                                 Qt6::Core)

# Link platform-specific libraries
if(APPLE)
  target_link_libraries(
    fat_partition_test
    PRIVATE "-framework Security" "-framework DiskArbitration"
            "-framework CoreFoundation")
endif()

# Include parent directory for headers
target_include_directories(fat_partition_test
                           PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)

target_compile_features(fat_partition_test PRIVATE cxx_std_20)
target_compile_options(fat_partition_test PRIVATE -Wall -Wextra -Wpedantic
                                                  $<$<CONFIG:Debug>:-g -O0>)

# These tests access a real partition and include writes. Keep them out of
# CTest; run explicitly against disposable media with both opt-in variables set.
add_custom_target(
  test_fat_partition
  COMMAND ${CMAKE_COMMAND} -E echo
          "Hardware tests are hidden from default runs and CTest."
  COMMAND ${CMAKE_COMMAND} -E echo
          "Use FAT_TEST_PARTITION_DEVICE=/dev/<partition> FAT_TEST_ALLOW_WRITES=1 ./fat_partition_test '[.fat-hardware]'"
  DEPENDS fat_partition_test
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  COMMENT "FAT partition test built; run explicitly against disposable media")

# Device/filename compatibility that gates CI and release build selection
add_executable(devicedetection_test devicedetection_test.cpp
               ../devicedetection.cpp)
target_include_directories(devicedetection_test PRIVATE ..)
target_compile_features(devicedetection_test PRIVATE cxx_std_20)
target_link_libraries(devicedetection_test PRIVATE Catch2::Catch2WithMain
                                                   Qt6::Core)
catch_discover_tests(devicedetection_test PROPERTIES LABELS "unit")

# OS/hardware list models and drive item, built without ImageWriter
add_executable(model_test oslistmodel_test.cpp hwlistmodel_test.cpp
               ../oslistmodel.cpp ../hwlistmodel.cpp ../drivelistitem.cpp)
set_target_properties(model_test PROPERTIES AUTOMOC ON)
target_compile_definitions(model_test PRIVATE CLI_ONLY_BUILD)
target_include_directories(model_test PRIVATE ..)
target_compile_features(model_test PRIVATE cxx_std_20)
target_link_libraries(model_test PRIVATE Catch2::Catch2WithMain Qt6::Core)
catch_discover_tests(model_test PROPERTIES LABELS "unit")

# Repository manager, CDN/GitHub sources (offline, signal driven; no QtGui)
add_executable(
  repository_github_test
  repository_github_test.cpp
  ../repository/repositorymanager.cpp
  ../repository/githubsource.cpp
  ../repository/laerdalcdnsource.cpp
  ../github/githubclient.cpp
  ../devicedetection.cpp)
set_target_properties(repository_github_test PROPERTIES AUTOMOC ON)
target_compile_definitions(repository_github_test PRIVATE CLI_ONLY_BUILD)
target_include_directories(repository_github_test
                           PRIVATE .. ${LibArchive_INCLUDE_DIRS})
target_compile_features(repository_github_test PRIVATE cxx_std_20)
target_link_libraries(repository_github_test
                      PRIVATE Catch2::Catch2 Qt6::Core Qt6::Network
                              ${LibArchive_LIBRARIES})
catch_discover_tests(repository_github_test PROPERTIES LABELS "unit")
