#include "HHUWorkLog.h"
#include "Fact.h"
#include "MultiVehicleManager.h"
#include "QGCLoggingCategory.h"
#include "Vehicle.h"

#include <QtCore/QDateTime>
#include <QtCore/QSettings>

#include <algorithm>

QGC_LOGGING_CATEGORY(HHUWorkLogLog, "Custom.HHUWorkLog")

namespace {
constexpr const char *kSessionKey = "HHU/workSession";
constexpr const char *kLastRunKey = "HHU/lastWorkRun";
constexpr const char *kCompletedKey = "HHU/routeCompletedVehicle";   ///< vehicle waiting at the end of its route
}

HHUWorkLog::HHUWorkLog(QObject *parent)
    : QObject(parent)
{
    // A session left open by a closed GCS continues when that vehicle connects again
    _session = QSettings().value(QString::fromLatin1(kSessionKey)).toMap();

    _saveTimer.setInterval(5000);
    (void) connect(&_saveTimer, &QTimer::timeout, this, &HHUWorkLog::_saveSession);
    _saveTimer.start();

    // MultiVehicleManager exists once the application is up
    QTimer::singleShot(0, this, [this]() {
        (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, [this](Vehicle *vehicle) {
            // still waiting at the end of the route after a GCS restart (the UI also needs it armed)
            const bool completed = vehicle && QSettings().value(QString::fromLatin1(kCompletedKey)).toString() == vehicleKey(vehicle);
            if (completed != _completed) {
                _completed = completed;
                emit completedChanged();
            }
            if (vehicle && !_session.isEmpty() && _session.value(QStringLiteral("vehicleKey")).toString() == vehicleKey(vehicle)) {
                _attach(vehicle);
            }
        });
    });
}

QString HHUWorkLog::vehicleKey(Vehicle *vehicle)
{
    if (!vehicle) {
        return QString();
    }
    return vehicle->vehicleUID() != 0 ? vehicle->vehicleUIDStr() : QStringLiteral("SYSID %1").arg(vehicle->id());
}

// ---- Session ------------------------------------------------------------------------------

void HHUWorkLog::start(Vehicle *vehicle, const QVariantMap &info)
{
    if (!vehicle) {
        return;
    }
    if (!_session.isEmpty()) {
        _finish(false);     // a new start ends the previous session
    }
    QSettings().remove(QString::fromLatin1(kCompletedKey));
    if (_completed) {
        _completed = false;
        emit completedChanged();
    }
    _session = info;
    _session.insert(QStringLiteral("vehicleKey"), vehicleKey(vehicle));
    _session.insert(QStringLiteral("start"), QDateTime::currentDateTime().toString(Qt::ISODate));
    const int startSeq = std::max(1, info.value(QStringLiteral("startSeq")).toInt());
    _session.insert(QStringLiteral("startSeq"), startSeq);
    _session.insert(QStringLiteral("reachedSeq"), startSeq - 1);
    _session.insert(QStringLiteral("currentSeq"), startSeq);
    _session.insert(QStringLiteral("moved"), false);
    _wasAuto = false;
    _attach(vehicle);
    _saveSession();
    emit activeChanged();
    qCDebug(HHUWorkLogLog) << "session started" << _session;
}

void HHUWorkLog::_attach(Vehicle *vehicle)
{
    if (_vehicle) {
        (void) disconnect(_vehicle, nullptr, this, nullptr);
        (void) disconnect(_vehicle->missionItemIndex(), nullptr, this, nullptr);
    }
    _vehicle = vehicle;
    (void) connect(vehicle->missionItemIndex(), &Fact::rawValueChanged, this, &HHUWorkLog::_onMissionIndex);
    (void) connect(vehicle, &Vehicle::flightModeChanged, this, &HHUWorkLog::_onFlightMode);
    (void) connect(vehicle, &Vehicle::armedChanged, this, &HHUWorkLog::_onArmed);
    _wasAuto = vehicle->flightMode() == vehicle->missionFlightMode();
    // Catch up with what happened while we were away (restart, link loss)
    _onMissionIndex();
    if (!vehicle->armed() && !_session.isEmpty()) {
        _onArmed();
    }
}

void HHUWorkLog::_onMissionIndex()
{
    if (!_vehicle || _session.isEmpty()) {
        return;
    }
    const int current = _vehicle->missionItemIndex()->rawValue().toInt();
    const int startSeq = _session.value(QStringLiteral("startSeq")).toInt();
    if (current < startSeq) {
        return;     // stale value before the start command took effect
    }
    if (current > startSeq) {
        _session.insert(QStringLiteral("moved"), true);
    }
    _session.insert(QStringLiteral("currentSeq"), current);
    // Driving to waypoint N means N-1 was reached
    const int reached = std::max(_session.value(QStringLiteral("reachedSeq")).toInt(), current - 1);
    _session.insert(QStringLiteral("reachedSeq"), reached);
}

