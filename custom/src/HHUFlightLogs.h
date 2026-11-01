#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>

class HHU4GLink;
class HHUTuning;
class Vehicle;

/// 飞控日志 (our own engineers only, hhu_config.json engineeringTuning): the autopilot's dataflash logs
/// (/APM/LOGS/*.BIN on the SD card, logs/ on SITL) downloaded over MAVFTP (QGC's FTPManager, burst read),
/// 4G included, to <save path>/飞控日志/<车号>/ under their own names, so Mission Planner opens them.
///
/// A file is downloaded as <name>.part and renamed only when its size matches the listing, so a cut
/// download never looks complete; a local file of the listed size counts as downloaded. Deleting on the
/// vehicle takes only downloaded files and never the newest log (it may be the one being written).
/// Downloads need the vehicle disarmed (the open log is not complete yet, and the transfer takes the link).
/// Exposed to QML as hhuLogs.
class HHUFlightLogs : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         connected       READ connected      NOTIFY stateChanged)
    Q_PROPERTY(bool         busy            READ busy           NOTIFY stateChanged)
    /// What is running ("下载 00000012.BIN（2 / 5）")
    Q_PROPERTY(QString      busyText        READ busyText       NOTIFY stateChanged)
    /// Current file 0…1, -1 when nothing is transferred
    Q_PROPERTY(double       progress        READ progress       NOTIFY progressChanged)
    /// "120 KB/s · 剩余 1:20" of the current file
    Q_PROPERTY(QString      speedText       READ speedText      NOTIFY progressChanged)
    /// Connected, disarmed, nothing running
    Q_PROPERTY(bool         canTransfer     READ canTransfer    NOTIFY stateChanged)
    /// Why downloads / deleting are disabled while connected ("" = they are not)
    Q_PROPERTY(QString      blockReason     READ blockReason    NOTIFY stateChanged)
    /// [{ name, size, downloaded, newest }], newest first
    Q_PROPERTY(QVariantList files           READ files          NOTIFY filesChanged)
    Q_PROPERTY(int          pendingCount    READ pendingCount   NOTIFY filesChanged)    ///< not downloaded yet
    Q_PROPERTY(double       pendingBytes    READ pendingBytes   NOTIFY filesChanged)
    Q_PROPERTY(QString      message         READ message        NOTIFY messageChanged)
    Q_PROPERTY(bool         messageError    READ messageError   NOTIFY messageChanged)
    /// Set by the page while it is shown: lists the logs when opened and after reconnecting
    Q_PROPERTY(bool         active          READ active         WRITE setActive     NOTIFY activeChanged)

public:
    HHUFlightLogs(HHU4GLink *link4G, HHUTuning *tuning, QObject *parent = nullptr);

    bool            connected() const;
    bool            busy() const { return _busy; }
    QString         busyText() const;
    double          progress() const { return _progress; }
    QString         speedText() const;
    bool            canTransfer() const;
    QString         blockReason() const;
    QVariantList    files() const { return _files; }
    int             pendingCount() const;
    double          pendingBytes() const;
    QString         message() const { return _message; }
    bool            messageError() const { return _messageError; }
    bool            active() const { return _active; }
    void            setActive(bool active);

    Q_INVOKABLE void refresh();
    /// Downloads these logs one after the other; [] = every log not downloaded yet
    Q_INVOKABLE void download(const QStringList &names);
    /// Stops after cancelling the running download (its .part is removed)
    Q_INVOKABLE void cancel();
    /// Deletes these logs on the vehicle: only downloaded ones, never the newest
    Q_INVOKABLE void removeDownloaded(const QStringList &names);
    Q_INVOKABLE QString folder() const;
    Q_INVOKABLE void openFolder() const;

signals:
    void stateChanged();
    void filesChanged();
    void progressChanged();
    void messageChanged();
    void activeChanged();

private:
    enum class Wait { None, List, Download, Delete };

    void _setVehicle(Vehicle *vehicle);
    void _setMessage(const QString &text, bool error);
    void _setBusy(bool busy, const QString &label = QString());
    void _relist();
    void _list(int candidate);
    void _markDownloaded();
    void _downloadNext();
    void _deleteNext();
    void _finish(const QString &text, bool error);
    qint64 _sizeOf(const QString &name) const;

    void _onListComplete(const QStringList &entries, const QString &error);
    void _onDownloadComplete(const QString &file, const QString &error);
    void _onDeleteComplete(const QString &file, const QString &error);
    void _onProgress(float value);

    HHU4GLink           *_link4G = nullptr;
    HHUTuning           *_tuning = nullptr;
    QPointer<Vehicle>   _vehicle;

    bool            _active = false;
    bool            _busy = false;
    bool            _listAfterReconnect = false;
    QString         _label;
    Wait            _wait = Wait::None;
    QString         _directory;
    int             _listCandidate = 0;
    QVariantList    _files;
    QString         _message;
    bool            _messageError = false;

    QStringList     _queue;             ///< downloads / deletions still to do
    int             _queueTotal = 0;
    int             _done = 0;
    qint64          _doneBytes = 0;
    bool            _cancelled = false;
    QString         _current;           ///< file being downloaded / deleted
    QString         _partFile;          ///< local <name>.part of the running download
    double          _progress = -1;
    QElapsedTimer   _fileClock;
    QElapsedTimer   _runClock;
};
