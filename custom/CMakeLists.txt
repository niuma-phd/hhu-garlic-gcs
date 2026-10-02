# ============================================================================
# 河海大学 大蒜播种车地面站 — QGC custom plugin
# Derived from upstream custom-example (QGC v5.1.4)
# ============================================================================

message(STATUS "QGC: Adding HHU Custom Plugin")

# Product version (检查更新 compares against it; sent in the 4G login)
set(HHU_APP_VERSION "1.0.1")

# ============================================================================
# Custom Resources
# ============================================================================

list(APPEND CUSTOM_RESOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/custom.qrc
)
set(QGC_RESOURCES ${QGC_RESOURCES} ${CUSTOM_RESOURCES} CACHE STRING "Paths to .qrc Resources" FORCE)

set(QML_IMPORT_PATH ${QML_IMPORT_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/res" CACHE STRING "Extra qml import paths" FORCE)

# ============================================================================
# HHU QML module (status bar, work panel, progress card)
# ============================================================================

qt_add_library(HHUControlsModule STATIC)

file(GLOB HHU_CONTROLS_QML CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/qml/HHU/Controls/*.qml ${CMAKE_CURRENT_SOURCE_DIR}/src/qml/HHU/Controls/*.js)
qgc_set_qt_resource_alias(${HHU_CONTROLS_QML})
set_source_files_properties(${CMAKE_CURRENT_SOURCE_DIR}/src/qml/HHU/Controls/HHUStyle.qml ${CMAKE_CURRENT_SOURCE_DIR}/src/qml/HHU/Controls/HHUState.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(HHUControlsModule
    URI HHU.Controls
    VERSION 1.0
    RESOURCE_PREFIX /qml
    QML_FILES
        ${HHU_CONTROLS_QML}
    NO_PLUGIN
)

# ============================================================================
# Editable tables (STATUSTEXT / PreArm translations, VCU fault codes): copied next to the
# executable as config/hhu_config.json; a copy is also built into the program (custom.qrc)
# ============================================================================

file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/res/config/hhu_config.json DESTINATION ${CMAKE_BINARY_DIR}/Release/config)
file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/res/config/hhu_config.json DESTINATION ${CMAKE_BINARY_DIR}/Debug/config)
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/res/config/hhu_config.json DESTINATION ${CMAKE_INSTALL_BINDIR}/config)

# UI fonts (HarmonyOS Sans SC, Barlow) next to the executable as fonts/ — loaded by CustomPlugin.
# HarmonyOS Sans: bundled unmodified with its license as the license requires (no subsetting).
file(GLOB HHU_FONT_FILES ${CMAKE_CURRENT_SOURCE_DIR}/res/fonts/*)
file(COPY ${HHU_FONT_FILES} DESTINATION ${CMAKE_BINARY_DIR}/Release/fonts)
file(COPY ${HHU_FONT_FILES} DESTINATION ${CMAKE_BINARY_DIR}/Debug/fonts)
install(FILES ${HHU_FONT_FILES} DESTINATION ${CMAKE_INSTALL_BINDIR}/fonts)

# ============================================================================
# Custom Plugin Sources
# ============================================================================

set(CUSTOM_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/CustomPlugin.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/CustomPlugin.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHU4GLink.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHU4GLink.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUConfig.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUConfig.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUFieldManager.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUFieldManager.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHULinkMonitor.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHULinkMonitor.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUNtrip.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUNtrip.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUSecret.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUSecret.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUService.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUService.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUSettings.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUSettings.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUVcuStatus.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUVcuStatus.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUWorkLog.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/HHUWorkLog.h
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_LIBRARIES
    HHUControlsModule
    Qt6::CorePrivate    # QZipWriter (log upload)
    Crypt32             # DPAPI (passwords)
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_INCLUDE_DIRECTORIES
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_DEFINITIONS
    QGC_CUSTOM_BUILD
    CUSTOMHEADER="CustomPlugin.h"
    CUSTOMCLASS=CustomPlugin
    HHU_APP_VERSION="${HHU_APP_VERSION}"
    CACHE INTERNAL "" FORCE
)

set(CUSTOM_QT_COMPONENTS
    Core
    CorePrivate
    Network
    CACHE INTERNAL "" FORCE
)
