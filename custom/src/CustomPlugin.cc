#include "CustomPlugin.h"
#include "QGCLoggingCategory.h"
#include "QGCPalette.h"
#include "QGCMAVLink.h"
#include "AppSettings.h"
#include "FlightMapSettings.h"
#include "UnitsSettings.h"
#include "QGCApplication.h"
#include "JsonParsing.h"
#include "BlankPlanCreator.h"
#include "HHU4GLink.h"
#include "HHUConfig.h"
#include "HHUFieldManager.h"
#include "HHUNtrip.h"
#include "HHUService.h"
#include "HHUWorkLog.h"
#include "LogManagerSettings.h"
#include "MavlinkSettings.h"
#include "HHULinkMonitor.h"
#include "HHUSettings.h"
#include "HHUVcuStatus.h"
#include "Vehicle.h"
#include "MultiVehicleManager.h"
#include "ParameterManager.h"
#include "Fact.h"

#include <QtCore/QApplicationStatic>
#include <QtCore/QFile>
#include <QtCore/QLocale>
#include <QtCore/QSettings>
#include <QtCore/QTimer>
#include <QtGui/QFont>
#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>

QGC_LOGGING_CATEGORY(CustomLog, "Custom.CustomPlugin")

Q_APPLICATION_STATIC(CustomPlugin, _customPluginInstance);

namespace {

// 河海大学校徽蓝
constexpr const char *kHhuBlue      = "#004B97";
constexpr const char *kHhuBlueLight = "#2F75C0";
constexpr const char *kHhuBlueTint  = "#E6EEF7";

void setAll(QGCPalette::PaletteColorInfo_t &colorInfo, const QColor &enabled, const QColor &disabled)
{
    colorInfo[QGCPalette::Light][QGCPalette::ColorGroupEnabled]  = enabled;
    colorInfo[QGCPalette::Light][QGCPalette::ColorGroupDisabled] = disabled;
    colorInfo[QGCPalette::Dark][QGCPalette::ColorGroupEnabled]   = enabled;
    colorInfo[QGCPalette::Dark][QGCPalette::ColorGroupDisabled]  = disabled;
}

} // namespace

CustomFlyViewOptions::CustomFlyViewOptions(CustomOptions *options, QObject *parent)
    : QGCFlyViewOptions(options, parent)
{
}

CustomOptions::CustomOptions(CustomPlugin *plugin, QObject *parent)
    : QGCOptions(parent)
    , _flyViewOptions(new CustomFlyViewOptions(this, this))
{
    Q_UNUSED(plugin);
}

/*===========================================================================*/

CustomPlugin::CustomPlugin(QObject *parent)
    : QGCCorePlugin(parent)
    , _options(new CustomOptions(this, this))
    , _hhuSettings(new HHUSettings(this))
    , _hhuConfig(new HHUConfig(this))
    , _vcuStatus(new HHUVcuStatus(this))
    , _linkMonitor(new HHULinkMonitor(_hhuSettings, this))
    , _link4G(new HHU4GLink(_linkMonitor, this))
    , _fields(new HHUFieldManager(this))
    , _workLog(new HHUWorkLog(this))
{
    _showAdvancedUI = false;
    QGuiApplication::setApplicationDisplayName(QStringLiteral("河海大学 大蒜播种车地面站"));

    // QGC renders with Open Sans; give Chinese glyphs a sans-serif fallback instead of the system Song font
    QFont::insertSubstitutions(QStringLiteral("Open Sans"),
                               { QStringLiteral("Microsoft YaHei UI"), QStringLiteral("Microsoft YaHei"),
                                 QStringLiteral("Noto Sans CJK SC"), QStringLiteral("Source Han Sans SC") });

    // QGCApplication picks the UI language from the raw settings file before this plugin
    // exists, so a first-run "Chinese" default must be written there and the language reloaded.
    QSettings settings;
    if (!settings.contains(AppSettings::qLocaleLanguageName)) {
        settings.setValue(AppSettings::qLocaleLanguageName, static_cast<int>(QLocale::Chinese));
        qgcApp()->setLanguage();
    }
    _installTranslations();
    (void) connect(qgcApp(), &QGCApplication::languageChanged, this, [this]() {
        _installTranslations();
        if (_qmlEngine) {
            _qmlEngine->retranslate();
        }
    });
}

