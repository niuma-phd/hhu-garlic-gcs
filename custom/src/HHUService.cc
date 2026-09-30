#include "HHUService.h"
#include "AppSettings.h"
#include "HHU4GLink.h"
#include "HHUConfig.h"
#include "QGCLoggingCategory.h"
#include "SettingsManager.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDir>
#include <QtCore/QDirIterator>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QProcess>
#include <QtCore/QSaveFile>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtCore/QTimer>
#include <QtCore/QUrl>
#include <QtCore/QVersionNumber>
#include <QtCore/private/qzipwriter_p.h>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslCertificate>
#include <QtNetwork/QSslConfiguration>

QGC_LOGGING_CATEGORY(HHUServiceLog, "Custom.HHUService")

namespace {
constexpr qint64 kChunk = 1024 * 1024;
constexpr int kKeepDays = 7;
constexpr const char *kUploadKey = "HHU/logUpload";   ///< resumable upload: id, zip, sha, size

QString sha256Of(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return QString();
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    (void) hash.addData(&f);
    return QString::fromLatin1(hash.result().toHex());
}

/// The relay server is reached by IP with a certificate from the operator's own CA. The 4G
/// connection imports that CA; HTTPS requests to the same server must trust it as well.
void applyServerCa(QNetworkRequest &request, const QString &caFile)
{
    if (caFile.isEmpty()) {
        return;
    }
    const QString path = caFile.startsWith(QStringLiteral("file:")) ? QUrl(caFile).toLocalFile() : caFile;
    const QList<QSslCertificate> extra = QSslCertificate::fromPath(path);
    if (extra.isEmpty()) {
        qCWarning(HHUServiceLog) << "CA certificate not readable" << path;
        return;
    }
    QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
    QList<QSslCertificate> cas = ssl.caCertificates();
    cas.append(extra);
    ssl.setCaCertificates(cas);
    request.setSslConfiguration(ssl);
}
}

HHUService::HHUService(HHUConfig *config, HHU4GLink *link4G, QObject *parent)
    : QObject(parent)
    , _config(config)
    , _link4G(link4G)
    , _nam(new QNetworkAccessManager(this))
{
    // Resume an interrupted upload
    const QVariantMap pending = QSettings().value(QString::fromLatin1(kUploadKey)).toMap();
    if (!pending.isEmpty() && QFile::exists(pending.value(QStringLiteral("zip")).toString())) {
        _zipPath = pending.value(QStringLiteral("zip")).toString();
        _zipSha = pending.value(QStringLiteral("sha")).toString();
        _zipSize = QFileInfo(_zipPath).size();
        _zipFiles = pending.value(QStringLiteral("files")).toInt();
        _uploadId = pending.value(QStringLiteral("id")).toString();
        _logState = QStringLiteral("ready");
        _logMessage = tr("An upload was interrupted. Tap upload to continue.");
    }
    QTimer::singleShot(3000, this, &HHUService::_pruneOldLogs);
    // Start-up update check (需求说明 §3.8), quiet when nothing is found or no server is configured
    QTimer::singleShot(10000, this, [this]() { checkForUpdate(true); });
}

QString HHUService::appVersion()
{
    return QStringLiteral(HHU_APP_VERSION);
}

QString HHUService::baseUrl() const
{
    if (!_config->serverBaseUrl().isEmpty()) {
        return _config->serverBaseUrl();
    }
    const QString host = _link4G->serverHost();
    return host.isEmpty() ? QString() : QStringLiteral("https://") + host;
}

QNetworkReply *HHUService::_send(const QString &method, const QString &path, const QByteArray &body, const QString &contentType)
{
    QNetworkRequest request(QUrl(baseUrl() + path));
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("HHU-GCS/%1").arg(appVersion()));
    request.setTransferTimeout(30000);
    applyServerCa(request, _link4G->caFile());
    const QVariantMap cred = _link4G->credentials();
    const QString vehicle = cred.value(QStringLiteral("vehicle")).toString();
    if (!vehicle.isEmpty()) {
        request.setRawHeader("Authorization", "Basic " + (vehicle + QLatin1Char(':') + cred.value(QStringLiteral("password")).toString()).toUtf8().toBase64());
    }
    if (!contentType.isEmpty()) {
        request.setHeader(QNetworkRequest::ContentTypeHeader, contentType);
    }
    QNetworkReply *reply = _nam->sendCustomRequest(request, method.toLatin1(), body);
    _reply = reply;
    _watchReply(reply);
    return reply;
}

