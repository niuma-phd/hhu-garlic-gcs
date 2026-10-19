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

    void handleMessage(const mavlink_message_t &message);
    /// Forget the previous vehicle's chassis (no "chassis link lost" alarm for a vehicle without VCU)
    Q_INVOKABLE void reset();

signals:
    void changed();
    void batteryChanged();

private:
    void _checkTimeout();
    void _clearBattery();

    bool   _valid = false;
    bool   _seen  = false;
    bool   _ok    = false;
    int    _mode  = 0;
    int    _fault = 0;

    bool   _batteryValid = false;
    double _soc  = qQNaN();
    double _batV = qQNaN();

    QElapsedTimer _lastRx;
    QElapsedTimer _lastSocRx;
    QTimer        _timeoutTimer;
};
