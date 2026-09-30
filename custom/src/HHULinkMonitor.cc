#include "HHULinkMonitor.h"
#include "HHUSettings.h"
#include "LinkConfiguration.h"
#include "LinkInterface.h"
#include "MAVLinkProtocol.h"
#include "MultiVehicleManager.h"
#include "Vehicle.h"

#include <QtCore/QSettings>

namespace {
constexpr int kTimesyncIntervalMs = 5000;
constexpr const char *kTotalsGroup = "HHU/traffic";
}

HHULinkMonitor::HHULinkMonitor(HHUSettings *settings, QObject *parent)
    : QObject(parent)
    , _settings(settings)
{
    QSettings s;
    s.beginGroup(kTotalsGroup);
    _totalUp = s.value("up", 0.0).toDouble();
    _totalDown = s.value("down", 0.0).toDouble();

    _clock.start();
    _timer.setInterval(500);
    (void) connect(&_timer, &QTimer::timeout, this, &HHULinkMonitor::_update);
    _timesyncTimer.setInterval(kTimesyncIntervalMs);
    (void) connect(&_timesyncTimer, &QTimer::timeout, this, &HHULinkMonitor::_sendTimesync);
}

HHULinkMonitor::~HHULinkMonitor()
{
    _saveTotals();
}

void HHULinkMonitor::messageReceived(Vehicle *vehicle, LinkInterface *link, const mavlink_message_t &message)
{
    if (vehicle != MultiVehicleManager::instance()->activeVehicle()) {
        return;
    }
    if (vehicle != _vehicle) {
        _activeVehicleChanged(vehicle);
    }
    if (link != _link) {
        _setLink(link);
    }
    _lastRx.restart();

    if (message.msgid == MAVLINK_MSG_ID_TIMESYNC) {
        mavlink_timesync_t ts{};
        mavlink_msg_timesync_decode(&message, &ts);
        // Our request echoed back: tc1 filled in by the vehicle, ts1 is the time we sent
        if (ts.tc1 != 0 && _timesyncSent != 0 && ts.ts1 == _timesyncSent) {
            _latencyMs = static_cast<int>((_clock.nsecsElapsed() - ts.ts1) / 1000000);
            _timesyncSent = 0;
            emit statsChanged();
        }
    }

    if (_silentSec != 0 || _linkLost) {
        _update();
    }
}

void HHULinkMonitor::_activeVehicleChanged(Vehicle *vehicle)
{
    _vehicle = vehicle;
    _setLink(nullptr);
    _lastOutageSec = 0;
    _latencyMs = -1;
    _sessionUp = 0;
    _sessionDown = 0;
    emit statsChanged();
    if (_linkLost) {
        _linkLost = false;
        emit linkLostChanged();
    }
    if (_silentSec != 0) {
        _silentSec = 0;
        emit silentSecChanged();
    }
    if (vehicle) {
        // A removed vehicle ends monitoring; the next vehicle starts it again
        (void) connect(vehicle, &QObject::destroyed, this, [this]() {
            _timer.stop();
            _timesyncTimer.stop();
            _saveTotals();
            _activeVehicleChanged(nullptr);
        });
        _timer.start();
        _timesyncTimer.start();
    }
}

void HHULinkMonitor::_setLink(LinkInterface *link)
{
    if (_link) {
        (void) disconnect(_link, nullptr, this, nullptr);
    }
    _link = link;

    QString type;
    if (link && link->linkConfiguration()) {
        const auto config = link->linkConfiguration();
        switch (config->type()) {
#ifndef QGC_NO_SERIAL_LINK
        case LinkConfiguration::TypeSerial:     type = QStringLiteral("serial");    break;
#endif
        case LinkConfiguration::TypeUdp:        type = QStringLiteral("udp");       break;
        // The 4G connection is a TCP link to the local HHU4GLink bridge
        case LinkConfiguration::TypeTcp:        type = config->name().startsWith(QStringLiteral("4G")) ? QStringLiteral("4g") : QStringLiteral("tcp"); break;
        case LinkConfiguration::TypeBluetooth:  type = QStringLiteral("bluetooth"); break;
        default:                                break;
        }
        (void) connect(link, &LinkInterface::bytesReceived, this, [this](LinkInterface *, const QByteArray &data) {
            _sessionDown += data.size();
            _totalDown += data.size();
        });
        (void) connect(link, &LinkInterface::bytesSent, this, [this](LinkInterface *, const QByteArray &data) {
            _sessionUp += data.size();
            _totalUp += data.size();
        });
    }
    if (type != _linkType) {
        _linkType = type;
        emit linkTypeChanged();
    }
}

void HHULinkMonitor::_sendTimesync()
{
    if (!_vehicle || !_link || _linkLost) {
        return;
    }
    mavlink_message_t msg;
    _timesyncSent = _clock.nsecsElapsed();
    (void) mavlink_msg_timesync_pack_chan(static_cast<uint8_t>(MAVLinkProtocol::instance()->getSystemId()),
                                          static_cast<uint8_t>(MAVLinkProtocol::getComponentId()),
                                          _link->mavlinkChannel(), &msg,
                                          0, _timesyncSent,
                                          static_cast<uint8_t>(_vehicle->id()), static_cast<uint8_t>(_vehicle->defaultComponentId()));
    (void) _vehicle->sendMessageOnLinkThreadSafe(_link, msg);
}

void HHULinkMonitor::_update()
{
    // Traffic counters change continuously; refresh the display once a second
    if (++_statsTick % 2 == 0) {
        emit statsChanged();
        if (_statsTick % 120 == 0) {
            _saveTotals();
        }
    }

    if (!_vehicle || !_lastRx.isValid()) {
        return;
    }
    const int silent = static_cast<int>(_lastRx.elapsed() / 1000);
    if (silent != _silentSec) {
        _silentSec = silent;
        emit silentSecChanged();
    }

    const bool lost = !_suppressLoss && _lastRx.elapsed() > _settings->linkLostSec() * 1000;
    if (lost != _linkLost) {
        if (!lost) {
            // Outage length = time from the last message before the loss until now
            _lastOutageSec = _outageStart.isValid() ? static_cast<int>(_outageStart.elapsed() / 1000) : 0;
        } else {
            _outageStart = _lastRx;
            _latencyMs = -1;
        }
        _linkLost = lost;
        emit linkLostChanged();
    }
}

void HHULinkMonitor::setSuppressLoss(bool suppress)
{
    if (suppress != _suppressLoss) {
        _suppressLoss = suppress;
        if (!suppress) {
            _lastRx.restart();  // the re-login gap is not an outage
        }
        _update();
        emit linkLostChanged();
    }
}

void HHULinkMonitor::resetTraffic()
{
    _sessionUp = _sessionDown = _totalUp = _totalDown = 0;
    _saveTotals();
    emit statsChanged();
}

void HHULinkMonitor::_saveTotals()
{
    QSettings s;
    s.beginGroup(kTotalsGroup);
    s.setValue("up", _totalUp);
    s.setValue("down", _totalDown);
}

QString HHULinkMonitor::formatBytes(double bytes)
{
    if (bytes >= 1024.0 * 1024.0 * 1024.0) return QStringLiteral("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
    if (bytes >= 1024.0 * 1024.0)          return QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    if (bytes >= 1024.0)                   return QStringLiteral("%1 KB").arg(bytes / 1024.0, 0, 'f', 0);
    return QStringLiteral("%1 B").arg(bytes, 0, 'f', 0);
}
