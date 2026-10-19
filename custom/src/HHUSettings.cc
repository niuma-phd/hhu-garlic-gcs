#include "HHUSettings.h"

#include <QtCore/QSettings>

#include <algorithm>
#include <cmath>

namespace {
constexpr const char *kGroup = "HHU";
}

HHUSettings::HHUSettings(QObject *parent)
    : QObject(parent)
{
    QSettings settings;
    settings.beginGroup(kGroup);
    _commandTimeoutSec = std::clamp(settings.value("commandTimeoutSec", _commandTimeoutSec).toInt(), 2, 30);
    _linkLostSec       = std::clamp(settings.value("linkLostSec", _linkLostSec).toInt(), 2, 30);
    _batteryDisplay    = std::clamp(settings.value("batteryDisplay", _batteryDisplay).toInt(), 0, 1);
    _lowBatteryPct     = std::clamp(settings.value("lowBatteryPct", _lowBatteryPct).toInt(), 5, 60);
    _maxWaypoints      = std::clamp(settings.value("maxWaypoints", _maxWaypoints).toInt(), 10, 10000);
    _fontSize          = std::clamp(settings.value("fontSize", _fontSize).toInt(), 0, 2);
    _highContrast      = settings.value("highContrast", _highContrast).toBool();
    _lastTurnRadius    = settings.value("lastTurnRadius", _lastTurnRadius).toDouble();
    _mapLabels         = settings.value("mapLabels", _mapLabels).toBool();
}

double HHUSettings::fontScale() const
{
    static constexpr double scales[] = { 1.0, 1.2, 1.4 };
    return scales[_fontSize];
}

void HHUSettings::_save(const char *key, const QVariant &value)
{
    QSettings settings;
    settings.beginGroup(kGroup);
    settings.setValue(key, value);
    emit changed();
}

void HHUSettings::setCommandTimeoutSec(int value)
{
    value = std::clamp(value, 2, 30);
    if (value != _commandTimeoutSec) {
        _commandTimeoutSec = value;
        _save("commandTimeoutSec", value);
    }
}

void HHUSettings::setLinkLostSec(int value)
{
    value = std::clamp(value, 2, 30);
    if (value != _linkLostSec) {
        _linkLostSec = value;
        _save("linkLostSec", value);
    }
}

void HHUSettings::setBatteryDisplay(int value)
{
    value = std::clamp(value, 0, 1);
    if (value != _batteryDisplay) {
        _batteryDisplay = value;
        _save("batteryDisplay", value);
    }
}

void HHUSettings::setLowBatteryPct(int value)
{
    value = std::clamp(value, 5, 60);
    if (value != _lowBatteryPct) {
        _lowBatteryPct = value;
        _save("lowBatteryPct", value);
    }
}

void HHUSettings::setMaxWaypoints(int value)
{
    value = std::clamp(value, 10, 10000);
    if (value != _maxWaypoints) {
        _maxWaypoints = value;
        _save("maxWaypoints", value);
    }
}

void HHUSettings::setFontSize(int value)
{
    value = std::clamp(value, 0, 2);
    if (value != _fontSize) {
        _fontSize = value;
        _save("fontSize", value);
    }
}

void HHUSettings::setHighContrast(bool value)
{
    if (value != _highContrast) {
        _highContrast = value;
        _save("highContrast", value);
    }
}

void HHUSettings::setMapLabels(bool value)
{
    if (value != _mapLabels) {
        _mapLabels = value;
        _save("mapLabels", value);
    }
}

void HHUSettings::setVehicleMaxSpeed(double value)
{
    if (!std::isfinite(value) || value < 0) {
        value = 0;
    }
    if (value != _vehicleMaxSpeed) {
        _vehicleMaxSpeed = value;
        emit changed();
    }
}

void HHUSettings::setVehicleWpSpeed(double value)
{
    if (!std::isfinite(value) || value < 0) {
        value = 0;
    }
    if (value != _vehicleWpSpeed) {
        _vehicleWpSpeed = value;
        emit changed();
    }
}

void HHUSettings::setLastTurnRadius(double value)
{
    if (std::isfinite(value) && value > 0 && value != _lastTurnRadius) {
        _lastTurnRadius = value;
        _save("lastTurnRadius", value);
    }
}
