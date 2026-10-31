#include "HHUABRun.h"
#include "HHUABField.h"
#include "HHUConfig.h"
#include "HHUVcuStatus.h"
#include "HHUWorkLog.h"
#include "QGCLoggingCategory.h"
#include "MissionItem.h"
#include "MissionManager.h"
#include "MultiVehicleManager.h"
#include "ParameterManager.h"
#include "Fact.h"
#include "Vehicle.h"

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QSettings>

#include <cmath>

QGC_LOGGING_CATEGORY(HHUABRunLog, "Custom.HHUABRun")

namespace {
constexpr int    kAuxWork = 300;            // RC aux function SCRIPTING1: work request of vcu_can.lua (garlic.15)
constexpr float  kAuxHigh = 2;
constexpr float  kAuxLow  = 0;
constexpr int    kTickMs = 200;
constexpr qint64 kNoWorkFbMs = 3000;        // no VCU_WORKFB this long: 车端未上报作业杆状态
constexpr qint64 kEchoMs = 2000;            // VCU_WREQ must follow the request this fast (garlic.15)
constexpr qint64 kAutoMs = 10000;           // the vehicle must be in AUTO this long after it was asked
constexpr qint64 kSettleMs = 1500;          // at the alignment point: wait before measuring
constexpr qint64 kEndHoldMs = 2500;         // end point reached: NAV_DELAY 1 s, then raise
constexpr double kArriveDist = 1.5;         // m from the last point of the route
constexpr qint64 kArriveStillMs = 3000;
constexpr qint64 kClearGiveUpMs = 120000;   // stop waiting to remove the AB route (vehicle kept driving)
const char      *kSettingsGroup = "HHU";
const char      *kKeySignature = "abRouteSignature";
constexpr int    kWfbTransport = 0;
constexpr int    kWfbLifting = 1;
constexpr int    kWfbWorking = 3;
constexpr int    kWfbFault = 4;
} // namespace

HHUABRun::HHUABRun(HHUConfig *config, HHUABField *field, HHUVcuStatus *vcu, HHUWorkLog *workLog, QObject *parent)
    : QObject(parent)
    , _config(config)
    , _field(field)
    , _vcu(vcu)
    , _workLog(workLog)
{
    _tickTimer.setInterval(kTickMs);
    (void) connect(&_tickTimer, &QTimer::timeout, this, &HHUABRun::_tick);
    (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, &HHUABRun::_onVehicleChanged);

    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    _signature = QJsonDocument::fromJson(settings.value(kKeySignature).toByteArray()).array().toVariantList();
    _clearTimer.setInterval(500);
    (void) connect(&_clearTimer, &QTimer::timeout, this, &HHUABRun::_tryClear);
    _watch(MultiVehicleManager::instance()->activeVehicle());
}

bool HHUABRun::workLink() const
{
    return _config->abWorkLink();
}

Vehicle *HHUABRun::_vehicle() const
{
    return _vehicleRef.data();
}

bool HHUABRun::_inAuto() const
{
    Vehicle *v = _vehicle();
    return v && v->flightMode() == v->missionFlightMode();
}

bool HHUABRun::_inHold() const
{
    Vehicle *v = _vehicle();
    return v && v->flightMode() == v->pauseFlightMode();
}

void HHUABRun::_setPhase(Phase phase, Fault fault)
{
    qCDebug(HHUABRunLog) << "phase" << _phase << "->" << phase << "fault" << fault << "line" << _line + 1;
    _phase = phase;
    _fault = fault;
    _phaseTime.restart();
    if (phase == Idle || phase == Done) {
        // the line has ended: its route must not stay on the vehicle as a normal route
        _requestClear();
    }
    if (phase == Idle) {
        _tickTimer.stop();
        _line = -1;
        _starting = false;
        _xtrack = _headingErr = qQNaN();
        emit trackChanged();
    } else if (!_tickTimer.isActive()) {
        _tickTimer.start();
    }
    emit changed();
}

// ---- Start ----------------------------------------------------------------------------------------

int HHUABRun::checkWorkEnable() const
{
    if (!workLink()) {
        return StartOk;
    }
    Vehicle *v = MultiVehicleManager::instance()->activeVehicle();
    if (!v) {
        return NoVehicle;
    }
    ParameterManager *params = v->parameterManager();
    const QString name = QStringLiteral("VCU_WORK_EN");
    if (!params->parameterExists(ParameterManager::defaultComponentId, name)
            || params->getParameter(ParameterManager::defaultComponentId, name)->rawValue().toInt() <= 0) {
        return WorkEnOff;
    }
    return StartOk;
}

