#include "HHUStraightTest.h"
#include "HHUTuning.h"
#include "QGCLoggingCategory.h"
#include "AppSettings.h"
#include "Fact.h"
#include "MultiVehicleManager.h"
#include "ParameterManager.h"
#include "SettingsManager.h"
#include "Vehicle.h"

#include <cmath>

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtGui/QDesktopServices>

QGC_LOGGING_CATEGORY(HHUStraightTestLog, "Custom.HHUStraightTest")

namespace {
constexpr double kAlignedDeg     = 15.0;    ///< the steady part starts once the heading is within this of the line ...
constexpr double kSteadyFrom     = 5.0;     ///< ... and the vehicle drove this far after that (m), so the turn of a
                                            ///< return leg and the first correction are not scored
constexpr double kCrossHyst      = 0.03;    ///< m: a crossing counts when the side changes beyond this
constexpr double kArriveDist     = 3.0;     ///< m from the leg's end
constexpr double kStillSpeed     = 0.1;     ///< m/s
constexpr qint64 kStillMs        = 1500;
constexpr qint64 kArmTimeoutMs   = 6000;
constexpr qint64 kNoPositionMs   = 5000;
constexpr int    kChartMax       = 1500;

/// summary columns: key, header
const QList<QPair<QString, QString>> kColumns = {
    { "time",       QStringLiteral("时间") },
    { "leg",        QStringLiteral("腿(1去2回)") },
    { "length",     QStringLiteral("设定距离m") },
    { "distance",   QStringLiteral("实走距离m") },
    { "speedSet",   QStringLiteral("设定车速m/s") },
    { "duration",   QStringLiteral("用时s") },
    { "rms",        QStringLiteral("全程横偏RMS m") },
    { "max",        QStringLiteral("稳定段最大横偏m") },
    { "steadyRms",  QStringLiteral("稳定段RMS m") },
    { "bias",       QStringLiteral("平均偏向m(+左)") },
    { "crossings",  QStringLiteral("过线次数") },
    { "headingRms", QStringLiteral("航向偏差RMS°") },
    { "speedMean",  QStringLiteral("平均车速m/s") },
    { "speedErr",   QStringLiteral("车速误差m/s") },
    { "overshoot",  QStringLiteral("终点停车m(+冲过)") },
    { "aborted",    QStringLiteral("中断") },
    { "detail",     QStringLiteral("明细文件") },
};

QString num(const QVariant &v, int decimals)
{
    const double d = v.toDouble();
    return std::isfinite(d) ? QString::number(d, 'f', decimals) : QString();
}

QStringList splitCsv(const QString &line)
{
    QStringList out;
    QString cur;
    bool quoted = false;
    for (int i = 0; i < line.size(); i++) {
        const QChar c = line.at(i);
        if (quoted) {
            if (c == '"' && i + 1 < line.size() && line.at(i + 1) == '"') { cur += '"'; i++; }
            else if (c == '"') quoted = false;
            else cur += c;
        } else if (c == '"') {
            quoted = true;
        } else if (c == ',') {
            out << cur; cur.clear();
        } else {
            cur += c;
        }
    }
    out << cur;
    return out;
}
} // namespace

HHUStraightTest::HHUStraightTest(HHUTuning *tuning, QObject *parent)
    : QObject(parent)
    , _tuning(tuning)
{
    _tick.setInterval(200);
    (void) connect(&_tick, &QTimer::timeout, this, &HHUStraightTest::_onTick);
}

QString HHUStraightTest::_vehicleName() const
{
    return _tuning ? _tuning->vehicleName() : QString();
}

QString HHUStraightTest::folder() const
{
    const QString savePath = SettingsManager::instance()->appSettings()->savePath()->rawValue().toString();
    QString name = _vehicleName();
    if (name.isEmpty()) {
        name = QStringLiteral("unknown");
    }
    return QDir(savePath).filePath(QStringLiteral("直线测试/") + name);
}

// ---- Run ----------------------------------------------------------------------------------------------

