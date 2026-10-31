#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>

#include "HHUABGeometry.h"

class HHUABField;
class HHUConfig;
class HHUVcuStatus;
class HHUWorkLog;
class MissionItem;
class Vehicle;

/// One AB line on the vehicle (作业页), driven by the ground station in four parts:
///   1 对准  lift up: route [speed abSpeedTransport, lead point = start − (d + Lc), alignment point = start − d]
///           in AUTO, then HOLD
///           and check the cross-track / heading error (out of limits: ask 仍然开始 / 结束本条)
///   2 放杆  DO_AUX_FUNCTION(300 SCRIPTING1, 2 high) → wait for WorkFb 3
///   3 作业  route [speed abSpeedWork, start, end, NAV_DELAY 1 s, DO_AUX_FUNCTION(300, low)] in AUTO. The DO command runs
///           when the NAV item before it starts, so the delay keeps the raise at the end; it is also the
///           fallback when the 4G link is lost
///   4 收杆  HOLD, DO_AUX_FUNCTION(300, low) again → wait for WorkFb 0 → line done, field saved
/// abWorkLink = false skips 2 and 4 (no DO_AUX in the route).
/// The routes uploaded for a line are remembered (settings, kept over a restart). When the line has ended
/// (完成, 结束本条, a fault ended) or a vehicle that still carries such a route is connected while no line
/// is driven, the route is removed from the vehicle (only in HOLD or disarmed): the 作业 page must not
/// offer it as a normal route (继续作业 would run it outside of the four parts). WorkFb / the request echo come from
/// HHUVcuStatus (VCU_WORKFB / VCU_WREQ of vcu_can.lua garlic.15). Exposed to QML as hhuABRun.
class HHUABRun : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int    phase      READ phase      NOTIFY changed)
    Q_PROPERTY(bool   active     READ active     NOTIFY changed)
    Q_PROPERTY(int    line       READ line       NOTIFY changed)    ///< 0-based line being driven, -1 = none
    Q_PROPERTY(int    fault      READ fault      NOTIFY changed)    ///< Fault, while phase is a fault phase
    /// the vehicle has not yet been put into AUTO for this part (no 暂停 / 继续 yet)
    Q_PROPERTY(bool   starting   READ starting   NOTIFY changed)
    Q_PROPERTY(bool   workLink   READ workLink   CONSTANT)
    /// cross-track error from the current line (m, + = left of the driving direction), NaN when unknown
    Q_PROPERTY(double xtrack     READ xtrack     NOTIFY trackChanged)
    /// heading error from the current line (deg), NaN when unknown
    Q_PROPERTY(double headingErr READ headingErr NOTIFY trackChanged)
    /// errors measured at the alignment point (shown in the 对准不合格 dialog)
    Q_PROPERTY(double alignXtrack     READ alignXtrack     NOTIFY changed)
    Q_PROPERTY(double alignHeadingErr READ alignHeadingErr NOTIFY changed)
    /// the route on the vehicle is one of the AB routes uploaded here (not offered as 车上航线 / 继续作业)
    Q_PROPERTY(bool   abRouteOnVehicle READ abRouteOnVehicle NOTIFY routeChanged)