void HHUWorkLog::itemReached(Vehicle *vehicle, int seq)
{
    if (_session.isEmpty() || vehicle != _vehicle) {
        return;
    }
    if (seq > _session.value(QStringLiteral("reachedSeq")).toInt()) {
        _session.insert(QStringLiteral("reachedSeq"), seq);
    }
    const int lastSeq = _session.value(QStringLiteral("lastSeq")).toInt();
    if (lastSeq > 0 && seq >= lastSeq) {
        _finish(true);
    }
}

void HHUWorkLog::_onFlightMode()
{
    if (!_vehicle || _session.isEmpty()) {
        return;
    }
    const bool isAuto = _vehicle->flightMode() == _vehicle->missionFlightMode();
    if (_wasAuto && !isAuto) {
        const int lastSeq = _session.value(QStringLiteral("lastSeq")).toInt();
        if (_session.value(QStringLiteral("currentSeq")).toInt() >= lastSeq && lastSeq > 0) {
            // ArduPilot Rover holds at the end of the route: the last waypoint was reached
            _session.insert(QStringLiteral("reachedSeq"), lastSeq);
            _finish(true);
            return;
        }
    }
    _wasAuto = isAuto;
}

void HHUWorkLog::_onArmed()
{
    if (_vehicle && !_vehicle->armed() && !_session.isEmpty()) {
        const int lastSeq = _session.value(QStringLiteral("lastSeq")).toInt();
        _finish(lastSeq > 0 && _session.value(QStringLiteral("reachedSeq")).toInt() >= lastSeq);
    }
}

void HHUWorkLog::_finish(bool routeCompleted)
{
    const int startSeq = _session.value(QStringLiteral("startSeq")).toInt();
    const int reached = _session.value(QStringLiteral("reachedSeq")).toInt();

    if (!routeCompleted && reached < startSeq && !_session.value(QStringLiteral("moved")).toBool()) {
        // Stopped before the vehicle got anywhere: keep the previous resume point
        qCDebug(HHUWorkLogLog) << "session discarded, vehicle did not move";
    } else {
        // 断点续作: remember where to continue, or forget it when the route was finished
        const QString key = _resumeKey(_session.value(QStringLiteral("vehicleKey")).toString(), _session.value(QStringLiteral("fieldId")).toString());
        QSettings settings;
        if (routeCompleted) {
            settings.remove(key);
        } else {
            settings.setValue(key, _session.value(QStringLiteral("currentSeq")).toInt());
        }
        // 上传日志 offers the time span of the last run
        QVariantMap run;
        run.insert(QStringLiteral("start"), _session.value(QStringLiteral("start")));
        run.insert(QStringLiteral("end"), QDateTime::currentDateTime().toString(Qt::ISODate));
        settings.setValue(QString::fromLatin1(kLastRunKey), run);
        emit lastRunChanged();
        if (routeCompleted) {
            settings.setValue(QString::fromLatin1(kCompletedKey), _session.value(QStringLiteral("vehicleKey")));
            _completed = true;
            emit completedChanged();
        }
        qCDebug(HHUWorkLogLog) << "session finished" << _session << "completed" << routeCompleted;
    }

    _session.clear();
    _saveSession();
    if (_vehicle) {
        (void) disconnect(_vehicle, nullptr, this, nullptr);
        (void) disconnect(_vehicle->missionItemIndex(), nullptr, this, nullptr);
        _vehicle = nullptr;
    }
    emit activeChanged();
}

QVariantMap HHUWorkLog::lastRun() const
{
    return QSettings().value(QString::fromLatin1(kLastRunKey)).toMap();
}

void HHUWorkLog::_saveSession()
{
    QSettings settings;
    if (_session.isEmpty()) {
        settings.remove(QString::fromLatin1(kSessionKey));
    } else {
        settings.setValue(QString::fromLatin1(kSessionKey), _session);
    }
}

// ---- Resume / vehicle field ------------------------------------------------------------------

QString HHUWorkLog::_resumeKey(const QString &vehicleKey, const QString &fieldId) const
{
    return QStringLiteral("HHU/resume/%1/%2").arg(QString(vehicleKey).replace(QLatin1Char('/'), QLatin1Char('_')), fieldId.isEmpty() ? QStringLiteral("none") : fieldId);
}

int HHUWorkLog::resumeWaypoint(Vehicle *vehicle, const QString &fieldId) const
{
    return QSettings().value(_resumeKey(vehicleKey(vehicle), fieldId), 0).toInt();
}

QString HHUWorkLog::vehicleField(Vehicle *vehicle) const
{
    return vehicle ? QSettings().value(QStringLiteral("HHU/vehicleField/") + QString(vehicleKey(vehicle)).replace(QLatin1Char('/'), QLatin1Char('_'))).toString() : QString();
}

void HHUWorkLog::setVehicleField(Vehicle *vehicle, const QString &fieldId)
{
    if (vehicle) {
        QSettings().setValue(QStringLiteral("HHU/vehicleField/") + QString(vehicleKey(vehicle)).replace(QLatin1Char('/'), QLatin1Char('_')), fieldId);
    }
}