QString HHUStraightTest::start(double length, double speed, bool roundTrip)
{
    if (_phase != Idle) {
        return tr("A test is running");
    }
    Vehicle *v = MultiVehicleManager::instance()->activeVehicle();
    if (!v) {
        return tr("Not connected");
    }
    if (v->armed()) {
        return tr("Stop and lock the vehicle first");
    }
    const QGeoCoordinate here = v->coordinate();
    if (!here.isValid() || !_lastPosition.isValid() || _lastPosition.elapsed() > kNoPositionMs || !std::isfinite(_lastHeading)) {
        return tr("No position from the vehicle");
    }

    if (_vehicle != v) {
        if (_vehicle) {
            (void) disconnect(_vehicle, nullptr, this, nullptr);
        }
        _vehicle = v;
        (void) connect(v, &Vehicle::armedChanged, this, &HHUStraightTest::_onArmedChanged);
        (void) connect(v, &Vehicle::flightModeChanged, this, &HHUStraightTest::_onFlightModeChanged);
    }

    _length = qBound(2.0, length, 500.0);
    _speedSet = qBound(0.1, speed, 3.0);
    _roundTrip = roundTrip;
    _start = here;
    _end = here.atDistanceAndAzimuth(_length, _lastHeading);
    _origin = { here.latitude(), here.longitude() };
    _message.clear();
    _abortedRun = false;
    _samples.clear();
    _results.clear();
    _previous.clear();
    _changedParams.clear();
    _runStamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
    _runClock.start();
    emit resultsChanged();

    _leg = 1;
    _setPhase(Starting);
    _legClock.start();
    // position / speed / nav output at 10 / 10 / 5 Hz while the test runs (back to the defaults at the end)
    _setRates(true);
    v->setFlightMode(v->gotoFlightMode());
    v->setArmed(true, false);
    _tick.start();
    qCDebug(HHUStraightTestLog) << "start" << _length << "m at" << _speedSet << "m/s heading" << _lastHeading << "round trip" << roundTrip;
    return QString();
}

void HHUStraightTest::stop()
{
    if (_phase == Idle) {
        return;
    }
    if (_phase == Starting || _phase == Driving) {
        _finishLeg(true, tr("Stopped"));
    } else if (_vehicle) {
        _vehicle->setFlightMode(_vehicle->pauseFlightMode());
        _vehicle->setArmed(false, false);
    }
}

void HHUStraightTest::clearResults()
{
    _results.clear();
    _previous.clear();
    _changedParams.clear();
    _message.clear();
    emit resultsChanged();
    emit stateChanged();
}

void HHUStraightTest::_setPhase(Phase phase)
{
    if (phase != _phase) {
        _phase = phase;
        emit stateChanged();
    }
}

void HHUStraightTest::_setRates(bool fast)
{
    if (!_vehicle) {
        return;
    }
    const QList<QPair<int, float>> rates = {
        { MAVLINK_MSG_ID_GLOBAL_POSITION_INT, 100000.f },
        { MAVLINK_MSG_ID_VFR_HUD, 100000.f },
        { MAVLINK_MSG_ID_NAV_CONTROLLER_OUTPUT, 200000.f },
    };
    for (const auto &r : rates) {
        // 0 = the vehicle's default rate
        _vehicle->sendMavCommand(_vehicle->defaultComponentId(), MAV_CMD_SET_MESSAGE_INTERVAL, false,
                                 static_cast<float>(r.first), fast ? r.second : 0.f);
    }
}

void HHUStraightTest::_startLeg(int leg)
{
    hhuab::LocalFrame frame(_origin);
    const hhuab::EN a = frame.toEN({ _start.latitude(), _start.longitude() });
    const hhuab::EN b = frame.toEN({ _end.latitude(), _end.longitude() });
    _leg = leg;
    _line = leg == 1 ? hhuab::Line{ a, b } : hhuab::Line{ b, a };
    _chart.clear();
    _legClock.start();
    _stillSince.invalidate();
    _gotoSends = 0;
    _setPhase(Driving);
    emit stateChanged();
    _sendGoto();
}

