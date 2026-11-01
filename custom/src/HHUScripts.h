#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTemporaryDir>
#include <QtCore/QVariantList>

#include <functional>
#include <memory>

class HHU4GLink;
class HHUTuning;
class Vehicle;

/// Lua 脚本 (our own engineers only, hhu_config.json engineeringTuning): the autopilot's scripts
/// directory over MAVFTP (QGC's FTPManager), 4G included. /APM/scripts on the SD card, scripts/ on SITL.
///
/// A script is replaced without ever leaving a partial file under its name: the old file is first
/// downloaded to <save path>/调参记录/<车号>/脚本备份/, the new one is uploaded as <name>.new, read
/// back and compared byte by byte, then the old file is deleted and <name>.new renamed. ArduPilot only
/// loads *.lua, so a left over .new does nothing. The scripts run the new file after 重启脚本
/// (MAV_CMD_SCRIPTING stop and restart) or an autopilot reboot. Changes need the vehicle disarmed.
/// Every change is appended to 脚本日志.csv. Exposed to QML as hhuScripts.
class HHUScripts : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         connected       READ connected      NOTIFY stateChanged)
    /// A MAVFTP operation is running
    Q_PROPERTY(bool         busy            READ busy           NOTIFY stateChanged)
    /// What is running ("上传 vcu_can.lua 45%")
    Q_PROPERTY(QString      busyText        READ busyText       NOTIFY stateChanged)
    /// Connected, disarmed, write access, nothing running
    Q_PROPERTY(bool         canModify       READ canModify      NOTIFY stateChanged)
    /// Why changes are disabled while the vehicle is connected ("" = they are not)
    Q_PROPERTY(QString      blockReason     READ blockReason    NOTIFY stateChanged)
    /// Scripts directory found on the vehicle ("" = not listed yet / none)
    Q_PROPERTY(QString      directory       READ directory      NOTIFY filesChanged)
    /// [{ name, size }] of the scripts directory, sorted by name
    Q_PROPERTY(QVariantList files           READ files          NOTIFY filesChanged)
    Q_PROPERTY(QString      message         READ message        NOTIFY messageChanged)
    Q_PROPERTY(bool         messageError    READ messageError   NOTIFY messageChanged)
    /// A script was changed since the scripts were last restarted
    Q_PROPERTY(bool         restartNeeded   READ restartNeeded  NOTIFY stateChanged)
    /// Set by the page while it is shown: lists the directory when opened and after reconnecting
    Q_PROPERTY(bool         active          READ active         WRITE setActive     NOTIFY activeChanged)

public:
    HHUScripts(HHU4GLink *link4G, HHUTuning *tuning, QObject *parent = nullptr);

    bool            connected() const;
    bool            busy() const { return _busy; }
    QString         busyText() const;
    bool            canModify() const;
    QString         blockReason() const;
    QString         directory() const { return _directory; }
    QVariantList    files() const { return _files; }
    QString         message() const { return _message; }
    bool            messageError() const { return _messageError; }
    bool            restartNeeded() const { return _restartNeeded; }
    bool            active() const { return _active; }
    void            setActive(bool active);

    /// Lists the scripts directory
    Q_INVOKABLE void refresh();
    /// Uploads a local file as <targetName> ("" = the local file's name), replacing a file of that name
    Q_INVOKABLE void upload(const QString &localPathOrUrl, const QString &targetName = QString());
    /// Backs the file up, then deletes it on the vehicle
    Q_INVOKABLE void remove(const QString &name);
    /// Downloads the file to the backup folder
    Q_INVOKABLE void backup(const QString &name);
    /// MAV_CMD_SCRIPTING stop and restart (disarmed only)
    Q_INVOKABLE void restartScripts();
    /// The local folder of the backups of this vehicle
    Q_INVOKABLE QString backupFolder() const;
    /// Opens the backup folder in the file manager (created if missing)
    Q_INVOKABLE void openBackupFolder() const;
    /// The file name the vehicle accepts ("" = ok, else why not)
    Q_INVOKABLE QString checkName(const QString &name) const;
    /// File name of a local path or file URL
    Q_INVOKABLE QString fileName(const QString &localPathOrUrl) const;
    /// Native local path of a file URL
    Q_INVOKABLE QString localPath(const QString &localPathOrUrl) const;
    Q_INVOKABLE bool    exists(const QString &name) const;

signals:
    void stateChanged();
    void filesChanged();
    void messageChanged();
    void activeChanged();

private:
    using Step = std::function<void()>;

    void _setVehicle(Vehicle *vehicle);
    void _setMessage(const QString &text, bool error);
    void _start(const QString &label, const QList<Step> &steps);
    void _next();
    void _fail(const QString &text);
    void _done(const QString &text);

    void _list(int candidate);
    bool _download(const QString &name, const QString &toDir, const QString &toName);
    QString _path(const QString &name) const;
    QString _logFolder() const;
    void _log(const QString &action, const QString &name, qint64 size, const QString &result);

    void _onListComplete(const QStringList &entries, const QString &error);
    void _onDownloadComplete(const QString &file, const QString &error);
    void _onUploadComplete(const QString &file, const QString &error);
    void _onDeleteComplete(const QString &file, const QString &error);
    void _onRenameComplete(const QString &file, const QString &error);
    void _onProgress(float value);

    HHU4GLink           *_link4G = nullptr;
    HHUTuning           *_tuning = nullptr;
    QPointer<Vehicle>   _vehicle;

    bool            _active = false;
    bool            _busy = false;
    bool            _restartNeeded = false;
    bool            _listAfterReconnect = false;
    QString         _label;
    float           _progress = -1;
    QString         _directory;
    QVariantList    _files;
    QString         _message;
    bool            _messageError = false;

    /// Running operation: one MAVFTP command per step, the step's completion runs the next one
    enum class Wait { None, List, Download, Upload, Delete, Rename };
    QList<Step>     _steps;
    Wait            _wait = Wait::None;
    bool            _ignoreError = false;   ///< the running step may fail (deleting a left over .new)
    bool            _quiet = false;         ///< listing after a failed change: its errors do not replace the message
    QString         _logAction;             ///< change running: logged with the error when it fails
    QString         _logName;
    qint64          _logSize = 0;
    int             _listCandidate = 0;
    QString         _expectedFile;          ///< local file of the running download
    std::unique_ptr<QTemporaryDir> _tempDir;
};
