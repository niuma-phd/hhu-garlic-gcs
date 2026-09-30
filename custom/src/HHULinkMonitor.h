#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>

#include "MAVLinkLib.h"

class HHUSettings;
class LinkInterface;
class Vehicle;

/// Link state of the active vehicle (需求说明 V1.0 §3.1, §3.6, §4.3):
/// - lost-link detection with the customer's own time (hhuSettings.linkLostSec), counting any message;
/// - latency by MAVLink TIMESYNC round trip every 5 s;
/// - traffic up/down for this connection and in total (kept across restarts, can be reset).
/// Exposed to QML as hhuLink.
class HHULinkMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool    linkLost         READ linkLost       NOTIFY linkLostChanged)
    /// Seconds since the last message from the vehicle (whole seconds, updated twice a second)
    Q_PROPERTY(int     silentSec        READ silentSec      NOTIFY silentSecChanged)
    /// Length of the last completed outage in seconds (for the "连接已恢复" notice)
    Q_PROPERTY(int     lastOutageSec    READ lastOutageSec  NOTIFY linkLostChanged)
    /// "serial", "udp", "tcp", "bluetooth", "4g" or "" (no vehicle)
    Q_PROPERTY(QString linkType         READ linkType       NOTIFY linkTypeChanged)
    /// Round trip time in ms, -1 when unknown
    Q_PROPERTY(int     latencyMs        READ latencyMs      NOTIFY statsChanged)
    Q_PROPERTY(double  sessionUpBytes   READ sessionUpBytes     NOTIFY statsChanged)
    Q_PROPERTY(double  sessionDownBytes READ sessionDownBytes   NOTIFY statsChanged)
    Q_PROPERTY(double  totalUpBytes     READ totalUpBytes       NOTIFY statsChanged)
    Q_PROPERTY(double  totalDownBytes   READ totalDownBytes     NOTIFY statsChanged)
    /// While true (4G re-login to update the RTK account) a silent link is not reported as lost
    Q_PROPERTY(bool    suppressLoss     READ suppressLoss   WRITE setSuppressLoss NOTIFY linkLostChanged)

public:
    HHULinkMonitor(HHUSettings *settings, QObject *parent = nullptr);
    ~HHULinkMonitor() override;

    bool    linkLost()          const { return _linkLost; }
    int     silentSec()         const { return _silentSec; }
    int     lastOutageSec()     const { return _lastOutageSec; }
    QString linkType()          const { return _linkType; }
    int     latencyMs()         const { return _latencyMs; }
    double  sessionUpBytes()    const { return _sessionUp; }
    double  sessionDownBytes()  const { return _sessionDown; }
    double  totalUpBytes()      const { return _totalUp; }
    double  totalDownBytes()    const { return _totalDown; }
    bool    suppressLoss()      const { return _suppressLoss; }
    void    setSuppressLoss(bool suppress);

    /// Called for every MAVLink message of a vehicle
    void messageReceived(Vehicle *vehicle, LinkInterface *link, const mavlink_message_t &message);

    Q_INVOKABLE void resetTraffic();
    /// "12.3 MB" style text
    Q_INVOKABLE static QString formatBytes(double bytes);

signals:
    void linkLostChanged();
    void silentSecChanged();
    void linkTypeChanged();
    void statsChanged();

private:
    void _activeVehicleChanged(Vehicle *vehicle);
    void _update();
    void _setLink(LinkInterface *link);
    void _sendTimesync();
    void _saveTotals();

    HHUSettings            *_settings = nullptr;
    QPointer<Vehicle>       _vehicle;
    QPointer<LinkInterface> _link;
    QElapsedTimer           _lastRx;
    QElapsedTimer           _outageStart;   ///< copy of _lastRx taken when the link was declared lost
    QElapsedTimer           _clock;         ///< time base of the TIMESYNC requests
    QTimer                  _timer;
    QTimer                  _timesyncTimer;
    bool                    _linkLost = false;
    bool                    _suppressLoss = false;
    int                     _silentSec = 0;
    int                     _lastOutageSec = 0;
    int                     _latencyMs = -1;
    qint64                  _timesyncSent = 0;
    QString                 _linkType;
    double                  _sessionUp = 0;
    double                  _sessionDown = 0;
    double                  _totalUp = 0;
    double                  _totalDown = 0;
    int                     _statsTick = 0;
};