public:
    enum Phase {
        Idle = 0,
        Aligning,       ///< 1 对准: driving to the alignment point
        AlignFailed,    ///< 1 对准不合格: 仍然开始 / 结束本条
        Lowering,       ///< 2 放杆
        LowerFault,     ///< 2 放杆故障: 重试放杆 / 结束本条 (fault says why)
        Working,        ///< 3 作业
        WorkFault,      ///< 3 作业中 WorkFb 1 / 4 (the vehicle holds): 重试放杆 / 结束本条
        Raising,        ///< 4 收杆
        RaiseFault,     ///< 4 收杆超时 / 故障: 重试收杆 / 结束 (line stays 未走)
        Done,           ///< 完成面板: 下一条 / 重走本条 / 选其他条 / 结束
        Ending,         ///< 结束本条: HOLD, raising
        EndAsk,         ///< 结束本条: 本条标为完成？
    };
    Q_ENUM(Phase)

    enum Fault {
        NoFault = 0,
        LiftTimeout,    ///< WorkFb did not reach 3 (0) in abLiftTimeout
        LiftFault,      ///< WorkFb 4
        LiftMoving,     ///< WorkFb 1 while working
        NoWorkFb,       ///< no VCU_WORKFB for 3 s: 车端未上报作业杆状态
        NoEcho,         ///< the request echo VCU_WREQ did not go high within 2 s: script older than garlic.15
        UploadFailed,   ///< route upload failed
        ModeFailed,     ///< the vehicle did not go to AUTO
    };
    Q_ENUM(Fault)

    /// Why start() refused
    enum StartError {
        StartOk = 0,
        NoVehicle,
        NoLines,
        WorkEnOff,      ///< VCU_WORK_EN = 0 (or missing) with abWorkLink
        Busy,           ///< a run or an upload is going on
    };
    Q_ENUM(StartError)

    HHUABRun(HHUConfig *config, HHUABField *field, HHUVcuStatus *vcu, HHUWorkLog *workLog, QObject *parent = nullptr);

    int    phase() const { return _phase; }
    bool   active() const { return _phase != Idle; }
    int    line() const { return _line; }
    int    fault() const { return _fault; }
    bool   starting() const { return _starting; }
    bool   workLink() const;
    double xtrack() const { return _xtrack; }
    double headingErr() const { return _headingErr; }
    double alignXtrack() const { return _alignXtrack; }
    double alignHeadingErr() const { return _alignHeadingErr; }
    bool   abRouteOnVehicle() const { return _abRoute; }

    /// VCU_WORK_EN check of 开始AB作业 (only with abWorkLink): StartOk or WorkEnOff
    Q_INVOKABLE int checkWorkEnable() const;
    /// Starts line `index` (0-based) from part 1; returns a StartError
    Q_INVOKABLE int start(int index);
    /// 对准不合格 → 仍然开始 (after the second confirmation)
    Q_INVOKABLE void startAnyway();
    /// 重试放杆 (LowerFault / WorkFault)
    Q_INVOKABLE void retryLower();
    /// 重试收杆 (RaiseFault)
    Q_INVOKABLE void retryRaise();
    /// 结束本条: HOLD → raise → ask
    Q_INVOKABLE void endLine();
    /// answer of 本条标为完成？
    Q_INVOKABLE void confirmEnd(bool done);
    /// 暂停 / 继续 while aligning or working (the lift stays as it is)
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    /// 结束 (完成面板) / close a fault without raising: back to idle
    Q_INVOKABLE void finish();

    /// MISSION_ITEM_REACHED from the vehicle (CustomPlugin)
    void itemReached(Vehicle *vehicle, int seq);

signals:
    void changed();
    void trackChanged();
    void routeChanged();

private:
    void _setPhase(Phase phase, Fault fault = NoFault);
    Vehicle *_vehicle() const;
    void _upload(const QList<MissionItem *> &items);
    void _onSendComplete(bool error);
    void _startAuto();
    void _sendLift(bool down);
    void _beginLower();
    void _beginWork(bool resumeOnly);
    void _beginRaise(bool ending);
    void _tick();
    void _updateTrack();
    void _onArmed(bool armed);
    void _onVehicleChanged(Vehicle *vehicle);
    void _hold();
    bool _inAuto() const;
    bool _inHold() const;
    MissionItem *_speedItem(int seq, double speed);
    QList<MissionItem *> _alignMission();
    QList<MissionItem *> _workMission();
    void _saveSignature(const QList<MissionItem *> &items);
    bool _matchesSignature(const QList<MissionItem *> &items) const;
    void _watch(Vehicle *vehicle);
    void _checkVehicleRoute();
    void _requestClear();
    void _tryClear();

    HHUConfig    *_config = nullptr;
    HHUABField   *_field = nullptr;
    HHUVcuStatus *_vcu = nullptr;
    HHUWorkLog   *_workLog = nullptr;
    QPointer<Vehicle> _vehicleRef;

    Phase  _phase = Idle;
    Fault  _fault = NoFault;
    int    _line = -1;
    bool   _starting = false;
    bool   _uploading = false;
    bool   _resumeWork = false;     ///< after 重试放杆 in WorkFault: continue the work route, no new upload
    bool   _ending = false;         ///< raising for 结束本条 (→ EndAsk) instead of the end of the line
    int    _lastSeq = 0;            ///< sequence of the last NAV item of the route on the vehicle
    bool   _endReached = false;     ///< 作业: the end point was reached
    hhuab::EN _target;              ///< last point of the route on the vehicle (alignment point / end point)
    double _xtrack = qQNaN();
    double _headingErr = qQNaN();
    double _alignXtrack = qQNaN();
    double _alignHeadingErr = qQNaN();

    QTimer        _tickTimer;
    QElapsedTimer _phaseTime;       ///< since the current wait started
    QElapsedTimer _liftSent;        ///< since the last DO_AUX_FUNCTION
    QElapsedTimer _endTime;         ///< since the end point / the alignment point was reached
    QElapsedTimer _autoTime;        ///< since AUTO was requested
    QElapsedTimer _stillTime;       ///< standing at the last point (arrival when MISSION_ITEM_REACHED was missed)

    QVariantList  _signature;       ///< last AB route uploaded: [cmd, p1, p2, lat, lon] per item after home
    bool          _abRoute = false;
    QPointer<Vehicle> _watched;     ///< vehicle whose route is compared with _signature
    QTimer        _clearTimer;      ///< waits until the AB route can be removed (HOLD / disarmed, no transfer)
    QElapsedTimer _clearSince;
};
