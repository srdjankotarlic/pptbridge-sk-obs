if(NOT OBS_SOURCE_DIR AND DEFINED ENV{OBS_SOURCE_DIR})
  set(OBS_SOURCE_DIR "$ENV{OBS_SOURCE_DIR}")
endif()

if(NOT OBS_SOURCE_DIR)
  set(_PPTBRIDGE_LOCAL_OBS_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../third_party/obs-studio")
  if(EXISTS "${_PPTBRIDGE_LOCAL_OBS_SOURCE_DIR}/libobs/obs-module.h")
    set(OBS_SOURCE_DIR "${_PPTBRIDGE_LOCAL_OBS_SOURCE_DIR}")
  endif()
endif()

if(NOT OBS_APP_DIR AND DEFINED ENV{OBS_APP_DIR})
  set(OBS_APP_DIR "$ENV{OBS_APP_DIR}")
endif()

if(NOT OBS_APP_DIR)
  set(OBS_APP_DIR "/Applications/OBS.app")
endif()

find_path(OBS_INCLUDE_DIR
  NAMES obs-module.h
  HINTS
    "${OBS_SOURCE_DIR}/libobs"
    "${OBS_SOURCE_DIR}/UI"
)

find_path(OBS_FRONTEND_INCLUDE_DIR
  NAMES obs-frontend-api.h
  HINTS
    "${OBS_SOURCE_DIR}/frontend/api"
    "${OBS_SOURCE_DIR}/UI/obs-frontend-api"
)

if(EXISTS "${OBS_APP_DIR}/Contents/Frameworks/libobs.framework")
  set(OBS_LIBOBS_LIBRARY "${OBS_APP_DIR}/Contents/Frameworks/libobs.framework")
else()
  find_library(OBS_LIBOBS_LIBRARY
    NAMES libobs
    HINTS
      "${OBS_APP_DIR}/Contents/Frameworks"
      "${OBS_APP_DIR}/Contents/Frameworks/libobs.framework"
  )
endif()

if(EXISTS "${OBS_APP_DIR}/Contents/Frameworks/obs-frontend-api.dylib")
  set(OBS_FRONTEND_LIBRARY "${OBS_APP_DIR}/Contents/Frameworks/obs-frontend-api.dylib")
else()
  find_library(OBS_FRONTEND_LIBRARY
    NAMES obs-frontend-api
    HINTS
      "${OBS_APP_DIR}/Contents/Frameworks"
  )
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(OBS
  REQUIRED_VARS
    OBS_INCLUDE_DIR
    OBS_FRONTEND_INCLUDE_DIR
    OBS_LIBOBS_LIBRARY
    OBS_FRONTEND_LIBRARY
)

mark_as_advanced(
  OBS_INCLUDE_DIR
  OBS_FRONTEND_INCLUDE_DIR
  OBS_LIBOBS_LIBRARY
  OBS_FRONTEND_LIBRARY
)
