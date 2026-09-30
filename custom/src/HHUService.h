#pragma once

#include <QtCore/QDateTime>
#include <QtCore/QFile>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QVariantMap>

class HHU4GLink;
class HHUConfig;
class QNetworkAccessManager;
class QNetworkReply;

/// Server services over HTTPS (需求说明 V1.0 §3.8, §4.4), same server as the 4G connection
/// unless hhu_config.json "server.baseUrl" says otherwise.
///
/// 检查更新: GET /api/version -> { version, url, sha256, notes }; the installer is downloaded,
///           checked against sha256 and started; the ground station then closes.
/// 日志上传: run logs and MAVLink telemetry logs of a time range are zipped and uploaded in
///           1 MB pieces that can be resumed (protocol proposal, see custom/tools/mock_server.py):
///             POST /api/logs                    { vehicle, password, name, size, sha256 } -> { upload_id, received }
///             GET  /api/logs/<id>               -> { received }
///             PUT  /api/logs/<id>?offset=<n>    body = next piece -> { received }
///             POST /api/logs/<id>/complete      -> { ticket }
///           vehicle number + password (of the 4G connection) authenticate every request (HTTP Basic).
/// Also keeps the local logs to 7 days. Exposed to QML as hhuService.
class HHUService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString  appVersion      READ appVersion     CONSTANT)
    Q_PROPERTY(QString  baseUrl         READ baseUrl        NOTIFY busyChanged)
    /// "idle", "checking", "available", "latest", "downloading", "installing", "error"
    Q_PROPERTY(QString  updateState     READ updateState    NOTIFY updateChanged)
    Q_PROPERTY(QVariantMap update       READ update         NOTIFY updateChanged)   ///< { version, notes, url, sha256 }
    Q_PROPERTY(QString  updateMessage   READ updateMessage  NOTIFY updateChanged)
    Q_PROPERTY(double   progress        READ progress       NOTIFY progressChanged) ///< 0..1 of the running download / upload
    /// "idle", "packing", "ready", "uploading", "done", "error"
    Q_PROPERTY(QString  logState        READ logState       NOTIFY logChanged)
    Q_PROPERTY(QString  logMessage      READ logMessage     NOTIFY logChanged)
    Q_PROPERTY(double   logZipSize      READ logZipSize     NOTIFY logChanged)
    Q_PROPERTY(int      logFileCount    READ logFileCount   NOTIFY logChanged)
    Q_PROPERTY(QString  ticket          READ ticket         NOTIFY logChanged)
    Q_PROPERTY(bool     busy            READ busy           NOTIFY busyChanged)

public:
    HHUService(HHUConfig *config, HHU4GLink *link4G, QObject *parent = nullptr);

    static QString appVersion();

    QString baseUrl() const;
    QString updateState() const { return _updateState; }
    QVariantMap update() const { return _update; }
    QString updateMessage() const { return _updateMessage; }
    double  progress() const { return _progress; }
    QString logState() const { return _logState; }
    QString logMessage() const { return _logMessage; }
    double  logZipSize() const { return _zipSize; }
    int     logFileCount() const { return _zipFiles; }
    QString ticket() const { return _ticket; }
    bool    busy() const { return !_reply.isNull(); }

    /// silent: no message when already up to date or the server is not reachable (start-up check)
    Q_INVOKABLE void checkForUpdate(bool silent = false);
    Q_INVOKABLE void downloadAndInstall();

    /// Packs the logs written between from and to (local time) into a zip; see logState
    Q_INVOKABLE void packLogs(const QDateTime &from, const QDateTime &to);
    Q_INVOKABLE void uploadLogs();
    Q_INVOKABLE bool exportLogs(const QString &path);
    Q_INVOKABLE void cancel();

    /// Log folders of this ground station (for the 高级 page)
    Q_INVOKABLE QStringList logFolders() const;

signals:
    void updateChanged();
    void progressChanged();
    void logChanged();
    void busyChanged();

private:
    void _watchReply(QNetworkReply *reply);
    QNetworkReply *_send(const QString &method, const QString &path, const QByteArray &body = QByteArray(), const QString &contentType = QString());
    void _setUpdate(const QString &state, const QString &message);
    void _setLog(const QString &state, const QString &message);
    void _uploadNext();
    void _pruneOldLogs();
    QString _errorText(QNetworkReply *reply) const;

    HHUConfig              *_config = nullptr;
    HHU4GLink              *_link4G = nullptr;
    QNetworkAccessManager  *_nam = nullptr;
    QPointer<QNetworkReply> _reply;

    QString     _updateState = QStringLiteral("idle");
    QVariantMap _update;
    QString     _updateMessage;
    bool        _silent = false;
    QString     _installerPath;

    QString     _logState = QStringLiteral("idle");
    QString     _logMessage;
    QString     _zipPath;
    double      _zipSize = 0;
    int         _zipFiles = 0;
    QString     _zipSha;
    QString     _uploadId;
    qint64      _uploaded = 0;
    QString     _ticket;
    double      _progress = 0;
};