void CustomPlugin::_installTranslations()
{
    // Overlay on top of upstream's translator (last installed is searched first)
    (void) qgcApp()->removeTranslator(&_hhuTranslator);
    if (QLocale().language() != QLocale::Chinese) {
        return;
    }
    if (_hhuTranslator.load(QStringLiteral(":/hhu/i18n/hhu_source_zh_CN.qm"))) {
        (void) qgcApp()->installTranslator(&_hhuTranslator);
    } else {
        qCWarning(CustomLog) << "HHU source translation missing";
    }
    // Fact metadata uses this single translator directly: replace upstream's file with our merged one
    if (!JsonParsing::translator()->load(QStringLiteral(":/hhu/i18n/hhu_json_zh_CN.qm"))) {
        qCWarning(CustomLog) << "HHU json translation missing";
    }
}

QGCCorePlugin *CustomPlugin::instance()
{
    return _customPluginInstance();
}

bool CustomPlugin::overrideSettingsGroupVisibility(const QString &name)
{
    static const QStringList hiddenGroups = {
        QStringLiteral("Video"),
        QStringLiteral("Viewer3D"),
        QStringLiteral("ADSBVehicleManager"),
        QStringLiteral("RemoteID"),
        QStringLiteral("Joystick"),
        QStringLiteral("JoystickManager"),
        QStringLiteral("GimbalController"),
        QStringLiteral("FirmwareUpgrade"),
    };
    return !hiddenGroups.contains(name);
}

