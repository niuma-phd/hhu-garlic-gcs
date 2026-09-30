#include "HHUNtrip.h"
#include "HHUConfig.h"
#include "HHUSecret.h"
#include "NTRIPSettings.h"
#include "QGCLoggingCategory.h"
#include "SettingsManager.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QSettings>
#include <QtNetwork/QTcpSocket>

QGC_LOGGING_CATEGORY(HHUNtripLog, "Custom.HHUNtrip")

namespace {
constexpr const char *kGroup = "HHU/ntrip";
constexpr int kTimeoutMs = 8000;
constexpr int kGgaVehicleGps = 1;   ///< NTRIPSettings ntripGgaPositionSource: Vehicle GPS
constexpr int kGgaIntervalSec = 5;
}

HHUNtrip::HHUNtrip(HHUConfig *config, QObject *parent)
    : QObject(parent)
    , _providers(config->ntripProviders())
{
    _timeout.setSingleShot(true);
    _timeout.setInterval(kTimeoutMs);
    (void) connect(&_timeout, &QTimer::timeout, this, [this]() {
        _finish(QStringLiteral("network"), tr("No answer from the RTK service. Check the address, port and internet connection."));
    });
    // QGC keeps the NTRIP password in its settings file: only in memory while we run
    (void) connect(qApp, &QCoreApplication::aboutToQuit, this, &HHUNtrip::_wipeQgcPassword);
}

QVariantMap HHUNtrip::account() const
{
    QSettings s;
    s.beginGroup(kGroup);
    if (s.value("host").toString().isEmpty()) {
        return QVariantMap();
    }
    return {
        { QStringLiteral("provider"),    s.value("provider") },
        { QStringLiteral("host"),        s.value("host") },
        { QStringLiteral("port"),        s.value("port", 8002) },
        { QStringLiteral("user"),        s.value("user") },
        { QStringLiteral("mount"),       s.value("mount") },
        { QStringLiteral("hasPassword"), !s.value("password").toString().isEmpty() },
    };
}

QString HHUNtrip::password() const
{
    QSettings s;
    s.beginGroup(kGroup);
    return HHUSecret::unprotect(s.value("password").toString());
}

void HHUNtrip::save(const QVariantMap &account)
{
    QSettings s;
    s.beginGroup(kGroup);
    s.setValue("provider", account.value(QStringLiteral("provider")).toString());
    s.setValue("host", account.value(QStringLiteral("host")).toString().trimmed());
    s.setValue("port", account.value(QStringLiteral("port")).toInt());
    s.setValue("user", account.value(QStringLiteral("user")).toString().trimmed());
    s.setValue("mount", account.value(QStringLiteral("mount")).toString().trimmed());
    const QString password = account.value(QStringLiteral("password")).toString();
    if (!password.isEmpty()) {
        s.setValue("password", HHUSecret::protect(password));
    }
    emit accountChanged();
}

void HHUNtrip::clear()
{
    QSettings().remove(QString::fromLatin1(kGroup));
    applyForwarding(false);
    _wipeQgcPassword();
    emit accountChanged();
}

void HHUNtrip::applyForwarding(bool forwardHere)
{
    NTRIPSettings *ntrip = SettingsManager::instance()->ntripSettings();
    const QVariantMap acc = account();
    if (!forwardHere || acc.isEmpty()) {
        ntrip->ntripServerConnectEnabled()->setRawValue(false);
        return;
    }
    ntrip->ntripServerHostAddress()->setRawValue(acc.value(QStringLiteral("host")));
    ntrip->ntripServerPort()->setRawValue(acc.value(QStringLiteral("port")));
    ntrip->ntripUsername()->setRawValue(acc.value(QStringLiteral("user")));
    ntrip->ntripPassword()->setRawValue(password());
    ntrip->ntripMountpoint()->setRawValue(acc.value(QStringLiteral("mount")));
    ntrip->ntripUseTls()->setRawValue(false);
    ntrip->ntripGgaPositionSource()->setRawValue(kGgaVehicleGps);  // VRS mountpoints need the vehicle position
    ntrip->ntripGgaIntervalSec()->setRawValue(kGgaIntervalSec);
    ntrip->ntripServerConnectEnabled()->setRawValue(true);
}

void HHUNtrip::_wipeQgcPassword()
{
    NTRIPSettings *ntrip = SettingsManager::instance()->ntripSettings();
    ntrip->ntripPassword()->setRawValue(QString());
    ntrip->ntripServerConnectEnabled()->setRawValue(false);
}