int HHUABRun::start(int index)
{
    Vehicle *v = MultiVehicleManager::instance()->activeVehicle();
    if (!v) {
        return NoVehicle;
    }
    if (index < 0 || index >= static_cast<int>(_field->geometry().size())) {
        return NoLines;
    }
    if (_uploading || (_phase != Idle && _phase != Done)) {
        return Busy;
    }
    const int enable = checkWorkEnable();
    if (enable != StartOk) {
        return enable;
    }

    if (_vehicleRef != v) {
        if (_vehicleRef) {
            (void) disconnect(_vehicleRef, nullptr, this, nullptr);
        }
        _vehicleRef = v;
        (void) connect(v, &Vehicle::coordinateChanged, this, &HHUABRun::_updateTrack);
        (void) connect(v, &Vehicle::armedChanged, this, &HHUABRun::_onArmed);
    }
    _clearTimer.stop();
    _line = index;
    _field->setSelected(index);
    _resumeWork = false;
    _ending = false;
    _endReached = false;
    _alignXtrack = _alignHeadingErr = qQNaN();
    _starting = true;
    _setPhase(Aligning);
    _updateTrack();
    _upload(_alignMission());
    return StartOk;
}

void HHUABRun::startAnyway()
{
    if (_phase != AlignFailed) {
        return;
    }
    if (workLink()) {
        _beginLower();
    } else {
        _beginWork(false);
    }
}

// ---- Routes ---------------------------------------------------------------------------------------

MissionItem *HHUABRun::_speedItem(int seq, double speed)
{
    // DO_CHANGE_SPEED before the first waypoint: ground speed (1), m/s, throttle unchanged (-1)
    return new MissionItem(seq, MAV_CMD_DO_CHANGE_SPEED, MAV_FRAME_MISSION, 1, speed, -1, 0, 0, 0, 0, true, false);
}

QList<MissionItem *> HHUABRun::_alignMission()
{
    const hhuab::Line &l = _field->geometry()[_line];
    Vehicle *v = _vehicle();
    QGeoCoordinate home = v->homePosition();
    if (!home.isValid()) {
        home = v->coordinate();
    }
    auto wp = [](int seq, const QGeoCoordinate &c) {
        return new MissionItem(seq, MAV_CMD_NAV_WAYPOINT, MAV_FRAME_GLOBAL_RELATIVE_ALT,
                               0, 0, 0, 0, c.latitude(), c.longitude(), 0, true, false);
    };
    const QGeoCoordinate lead  = _field->toCoordinate(hhuab::along(l, -(_field->leadD() + _field->leadLc())));
    const QGeoCoordinate align = _field->toCoordinate(hhuab::along(l, -_field->leadD()));
    _lastSeq = 3;
    _target = hhuab::along(l, -_field->leadD());
    // lift up: the VCU drives 5 km/h, the autopilot plans turns and the stop with that speed
    return { wp(0, home), _speedItem(1, _config->abLine().speedTransport), wp(2, lead), wp(3, align) };
}

QList<MissionItem *> HHUABRun::_workMission()
{
    const hhuab::Line &l = _field->geometry()[_line];
    Vehicle *v = _vehicle();
    QGeoCoordinate home = v->homePosition();
    if (!home.isValid()) {
        home = v->coordinate();
    }
    auto wp = [](int seq, const QGeoCoordinate &c) {
        return new MissionItem(seq, MAV_CMD_NAV_WAYPOINT, MAV_FRAME_GLOBAL_RELATIVE_ALT,
                               0, 0, 0, 0, c.latitude(), c.longitude(), 0, true, false);
    };
    // lift down: the VCU drives 2 km/h; without the lift link the lift stays up and the vehicle drives 5 km/h
    const double speed = workLink() ? _config->abLine().speedWork : _config->abLine().speedTransport;
    QList<MissionItem *> items { wp(0, home), _speedItem(1, speed), wp(2, _field->toCoordinate(l.start)), wp(3, _field->toCoordinate(l.end)) };
    _lastSeq = 3;
    _target = l.end;
    if (workLink()) {
        // DO items run when the NAV item before them starts: the 1 s delay after the end point keeps the
        // raise at the end (without it the lift would go up as soon as the start point is passed)
        items.append(new MissionItem(4, MAV_CMD_NAV_DELAY, MAV_FRAME_MISSION, 1, -1, -1, -1, 0, 0, 0, true, false));
        items.append(new MissionItem(5, MAV_CMD_DO_AUX_FUNCTION, MAV_FRAME_MISSION, kAuxWork, kAuxLow, 0, 0, 0, 0, 0, true, false));
    }
    return items;
}

