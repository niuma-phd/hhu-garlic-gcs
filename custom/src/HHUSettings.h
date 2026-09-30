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
    /// 低电量告警阈值 (%)
    Q_PROPERTY(int    lowBatteryPct     READ lowBatteryPct     WRITE setLowBatteryPct     NOTIFY changed)
    /// 航点数上限 used by the upload check
    Q_PROPERTY(int    maxWaypoints      READ maxWaypoints      WRITE setMaxWaypoints      NOTIFY changed)
    /// 字号: 0 标准, 1 大, 2 特大 (HHU status bar, work panel, dialogs)
    Q_PROPERTY(int    fontSize          READ fontSize          WRITE setFontSize          NOTIFY changed)
    Q_PROPERTY(double fontScale         READ fontScale                                    NOTIFY changed)
    /// 户外高对比度: opaque panels, black text, heavier borders
    Q_PROPERTY(bool   highContrast      READ highContrast      WRITE setHighContrast      NOTIFY changed)
    /// 地图注记: TianDiTu place names / roads over the base map
    Q_PROPERTY(bool   mapLabels         READ mapLabels         WRITE setMapLabels         NOTIFY changed)
    /// 面积单位: 0 亩, 1 公顷
    Q_PROPERTY(int    areaUnit          READ areaUnit          WRITE setAreaUnit          NOTIFY changed)
    /// Last TURN_RADIUS read from a vehicle, so the turn check also works while planning offline (NaN if never read)
    Q_PROPERTY(double lastTurnRadius    READ lastTurnRadius    WRITE setLastTurnRadius    NOTIFY changed)

public:
    explicit HHUSettings(QObject *parent = nullptr);

    int    commandTimeoutSec() const { return _commandTimeoutSec; }
    int    linkLostSec()       const { return _linkLostSec; }
    int    lowBatteryPct()     const { return _lowBatteryPct; }
    int    maxWaypoints()      const { return _maxWaypoints; }
    int    fontSize()          const { return _fontSize; }
    double fontScale()         const;
    bool   highContrast()      const { return _highContrast; }
    int    areaUnit()          const { return _areaUnit; }
    bool   mapLabels()         const { return _mapLabels; }
    double lastTurnRadius()    const { return _lastTurnRadius; }

    void setCommandTimeoutSec(int value);
    void setLinkLostSec(int value);
    void setLowBatteryPct(int value);
    void setMaxWaypoints(int value);
    void setFontSize(int value);
    void setHighContrast(bool value);
    void setAreaUnit(int value);
    void setMapLabels(bool value);
    void setLastTurnRadius(double value);

    /// Area in square meters formatted in the chosen unit, e.g. "3.25 亩"
    Q_INVOKABLE QString formatArea(double squareMeters) const;

signals:
    void changed();

private:
    void _save(const char *key, const QVariant &value);

    int    _commandTimeoutSec = 5;
    int    _linkLostSec       = 5;
    int    _lowBatteryPct     = 20;
    int    _maxWaypoints      = 700;
    int    _fontSize          = 0;
    bool   _highContrast      = false;
    int    _areaUnit          = 0;
    bool   _mapLabels         = true;
    double _lastTurnRadius    = qQNaN();
};
