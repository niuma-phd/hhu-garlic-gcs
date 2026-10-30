#pragma once

#include <QtCore/QAbstractListModel>
#include <QtCore/QElapsedTimer>
#include <QtCore/QHash>
#include <QtCore/QList>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>

#include "MAVLinkLib.h"

class HHU4GLink;
class Vehicle;

/// 工程调参 (our own engineers only, hhu_config.json engineeringTuning): a fixed list of autopilot
/// parameters (config/hhu_tuning_params.json) read and written over the vehicle link, 4G included.
///
/// Editing only marks a row pending. write() first saves a snapshot of the vehicle's current values
/// (<save path>/调参记录/<车号>/yyyyMMdd_HHmmss_写前.param, Mission Planner format), then sends one
/// PARAM_SET at a time and waits for the PARAM_VALUE read back (float32, tolerance 1e-4): resent after
/// 1.5 s, up to 3 times. Every item is appended to 调参日志.csv in the same folder. A link loss stops
/// the remaining items; once the link is back the list is read again. ArduPilot saves a PARAM_SET
/// to EEPROM by itself. Integer parameters may arrive either as a cast float or in the float's bytes
/// (seen on the QGC link of SITL); see _decode().
/// Exposed to QML as hhuTuning (a list model with one row per parameter).
class HHUTuning : public QAbstractListModel
{
    Q_OBJECT
    /// A vehicle is connected and its link is not lost
    Q_PROPERTY(bool     connected       READ connected      NOTIFY stateChanged)
    Q_PROPERTY(bool     reading         READ reading        NOTIFY stateChanged)
    Q_PROPERTY(bool     writing         READ writing        NOTIFY stateChanged)
    /// Disarmed or in HOLD, connected with write access, nothing running
    Q_PROPERTY(bool     canWrite        READ canWrite       NOTIFY stateChanged)
    /// Why write is disabled while the vehicle is connected ("" = it is not, or no reason to show)
    Q_PROPERTY(QString  blockReason     READ blockReason    NOTIFY stateChanged)
    Q_PROPERTY(bool     armed           READ armed          NOTIFY stateChanged)
    Q_PROPERTY(int      pendingCount    READ pendingCount   NOTIFY rowsChanged)
    Q_PROPERTY(int      invalidCount    READ invalidCount   NOTIFY rowsChanged)
    /// Result line of the last write ("成功 x 项，失败 y 项") or of a load / error
    Q_PROPERTY(QString  summary         READ summary        NOTIFY summaryChanged)
    Q_PROPERTY(bool     summaryError    READ summaryError   NOTIFY summaryChanged)
    /// A parameter that needs an autopilot reboot was written
    Q_PROPERTY(bool     rebootNeeded    READ rebootNeeded   NOTIFY stateChanged)
    /// 车号 used for the snapshot / log folder
    Q_PROPERTY(QString  vehicleName     READ vehicleName    NOTIFY stateChanged)
    /// Set by the page while it is shown: reads the list when opened and after reconnecting
    Q_PROPERTY(bool     active          READ active         WRITE setActive     NOTIFY activeChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        GroupRole,
        GroupStartRole,     ///< first row of its group (group heading above it)
        MinRole,
        MaxRole,
        StepRole,
        DecimalsRole,
        RebootRole,
        MissingRole,        ///< the vehicle has no such parameter
        CurrentTextRole,    ///< value on the vehicle, "" until read
        InputRole,
        PendingRole,        ///< input differs from the vehicle (to be written)
        InvalidRole,        ///< input is no number / out of range
        StatusRole,         ///< "", "reading", "writing", "ok", "fail", "unconfirmed", "unread"
        StatusTextRole,
    };