void CustomPlugin::adjustSettingMetaData(const QString &settingsGroup, FactMetaData &metaData, bool &userVisible)
{
    QGCCorePlugin::adjustSettingMetaData(settingsGroup, metaData, userVisible);

    const QString name = metaData.name();

    if (settingsGroup == AppSettings::settingsGroup) {
        // Fixed product configuration: hidden settings are forced to these defaults
        if (name == AppSettings::offlineEditingFirmwareClassName || name == AppSettings::preferredFirmwareClassName) {
            metaData.setRawDefaultValue(QGCMAVLink::FirmwareClassArduPilot);
            userVisible = false;
        } else if (name == AppSettings::offlineEditingVehicleClassName || name == AppSettings::preferredVehicleClassName) {
            metaData.setRawDefaultValue(QGCMAVLink::VehicleClassRoverBoat);
            userVisible = false;
        } else if (name == AppSettings::indoorPaletteName) {
            // 0 = Outdoor = light theme (blue/white branding)
            metaData.setRawDefaultValue(0);
            userVisible = false;
        } else if (name == AppSettings::virtualJoystickName
                   || name == AppSettings::mapboxTokenName
                   || name == AppSettings::mapboxAccountName
                   || name == AppSettings::mapboxStyleName
                   || name == AppSettings::esriTokenName
                   || name == AppSettings::vworldTokenName
                   || name == AppSettings::openaipTokenName
                   || name == AppSettings::customURLName
                   || name == AppSettings::followTargetName
                   || name == AppSettings::savePathName
                   || name == AppSettings::clearSettingsNextBootName) {
            userVisible = false;
        } else if (name == AppSettings::tiandituTokenName) {
            // Only 浏览器端 keys can download tiles (QGC sends a map.tianditu.gov.cn Referer)
            metaData.setShortDescription(tr("Must be a TianDiTu key of type \"Browser\". A \"Server\" key cannot download map images."));
        } else if (name == AppSettings::offlineEditingCruiseSpeedName) {
            // Only used for route time estimates; typical seeding speed, rover range
            metaData.setRawMin(0.1);
            metaData.setRawUserMin(0.2);
            metaData.setRawUserMax(5.0);
            metaData.setRawDefaultValue(1.0);
        } else if (name == AppSettings::defaultMissionItemAltitudeName) {
            // Rover: waypoints are written with altitude 0 (需求说明 §6)
            metaData.setRawDefaultValue(0.0);
            userVisible = false;
        } else if (name == AppSettings::qLocaleLanguageName) {
            // First-run default only; still user selectable (中文 / English)
            metaData.setRawDefaultValue(QLocale::Chinese);
        }
    } else if (settingsGroup == LogManagerSettings::settingsGroup) {
        // Run logs are kept for after-sales (需求说明 V1.0 §5 日志, 7 days, see HHUService)
        if (name == LogManagerSettings::diskLoggingEnabledName) {
            metaData.setRawDefaultValue(true);
        }
    } else if (settingsGroup == MavlinkSettings::settingsGroup) {
        // MAVLink communication log of every connection, also when the vehicle never armed
        if (name == MavlinkSettings::telemetrySaveName || name == MavlinkSettings::telemetrySaveNotArmedName) {
            metaData.setRawDefaultValue(true);
        }
    } else if (settingsGroup == FlightMapSettings::settingsGroup) {
        // First-run default: 天地图卫星 (CGCS2000 ≈ WGS-84, no offset correction needed)
        if (name == FlightMapSettings::mapProviderName) {
            metaData.setRawDefaultValue(QStringLiteral("TianDiTu"));
        } else if (name == FlightMapSettings::mapTypeName) {
            metaData.setRawDefaultValue(QStringLiteral("Satellite"));
        }
    } else if (settingsGroup == UnitsSettings::settingsGroup) {
        // Upstream speed unit names are not translatable; offer only the units the customer needs (§4)
        const bool zh = QLocale().language() == QLocale::Chinese;
        if (name == UnitsSettings::speedUnitsName) {
            metaData.setEnumInfo({ zh ? QStringLiteral("米/秒") : QStringLiteral("m/s"),
                                   zh ? QStringLiteral("千米/时") : QStringLiteral("km/h") },
                                 { UnitsSettings::SpeedUnitsMetersPerSecond, UnitsSettings::SpeedUnitsKilometersPerHour });
            metaData.setRawDefaultValue(UnitsSettings::SpeedUnitsMetersPerSecond);
        } else if (name == UnitsSettings::areaUnitsName) {
            metaData.setEnumInfo({ zh ? QStringLiteral("平方米") : QStringLiteral("Square meters"),
                                   zh ? QStringLiteral("公顷") : QStringLiteral("Hectares") },
                                 { UnitsSettings::AreaUnitsSquareMeters, UnitsSettings::AreaUnitsHectares });
            metaData.setRawDefaultValue(UnitsSettings::AreaUnitsHectares);
        } else if (name == UnitsSettings::horizontalDistanceUnitsName) {
            metaData.setRawDefaultValue(UnitsSettings::HorizontalDistanceUnitsMeters);
            userVisible = false;
        } else if (name == UnitsSettings::verticalDistanceUnitsName) {
            metaData.setRawDefaultValue(UnitsSettings::VerticalDistanceUnitsMeters);
            userVisible = false;
        } else if (name == UnitsSettings::temperatureUnitsName) {
            userVisible = false;
        }
    }
}

