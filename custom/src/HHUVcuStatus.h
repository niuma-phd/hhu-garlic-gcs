#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QTimer>

#include "MAVLinkLib.h"

/// Chassis (VCU) state reported by the vehicle's vcu_can.lua via NAMED_VALUE_FLOAT
/// (需求说明 §5.3): the 3 values VCU_OK, VCU_MODE, VCU_FAULT.
class HHUVcuStatus : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool   valid READ valid NOTIFY changed)   ///< a VCU_* value arrived within the last 3 s
    Q_PROPERTY(bool   seen  READ seen  NOTIFY changed)   ///< VCU data arrived at least once from the current vehicle
    Q_PROPERTY(bool   ok    READ ok    NOTIFY changed)
    Q_PROPERTY(int    mode  READ mode  NOTIFY changed)   ///< 0 未知（NavSta 无效）, 1 遥控 / 切换中, 2 无人
    Q_PROPERTY(int    fault READ fault NOTIFY changed)

public:
    explicit HHUVcuStatus(QObject *parent = nullptr);

    bool   valid() const { return _valid; }
    bool   seen()  const { return _seen; }
    bool   ok()    const { return _ok; }
    int    mode()  const { return _mode; }
    int    fault() const { return _fault; }

    void handleMessage(const mavlink_message_t &message);
    /// Forget the previous vehicle's chassis (no "chassis link lost" alarm for a vehicle without VCU)
    Q_INVOKABLE void reset();

signals:
    void changed();

private:
    void _checkTimeout();

    bool   _valid = false;
    bool   _seen  = false;
    bool   _ok    = false;
    int    _mode  = 0;
    int    _fault = 0;

    QElapsedTimer _lastRx;
    QTimer        _timeoutTimer;
};