void HHUABRun::_upload(const QList<MissionItem *> &items)
{
    Vehicle *v = _vehicle();
    MissionManager *manager = v ? v->missionManager() : nullptr;
    if (!manager || manager->inProgress()) {
        qDeleteAll(items);
        _setPhase(_phase == Aligning ? Idle : WorkFault, UploadFailed);
        return;
    }
    _saveSignature(items);
    _uploading = true;
    _starting = true;
    (void) connect(manager, &PlanManager::sendComplete, this, &HHUABRun::_onSendComplete, Qt::SingleShotConnection);
    manager->writeMissionItems(items);
    emit changed();
}

void HHUABRun::_onSendComplete(bool error)
{
    _uploading = false;
    if (_phase != Aligning && _phase != Working) {
        return;
    }
    if (error) {
        qCWarning(HHUABRunLog) << "route upload failed";
        // the failure is reported by the next state: back to idle while aligning, a fault while working
        const Phase failed = _phase == Aligning ? Idle : WorkFault;
        _setPhase(failed, UploadFailed);
        emit changed();
        return;
    }
    // a new route on the vehicle: the resume point of the 手工航点 route no longer applies
    _workLog->clearResume(_vehicle());
    _startAuto();
}

void HHUABRun::_startAuto()
{
    Vehicle *v = _vehicle();
    if (!v) {
        return;
    }
    _endReached = false;
    _starting = true;
    _stillTime.invalidate();
    _autoTime.restart();
    v->setCurrentMissionSequence(1);
    if (v->armed()) {
        v->setFlightMode(v->missionFlightMode());
    } else {
        // Rover: arm in Guided, then MISSION_START (the same way 开始作业 starts a route)
        v->startMission();
    }
    emit changed();
}

// ---- Lift -----------------------------------------------------------------------------------------

void HHUABRun::_sendLift(bool down)
{
    Vehicle *v = _vehicle();
    if (!v) {
        return;
    }
    _liftSent.restart();
    v->sendMavCommand(v->defaultComponentId(), MAV_CMD_DO_AUX_FUNCTION, false, kAuxWork, down ? kAuxHigh : kAuxLow);
}

void HHUABRun::_beginLower()
{
    _hold();
    _setPhase(Lowering);
    _sendLift(true);
}

void HHUABRun::retryLower()
{
    if (_phase != LowerFault && _phase != WorkFault) {
        return;
    }
    _resumeWork = _phase == WorkFault && _fault != UploadFailed;
    if (_phase == WorkFault && (_fault == UploadFailed || _fault == ModeFailed) && _vcu->workFb() == kWfbWorking) {
        // the lift is down already: only the route / AUTO failed
        _beginWork(_fault == ModeFailed);
        return;
    }
    if (!workLink() || (_vcu->workFbValid() && _vcu->workFb() == kWfbWorking && _vcu->workReq() == 1)) {
        // no lift, or it is down again by now
        _beginWork(_resumeWork);
        return;
    }
    // after a fault the VCU moves the lift again on a new request: lift fault → raise first is the
    // VCU's business, the ground station just sends the request again (low first when it was high)
    _hold();
    _setPhase(Lowering);
    if (_vcu->workReq() == 1 || _vcu->workFb() == kWfbFault) {
        _sendLift(false);
        QTimer::singleShot(600, this, [this]() {
            if (_phase == Lowering) {
                _sendLift(true);
                _phaseTime.restart();
            }
        });
    } else {
        _sendLift(true);
    }
}

void HHUABRun::_beginWork(bool resumeOnly)
{
    _setPhase(Working);
    _endReached = false;
    if (resumeOnly) {
        _startAuto();
    } else {
        _upload(_workMission());
    }
}

void HHUABRun::_beginRaise(bool ending)
{
    _ending = ending;
    _hold();
    _setPhase(ending ? Ending : Raising);
    _sendLift(false);
}