void CustomPlugin::paletteOverride(const QString &colorName, QGCPalette::PaletteColorInfo_t &colorInfo)
{
    const QColor blue(kHhuBlue);
    const QColor blueLight(kHhuBlueLight);
    const QColor tint(kHhuBlueTint);
    const QColor white(QStringLiteral("#ffffff"));
    const QColor grey(QStringLiteral("#9d9d9d"));

    if (colorName == QStringLiteral("buttonHighlight")) {
        setAll(colorInfo, blue, QColor(QStringLiteral("#e4e4e4")));
    } else if (colorName == QStringLiteral("buttonHighlightText")) {
        setAll(colorInfo, white, QColor(QStringLiteral("#2c2c2c")));
    } else if (colorName == QStringLiteral("buttonBorder") || colorName == QStringLiteral("groupBorder")) {
        colorInfo[QGCPalette::Light][QGCPalette::ColorGroupEnabled] = blue;
        colorInfo[QGCPalette::Light][QGCPalette::ColorGroupDisabled] = grey;
    } else if (colorName == QStringLiteral("primaryButton")) {
        setAll(colorInfo, blue, QColor(QStringLiteral("#585858")));
    } else if (colorName == QStringLiteral("primaryButtonText")) {
        setAll(colorInfo, white, QColor(QStringLiteral("#cad0d0")));
    } else if (colorName == QStringLiteral("missionItemEditor")) {
        colorInfo[QGCPalette::Light][QGCPalette::ColorGroupEnabled] = tint;
    } else if (colorName == QStringLiteral("toolStripHoverColor")) {
        colorInfo[QGCPalette::Light][QGCPalette::ColorGroupEnabled] = blueLight;
    } else if (colorName == QStringLiteral("mapButtonHighlight") || colorName == QStringLiteral("mapIndicator")) {
        setAll(colorInfo, blueLight, QColor(QStringLiteral("#585858")));
    } else if (colorName == QStringLiteral("colorBlue") || colorName == QStringLiteral("brandingBlue")) {
        setAll(colorInfo, blue, blue);
    } else if (colorName == QStringLiteral("brandingPurple")) {
        setAll(colorInfo, blue, blue);
    } else if (colorName == QStringLiteral("toolbarBackground")) {
        colorInfo[QGCPalette::Light][QGCPalette::ColorGroupEnabled]  = QColor(QStringLiteral("#e6ffffff"));
        colorInfo[QGCPalette::Light][QGCPalette::ColorGroupDisabled] = QColor(QStringLiteral("#e6ffffff"));
    }
}

bool CustomPlugin::mavlinkMessage(Vehicle *vehicle, LinkInterface *link, const mavlink_message_t &message)
{
    _linkMonitor->messageReceived(vehicle, link, message);
    _vcuStatus->handleMessage(message);
    if (message.msgid == MAVLINK_MSG_ID_MISSION_ITEM_REACHED) {
        _workLog->itemReached(vehicle, mavlink_msg_mission_item_reached_get_seq(&message));
    } else if (message.msgid == MAVLINK_MSG_ID_STATUSTEXT) {
        return _translateStatusText(vehicle, message);
    }
    return true;
}

bool CustomPlugin::_translateStatusText(Vehicle *vehicle, const mavlink_message_t &message)
{
    // The translation table is Chinese; English UI shows the vehicle's own text
    if (QLocale().language() != QLocale::Chinese) {
        return true;
    }

    mavlink_statustext_t statusText{};
    mavlink_msg_statustext_decode(&message, &statusText);
    if (statusText.id != 0) {
        return true;    // chunked text (never sent by our Rover firmware): leave it to QGC
    }
    const QString text = QString::fromUtf8(statusText.text, static_cast<int>(strnlen(statusText.text, sizeof(statusText.text))));
    const QString translated = _hhuConfig->translateStatusText(text);
    if (translated.isEmpty()) {
        return true;
    }

    // Hand the translated text to the vehicle's message list the way QGC adds event texts
    // (same severity handling: errors also pop up). Vehicle::_onStatusTextFromEvent is a private slot.
    const bool ok = QMetaObject::invokeMethod(vehicle, "_onStatusTextFromEvent", Qt::DirectConnection,
                                              Q_ARG(uint8_t, message.compid),
                                              Q_ARG(int, statusText.severity),
                                              Q_ARG(QString, translated.toHtmlEscaped()),
                                              Q_ARG(QString, QString()));
    if (!ok) {
        qCWarning(CustomLog) << "cannot inject translated STATUSTEXT, showing original";
        return true;
    }
    if (text.startsWith(QStringLiteral("PreArm"), Qt::CaseInsensitive) || text.startsWith(QStringLiteral("Arm:"), Qt::CaseInsensitive)) {
        vehicle->setPrearmError(translated);    // shown by the work panel when starting fails
    }
    qCDebug(CustomLog) << "STATUSTEXT" << text << "->" << translated;
    return false;
}

