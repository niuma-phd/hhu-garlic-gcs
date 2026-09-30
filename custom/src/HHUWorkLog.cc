#include "HHUWorkLog.h"
#include "Fact.h"
#include "MultiVehicleManager.h"
#include "QGCLoggingCategory.h"
#include "Vehicle.h"

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSaveFile>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtCore/QUrl>
#include <QtCore/QUuid>

#include <algorithm>

QGC_LOGGING_CATEGORY(HHUWorkLogLog, "Custom.HHUWorkLog")

namespace {
QString dataFile()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/work_records.json");
}
constexpr const char *kSessionKey = "HHU/workSession";
constexpr double kMaxStepMeters = 50.0;    ///< larger position jumps (GPS glitch, link gap) are not added to the odometer
}

HHUWorkLog::HHUWorkLog(QObject *parent)
    : QObject(parent)
{
    // The data folder depends on the application name, which is final only once the application runs
    QTimer::singleShot(0, this, [this]() {
        (void) QDir().mkpath(QFileInfo(dataFile()).absolutePath());
        _loadRecords();
        qCDebug(HHUWorkLogLog) << "records" << dataFile() << _records.count();
        emit recordsChanged();
    });

    // A session left open by a closed GCS continues when that vehicle connects again
    _session = QSettings().value(QString::fromLatin1(kSessionKey)).toMap();

    _saveTimer.setInterval(5000);
    (void) connect(&_saveTimer, &QTimer::timeout, this, &HHUWorkLog::_saveSession);
    _saveTimer.start();

    // MultiVehicleManager exists once the application is up
    QTimer::singleShot(0, this, [this]() {
        (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, [this](Vehicle *vehicle) {
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
    _session = info;
    _session.insert(QStringLiteral("id"), QUuid::createUuid().toString(QUuid::WithoutBraces).left(8));
    _session.insert(QStringLiteral("vehicleKey"), vehicleKey(vehicle));
    _session.insert(QStringLiteral("start"), QDateTime::currentDateTime().toString(Qt::ISODate));
    const int startSeq = std::max(1, info.value(QStringLiteral("startSeq")).toInt());
    _session.insert(QStringLiteral("startSeq"), startSeq);
    _session.insert(QStringLiteral("reachedSeq"), startSeq - 1);
    _session.insert(QStringLiteral("currentSeq"), startSeq);
    _session.insert(QStringLiteral("odometer"), 0.0);
    _session.insert(QStringLiteral("interruptions"), 0);
    _lastCoord = QGeoCoordinate();
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
    _lastCoord = QGeoCoordinate();
    (void) connect(vehicle->missionItemIndex(), &Fact::rawValueChanged, this, &HHUWorkLog::_onMissionIndex);
    (void) connect(vehicle, &Vehicle::flightModeChanged, this, &HHUWorkLog::_onFlightMode);
    (void) connect(vehicle, &Vehicle::armedChanged, this, &HHUWorkLog::_onArmed);
    (void) connect(vehicle, &Vehicle::coordinateChanged, this, &HHUWorkLog::_onCoordinate);
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
        _session.insert(QStringLiteral("interruptions"), _session.value(QStringLiteral("interruptions")).toInt() + 1);
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

void HHUWorkLog::_onCoordinate(const QGeoCoordinate &coordinate)
{
    if (_session.isEmpty() || !coordinate.isValid()) {
        return;
    }
    if (_lastCoord.isValid()) {
        const double step = _lastCoord.distanceTo(coordinate);
        if (step < kMaxStepMeters) {
            _session.insert(QStringLiteral("odometer"), _session.value(QStringLiteral("odometer")).toDouble() + step);
        }
    }
    _lastCoord = coordinate;
}

void HHUWorkLog::linkInterrupted()
{
    if (!_session.isEmpty()) {
        _session.insert(QStringLiteral("interruptions"), _session.value(QStringLiteral("interruptions")).toInt() + 1);
        _lastCoord = QGeoCoordinate();  // no odometer jump across the gap
    }
}

void HHUWorkLog::_finish(bool routeCompleted)
{
    const QVariantList cumulative = _session.value(QStringLiteral("cumulative")).toList();
    const int startSeq = _session.value(QStringLiteral("startSeq")).toInt();
    const int reached = _session.value(QStringLiteral("reachedSeq")).toInt();
    auto cum = [&cumulative](int seq) {
        return (seq >= 0 && seq < cumulative.count()) ? cumulative[seq].toDouble() : 0.0;
    };
    // The leg into the start waypoint is driven too (resuming mid-leg); records of a field add up without gaps
    const double routeLength = reached >= startSeq ? std::max(0.0, cum(reached) - cum(startSeq - 1)) : 0.0;
    const double swath = _session.value(QStringLiteral("swath")).toDouble();

    const QDateTime start = QDateTime::fromString(_session.value(QStringLiteral("start")).toString(), Qt::ISODate);
    const QDateTime end = QDateTime::currentDateTime();

    if (!routeCompleted && reached < startSeq && _session.value(QStringLiteral("odometer")).toDouble() < 1.0) {
        // Stopped before the vehicle moved: nothing to record, keep the previous resume point
        qCDebug(HHUWorkLogLog) << "session discarded, vehicle did not move";
        _session.clear();
        _saveSession();
        if (_vehicle) {
            (void) disconnect(_vehicle, nullptr, this, nullptr);
            (void) disconnect(_vehicle->missionItemIndex(), nullptr, this, nullptr);
            _vehicle = nullptr;
        }
        emit activeChanged();
        return;
    }

    QVariantMap record;
    record.insert(QStringLiteral("id"),             _session.value(QStringLiteral("id")));
    record.insert(QStringLiteral("date"),           start.date().toString(Qt::ISODate));
    record.insert(QStringLiteral("vehicle"),        _session.value(QStringLiteral("vehicleKey")));
    record.insert(QStringLiteral("fieldId"),        _session.value(QStringLiteral("fieldId")));
    record.insert(QStringLiteral("field"),          _session.value(QStringLiteral("fieldName")));
    record.insert(QStringLiteral("start"),          start.toString(Qt::ISODate));
    record.insert(QStringLiteral("end"),            end.toString(Qt::ISODate));
    record.insert(QStringLiteral("durationSec"),    start.secsTo(end));
    record.insert(QStringLiteral("odometer"),       _session.value(QStringLiteral("odometer")));
    record.insert(QStringLiteral("routeLength"),    routeLength);
    record.insert(QStringLiteral("area"),           routeLength * swath);
    record.insert(QStringLiteral("fromSeq"),        startSeq);
    record.insert(QStringLiteral("toSeq"),          std::max(reached, startSeq - 1));
    record.insert(QStringLiteral("interruptions"),  _session.value(QStringLiteral("interruptions")));
    record.insert(QStringLiteral("completed"),      routeCompleted);

    _records.prepend(record);
    _saveRecords();

    // 断点续作: remember where to continue, or forget it when the route was finished
    const QString key = _resumeKey(_session.value(QStringLiteral("vehicleKey")).toString(), _session.value(QStringLiteral("fieldId")).toString());
    QSettings settings;
    if (routeCompleted) {
        settings.remove(key);
    } else {
        settings.setValue(key, _session.value(QStringLiteral("currentSeq")).toInt());
    }

    _session.clear();
    _saveSession();
    if (_vehicle) {
        (void) disconnect(_vehicle, nullptr, this, nullptr);
        (void) disconnect(_vehicle->missionItemIndex(), nullptr, this, nullptr);
        _vehicle = nullptr;
    }
    emit recordsChanged();
    emit recordAdded(record);
    emit activeChanged();
    qCDebug(HHUWorkLogLog) << "session finished" << record;
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

// ---- Records ------------------------------------------------------------------------------

void HHUWorkLog::_loadRecords()
{
    QFile file(dataFile());
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonArray list = QJsonDocument::fromJson(file.readAll()).array();
    _records.clear();
    for (const QJsonValue &v : list) {
        _records.append(v.toObject().toVariantMap());
    }
}

void HHUWorkLog::_saveRecords()
{
    QJsonArray list;
    for (const QVariant &r : std::as_const(_records)) {
        list.append(QJsonObject::fromVariantMap(r.toMap()));
    }
    QSaveFile file(dataFile());
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(list).toJson());
        if (!file.commit()) {
            qCWarning(HHUWorkLogLog) << "cannot write work records" << file.errorString();
        }
    }
}

void HHUWorkLog::removeRecord(const QString &id)
{
    for (int i = 0; i < _records.count(); i++) {
        if (_records[i].toMap().value(QStringLiteral("id")).toString() == id) {
            _records.removeAt(i);
            _saveRecords();
            emit recordsChanged();
            return;
        }
    }
}

QStringList HHUWorkLog::vehicles() const
{
    QStringList list;
    for (const QVariant &r : _records) {
        const QString v = r.toMap().value(QStringLiteral("vehicle")).toString();
        if (!v.isEmpty() && !list.contains(v)) list.append(v);
    }
    return list;
}

QStringList HHUWorkLog::fieldNames() const
{
    QStringList list;
    for (const QVariant &r : _records) {
        const QString f = r.toMap().value(QStringLiteral("field")).toString();
        if (!f.isEmpty() && !list.contains(f)) list.append(f);
    }
    return list;
}

QVariantList HHUWorkLog::query(const QString &fromDate, const QString &toDate, const QString &vehicle, const QString &field) const
{
    QVariantList result;
    for (const QVariant &v : _records) {
        const QVariantMap r = v.toMap();
        const QString date = r.value(QStringLiteral("date")).toString();
        if (!fromDate.isEmpty() && date < fromDate) continue;
        if (!toDate.isEmpty() && date > toDate) continue;
        if (!vehicle.isEmpty() && r.value(QStringLiteral("vehicle")).toString() != vehicle) continue;
        if (!field.isEmpty() && r.value(QStringLiteral("field")).toString() != field) continue;
        result.append(r);
    }
    return result;
}

bool HHUWorkLog::exportCsv(const QString &path, const QVariantList &records) const
{
    QString filePath = path;
    if (filePath.startsWith(QStringLiteral("file:"))) {
        filePath = QUrl(filePath).toLocalFile();
    }
    QSaveFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    auto csv = [](QString s) {
        if (s.contains(QLatin1Char(',')) || s.contains(QLatin1Char('"')) || s.contains(QLatin1Char('\n'))) {
            s.replace(QStringLiteral("\""), QStringLiteral("\"\""));
            s = QStringLiteral("\"") + s + QStringLiteral("\"");
        }
        return s;
    };
    QStringList lines;
    lines << tr("Date,Vehicle,Field,Start,End,Duration (min),Distance driven (m),Route done (m),Area (mu),Area (ha),Waypoints,Interruptions,Route finished");
    for (const QVariant &v : records) {
        const QVariantMap r = v.toMap();
        const double area = r.value(QStringLiteral("area")).toDouble();
        QStringList cols;
        cols << r.value(QStringLiteral("date")).toString()
             << csv(r.value(QStringLiteral("vehicle")).toString())
             << csv(r.value(QStringLiteral("field")).toString())
             << QDateTime::fromString(r.value(QStringLiteral("start")).toString(), Qt::ISODate).toString(QStringLiteral("HH:mm:ss"))
             << QDateTime::fromString(r.value(QStringLiteral("end")).toString(), Qt::ISODate).toString(QStringLiteral("HH:mm:ss"))
             << QString::number(r.value(QStringLiteral("durationSec")).toDouble() / 60.0, 'f', 1)
             << QString::number(r.value(QStringLiteral("odometer")).toDouble(), 'f', 0)
             << QString::number(r.value(QStringLiteral("routeLength")).toDouble(), 'f', 0)
             << QString::number(area * 15.0 / 10000.0, 'f', 2)
             << QString::number(area / 10000.0, 'f', 3)
             << QStringLiteral("%1-%2").arg(r.value(QStringLiteral("fromSeq")).toInt()).arg(r.value(QStringLiteral("toSeq")).toInt())
             << QString::number(r.value(QStringLiteral("interruptions")).toInt())
             << (r.value(QStringLiteral("completed")).toBool() ? tr("Yes") : tr("No"));
        lines << cols.join(QLatin1Char(','));
    }
    file.write("\xEF\xBB\xBF");     // UTF-8 BOM for Excel
    file.write(lines.join(QStringLiteral("\r\n")).toUtf8());
    file.write("\r\n");
    return file.commit();
}