void HHUStraightTest::_sendGoto()
{
    if (!_vehicle) {
        return;
    }
    _vehicle->guidedModeGotoLocation(_leg == 1 ? _end : _start);
    // after the goto: entering GUIDED resets the speed to WP_SPEED
    _vehicle->guidedModeChangeGroundSpeedMetersSecond(_speedSet);
    _gotoSends++;
}

void HHUStraightTest::_onArmedChanged(bool armed)
{
    if (_phase == Starting && armed) {
        _startLeg(1);
    } else if (!armed && (_phase == Starting || _phase == Driving)) {
        _finishLeg(true, tr("The vehicle was locked (emergency stop)"));
    } else if (!armed && _phase == Stopping) {
        _tick.stop();
        _setPhase(Idle);
    }
}

void HHUStraightTest::_onFlightModeChanged(const QString &mode)
{
    if (_phase == Driving && _vehicle && mode != _vehicle->gotoFlightMode()) {
        _finishLeg(true, tr("The vehicle left GUIDED (%1)").arg(mode));
    }
}

void HHUStraightTest::_onTick()
{
    if (_phase == Starting) {
        if (_legClock.elapsed() > kArmTimeoutMs) {
            const QString why = _vehicle && !_vehicle->prearmError().isEmpty() ? _vehicle->prearmError() : tr("The vehicle did not arm");
            _finishLeg(true, why);
        }
        return;
    }
    if (_phase == Stopping) {
        // the vehicle may miss the disarm over 4G
        if (_vehicle && _vehicle->armed() && _legClock.elapsed() > 1500) {
            _vehicle->emergencyStop();
            _legClock.start();
        } else if (!_vehicle || !_vehicle->armed()) {
            _tick.stop();
            _setPhase(Idle);
        }
        return;
    }
    if (_phase != Driving) {
        return;
    }
    if (!_lastPosition.isValid() || _lastPosition.elapsed() > kNoPositionMs) {
        _finishLeg(true, tr("No position data from the vehicle"));
        return;
    }
    // the speed command once more (4G can drop one)
    if (_gotoSends == 1 && _legClock.elapsed() > 1000) {
        _vehicle->guidedModeChangeGroundSpeedMetersSecond(_speedSet);
        _gotoSends++;
    }
    const double legLength = hhuab::length(_line);
    const double left = legLength - _along;
    if (std::isfinite(left) && std::fabs(left) < kArriveDist + 2.0 && std::isfinite(_speed) && _speed < kStillSpeed) {
        if (!_stillSince.isValid()) {
            _stillSince.start();
        } else if (_stillSince.elapsed() > kStillMs) {
            _finishLeg(false, QString());
            return;
        }
    } else {
        _stillSince.invalidate();
    }
    const double maxSeconds = legLength / _speedSet * 3.0 + 30.0;
    if (_legClock.elapsed() > maxSeconds * 1000) {
        _finishLeg(true, tr("Did not reach the end in %1 s").arg(qRound(maxSeconds)));
    }
}

void HHUStraightTest::_finishLeg(bool aborted, const QString &reason)
{
    if (_phase == Driving) {
        _results.append(_legResult(_leg, aborted));
        emit resultsChanged();
    }
    if (!aborted && _leg == 1 && _roundTrip) {
        _startLeg(2);
        return;
    }
    _finishRun(aborted, reason);
}

void HHUStraightTest::_finishRun(bool aborted, const QString &reason)
{
    _abortedRun = aborted;
    _message = reason;
    _setRates(false);
    if (_vehicle) {
        _vehicle->setFlightMode(_vehicle->pauseFlightMode());
        if (_vehicle->armed()) {
            _vehicle->setArmed(false, false);
        }
    }
    _legClock.start();
    _setPhase(_vehicle && _vehicle->armed() ? Stopping : Idle);
    if (_phase == Idle) {
        _tick.stop();
    }

    const QVariantMap params = _paramSnapshot();
    const QVariantList previousRows = _readSummary(2);
    // the run before: its rows share the time stamp of the newest row
    _previous.clear();
    QVariantMap previousParams;
    if (!previousRows.isEmpty()) {
        const QString stamp = previousRows.first().toMap().value("time").toString();
        for (const QVariant &row : previousRows) {
            if (row.toMap().value("time").toString() == stamp) {
                _previous.prepend(row);
            }
        }
        previousParams = previousRows.first().toMap().value("params").toMap();
    }
    _changedParams.clear();
    for (auto it = params.cbegin(); it != params.cend(); ++it) {
        if (previousParams.contains(it.key()) && previousParams.value(it.key()).toString() != it.value().toString()) {
            _changedParams << QStringLiteral("%1 %2 → %3").arg(it.key(), previousParams.value(it.key()).toString(), it.value().toString());
        }
    }
    _writeFiles(params);
    emit stateChanged();
    emit resultsChanged();
    emit finished();
    qCDebug(HHUStraightTestLog) << "finished, aborted" << aborted << reason << _results;
}