void HHUABRun::retryRaise()
{
    if (_phase != RaiseFault) {
        return;
    }
    _beginRaise(_ending);
}

// ---- Operator -------------------------------------------------------------------------------------

void HHUABRun::endLine()
{
    switch (_phase) {
    case Aligning:
    case AlignFailed:
        // the lift is still up: nothing done on this line
        _hold();
        _setPhase(Idle);
        break;
    case Lowering:
    case LowerFault:
    case Working:
    case WorkFault:
    case RaiseFault:
        if (workLink()) {
            _beginRaise(true);
        } else {
            _hold();
            _setPhase(EndAsk);
        }
        break;
    default:
        break;
    }
}

void HHUABRun::confirmEnd(bool done)
{
    if (_phase != EndAsk) {
        return;
    }
    if (done) {
        _field->setLineStatus(_line, HHUABField::Done);
        (void) _field->save();
    }
    _setPhase(Idle);
}

void HHUABRun::pause()
{
    if ((_phase == Aligning || _phase == Working) && _inAuto()) {
        _hold();
    }
}

void HHUABRun::resume()
{
    Vehicle *v = _vehicle();
    if (v && (_phase == Aligning || _phase == Working) && !_inAuto() && !_starting) {
        v->setFlightMode(v->missionFlightMode());
    }
}

void HHUABRun::finish()
{
    if (_phase == Done || _phase == RaiseFault || _phase == EndAsk) {
        _setPhase(Idle);
    }
}

void HHUABRun::_hold()
{
    Vehicle *v = _vehicle();
    if (v && v->armed() && !_inHold()) {
        v->setFlightMode(v->pauseFlightMode());
    }
}

// ---- Vehicle events -------------------------------------------------------------------------------

void HHUABRun::itemReached(Vehicle *vehicle, int seq)
{
    qCDebug(HHUABRunLog) << "item reached" << seq << "phase" << _phase << "starting" << _starting << "last" << _lastSeq << "end" << _endReached;
    if (vehicle != _vehicle() || _starting || seq != _lastSeq || _endReached) {
        return;
    }
    if (_phase == Aligning || _phase == Working) {
        qCDebug(HHUABRunLog) << "reached" << seq << "in phase" << _phase;
        _endReached = true;
        _endTime.restart();
        if (_phase == Aligning || !workLink()) {
            _hold();
        }
    }
}

void HHUABRun::_onArmed(bool armed)
{
    if (armed || _phase == Idle || _phase == Done || _phase == EndAsk) {
        return;
    }
    // 停车上锁 (or disarmed on the vehicle) during the run: the run ends, the lift goes up
    qCDebug(HHUABRunLog) << "disarmed during phase" << _phase;
    if (workLink() && _phase != Aligning && _phase != AlignFailed) {
        _sendLift(false);
    }
    _setPhase(Idle);
}

void HHUABRun::_onVehicleChanged(Vehicle *vehicle)
{
    _watch(vehicle);
    if (vehicle == _vehicleRef) {
        return;
    }
    // link lost for good / another vehicle: the vehicle finishes the route on its own (the route raises
    // the lift at its end); the line stays 未走 until it is marked
    if (_vehicleRef) {
        (void) disconnect(_vehicleRef, nullptr, this, nullptr);
    }
    _vehicleRef = nullptr;
    _uploading = false;
    if (_phase != Idle) {
        _setPhase(Idle);
    }
}

void HHUABRun::_updateTrack()
{
    Vehicle *v = _vehicle();
    if (!v || _line < 0 || _line >= static_cast<int>(_field->geometry().size()) || !v->coordinate().isValid()) {
        return;
    }
    const hhuab::Line &l = _field->geometry()[_line];
    _xtrack = hhuab::crossTrack(l, _field->toEN(v->coordinate()));
    const double heading = v->heading()->rawValue().toDouble();
    _headingErr = std::isfinite(heading) ? hhuab::headingError(l, heading) : qQNaN();
    emit trackChanged();
}