QString HHUService::_errorText(QNetworkReply *reply) const
{
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status == 401 || status == 403) {
        return tr("The server refused the vehicle number or password.");
    }
    if (status > 0) {
        return tr("Server error (HTTP %1).").arg(status);
    }
    return tr("Cannot reach the server: %1").arg(reply->errorString());
}

void HHUService::_watchReply(QNetworkReply *reply)
{
    // Not busy any more as soon as the reply finished (it is deleted later); connected before the
    // callers' own handlers, so a follow-up request started there is tracked again
    (void) connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (_reply == reply) {
            _reply = nullptr;
        }
        emit busyChanged();
    });
    emit busyChanged();
}

void HHUService::cancel()
{
    if (_reply) {
        _reply->abort();
    }
}

// ---- Update ----------------------------------------------------------------------------------

void HHUService::_setUpdate(const QString &state, const QString &message)
{
    _updateState = state;
    _updateMessage = message;
    emit updateChanged();
}

void HHUService::checkForUpdate(bool silent)
{
    if (baseUrl().isEmpty()) {
        if (!silent) {
            _setUpdate(QStringLiteral("error"), tr("No server configured. Set up the 4G connection first."));
        }
        return;
    }
    if (_reply) {
        return;
    }
    _silent = silent;
    _setUpdate(QStringLiteral("checking"), tr("Checking for updates…"));
    QNetworkReply *reply = _send(QStringLiteral("GET"), QStringLiteral("/api/version"));
    (void) connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            _setUpdate(_silent ? QStringLiteral("idle") : QStringLiteral("error"), _silent ? QString() : _errorText(reply));
            return;
        }
        const QJsonObject info = QJsonDocument::fromJson(reply->readAll()).object();
        const QVersionNumber latest = QVersionNumber::fromString(info.value(QStringLiteral("version")).toString());
        const QVersionNumber mine = QVersionNumber::fromString(appVersion());
        if (!latest.isNull() && latest > mine) {
            _update = info.toVariantMap();
            _setUpdate(QStringLiteral("available"), tr("Version %1 is available.").arg(latest.toString()));
        } else {
            _setUpdate(_silent ? QStringLiteral("idle") : QStringLiteral("latest"), _silent ? QString() : tr("This is the latest version (%1).").arg(appVersion()));
        }
    });
}

void HHUService::downloadAndInstall()
{
    const QString url = _update.value(QStringLiteral("url")).toString();
    if (url.isEmpty() || _reply) {
        return;
    }
    _installerPath = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath(QFileInfo(QUrl(url).path()).fileName());
    if (QFileInfo(_installerPath).fileName().isEmpty()) {
        _installerPath = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath(QStringLiteral("HHU-GCS-setup.exe"));
    }
    _setUpdate(QStringLiteral("downloading"), tr("Downloading the update…"));
    QNetworkRequest request{ QUrl(url).isRelative() ? QUrl(baseUrl() + url) : QUrl(url) };
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("HHU-GCS/%1").arg(appVersion()));
    applyServerCa(request, _link4G->caFile());
    QNetworkReply *reply = _nam->get(request);
    _reply = reply;
    _watchReply(reply);
    auto *file = new QFile(_installerPath, reply);
    if (!file->open(QIODevice::WriteOnly)) {
        reply->abort();
        _setUpdate(QStringLiteral("error"), tr("Cannot save the download: %1").arg(file->errorString()));
        return;
    }
    (void) connect(reply, &QNetworkReply::readyRead, this, [reply, file]() { file->write(reply->readAll()); });
    (void) connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        _progress = total > 0 ? double(got) / double(total) : 0;
        emit progressChanged();
    });
    (void) connect(reply, &QNetworkReply::finished, this, [this, reply, file]() {
        file->write(reply->readAll());
        file->close();
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            _setUpdate(QStringLiteral("error"), _errorText(reply));
            return;
        }
        const QString expected = _update.value(QStringLiteral("sha256")).toString().toLower();
        if (expected.isEmpty() || sha256Of(_installerPath) != expected) {
            (void) QFile::remove(_installerPath);
            _setUpdate(QStringLiteral("error"), tr("The download is damaged (checksum mismatch) and was not installed."));
            return;
        }
        _setUpdate(QStringLiteral("installing"), tr("Starting the installer…"));
        if (QProcess::startDetached(_installerPath, {})) {
            QTimer::singleShot(1500, qApp, &QCoreApplication::quit);
        } else {
            _setUpdate(QStringLiteral("error"), tr("Cannot start the installer %1").arg(_installerPath));
        }
    });
}

