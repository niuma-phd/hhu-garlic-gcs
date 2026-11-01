#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QTimer>

#include "MAVLinkLib.h"

/// Chassis (VCU) state reported by the vehicle's vcu_can.lua via NAMED_VALUE_FLOAT
/// (需求说明 §5.3), 5 values:
///   VCU_OK, VCU_MODE, VCU_FAULT  always sent at 5 Hz → valid / seen / ok / mode / fault
///   VCU_SOC, VCU_BATV            电量两项可能不发: vcu_can.lua (garlic.12) sends them only while it
///                                receives VCU_HealthSta (0x1806407D), which is not part of Nav ↔ VCU
///                                v1.0. They have their own freshness (batteryValid) and do not keep
///                                `valid` alive. VCU_BATV is 0 when the voltage is out of range.
///   VCU_WORKFB, VCU_WREQ         作业杆 (protocol v1.1, garlic.15): WorkFb on change + 1 Hz while NavSta is
///                                valid; the work request (SCRIPTING1) on change + 1 Hz while VCU_WORK_EN=1.
///                                Own freshness (workFbValid / workReqValid). The status bar and the AB line
///                                run (HHUABField) both read WorkFb from here.
///   VCU_SYSFLT, VCU_DRVFLT,      协议外 HealthSta (garlic.16/17, issue #10): Sys_Fault 0~7, the first non-zero
///   VCU_DRVCH                    drive fault code and its channel 1~3. Report only (VCU_FB_CHK=0): shown as a
///                                yellow hint, never a drive blocker. Own freshness (healthValid).
/// Also the RC start handshake from vcu_can.lua's STATUSTEXT ("VCU: wait RC start" / "VCU: RC start OK"),
/// and the vehicle parameters the ground station's own drive checks follow (VCU_RTK_REQ, VCU_ENABLE), so
/// that a check switched off on the vehicle is not kept up here.
class HHUVcuStatus : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool   valid READ valid NOTIFY changed)   ///< a VCU_* value arrived within the last 3 s
    Q_PROPERTY(bool   seen  READ seen  NOTIFY changed)   ///< VCU data arrived at least once from the current vehicle
    Q_PROPERTY(bool   ok    READ ok    NOTIFY changed)
    Q_PROPERTY(int    mode  READ mode  NOTIFY changed)   ///< 0 未知（NavSta 无效）, 1 遥控 / 切换中, 2 无人
    Q_PROPERTY(int    fault READ fault NOTIFY changed)
    /// VCU_SOC in 0…100 arrived within the last 3 s; the battery item and alarm show only then
    Q_PROPERTY(bool   batteryValid READ batteryValid NOTIFY batteryChanged)
    /// batteryValid and 0 < batV ≤ 100 (otherwise the voltage is shown as "—")
    Q_PROPERTY(bool   batVValid    READ batVValid    NOTIFY batteryChanged)
    Q_PROPERTY(double soc          READ soc          NOTIFY batteryChanged)   ///< percent, NaN when not batteryValid
    Q_PROPERTY(double batV         READ batV         NOTIFY batteryChanged)   ///< volts, NaN until received
    /// VCU_WORKFB arrived within the last 3 s
    Q_PROPERTY(bool   workFbValid  READ workFbValid  NOTIFY workChanged)
    /// 0 运输就绪, 1 升降杆中, 2 作业位就绪, 3 作业中, 4 升降超时故障; -1 until received
    Q_PROPERTY(int    workFb       READ workFb       NOTIFY workChanged)
    /// VCU_WREQ (work request echo) arrived within the last 3 s
    Q_PROPERTY(bool   workReqValid READ workReqValid NOTIFY workChanged)
    /// 1 = the vehicle sees the work request high; -1 until received
    Q_PROPERTY(int    workReq      READ workReq      NOTIFY workChanged)
    /// 0 unknown (no handshake message seen since connecting), 1 waiting for Ready on the remote control
    /// (wait RC start / handover failed / RC link lost), 2 RC start OK. Back to 0 when VCU_MODE leaves 2.
    Q_PROPERTY(int    rcStart      READ rcStart      NOTIFY changed)
    /// VCU_SYSFLT / VCU_DRVFLT arrived within the last 3 s
    Q_PROPERTY(bool   healthValid  READ healthValid  NOTIFY healthChanged)
    Q_PROPERTY(int    sysFault     READ sysFault     NOTIFY healthChanged)   ///< Sys_Fault 0~7 (faultCodes 0x01~0x07)
    Q_PROPERTY(int    drvFault     READ drvFault     NOTIFY healthChanged)   ///< drive fault code, 0 none
    Q_PROPERTY(int    drvChannel   READ drvChannel   NOTIFY healthChanged)   ///< 1~3, 0 none
    /// VCU_RTK_REQ of the vehicle: 0 no check, 1 float or fixed, 2 fixed only; -1 unknown (parameter
    /// missing or not loaded: the ground station then asks for RTK fixed as before)
    Q_PROPERTY(int    rtkReq       READ rtkReq       NOTIFY paramsChanged)
    /// false when the vehicle has VCU_ENABLE = 0 (CAN bridge off, bench test): no chassis checks then
    Q_PROPERTY(bool   bridgeEnabled READ bridgeEnabled NOTIFY paramsChanged)