// ---- Samples ------------------------------------------------------------------------------------------

void HHUStraightTest::handleMessage(Vehicle *vehicle, const mavlink_message_t &message)
{
    if (!vehicle || vehicle != MultiVehicleManager::instance()->activeVehicle() || message.sysid != vehicle->id()
            || message.compid != vehicle->defaultComponentId()) {
        return;
    }
    switch (message.msgid) {
    case MAVLINK_MSG_ID_VFR_HUD: {
        mavlink_vfr_hud_t m{};
        mavlink_msg_vfr_hud_decode(&message, &m);
        _speed = m.groundspeed;
        _throttle = m.throttle;
        break;
    }
    case MAVLINK_MSG_ID_NAV_CONTROLLER_OUTPUT: {
        mavlink_nav_controller_output_t m{};
        mavlink_msg_nav_controller_output_decode(&message, &m);
        _fcXtrack = m.xtrack_error;
        break;
    }
    case MAVLINK_MSG_ID_SERVO_OUTPUT_RAW: {
        mavlink_servo_output_raw_t m{};
        mavlink_msg_servo_output_raw_decode(&message, &m);
        _servo1 = m.servo1_raw;
        _servo3 = m.servo3_raw;
        break;
    }
    case MAVLINK_MSG_ID_GLOBAL_POSITION_INT: {
        mavlink_global_position_int_t m{};
        mavlink_msg_global_position_int_decode(&message, &m);
        _lastPosition.start();
        if (m.hdg != UINT16_MAX) {
            _lastHeading = m.hdg / 100.0;
        }
        if (_phase != Driving) {
            break;
        }
        Sample s;
        s.t = _runClock.elapsed() / 1000.0;
        s.leg = _leg;
        s.lat = m.lat / 1e7;
        s.lon = m.lon / 1e7;
        hhuab::LocalFrame frame(_origin);
        const hhuab::EN p = frame.toEN({ s.lat, s.lon });
        const hhuab::EN d = hhuab::direction(_line);
        s.along = (p.e - _line.start.e) * d.e + (p.n - _line.start.n) * d.n;
        s.xtrack = hhuab::crossTrack(_line, p);
        s.heading = _lastHeading;
        s.headingErr = hhuab::headingError(_line, _lastHeading);
        s.speed = _speed;
        s.throttle = _throttle;
        s.fcXtrack = _fcXtrack;
        s.servo1 = _servo1;
        s.servo3 = _servo3;
        _samples.append(s);
        _xtrack = s.xtrack;
        _headingErr = s.headingErr;
        _along = s.along;
        if (_chart.size() >= kChartMax) {
            _chart.removeFirst();
        }
        _chart.append(QVariantMap{ { "s", s.along }, { "x", s.xtrack } });
        emit sampleChanged();
        break;
    }
    default:
        break;
    }
}

// ---- Scoring ------------------------------------------------------------------------------------------

