cmake_minimum_required(VERSION 3.21)

project(pptbridge-obs-native VERSION 0.1.0 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

set(PPTBRIDGE_BRAND_NAME "PPTBridge SK for OBS")
set(PPTBRIDGE_AUTHOR_NAME "Srđan Kotarlić")

option(PPTBRIDGE_INSTALL_TO_USER_OBS "Install to the current user's OBS plugin folder" OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

find_package(OBS REQUIRED)
find_path(SIMDE_INCLUDE_DIR
  NAMES simde/simde-common.h
  HINTS /opt/homebrew/include /usr/local/include
)

if(NOT SIMDE_INCLUDE_DIR)
  message(FATAL_ERROR "SIMDe headers were not found. Install simde or point CMake to its include directory.")
endif()

set(OBS_DATA_PATH "data")
set(OBS_PLUGIN_PATH "plugins")
set(OBS_PLUGIN_DESTINATION "plugins")
set(OBS_RELEASE_CANDIDATE 0)
set(OBS_BETA 0)

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")
configure_file(
  "${OBS_SOURCE_DIR}/libobs/obsconfig.h.in"
  "${CMAKE_CURRENT_BINARY_DIR}/generated/obsconfig.h"
  @ONLY
)

add_library(pptbridge-obs MODULE
  src/plugin-main.mm
  src/presentation_document.mm
  src/pptbridge_registry.cpp
  src/source_slide.mm
  src/source_presenter.mm
)

target_include_directories(pptbridge-obs PRIVATE
  "${OBS_INCLUDE_DIR}"
  "${OBS_FRONTEND_INCLUDE_DIR}"
  "${SIMDE_INCLUDE_DIR}"
  "${CMAKE_CURRENT_BINARY_DIR}/generated"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_compile_definitions(pptbridge-obs PRIVATE
  PPTBRIDGE_OBS_NATIVE_VERSION="${PROJECT_VERSION}"
)

target_compile_options(pptbridge-obs PRIVATE
  "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

target_link_libraries(pptbridge-obs PRIVATE
  ${OBS_LIBOBS_LIBRARY}
  ${OBS_FRONTEND_LIBRARY}
  "-framework Foundation"
  "-framework AppKit"
  "-framework PDFKit"
  "-framework CoreGraphics"
)

set_target_properties(pptbridge-obs PROPERTIES
  PREFIX ""
  OUTPUT_NAME "pptbridge-obs"
  BUNDLE TRUE
  BUNDLE_EXTENSION "plugin"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Info.plist.in"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bundle"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bundle"
)

add_custom_command(TARGET pptbridge-obs POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E make_directory
    "$<TARGET_BUNDLE_CONTENT_DIR:pptbridge-obs>/Resources"
  COMMAND "${CMAKE_COMMAND}" -E copy_directory
    "${CMAKE_CURRENT_SOURCE_DIR}/data"
    "$<TARGET_BUNDLE_CONTENT_DIR:pptbridge-obs>/Resources"
)

install(TARGETS pptbridge-obs
  LIBRARY DESTINATION "."
  BUNDLE DESTINATION "."
)
install(DIRECTORY data/ DESTINATION "pptbridge-obs.plugin/Contents/Resources")

if(PPTBRIDGE_INSTALL_TO_USER_OBS)
  install(CODE [[
    set(OBS_PLUGIN_HOME "$ENV{HOME}/Library/Application Support/obs-studio/plugins")
    file(MAKE_DIRECTORY "${OBS_PLUGIN_HOME}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E copy_directory
      "${CMAKE_INSTALL_PREFIX}/pptbridge-obs.plugin"
      "${OBS_PLUGIN_HOME}/pptbridge-obs.plugin"
    )
  ]])
endif()