public:
    explicit HHUVcuStatus(QObject *parent = nullptr);

    bool   valid() const { return _valid; }
    bool   seen()  const { return _seen; }
    bool   ok()    const { return _ok; }
    int    mode()  const { return _mode; }
    int    fault() const { return _fault; }
    bool   batteryValid() const { return _batteryValid; }
    bool   batVValid()    const { return _batteryValid && _batV > 0 && _batV <= 100; }
    double soc()          const { return _soc; }
    double batV()         const { return _batV; }
    bool   workFbValid()  const { return _workFbValid; }
    int    workFb()       const { return _workFb; }
    bool   workReqValid() const { return _workReqValid; }
    int    workReq()      const { return _workReq; }
    int    rcStart()      const { return _rcStart; }
    bool   healthValid()  const { return _healthValid; }
    int    sysFault()     const { return _healthValid ? _sysFault : 0; }
    int    drvFault()     const { return _healthValid ? _drvFault : 0; }
    int    drvChannel()   const { return _healthValid ? _drvChannel : 0; }
    int    rtkReq()       const { return _rtkReq; }
    bool   bridgeEnabled() const { return _bridgeEnabled; }
    /// ms since the last VCU_WORKFB / VCU_WREQ (-1 = never)
    qint64 workFbAgeMs()  const { return _lastWorkFbRx.isValid() ? _lastWorkFbRx.elapsed() : -1; }
    qint64 workReqAgeMs() const { return _lastWorkReqRx.isValid() ? _lastWorkReqRx.elapsed() : -1; }

    void handleMessage(const mavlink_message_t &message);
    /// Forget the previous vehicle's chassis (no "chassis link lost" alarm for a vehicle without VCU)
    Q_INVOKABLE void reset();

signals:
    void changed();
    void batteryChanged();
    void workChanged();
    void paramsChanged();
    void healthChanged();

private:
    void _checkTimeout();
    void _clearBattery();
    void _clearWork();
    void _handleStatusText(const mavlink_message_t &message);
    void _readParams();

    bool   _valid = false;
    bool   _seen  = false;
    bool   _ok    = false;
    int    _mode  = 0;
    int    _fault = 0;

    bool   _batteryValid = false;
    double _soc  = qQNaN();
    double _batV = qQNaN();

    bool   _workFbValid  = false;
    int    _workFb       = -1;
    bool   _workReqValid = false;
    int    _workReq      = -1;

    int    _rcStart      = 0;
    bool   _healthValid  = false;
    int    _sysFault     = 0;
    int    _drvFault     = 0;
    int    _drvChannel   = 0;
    QElapsedTimer _lastHealthRx;
    int    _rtkReq       = -1;
    bool   _bridgeEnabled = true;

    QElapsedTimer _lastRx;
    QElapsedTimer _lastSocRx;
    QElapsedTimer _lastWorkFbRx;
    QElapsedTimer _lastWorkReqRx;
    QTimer        _timeoutTimer;
};