void HHUABRun::_tick()
{
    Vehicle *v = _vehicle();
    if (!v) {
        return;
    }
    const qint64 liftTimeoutMs = qint64(_config->abLine().liftTimeout) * 1000;
    const bool fbFresh = _vcu->workFbValid();
    const int fb = _vcu->workFb();

    if ((_phase == Aligning || _phase == Working) && _starting && !_uploading) {
        if (_inAuto()) {
            _starting = false;
            emit changed();
        } else if (_autoTime.isValid() && _autoTime.elapsed() > kAutoMs) {
            _setPhase(_phase == Aligning ? Idle : WorkFault, ModeFailed);
            return;
        }
    }

    // arrival without MISSION_ITEM_REACHED (lost on the link): standing still at the last point for 3 s
    if ((_phase == Aligning || _phase == Working) && !_starting && !_endReached && v->coordinate().isValid()) {
        const hhuab::EN p = _field->toEN(v->coordinate());
        const double dist = std::hypot(p.e - _target.e, p.n - _target.n);
        const double speed = v->groundSpeed()->rawValue().toDouble();
        if (dist < kArriveDist && std::isfinite(speed) && speed < 0.05) {
            if (!_stillTime.isValid()) {
                _stillTime.start();
            } else if (_stillTime.elapsed() > kArriveStillMs) {
                qCDebug(HHUABRunLog) << "arrived (standing at the last point," << dist << "m)";
                itemReached(v, _lastSeq);
            }
        } else {
            _stillTime.invalidate();
        }
    }

    switch (_phase) {
    case Aligning:
        if (_endReached && _endTime.elapsed() > kSettleMs) {
            const double speed = v->groundSpeed()->rawValue().toDouble();
            if (std::isfinite(speed) && speed > 0.05 && _endTime.elapsed() < 4 * kSettleMs) {
                break;      // still rolling
            }
            _updateTrack();
            _alignXtrack = _xtrack;
            _alignHeadingErr = _headingErr;
            const bool ok = std::isfinite(_xtrack) && std::isfinite(_headingErr)
                            && std::fabs(_xtrack) <= _config->abLine().alignXtrack
                            && std::fabs(_headingErr) <= _config->abLine().alignHeading;
            qCDebug(HHUABRunLog) << "aligned: xtrack" << _xtrack << "heading" << _headingErr << (ok ? "ok" : "out of limits");
            if (!ok) {
                _setPhase(AlignFailed);
            } else if (workLink()) {
                _beginLower();
            } else {
                _beginWork(false);
            }
        }
        break;

    case Lowering:
        if (fbFresh && fb == kWfbWorking && _liftSent.elapsed() > kTickMs) {
            _beginWork(_resumeWork);
        } else if (_vcu->workFbAgeMs() < 0 || _vcu->workFbAgeMs() > kNoWorkFbMs) {
            if (_phaseTime.elapsed() > kNoWorkFbMs) {
                _setPhase(LowerFault, NoWorkFb);
            }
        } else if (_liftSent.elapsed() > kEchoMs
                   && !(_vcu->workReq() == 1 && _vcu->workReqAgeMs() >= 0 && _vcu->workReqAgeMs() < _liftSent.elapsed())) {
            _setPhase(LowerFault, NoEcho);
        } else if (fbFresh && fb == kWfbFault && _liftSent.elapsed() > 1000) {
            _setPhase(LowerFault, LiftFault);
        } else if (_phaseTime.elapsed() > liftTimeoutMs) {
            _setPhase(LowerFault, LiftTimeout);
        }
        break;

    case Working:
        if (_starting) {
            break;
        }
        if (_endReached) {
            if (!workLink()) {
                _field->setLineStatus(_line, HHUABField::Done);
                (void) _field->save();
                _setPhase(Done);
            } else if (_inHold() || _endTime.elapsed() > kEndHoldMs) {
                _beginRaise(false);
            }
        } else if (workLink() && fbFresh && (fb == kWfbLifting || fb == kWfbFault)) {
            if (fb == kWfbLifting && _vcu->workReq() == 0) {
                // the route's own DO_AUX_FUNCTION low ran: the end point was reached
                _endReached = true;
                _endTime.restart();
            } else {
                // the vehicle holds by itself (vcu_can.lua: lift moving / lift fault while driving)
                _setPhase(WorkFault, fb == kWfbFault ? LiftFault : LiftMoving);
            }
        }
        break;

    case Raising:
    case Ending:
        if (fbFresh && fb == kWfbTransport && _liftSent.elapsed() > 1000) {
            if (_ending) {
                _setPhase(EndAsk);
            } else {
                _field->setLineStatus(_line, HHUABField::Done);
                (void) _field->save();
                _setPhase(Done);
            }
        } else if (_vcu->workFbAgeMs() < 0 || _vcu->workFbAgeMs() > kNoWorkFbMs) {
            if (_phaseTime.elapsed() > kNoWorkFbMs) {
                _setPhase(RaiseFault, NoWorkFb);
            }
        } else if (fbFresh && fb == kWfbFault && _liftSent.elapsed() > 1000) {
            _setPhase(RaiseFault, LiftFault);
        } else if (_phaseTime.elapsed() > liftTimeoutMs) {
            _setPhase(RaiseFault, LiftTimeout);
        }
        break;

    default:
        break;
    }
}

