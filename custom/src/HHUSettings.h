#pragma once

#include <QtCore/QObject>

/// Customer settings of the HHU build that QGC has no setting for (需求说明 V1.0 §3.4).
/// Stored in the QGC settings file under group "HHU"; exposed to QML as hhuSettings.
class HHUSettings : public QObject
{
    Q_OBJECT
    /// 指令超时: seconds to wait for the vehicle to carry out a work command
    Q_PROPERTY(int    commandTimeoutSec READ commandTimeoutSec WRITE setCommandTimeoutSec NOTIFY changed)
    /// 连接中断判定时间: seconds without vehicle data before the link counts as lost
    Q_PROPERTY(int    linkLostSec       READ linkLostSec       WRITE setLinkLostSec       NOTIFY changed)
    /// 航点数上限 used by the upload check
    Q_PROPERTY(int    maxWaypoints      READ maxWaypoints      WRITE setMaxWaypoints      NOTIFY changed)
    /// 字号: 0 标准, 1 大, 2 特大 (HHU status bar, work panel, dialogs)
    Q_PROPERTY(int    fontSize          READ fontSize          WRITE setFontSize          NOTIFY changed)
    Q_PROPERTY(double fontScale         READ fontScale                                    NOTIFY changed)
    /// 户外高对比度: opaque panels, black text, heavier borders
    Q_PROPERTY(bool   highContrast      READ highContrast      WRITE setHighContrast      NOTIFY changed)
    /// 地图注记: TianDiTu place names / roads over the base map
    Q_PROPERTY(bool   mapLabels         READ mapLabels         WRITE setMapLabels         NOTIFY changed)
    /// Last TURN_RADIUS read from a vehicle, so the turn check also works while planning offline (NaN if never read)
    Q_PROPERTY(double lastTurnRadius    READ lastTurnRadius    WRITE setLastTurnRadius    NOTIFY changed)
    /// Highest route speed of the connected vehicle: the lower of WP_SPEED / VCU_V_MAX (0 = not known)
    Q_PROPERTY(double vehicleMaxSpeed   READ vehicleMaxSpeed                              NOTIFY changed)

public:
    explicit HHUSettings(QObject *parent = nullptr);

    int    commandTimeoutSec() const { return _commandTimeoutSec; }
    int    linkLostSec()       const { return _linkLostSec; }
    int    maxWaypoints()      const { return _maxWaypoints; }
    int    fontSize()          const { return _fontSize; }
    double fontScale()         const;
    bool   highContrast()      const { return _highContrast; }
    bool   mapLabels()         const { return _mapLabels; }
    double lastTurnRadius()    const { return _lastTurnRadius; }
    double vehicleMaxSpeed()   const { return _vehicleMaxSpeed; }

    void setCommandTimeoutSec(int value);
    void setLinkLostSec(int value);
    void setMaxWaypoints(int value);
    void setFontSize(int value);
    void setHighContrast(bool value);
    void setMapLabels(bool value);
    void setLastTurnRadius(double value);
    void setVehicleMaxSpeed(double value);

signals:
    void changed();

private:
    void _save(const char *key, const QVariant &value);

    int    _commandTimeoutSec = 5;
    int    _linkLostSec       = 5;
    int    _maxWaypoints      = 700;
    int    _fontSize          = 0;
    bool   _highContrast      = false;
    bool   _mapLabels         = true;
    double _lastTurnRadius    = qQNaN();
    double _vehicleMaxSpeed   = 0;    ///< not saved: belongs to the vehicle connected now
};
