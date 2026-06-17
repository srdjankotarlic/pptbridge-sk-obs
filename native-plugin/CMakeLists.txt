cmake_minimum_required(VERSION 3.21)

set(PPTBRIDGE_LANGUAGES CXX)
if(APPLE)
  list(APPEND PPTBRIDGE_LANGUAGES OBJCXX)
endif()

project(pptbridge-obs-native VERSION 0.5.2 LANGUAGES ${PPTBRIDGE_LANGUAGES})

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

if(APPLE)
  find_path(SIMDE_INCLUDE_DIR
    NAMES simde/simde-common.h
    HINTS /opt/homebrew/include /usr/local/include
  )

  if(NOT SIMDE_INCLUDE_DIR)
    message(FATAL_ERROR "SIMDe headers were not found. Install simde or point CMake to its include directory.")
  endif()
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

set(PPTBRIDGE_SOURCES
  src/pptbridge_osc_server.cpp
  src/pptbridge_registry.cpp
)

if(APPLE)
  list(APPEND PPTBRIDGE_SOURCES
    src/plugin-main.mm
    src/presentation_document.mm
    src/source_slide.mm
    src/source_presenter.mm
  )
elseif(WIN32)
  list(APPEND PPTBRIDGE_SOURCES
    src/plugin-main.cpp
    src/presentation_document_win.cpp
    src/source_slide_win.cpp
    src/source_presenter.cpp
  )
else()
  message(FATAL_ERROR "PPTBridge SK currently supports only macOS and Windows builds.")
endif()

add_library(pptbridge-obs MODULE ${PPTBRIDGE_SOURCES})

target_include_directories(pptbridge-obs PRIVATE
  "${OBS_INCLUDE_DIR}"
  "${OBS_FRONTEND_INCLUDE_DIR}"
  "${CMAKE_CURRENT_BINARY_DIR}/generated"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

if(APPLE)
  target_include_directories(pptbridge-obs PRIVATE "${SIMDE_INCLUDE_DIR}")
endif()

target_compile_definitions(pptbridge-obs PRIVATE
  PPTBRIDGE_OBS_NATIVE_VERSION="${PROJECT_VERSION}"
)

if(APPLE)
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
elseif(WIN32)
  target_compile_definitions(pptbridge-obs PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    UNICODE
    _UNICODE
    _CRT_SECURE_NO_WARNINGS
  )

  target_link_libraries(pptbridge-obs PRIVATE
    ${OBS_LIBOBS_LIBRARY}
    ${OBS_FRONTEND_LIBRARY}
    ws2_32
    gdiplus
    ole32
    shell32
  )

  set_target_properties(pptbridge-obs PROPERTIES
    PREFIX ""
    OUTPUT_NAME "pptbridge-obs"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bundle"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bundle"
  )

  add_custom_command(TARGET pptbridge-obs POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
      "$<TARGET_FILE_DIR:pptbridge-obs>/data/obs-plugins/pptbridge-obs"
    COMMAND "${CMAKE_COMMAND}" -E copy_directory
      "${CMAKE_CURRENT_SOURCE_DIR}/data"
      "$<TARGET_FILE_DIR:pptbridge-obs>/data/obs-plugins/pptbridge-obs"
  )

  install(TARGETS pptbridge-obs
    RUNTIME DESTINATION "obs-plugins/64bit"
    LIBRARY DESTINATION "obs-plugins/64bit"
  )
  install(DIRECTORY data/ DESTINATION "data/obs-plugins/pptbridge-obs")
endif()