    HHUTuning(HHU4GLink *link4G, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool    connected() const;
    bool    reading() const { return _reading; }
    bool    writing() const { return _writing; }
    bool    canWrite() const;
    QString blockReason() const;
    bool    armed() const;
    int     pendingCount() const;
    int     invalidCount() const;
    QString summary() const { return _summary; }
    bool    summaryError() const { return _summaryError; }
    bool    rebootNeeded() const { return _rebootNeeded; }
    QString vehicleName() const;
    bool    active() const { return _active; }
    void    setActive(bool active);

    /// Reads every parameter of the list from the vehicle (edited inputs are kept)
    Q_INVOKABLE void read();
    Q_INVOKABLE void setInput(int row, const QString &text);
    /// − / + button: one step (direction -1 / 1), kept in range
    Q_INVOKABLE void stepInput(int row, int direction);
    /// Inputs back to the vehicle's values
    Q_INVOKABLE void discard();
    /// Snapshot, then writes the pending rows one by one
    Q_INVOKABLE void write();
    /// Snapshots of this vehicle, newest first: [{ path, label }]
    Q_INVOKABLE QVariantList snapshots() const;
    /// Fills the inputs from a Mission Planner .param file (only the listed parameters, nothing is
    /// written). Returns the number of parameters taken, -1 when the file cannot be read.
    Q_INVOKABLE int loadParamFile(const QString &pathOrUrl);
    /// MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN (disarmed only)
    Q_INVOKABLE void rebootAutopilot();

    void handleMessage(Vehicle *vehicle, const mavlink_message_t &message);

signals:
    void stateChanged();
    void rowsChanged();
    void summaryChanged();
    void activeChanged();

private:
    struct Row {
        QString name;
        QString group;
        double  min = 0;
        double  max = 0;
        double  step = 1;
        int     decimals = 0;
        bool    integer = false;
        bool    reboot = false;
        int     exists = -1;        ///< -1 unknown, 0 no, 1 yes
        bool    hasCurrent = false;
        float   current = 0;
        uint8_t type = MAV_PARAM_TYPE_REAL32;
        bool    bytewise = false;   ///< integer value came in the float's bytes (written back the same way)
        QString input;
        bool    edited = false;
        QString status;
        QString statusText;
    };

    struct ReadRequest {
        int attempts = 0;
        QElapsedTimer sent;
    };

    void _loadList();
    bool _loadList(const QString &path);
    void _setVehicle(Vehicle *vehicle);
    void _updateExists();
    void _markMissing(int row);
    void _onCommunicationLost(bool lost);
    void _rowChanged(int row);
    void _setStatus(int row, const QString &status, const QString &text);
    void _setSummary(const QString &text, bool error);
    bool _inputValue(const Row &row, double &value) const;
    bool _isInvalid(const Row &row) const;
    bool _isPending(const Row &row) const;
    int  _rowOf(const QString &name) const;

    void _startRead(bool keepStatus, bool resetInputs);
    void _sendReads();
    void _checkReads();
    void _finishRead();
    void _abortRead();

    void _writeNext();
    void _sendWrite();
    void _writeTimeout();
    void _finishItem(const QString &status, const QString &text);
    void _finishWrite(bool interrupted);

    bool _sendParamRequestRead(const QString &name);
    bool _sendParamSet(const Row &row, float value);
    QString _folder() const;
    bool _saveSnapshot(QString &error);
    void _log(const Row &row, const QString &oldValue, const QString &newValue, const QString &result);

    static QString _format(float value);
    static float _decode(const mavlink_param_value_t &paramValue, bool &bytewise);

    HHU4GLink           *_link4G = nullptr;
    QPointer<Vehicle>   _vehicle;
    QList<Row>          _rows;

    bool    _active = false;
    bool    _reading = false;
    bool    _writing = false;
    bool    _rebootNeeded = false;
    bool    _intBytewise = false;   ///< this vehicle sends integers in the float's bytes (a 0 does not tell)
    bool    _readAfterReconnect = false;
    bool    _resetInputsAfterRead = false;
    QString _summary;
    bool    _summaryError = false;

    QList<QString>                  _readQueue;
    QHash<QString, ReadRequest>     _readInFlight;
    QTimer                          _readTimer;

    QList<int>  _writeQueue;
    int         _writeRow = -1;
    float       _writeTarget = 0;
    int         _writeAttempts = 0;
    bool        _writeMismatch = false;
    float       _writeReadBack = 0;
    QString     _writeOldText;
    int         _okCount = 0;
    int         _failCount = 0;
    int         _unconfirmedCount = 0;
    QTimer      _writeTimer;
};