// ---- AB route left on the vehicle -----------------------------------------------------------------

void HHUABRun::_saveSignature(const QList<MissionItem *> &items)
{
    QJsonArray sig;
    for (const MissionItem *item : items) {
        if (item->sequenceNumber() == 0) {
            continue;   // home: the vehicle reports its own
        }
        sig.append(QJsonArray{ static_cast<int>(item->command()), item->param1(), item->param2(), item->param5(), item->param6() });
    }
    _signature = sig.toVariantList();
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    settings.setValue(kKeySignature, QJsonDocument(sig).toJson(QJsonDocument::Compact));
}

bool HHUABRun::_matchesSignature(const QList<MissionItem *> &items) const
{
    if (_signature.isEmpty()) {
        return false;
    }
    int i = 0;
    for (const MissionItem *item : items) {
        if (item->sequenceNumber() == 0) {
            continue;
        }
        if (i >= _signature.size()) {
            return false;
        }
        const QVariantList s = _signature[i++].toList();
        if (s.size() != 5 || s[0].toInt() != static_cast<int>(item->command())
                || std::fabs(s[1].toDouble() - item->param1()) > 1e-3 || std::fabs(s[2].toDouble() - item->param2()) > 1e-3
                || std::fabs(s[3].toDouble() - item->param5()) > 2e-7 || std::fabs(s[4].toDouble() - item->param6()) > 2e-7) {
            return false;
        }
    }
    return i == _signature.size();
}

void HHUABRun::_watch(Vehicle *vehicle)
{
    if (vehicle == _watched) {
        return;
    }
    if (_watched) {
        (void) disconnect(_watched->missionManager(), nullptr, this, nullptr);
    }
    _watched = vehicle;
    if (vehicle) {
        MissionManager *manager = vehicle->missionManager();
        // read at connection, written by anyone (手工航点 too), removed
        (void) connect(manager, &PlanManager::newMissionItemsAvailable, this, &HHUABRun::_checkVehicleRoute);
        (void) connect(manager, &PlanManager::sendComplete, this, &HHUABRun::_checkVehicleRoute);
        (void) connect(manager, &PlanManager::removeAllComplete, this, &HHUABRun::_checkVehicleRoute);
    }
    _checkVehicleRoute();
}

void HHUABRun::_checkVehicleRoute()
{
    Vehicle *v = _watched.data();
    const bool ab = v && !v->missionManager()->inProgress() && _matchesSignature(v->missionManager()->missionItems());
    if (ab != _abRoute) {
        _abRoute = ab;
        qCDebug(HHUABRunLog) << "AB route on the vehicle:" << ab;
        emit routeChanged();
    }
    // a left-over AB route (line ended, ground station restarted) while no line is driven
    if (ab && _phase == Idle && !_uploading) {
        _requestClear();
    }
}

void HHUABRun::_requestClear()
{
    if (!_clearTimer.isActive()) {
        _clearSince.restart();
        _clearTimer.start();
    }
}

void HHUABRun::_tryClear()
{
    Vehicle *v = _watched.data();
    // never while a line is driven (对准 / 放杆 / 作业 / 收杆): only when it has ended
    if (!v || (_phase != Idle && _phase != Done) || _uploading || _clearSince.elapsed() > kClearGiveUpMs) {
        _clearTimer.stop();
        return;
    }
    MissionManager *manager = v->missionManager();
    if (manager->inProgress()) {
        return;
    }
    if (!_matchesSignature(manager->missionItems())) {
        _clearTimer.stop();     // not (any more) the AB route: e.g. a 手工航点 route was uploaded
        return;
    }
    if (v->armed() && v->flightMode() != v->pauseFlightMode()) {
        return;                 // only in HOLD or disarmed
    }
    qCDebug(HHUABRunLog) << "removing the AB route from the vehicle";
    _clearTimer.stop();
    manager->removeAll();
}