QVariantMap HHUStraightTest::_legResult(int leg, bool aborted) const
{
    const double legLength = hhuab::length(_line);
    double sumSq = 0, maxAbs = 0, steadySq = 0, steadySum = 0, headingSq = 0, speedSum = 0, speedErrSum = 0;
    double driven = 0, lastAlong = qQNaN();
    int n = 0, steadyN = 0, crossings = 0, side = 0;
    bool aligned = false;
    double alignedAt = 0;
    double t0 = qQNaN(), t1 = qQNaN();
    for (const Sample &s : _samples) {
        if (s.leg != leg) {
            continue;
        }
        if (std::isnan(t0)) t0 = s.t;
        t1 = s.t;
        lastAlong = s.along;
        driven = std::max(driven, s.along);
        if (s.along < 0 || s.along > legLength) {
            continue;
        }
        n++;
        sumSq += s.xtrack * s.xtrack;
        if (!aligned && std::fabs(s.headingErr) < kAlignedDeg) {
            aligned = true;
            alignedAt = s.along;
        }
        if (!aligned || s.along < alignedAt + kSteadyFrom) {
            continue;
        }
        steadyN++;
        maxAbs = std::max(maxAbs, std::fabs(s.xtrack));
        steadySq += s.xtrack * s.xtrack;
        steadySum += s.xtrack;
        headingSq += s.headingErr * s.headingErr;
        speedSum += s.speed;
        speedErrSum += s.speed - _speedSet;
        const int now = s.xtrack > kCrossHyst ? 1 : (s.xtrack < -kCrossHyst ? -1 : 0);
        if (now != 0) {
            if (side != 0 && now != side) {
                crossings++;
            }
            side = now;
        }
    }
    const double nan = qQNaN();
    QVariantMap r;
    r["leg"] = leg;
    r["aborted"] = aborted;
    r["length"] = legLength;
    r["distance"] = driven;
    r["speedSet"] = _speedSet;
    r["duration"] = std::isnan(t0) ? nan : t1 - t0;
    r["samples"] = n;
    r["rms"] = n > 0 ? std::sqrt(sumSq / n) : nan;
    r["max"] = steadyN > 0 ? maxAbs : nan;
    r["steadyRms"] = steadyN > 0 ? std::sqrt(steadySq / steadyN) : nan;
    r["bias"] = steadyN > 0 ? steadySum / steadyN : nan;
    r["crossings"] = steadyN > 0 ? crossings : -1;
    r["headingRms"] = steadyN > 0 ? std::sqrt(headingSq / steadyN) : nan;
    r["speedMean"] = steadyN > 0 ? speedSum / steadyN : nan;
    r["speedErr"] = steadyN > 0 ? speedErrSum / steadyN : nan;
    r["overshoot"] = aborted || std::isnan(lastAlong) ? nan : lastAlong - legLength;
    return r;
}

QVariantMap HHUStraightTest::_paramSnapshot() const
{
    QVariantMap out;
    if (!_tuning) {
        return out;
    }
    const QVariantMap tuned = _tuning->currentValues();
    ParameterManager *pm = _vehicle ? _vehicle->parameterManager() : nullptr;
    const int comp = ParameterManager::defaultComponentId;
    for (const QString &name : _tuning->parameterNames()) {
        QString value;
        if (pm && pm->parametersReady() && pm->parameterExists(comp, name)) {
            value = pm->getParameter(comp, name)->rawValueString();
        } else if (tuned.contains(name)) {
            value = tuned.value(name).toString();
        }
        out[name] = value;
    }
    return out;
}

// ---- Files --------------------------------------------------------------------------------------------

