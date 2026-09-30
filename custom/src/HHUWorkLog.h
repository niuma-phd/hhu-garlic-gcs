#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtPositioning/QGeoCoordinate>

class Vehicle;

/// 作业记录 and 断点续作 (需求说明 V1.0 §3.2, §3.7).
/// A session runs from 开始作业 until the route is finished or the vehicle is disarmed. While it runs,
/// the waypoint reached, odometer and interruptions (pauses, link losses) are followed on the vehicle;
/// the open session is saved so it survives a GCS restart and is completed from the vehicle's data
/// once the link is back. Records: <AppData>/work_records.json. Exposed to QML as hhuWork.
class HHUWorkLog : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         active      READ active     NOTIFY activeChanged)
    Q_PROPERTY(QVariantList records     READ records    NOTIFY recordsChanged)
    /// Distinct vehicle / field names in the records (filter choices)
    Q_PROPERTY(QStringList  vehicles    READ vehicles   NOTIFY recordsChanged)
    Q_PROPERTY(QStringList  fieldNames  READ fieldNames NOTIFY recordsChanged)

public:
    explicit HHUWorkLog(QObject *parent = nullptr);

    bool active() const { return !_session.isEmpty(); }
    QVariantList records() const { return _records; }
    QStringList vehicles() const;
    QStringList fieldNames() const;

    /// Stable id of a vehicle: flight controller UID, or the MAVLink system id when unknown
    Q_INVOKABLE static QString vehicleKey(Vehicle *vehicle);

    /// Starts a session. info: fieldId, fieldName, swath (m), startSeq, lastSeq,
    /// cumulative (list: route length in m from the first waypoint up to each sequence number)
    Q_INVOKABLE void start(Vehicle *vehicle, const QVariantMap &info);
    /// Called on link loss / restore by the 作业 page
    Q_INVOKABLE void linkInterrupted();
    /// MISSION_ITEM_REACHED from the vehicle (Rover holds in AUTO at the end of the route, so this is
    /// how the end of the route is recognised)
    void itemReached(Vehicle *vehicle, int seq);

    /// 断点续作: waypoint the vehicle was driving to when work on this field last stopped (0 = none)
    Q_INVOKABLE int resumeWaypoint(Vehicle *vehicle, const QString &fieldId) const;
    /// Field last uploaded to this vehicle ("" = unknown)
    Q_INVOKABLE QString vehicleField(Vehicle *vehicle) const;
    Q_INVOKABLE void setVehicleField(Vehicle *vehicle, const QString &fieldId);

    /// Records filtered by date (yyyy-MM-dd, inclusive, "" = open), vehicle and field ("" = all)
    Q_INVOKABLE QVariantList query(const QString &fromDate, const QString &toDate, const QString &vehicle, const QString &field) const;
    /// Writes records as CSV (UTF-8 with BOM so Excel shows Chinese correctly); false on error
    Q_INVOKABLE bool exportCsv(const QString &path, const QVariantList &records) const;
    Q_INVOKABLE void removeRecord(const QString &id);
    /// Asks the 作业 page (which hosts the window) to show the work records
    Q_INVOKABLE void requestShowRecords() { emit showRecordsRequested(); }

signals:
    void activeChanged();
    void recordsChanged();
    /// A session was closed and stored
    void recordAdded(const QVariantMap &record);
    void showRecordsRequested();

private:
    void _attach(Vehicle *vehicle);
    void _onMissionIndex();
    void _onFlightMode();
    void _onArmed();
    void _onCoordinate(const QGeoCoordinate &coordinate);
    void _finish(bool routeCompleted);
    void _saveSession();
    void _loadRecords();
    void _saveRecords();
    QString _resumeKey(const QString &vehicleKey, const QString &fieldId) const;

    QVariantMap         _session;   ///< open session (empty = none)
    QVariantList        _records;
    QPointer<Vehicle>   _vehicle;
    QGeoCoordinate      _lastCoord;
    bool                _wasAuto = false;
    QTimer              _saveTimer;
};
