#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantMap>

class Vehicle;

/// 断点续作 (需求说明 V1.0 §3.2).
/// A session runs from 开始作业 until the route is finished or the vehicle is disarmed. While it runs,
/// the waypoint the vehicle drives to is followed; the open session is saved so it survives a GCS
/// restart and is completed from the vehicle's data once the link is back. When it ends, the resume
/// point of the field is stored (or cleared when the route was finished). Exposed to QML as hhuWork.
class HHUWorkLog : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         active      READ active     NOTIFY activeChanged)
    /// { start, end } (ISO date-times) of the last finished work run, empty when there was none
    Q_PROPERTY(QVariantMap  lastRun     READ lastRun    NOTIFY lastRunChanged)
    /// The last run reached the end of the route (cleared by the next 开始作业 or another vehicle)
    Q_PROPERTY(bool         completed   READ completed  NOTIFY completedChanged)

public:
    explicit HHUWorkLog(QObject *parent = nullptr);

    bool active() const { return !_session.isEmpty(); }
    QVariantMap lastRun() const;
    bool completed() const { return _completed; }

    /// Stable id of a vehicle: flight controller UID, or the MAVLink system id when unknown
    Q_INVOKABLE static QString vehicleKey(Vehicle *vehicle);

    /// Starts a session. info: fieldId, startSeq, lastSeq
    Q_INVOKABLE void start(Vehicle *vehicle, const QVariantMap &info);
    /// MISSION_ITEM_REACHED from the vehicle (Rover holds in AUTO at the end of the route, so this is
    /// how the end of the route is recognised)
    void itemReached(Vehicle *vehicle, int seq);

    /// 断点续作: waypoint the vehicle was driving to when work on this field last stopped (0 = none)
    Q_INVOKABLE int resumeWaypoint(Vehicle *vehicle, const QString &fieldId) const;
    /// Field last uploaded to this vehicle ("" = unknown)
    Q_INVOKABLE QString vehicleField(Vehicle *vehicle) const;
    Q_INVOKABLE void setVehicleField(Vehicle *vehicle, const QString &fieldId);


signals:
    void activeChanged();
    void lastRunChanged();
    void completedChanged();

private:
    void _attach(Vehicle *vehicle);
    void _onMissionIndex();
    void _onFlightMode();
    void _onArmed();
    void _finish(bool routeCompleted);
    void _saveSession();
    QString _resumeKey(const QString &vehicleKey, const QString &fieldId) const;

    QVariantMap         _session;   ///< open session (empty = none)
    QPointer<Vehicle>   _vehicle;
    bool                _wasAuto = false;
    bool                _completed = false;
    QTimer              _saveTimer;
};