void HHUStraightTest::_writeFiles(const QVariantMap &params)
{
    const QString dir = folder();
    if (!QDir().mkpath(dir)) {
        qCWarning(HHUStraightTestLog) << "cannot create" << dir;
        return;
    }
    const QString detailName = _runStamp + QStringLiteral("_明细.csv");
    {
        QFile f(QDir(dir).filePath(detailName));
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream ts(&f);
            ts << QChar(0xFEFF) << "t_s,leg,lat,lon,along_m,xtrack_m(+left),heading_deg,heading_err_deg,speed_mps,speed_set_mps,throttle_pct,fc_xtrack_m,servo1,servo3\n";
            for (const Sample &s : _samples) {
                ts << QString::number(s.t, 'f', 2) << ',' << s.leg << ',' << QString::number(s.lat, 'f', 8) << ',' << QString::number(s.lon, 'f', 8) << ','
                   << QString::number(s.along, 'f', 3) << ',' << QString::number(s.xtrack, 'f', 3) << ',' << QString::number(s.heading, 'f', 1) << ','
                   << QString::number(s.headingErr, 'f', 2) << ',' << QString::number(s.speed, 'f', 3) << ',' << QString::number(_speedSet, 'f', 2) << ','
                   << s.throttle << ',' << (std::isfinite(s.fcXtrack) ? QString::number(s.fcXtrack, 'f', 3) : QString()) << ',' << s.servo1 << ',' << s.servo3 << '\n';
            }
        }
    }

    QStringList header;
    for (const auto &c : kColumns) header << c.second;
    const QStringList names = params.keys();
    header << names;
    const QString headerLine = header.join(',');

    const QString summaryPath = QDir(dir).filePath(QStringLiteral("汇总.csv"));
    QFile summary(summaryPath);
    if (summary.exists() && summary.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString first = QString::fromUtf8(summary.readLine()).trimmed();
        if (first.startsWith(QChar(0xFEFF))) first.remove(0, 1);
        summary.close();
        if (first != headerLine) {
            // the tuning list changed: keep the old table, start a new one
            (void) QFile::rename(summaryPath, QDir(dir).filePath(QStringLiteral("汇总_至%1.csv").arg(_runStamp)));
        }
    }
    const bool fresh = !QFile::exists(summaryPath);
    if (!summary.open(QIODevice::Append | QIODevice::Text)) {
        qCWarning(HHUStraightTestLog) << "cannot write" << summaryPath;
        return;
    }
    QTextStream ts(&summary);
    if (fresh) {
        ts << QChar(0xFEFF) << headerLine << '\n';
    }
    for (const QVariant &v : _results) {
        const QVariantMap r = v.toMap();
        QStringList row;
        row << _runStamp << r["leg"].toString() << num(r["length"], 1) << num(r["distance"], 1) << num(r["speedSet"], 2) << num(r["duration"], 1)
            << num(r["rms"], 3) << num(r["max"], 3) << num(r["steadyRms"], 3) << num(r["bias"], 3)
            << (r["crossings"].toInt() >= 0 ? r["crossings"].toString() : QString()) << num(r["headingRms"], 2)
            << num(r["speedMean"], 3) << num(r["speedErr"], 3) << num(r["overshoot"], 2)
            << (r["aborted"].toBool() ? QStringLiteral("是") : QString()) << detailName;
        for (const QString &name : names) row << params.value(name).toString();
        ts << row.join(',') << '\n';
    }
}

QVariantList HHUStraightTest::_readSummary(int count) const
{
    QVariantList out;
    QFile f(QDir(folder()).filePath(QStringLiteral("汇总.csv")));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return out;
    }
    QString headerLine = QString::fromUtf8(f.readLine()).trimmed();
    if (headerLine.startsWith(QChar(0xFEFF))) headerLine.remove(0, 1);
    const QStringList header = splitCsv(headerLine);
    QStringList lines;
    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (!line.isEmpty()) lines << line;
    }
    for (int i = static_cast<int>(lines.size()) - 1; i >= 0 && out.size() < count; i--) {
        const QStringList cells = splitCsv(lines.at(i));
        QVariantMap row, params;
        for (int c = 0; c < header.size() && c < cells.size(); c++) {
            if (c < kColumns.size()) {
                const QString key = kColumns.at(c).first;
                row[key] = key == "time" || key == "detail" ? QVariant(cells.at(c))
                         : key == "aborted" ? QVariant(!cells.at(c).isEmpty())
                         : cells.at(c).isEmpty() ? QVariant(qQNaN()) : QVariant(cells.at(c).toDouble());
            } else {
                params[header.at(c)] = cells.at(c);
            }
        }
        row["params"] = params;
        out << row;
    }
    return out;
}

QVariantList HHUStraightTest::history(int count) const
{
    return _readSummary(count);
}

void HHUStraightTest::openFolder() const
{
    const QString dir = folder();
    (void) QDir().mkpath(dir);
    (void) QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}
