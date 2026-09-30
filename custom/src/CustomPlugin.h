#pragma once

#include <QtCore/QTranslator>
#include <QtQml/QQmlAbstractUrlInterceptor>

#include "QGCCorePlugin.h"
#include "QGCOptions.h"

class CustomOptions;
class CustomPlugin;
class HHU4GLink;
class HHUConfig;
class HHUFieldManager;
class HHUNtrip;
class HHUService;
class HHUWorkLog;
class HHULinkMonitor;
class HHUSettings;
class HHUVcuStatus;
class PlanCreator;
class PlanMasterController;
class Vehicle;
class LinkInterface;
class QQmlApplicationEngine;

Q_DECLARE_LOGGING_CATEGORY(CustomLog)

class CustomFlyViewOptions : public QGCFlyViewOptions
{
    Q_OBJECT

public:
    explicit CustomFlyViewOptions(CustomOptions *options, QObject *parent = nullptr);

    // Overrides from QGCFlyViewOptions

    /// One ground station drives one rover
    bool showMultiVehicleList() const final { return false; }
    /// Aircraft-only guided actions
    bool guidedBarShowOrbit() const final { return false; }
    bool guidedBarShowROI() const final { return false; }
};

/*===========================================================================*/

class CustomOptions : public QGCOptions
{
    Q_OBJECT

public:
    explicit CustomOptions(CustomPlugin *plugin, QObject *parent = nullptr);

    // Overrides from QGCOptions

    /// Firmware is flashed by engineers with Mission Planner
    bool showFirmwareUpgrade() const final { return false; }
    bool showPX4LogTransferOptions() const final { return false; }
    bool multiVehicleEnabled() const final { return false; }
    bool showMissionAbsoluteAltitude() const final { return false; }
    /// Plan view offers waypoints only
    bool missionWaypointsOnly() const final { return true; }
    bool checkFirmwareVersion() const final { return false; }
    /// Hides the altitude profile / stats strip under the route map
    bool showMissionStatus() const final { return false; }
    QGCFlyViewOptions *flyViewOptions() const final { return _flyViewOptions; }

private:
    CustomFlyViewOptions *_flyViewOptions = nullptr;
};

/*===========================================================================*/

class CustomPlugin : public QGCCorePlugin
{
    Q_OBJECT

public:
    explicit CustomPlugin(QObject *parent = nullptr);

    static QGCCorePlugin *instance();

    // Overrides from QGCCorePlugin

    QGCOptions *options() final { return _options; }
    /// Analyze tools are for engineers (Mission Planner), none here
    const QVariantList &analyzePages() final { return _emptyList; }
    /// Hide whole settings groups that do not apply to this product
    bool overrideSettingsGroupVisibility(const QString &name) final;
    /// Product defaults (Chinese, TianDiTu, ArduPilot Rover, light theme)
    void adjustSettingMetaData(const QString &settingsGroup, FactMetaData &metaData, bool &userVisible) final;
    /// HHU blue/white branding
    void paletteOverride(const QString &colorName, QGCPalette::PaletteColorInfo_t &colorInfo) final;
    /// No first run wizard: vehicle type and units are preset
    QList<int> firstRunPromptStdIds() final { return {}; }
    QString showAdvancedUIMessage() const final { return QString(); }
    /// Route page: waypoints only for now (地块覆盖 / Fields2Cover item will be added here)
    QVariantList complexMissionItemNames(Vehicle *vehicle) final { Q_UNUSED(vehicle); return {}; }
    /// Route templates: blank route only
    QList<PlanCreator *> planCreators(PlanMasterController *planMasterController) final;
    /// Feeds VCU_* values to the chassis status, tracks the link and shows vehicle STATUSTEXT in customer wording
    bool mavlinkMessage(Vehicle *vehicle, LinkInterface *link, const mavlink_message_t &message) final;
    /// Installs the QML override interceptor
    QQmlApplicationEngine *createQmlApplicationEngine(QObject *parent) final;
    /// Releases the url interceptor attached in createQmlApplicationEngine before the engine is destroyed
    void destroyQmlApplicationEngine(QQmlApplicationEngine *qmlEngine) final;

private:
    /// zh_CN overlay (custom/translations, built by tools/i18n.py)
    void _installTranslations();
    /// Replaces a STATUSTEXT by its hhu_config.json translation; false when the message was consumed
    bool _translateStatusText(Vehicle *vehicle, const mavlink_message_t &message);

    CustomOptions *_options = nullptr;
    QTranslator _hhuTranslator;
    HHUSettings *_hhuSettings = nullptr;
    HHUConfig *_hhuConfig = nullptr;
    HHUVcuStatus *_vcuStatus = nullptr;
    HHULinkMonitor *_linkMonitor = nullptr;
    HHU4GLink *_link4G = nullptr;
    HHUFieldManager *_fields = nullptr;
    HHUWorkLog *_workLog = nullptr;
    HHUNtrip *_ntrip = nullptr;
    HHUService *_service = nullptr;
    QQmlApplicationEngine *_qmlEngine = nullptr;
    class CustomOverrideInterceptor *_urlInterceptor = nullptr;
    const QVariantList _emptyList;
};

/*===========================================================================*/

/// Replaces any qrc QML/resource whose path also exists under ":/Custom"
class CustomOverrideInterceptor : public QQmlAbstractUrlInterceptor
{
public:
    CustomOverrideInterceptor() = default;

    QUrl intercept(const QUrl &url, QQmlAbstractUrlInterceptor::DataType type) final;
};