QList<PlanCreator *> CustomPlugin::planCreators(PlanMasterController *planMasterController)
{
    return { new BlankPlanCreator(planMasterController) };
}

QQmlApplicationEngine *CustomPlugin::createQmlApplicationEngine(QObject *parent)
{
    _qmlEngine = QGCCorePlugin::createQmlApplicationEngine(parent);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuVcu"), _vcuStatus);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuSettings"), _hhuSettings);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuConfig"), _hhuConfig);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuLink"), _linkMonitor);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhu4G"), _link4G);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuFields"), _fields);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuWork"), _workLog);

    // These need the settings / network stack, which exist once the QML engine is created
    if (!_ntrip) {
        _ntrip = new HHUNtrip(_hhuConfig, this);
        _service = new HHUService(_hhuConfig, _link4G, this);
        // RTK corrections: from this computer on serial / UDP / TCP / Bluetooth, from the server on 4G
        (void) connect(_link4G, &HHU4GLink::stateChanged, this, [this]() { _ntrip->applyForwarding(!_link4G->active()); });
        // TURN_RADIUS for the route check (急弯标红), kept for offline planning
        (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, [this](Vehicle *vehicle) {
            if (!vehicle) {
                return;
            }
            ParameterManager *params = vehicle->parameterManager();
            auto readTurnRadius = [this, params]() {
                if (params->parametersReady() && params->parameterExists(ParameterManager::defaultComponentId, QStringLiteral("TURN_RADIUS"))) {
                    Fact *fact = params->getParameter(ParameterManager::defaultComponentId, QStringLiteral("TURN_RADIUS"));
                    _hhuSettings->setLastTurnRadius(fact->rawValue().toDouble());
                    (void) connect(fact, &Fact::rawValueChanged, this, [this](const QVariant &value) {
                        _hhuSettings->setLastTurnRadius(value.toDouble());
                    }, Qt::UniqueConnection);
                }
            };
            (void) connect(params, &ParameterManager::parametersReadyChanged, this, readTurnRadius);
            readTurnRadius();
        });
        QTimer::singleShot(0, this, [this]() {
            _link4G->autoStart();
            _ntrip->applyForwarding(!_link4G->active());
        });
    }
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuNtrip"), _ntrip);
    _qmlEngine->rootContext()->setContextProperty(QStringLiteral("hhuService"), _service);

    _urlInterceptor = new CustomOverrideInterceptor();
    _qmlEngine->addUrlInterceptor(_urlInterceptor);

    return _qmlEngine;
}

void CustomPlugin::destroyQmlApplicationEngine(QQmlApplicationEngine *qmlEngine)
{
    if (qmlEngine && (qmlEngine == _qmlEngine)) {
        qmlEngine->removeUrlInterceptor(_urlInterceptor);
        delete _urlInterceptor;
        _urlInterceptor = nullptr;
        _qmlEngine = nullptr;
    }

    QGCCorePlugin::destroyQmlApplicationEngine(qmlEngine);
}

/*===========================================================================*/

QUrl CustomOverrideInterceptor::intercept(const QUrl &url, QQmlAbstractUrlInterceptor::DataType type)
{
    switch (type) {
    case QQmlAbstractUrlInterceptor::QmlFile:
    case QQmlAbstractUrlInterceptor::UrlString:
        if (url.scheme() == QStringLiteral("qrc")) {
            const QString overrideRes = QStringLiteral(":/Custom%1").arg(url.path());
            if (QFile::exists(overrideRes)) {
                QUrl result;
                result.setScheme(QStringLiteral("qrc"));
                result.setPath(overrideRes.mid(1));
                return result;
            }
        }
        break;
    default:
        break;
    }

    return url;
}