// ---- Caster requests ------------------------------------------------------------------------

void HHUNtrip::test(const QString &host, int port, const QString &user, const QString &password, const QString &mount)
{
    const QString pw = password.isEmpty() ? this->password() : password;
    _request(host, port, user, pw, QStringLiteral("/") + mount.trimmed(), false);
}

void HHUNtrip::fetchMountpoints(const QString &host, int port, const QString &user, const QString &password)
{
    const QString pw = password.isEmpty() ? this->password() : password;
    _request(host, port, user, pw, QStringLiteral("/"), true);
}

void HHUNtrip::cancel()
{
    if (_socket) {
        _socket->disconnect(this);
        _socket->abort();
        _socket->deleteLater();
        _socket = nullptr;
        _timeout.stop();
        emit testingChanged();
    }
}

void HHUNtrip::_request(const QString &host, int port, const QString &user, const QString &password, const QString &path, bool listMode)
{
    cancel();
    _listMode = listMode;
    _reply.clear();
    auto *socket = new QTcpSocket(this);
    _socket = socket;
    emit testingChanged();

    const QByteArray request =
        "GET " + path.toUtf8() + " HTTP/1.1\r\n"
        "Host: " + host.toUtf8() + "\r\n"
        "Ntrip-Version: Ntrip/2.0\r\n"
        "User-Agent: NTRIP HHU-GCS\r\n"
        "Authorization: Basic " + (user + QLatin1Char(':') + password).toUtf8().toBase64() + "\r\n"
        "Connection: close\r\n\r\n";

    (void) connect(socket, &QTcpSocket::connected, this, [socket, request]() { socket->write(request); });
    (void) connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
        _reply.append(socket->readAll());
        const int headerEnd = _reply.indexOf("\r\n");
        if (headerEnd < 0) {
            return;
        }
        const QString status = QString::fromLatin1(_reply.left(headerEnd)).trimmed();
        const bool ok200 = status.contains(QStringLiteral(" 200"));
        const bool sourceTable = status.startsWith(QStringLiteral("SOURCETABLE")) || _reply.contains("gnss/sourcetable");

        if (status.contains(QStringLiteral(" 401"))) {
            _finish(QStringLiteral("auth"), tr("Login failed: wrong user name or password, or the account has expired."));
        } else if (status.contains(QStringLiteral(" 404"))) {
            _finish(QStringLiteral("mount"), tr("The mountpoint does not exist. Get the list and choose one."));
        } else if (!ok200) {
            _finish(QStringLiteral("network"), tr("The RTK service answered: %1").arg(status));
        } else if (_listMode) {
            // Collect the whole source table ("ENDSOURCETABLE" or connection close)
            if (_reply.contains("ENDSOURCETABLE")) {
                QStringList names;
                for (const QByteArray &line : _reply.split('\n')) {
                    if (line.startsWith("STR;")) {
                        const QList<QByteArray> cols = line.split(';');
                        if (cols.size() > 1 && !names.contains(QString::fromUtf8(cols[1]))) {
                            names.append(QString::fromUtf8(cols[1]));
                        }
                    }
                }
                _mountpoints = names;
                emit mountpointsChanged();
                _finish(QStringLiteral("ok"), tr("%1 mountpoints found").arg(names.count()));
            }
        } else if (sourceTable) {
            _finish(QStringLiteral("mount"), tr("The mountpoint does not exist. Get the list and choose one."));
        } else {
            _finish(QStringLiteral("ok"), tr("Connection test passed."));
        }
    });
    (void) connect(socket, &QTcpSocket::errorOccurred, this, [this, socket](QAbstractSocket::SocketError error) {
        if (_listMode && error == QAbstractSocket::RemoteHostClosedError && _reply.contains("STR;")) {
            _reply.append("\nENDSOURCETABLE");
            emit socket->readyRead();
            return;
        }
        _finish(QStringLiteral("network"), tr("Cannot reach the RTK service: %1").arg(socket->errorString()));
    });

    _timeout.start();
    socket->connectToHost(host.trimmed(), static_cast<quint16>(port));
}

void HHUNtrip::_finish(const QString &code, const QString &message)
{
    qCDebug(HHUNtripLog) << code << message;
    cancel();
    emit testFinished(code, message);
}