// ---- Logs ------------------------------------------------------------------------------------

QStringList HHUService::logFolders() const
{
    AppSettings *app = SettingsManager::instance()->appSettings();
    return { app->logSavePath(), app->telemetrySavePath() };
}

void HHUService::_pruneOldLogs()
{
    const QDateTime limit = QDateTime::currentDateTime().addDays(-kKeepDays);
    for (const QString &folder : logFolders()) {
        if (folder.isEmpty()) continue;
        QDirIterator it(folder, { QStringLiteral("*.tlog"), QStringLiteral("*.log"), QStringLiteral("*.txt"), QStringLiteral("*.csv") },
                        QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo fi(it.next());
            if (fi.lastModified() < limit) {
                (void) QFile::remove(fi.absoluteFilePath());
            }
        }
    }
    // Old packed zips
    QDirIterator zips(QStandardPaths::writableLocation(QStandardPaths::TempLocation), { QStringLiteral("HHU-GCS-logs-*.zip") }, QDir::Files);
    while (zips.hasNext()) {
        const QFileInfo fi(zips.next());
        if (fi.lastModified() < limit && fi.absoluteFilePath() != _zipPath) {
            (void) QFile::remove(fi.absoluteFilePath());
        }
    }
}

void HHUService::_setLog(const QString &state, const QString &message)
{
    _logState = state;
    _logMessage = message;
    emit logChanged();
}

void HHUService::packLogs(const QDateTime &from, const QDateTime &to)
{
    _setLog(QStringLiteral("packing"), tr("Packing logs…"));
    QSettings().remove(QString::fromLatin1(kUploadKey));
    _uploadId.clear();
    _ticket.clear();

    _zipPath = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation))
                   .filePath(QStringLiteral("HHU-GCS-logs-%1.zip").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"))));
    QZipWriter zip(_zipPath);
    zip.setCompressionPolicy(QZipWriter::AlwaysCompress);
    _zipFiles = 0;
    for (const QString &folder : logFolders()) {
        if (folder.isEmpty()) continue;
        QDirIterator it(folder, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo fi(it.next());
            // A file belongs to the range when it was written during it (log files span their session)
            if (fi.lastModified() < from || (fi.birthTime().isValid() && fi.birthTime() > to)) {
                continue;
            }
            QFile f(fi.absoluteFilePath());
            if (f.open(QIODevice::ReadOnly)) {
                zip.addFile(QDir(folder).dirName() + QLatin1Char('/') + QDir(folder).relativeFilePath(fi.absoluteFilePath()), &f);
                _zipFiles++;
            }
        }
    }
    // Configuration tables and version help after-sales
    zip.addFile(QStringLiteral("info.txt"), QStringLiteral("HHU-GCS %1\nQGC %2\nrange %3 .. %4\nconfig %5\n")
                    .arg(appVersion(), QCoreApplication::applicationVersion(), from.toString(Qt::ISODate), to.toString(Qt::ISODate), _config->source())
                    .toUtf8());
    zip.close();

    if (zip.status() != QZipWriter::NoError) {
        _setLog(QStringLiteral("error"), tr("Could not pack the logs."));
        return;
    }
    _zipSize = QFileInfo(_zipPath).size();
    _zipSha = sha256Of(_zipPath);
    _setLog(QStringLiteral("ready"), _zipFiles > 0 ? QString() : tr("No log files in this time range."));
}

bool HHUService::exportLogs(const QString &path)
{
    QString target = path.startsWith(QStringLiteral("file:")) ? QUrl(path).toLocalFile() : path;
    (void) QFile::remove(target);
    return !_zipPath.isEmpty() && QFile::copy(_zipPath, target);
}

