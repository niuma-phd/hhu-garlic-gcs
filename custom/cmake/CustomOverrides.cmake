# ============================================================================
# 河海大学 大蒜播种车地面站 — QGC custom build overrides
# ============================================================================

# ----------------------------------------------------------------------------
# Application Branding
# ----------------------------------------------------------------------------
set(QGC_APP_NAME "HHU-GCS" CACHE STRING "App Name" FORCE)
set(QGC_APP_DESCRIPTION "河海大学 大蒜播种车地面站" CACHE STRING "Application description" FORCE)
set(QGC_ORG_NAME "HHU" CACHE STRING "Organization name" FORCE)
set(QGC_ORG_DOMAIN "hhu.edu.cn" CACHE STRING "Organization domain" FORCE)
set(QGC_PACKAGE_NAME "cn.edu.hhu.gcs" CACHE STRING "Package identifier" FORCE)
set(QGC_ANDROID_PACKAGE_NAME "cn.edu.hhu.gcs" CACHE STRING "Android package identifier" FORCE)

# ----------------------------------------------------------------------------
# Custom Icons and Graphics
# ----------------------------------------------------------------------------
if(EXISTS "${CMAKE_SOURCE_DIR}/${QGC_CUSTOM_DIR}/deploy/windows/WindowsQGC.ico")
    set(QGC_WINDOWS_ICON_PATH "${CMAKE_SOURCE_DIR}/${QGC_CUSTOM_DIR}/deploy/windows/WindowsQGC.ico" CACHE FILEPATH "Windows Icon Path" FORCE)
endif()

# ----------------------------------------------------------------------------
# Feature Set Customization
# ----------------------------------------------------------------------------
# ArduPilot Rover only: drop the PX4 plugin factory, keep the stock APM one.
set(QGC_DISABLE_PX4_PLUGIN_FACTORY ON CACHE BOOL "Disable PX4 Plugin Factory" FORCE)
set(QGC_DISABLE_APM_PLUGIN_FACTORY OFF CACHE BOOL "Disable APM Plugin Factory" FORCE)

# No video on this vehicle
set(QGC_ENABLE_GST_VIDEOSTREAMING OFF CACHE BOOL "Enable GStreamer video backend" FORCE)

# Release branding: no " Daily" suffix on the app name
set(QGC_STABLE_BUILD ON CACHE BOOL "Stable release build" FORCE)