void HHUService::uploadLogs()
{
    if (_zipPath.isEmpty() || _reply) {
        return;
    }
    if (baseUrl().isEmpty() || _link4G->credentials().value(QStringLiteral("vehicle")).toString().isEmpty()) {
        _setLog(QStringLiteral("error"), tr("Uploading needs the 4G connection settings (server, vehicle number, password)."));
        return;
    }
    _setLog(QStringLiteral("uploading"), tr("Uploading…"));

    QNetworkReply *reply;
    if (_uploadId.isEmpty()) {
        const QJsonObject start{
            { QStringLiteral("vehicle"), _link4G->credentials().value(QStringLiteral("vehicle")).toString() },
            { QStringLiteral("name"),    QFileInfo(_zipPath).fileName() },
            { QStringLiteral("size"),    _zipSize },
            { QStringLiteral("sha256"),  _zipSha },
        };
        reply = _send(QStringLiteral("POST"), QStringLiteral("/api/logs"), QJsonDocument(start).toJson(QJsonDocument::Compact), QStringLiteral("application/json"));
    } else {
        reply = _send(QStringLiteral("GET"), QStringLiteral("/api/logs/") + _uploadId);
    }
    (void) connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            _setLog(QStringLiteral("error"), _errorText(reply) + QLatin1Char(' ') + tr("Tap upload again to continue."));
            return;
        }
        const QJsonObject r = QJsonDocument::fromJson(reply->readAll()).object();
        if (_uploadId.isEmpty()) {
            _uploadId = r.value(QStringLiteral("upload_id")).toString();
        }
        _uploaded = static_cast<qint64>(r.value(QStringLiteral("received")).toDouble());
        QSettings().setValue(QString::fromLatin1(kUploadKey), QVariantMap{
            { QStringLiteral("id"), _uploadId }, { QStringLiteral("zip"), _zipPath },
            { QStringLiteral("sha"), _zipSha }, { QStringLiteral("files"), _zipFiles } });
        _uploadNext();
    });
}

void HHUService::_uploadNext()
{
    _progress = _zipSize > 0 ? double(_uploaded) / _zipSize : 1;
    emit progressChanged();

    if (_uploaded >= static_cast<qint64>(_zipSize)) {
        QNetworkReply *reply = _send(QStringLiteral("POST"), QStringLiteral("/api/logs/%1/complete").arg(_uploadId));
        (void) connect(reply, &QNetworkReply::finished, this, [this, reply]() {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                _setLog(QStringLiteral("error"), _errorText(reply) + QLatin1Char(' ') + tr("Tap upload again to continue."));
                return;
            }
            _ticket = QJsonDocument::fromJson(reply->readAll()).object().value(QStringLiteral("ticket")).toString();
            QSettings().remove(QString::fromLatin1(kUploadKey));
            _uploadId.clear();
            _setLog(QStringLiteral("done"), tr("Upload finished. Ticket number: %1").arg(_ticket));
        });
        return;
    }

    QFile f(_zipPath);
    if (!f.open(QIODevice::ReadOnly) || !f.seek(_uploaded)) {
        _setLog(QStringLiteral("error"), tr("The packed log file is missing. Pack the logs again."));
        return;
    }
    const QByteArray piece = f.read(kChunk);
    QNetworkReply *reply = _send(QStringLiteral("PUT"), QStringLiteral("/api/logs/%1?offset=%2").arg(_uploadId).arg(_uploaded), piece, QStringLiteral("application/octet-stream"));
    (void) connect(reply, &QNetworkReply::uploadProgress, this, [this](qint64 sent, qint64) {
        _progress = _zipSize > 0 ? double(_uploaded + sent) / _zipSize : 1;
        emit progressChanged();
    });
    (void) connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            _setLog(QStringLiteral("error"), _errorText(reply) + QLatin1Char(' ') + tr("Tap upload again to continue."));
            return;
        }
        _uploaded = static_cast<qint64>(QJsonDocument::fromJson(reply->readAll()).object().value(QStringLiteral("received")).toDouble());
        _uploadNext();
    });
}
