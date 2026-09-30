#include "HHU4GLink.h"
#include "HHULinkMonitor.h"
#include "HHUSecret.h"
#include "LinkManager.h"
#include "QGCLoggingCategory.h"
#include "TCPLink.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSettings>
#include <QtCore/QUrl>
#include <QtCore/QUuid>
#include <QtNetwork/QSslCertificate>
#include <QtNetwork/QSslConfiguration>
#include <QtNetwork/QTcpServer>
#include <QtNetwork/QTcpSocket>

#include <algorithm>

QGC_LOGGING_CATEGORY(HHU4GLog, "Custom.HHU4GLink")

namespace {
constexpr int kLoginTimeoutMs = 5000;
constexpr int kMaxRetrySec = 30;
constexpr int kMaxLoginLine = 1024;
constexpr const char *kConfigsKey = "HHU/4g/configsJson";
constexpr const char *kLastKey = "HHU/4g/last";
constexpr const char *kClientKey = "HHU/4g/clientId";
}

HHU4GLink::HHU4GLink(HHULinkMonitor *linkMonitor, QObject *parent)
    : QObject(parent)
    , _linkMonitor(linkMonitor)
{
    QSettings settings;
    _clientId = settings.value(QString::fromLatin1(kClientKey)).toString();
    if (_clientId.isEmpty()) {
        _clientId = QStringLiteral("gcs-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(12);
        settings.setValue(QString::fromLatin1(kClientKey), _clientId);
    }
    _loadConfigs();

    _loginTimer.setSingleShot(true);
    _loginTimer.setInterval(kLoginTimeoutMs);
    (void) connect(&_loginTimer, &QTimer::timeout, this, &HHU4GLink::_onLoginTimeout);
    _retryTimer.setSingleShot(true);
    (void) connect(&_retryTimer, &QTimer::timeout, this, &HHU4GLink::_openSocket);
    _retryTick.setInterval(1000);
    (void) connect(&_retryTick, &QTimer::timeout, this, &HHU4GLink::retryChanged);
}

HHU4GLink::~HHU4GLink()
{
    _userStop = true;
    if (_socket) {
        _socket->abort();
    }
}

// ---- Configs -------------------------------------------------------------------------------

// Stored as JSON text (readable in the settings file); passwords are HHUSecret-protected
void HHU4GLink::_loadConfigs()
{
    const QString json = QSettings().value(QString::fromLatin1(kConfigsKey)).toString();
    _configs = QJsonDocument::fromJson(json.toUtf8()).array().toVariantList();
}

void HHU4GLink::_saveConfigs()
{
    QSettings().setValue(QString::fromLatin1(kConfigsKey),
                         QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(_configs)).toJson(QJsonDocument::Compact)));
    emit configsChanged();
}

QVariantList HHU4GLink::configs() const
{
    QVariantList list;
    for (const QVariant &v : _configs) {
        QVariantMap c = v.toMap();
        c.insert(QStringLiteral("hasPassword"), !c.value(QStringLiteral("password")).toString().isEmpty());
        c.remove(QStringLiteral("password"));
        list.append(c);
    }
    return list;
}

QVariantMap HHU4GLink::_config(int index) const
{
    if (index < 0 || index >= _configs.count()) {
        return QVariantMap();
    }
    QVariantMap c = _configs[index].toMap();
    c.insert(QStringLiteral("password"), HHUSecret::unprotect(c.value(QStringLiteral("password")).toString()));
    return c;
}

int HHU4GLink::saveConfig(int index, const QVariantMap &config)
{
    QVariantMap stored = (index >= 0 && index < _configs.count()) ? _configs[index].toMap() : QVariantMap();
    for (const char *key : { "name", "host", "vehicle", "caFile" }) {
        stored.insert(QString::fromLatin1(key), config.value(QString::fromLatin1(key)).toString().trimmed());
    }
    stored.insert(QStringLiteral("port"), config.value(QStringLiteral("port"), 7000).toInt());
    stored.insert(QStringLiteral("tls"), config.value(QStringLiteral("tls"), true).toBool());
    const QString password = config.value(QStringLiteral("password")).toString();
    if (!password.isEmpty()) {
        stored.insert(QStringLiteral("password"), HHUSecret::protect(password));
    }
    if (index >= 0 && index < _configs.count()) {
        _configs[index] = stored;
    } else {
        _configs.append(stored);
        index = _configs.count() - 1;
    }
    _saveConfigs();
    return index;
}

void HHU4GLink::removeConfig(int index)
{
    if (index < 0 || index >= _configs.count()) {
        return;
    }
    if (index == _activeIndex) {
        disconnectLink();
    } else if (_activeIndex > index) {
        _activeIndex--;
    }
    _configs.removeAt(index);
    _saveConfigs();
}

QString HHU4GLink::serverHost() const
{
    const int index = _activeIndex >= 0 ? _activeIndex : (_configs.isEmpty() ? -1 : 0);
    return index >= 0 ? _configs[index].toMap().value(QStringLiteral("host")).toString() : QString();
}

QVariantMap HHU4GLink::credentials() const
{
    const QVariantMap c = _config(_activeIndex >= 0 ? _activeIndex : 0);
    return { { QStringLiteral("vehicle"), c.value(QStringLiteral("vehicle")) },
             { QStringLiteral("password"), c.value(QStringLiteral("password")) } };
}

// ---- Connection -----------------------------------------------------------------------------

void HHU4GLink::_setState(const QString &state, const QString &text)
{
    _state = state;
    _statusText = text;
    emit stateChanged();
    qCDebug(HHU4GLog) << state << text;
}

int HHU4GLink::retryInSec() const
{
    return _retryTimer.isActive() ? (_retryTimer.remainingTime() + 999) / 1000 : 0;
}

void HHU4GLink::autoStart()
{
    const int last = QSettings().value(QString::fromLatin1(kLastKey), -1).toInt();
    if (last >= 0 && last < _configs.count()) {
        connectTo(last);
    }
}

void HHU4GLink::connectTo(int index)
{
    if (index < 0 || index >= _configs.count()) {
        return;
    }
    if (_activeIndex >= 0) {
        disconnectLink();
    }
    _activeIndex = index;
    _userStop = false;
    _retryDelaySec = 0;
    _readOnly = false;
    QSettings().setValue(QString::fromLatin1(kLastKey), index);
    _openSocket();
}

void HHU4GLink::disconnectLink()
{
    _userStop = true;
    _retryTimer.stop();
    _retryTick.stop();
    _loginTimer.stop();
    if (_socket) {
        _socket->abort();
    }
    _stopBridge();
    _activeIndex = -1;
    _loggedIn = false;
    _readOnly = false;
    _pendingNtrip.clear();
    _linkMonitor->setSuppressLoss(false);
    QSettings().remove(QString::fromLatin1(kLastKey));
    _setState(QStringLiteral("idle"), QString());
}

void HHU4GLink::_openSocket()
{
    _retryTick.stop();
    const QVariantMap c = _config(_activeIndex);
    if (c.isEmpty()) {
        return;
    }
    if (_socket) {
        _socket->disconnect(this);
        _socket->abort();
        _socket->deleteLater();
    }
    _socket = new QSslSocket(this);
    _lineBuffer.clear();
    _loggedIn = false;
    _lossHandled = false;

    (void) connect(_socket, &QSslSocket::readyRead, this, &HHU4GLink::_onReadyRead);
    (void) connect(_socket, &QSslSocket::disconnected, this, &HHU4GLink::_onDisconnected);
    (void) connect(_socket, &QSslSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        qCDebug(HHU4GLog) << "socket error" << (_socket ? _socket->errorString() : QString());
        if (_socket && _socket->state() == QAbstractSocket::UnconnectedState) {
            _onDisconnected();
        }
    });

    const QString host = c.value(QStringLiteral("host")).toString();
    const quint16 port = static_cast<quint16>(c.value(QStringLiteral("port"), 7000).toInt());
    if (!_pendingNtrip.isEmpty()) {
        _setState(QStringLiteral("connecting"), tr("Updating the RTK account…"));
    } else {
        _setState(QStringLiteral("connecting"), tr("Connecting to %1…").arg(host));
    }

    if (c.value(QStringLiteral("tls"), true).toBool()) {
        QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
        const QString caFile = c.value(QStringLiteral("caFile")).toString();
        if (!caFile.isEmpty()) {
            QList<QSslCertificate> cas = ssl.caCertificates();
            cas.append(QSslCertificate::fromPath(caFile.startsWith(QStringLiteral("file:")) ? QUrl(caFile).toLocalFile() : caFile));
            ssl.setCaCertificates(cas);
        }
        _socket->setSslConfiguration(ssl);
        (void) connect(_socket, &QSslSocket::encrypted, this, &HHU4GLink::_onConnected);
        (void) connect(_socket, &QSslSocket::sslErrors, this, [this](const QList<QSslError> &errors) {
            QStringList text;
            for (const QSslError &e : errors) text << e.errorString();
            qCWarning(HHU4GLog) << "TLS errors" << text;
            _userStop = true;   // a certificate problem does not go away by retrying
            _setState(QStringLiteral("failed"), tr("The server certificate is not trusted. Import the server's CA certificate in the connection settings."));
        });
        _socket->connectToHostEncrypted(host, port);
    } else {
        (void) connect(_socket, &QSslSocket::connected, this, &HHU4GLink::_onConnected);
        _socket->connectToHost(host, port);
    }
    _loginTimer.start();
}

void HHU4GLink::_onConnected()
{
    const QVariantMap c = _config(_activeIndex);
    QJsonObject auth{
        { QStringLiteral("type"),     QStringLiteral("auth") },
        { QStringLiteral("ver"),      1 },
        { QStringLiteral("role"),     QStringLiteral("gcs") },
        { QStringLiteral("vehicle"),  c.value(QStringLiteral("vehicle")).toString() },
        { QStringLiteral("password"), c.value(QStringLiteral("password")).toString() },
        { QStringLiteral("client"),   _clientId },
        { QStringLiteral("app"),      QStringLiteral(HHU_APP_VERSION) },
    };
    if (!_pendingNtrip.isEmpty()) {
        auth.insert(QStringLiteral("ntrip"), QJsonObject::fromVariantMap(_pendingNtrip));
    }
    QByteArray line = QJsonDocument(auth).toJson(QJsonDocument::Compact);
    if (line.size() + 1 > kMaxLoginLine) {
        _userStop = true;
        _socket->abort();
        _setState(QStringLiteral("failed"), tr("The login data is too long. Shorten the vehicle number, password or RTK account."));
        return;
    }
    line.append('\n');
    _socket->write(line);
    _loginTimer.start();    // 5 s for the answer
}

void HHU4GLink::_onReadyRead()
{
    const QByteArray data = _socket->readAll();
    if (_loggedIn) {
        if (_client) {
            _client->write(data);
        }
        return;
    }
    _lineBuffer.append(data);
    const int nl = _lineBuffer.indexOf('\n');
    if (nl < 0) {
        if (_lineBuffer.size() > kMaxLoginLine * 4) {
            _socket->abort();
        }
        return;
    }
    const QByteArray line = _lineBuffer.left(nl);
    const QByteArray rest = _lineBuffer.mid(nl + 1);
    _lineBuffer.clear();
    _handleLoginResult(line);
    if (_loggedIn && !rest.isEmpty() && _client) {
        _client->write(rest);
    }
}

void HHU4GLink::_handleLoginResult(const QByteArray &line)
{
    _loginTimer.stop();
    const QJsonObject result = QJsonDocument::fromJson(line).object();
    const bool ok = result.value(QStringLiteral("ok")).toBool();
    const int code = result.value(QStringLiteral("code")).toInt(-1);
    const bool ntripUpdate = !_pendingNtrip.isEmpty();

    if (result.value(QStringLiteral("type")).toString() != QStringLiteral("auth_result")) {
        _socket->abort();
        _setState(QStringLiteral("failed"), tr("The server did not answer the login correctly."));
        return;
    }

    if (ntripUpdate) {
        const bool saved = ok && result.value(QStringLiteral("ntrip_saved")).toBool();
        _pendingNtrip.clear();
        _linkMonitor->setSuppressLoss(false);
        emit ntripUpdateFinished(saved, saved ? tr("The RTK account was updated.") : tr("The RTK account could not be updated."));
    }

    if (ok) {
        _loggedIn = true;
        _retryDelaySec = 0;
        _readOnly = result.value(QStringLiteral("access")).toString() == QStringLiteral("readonly");
        _startBridge();
        _setState(QStringLiteral("online"), _readOnly ? tr("Another ground station controls this vehicle, read only") : tr("Connected"));
        return;
    }

    switch (code) {
    case 1:
        _userStop = true;
        _setState(QStringLiteral("failed"), tr("Wrong vehicle number or password"));
        break;
    case 2:
        _setState(QStringLiteral("retrying"), tr("The vehicle is offline. Check the vehicle power and 4G signal."));
        break;
    case 4:
        _userStop = true;
        _setState(QStringLiteral("failed"), tr("Please upgrade the ground station software"));
        break;
    default: {
        const QString msg = result.value(QStringLiteral("msg")).toString();
        _setState(QStringLiteral("retrying"), msg.isEmpty() ? tr("Server error (code %1)").arg(code) : msg);
        break;
    }
    }
    _socket->abort();
}

void HHU4GLink::_onLoginTimeout()
{
    if (_socket && !_loggedIn) {
        qCDebug(HHU4GLog) << "login timeout";
        _setState(QStringLiteral("retrying"), tr("No answer from the server"));
        _socket->abort();
        _onDisconnected();
    }
}

void HHU4GLink::_onDisconnected()
{
    // abort() can report both disconnected and errorOccurred: handle the loss once per socket
    if (!_socket || _activeIndex < 0 || _lossHandled) {
        return;
    }
    _lossHandled = true;
    _loginTimer.stop();
    const bool wasOnline = _loggedIn;
    _loggedIn = false;
    if (_userStop) {
        if (_state != QStringLiteral("failed")) {
            _setState(QStringLiteral("idle"), QString());
        }
        if (!_pendingNtrip.isEmpty()) {
            _pendingNtrip.clear();
            _linkMonitor->setSuppressLoss(false);
            emit ntripUpdateFinished(false, _statusText);
        }
        return;
    }
    if (!_pendingNtrip.isEmpty() && wasOnline) {
        // Deliberate re-login with the RTK account: reconnect right away
        QTimer::singleShot(0, this, &HHU4GLink::_openSocket);
        return;
    }
    if (!_pendingNtrip.isEmpty()) {
        _pendingNtrip.clear();
        _linkMonitor->setSuppressLoss(false);
        emit ntripUpdateFinished(false, tr("No connection to the server"));
    }
    if (_state != QStringLiteral("retrying")) {
        _setState(QStringLiteral("retrying"), tr("Connection to the server lost"));
    }
    _scheduleRetry();
}

void HHU4GLink::_scheduleRetry()
{
    _retryDelaySec = _retryDelaySec == 0 ? 2 : std::min(_retryDelaySec * 2, kMaxRetrySec);
    _retryTimer.start(_retryDelaySec * 1000);
    _retryTick.start();
    emit retryChanged();
}

void HHU4GLink::updateNtrip(const QVariantMap &ntrip)
{
    if (!_loggedIn || !_socket) {
        emit ntripUpdateFinished(false, tr("The 4G connection is not online"));
        return;
    }
    if (_readOnly) {
        emit ntripUpdateFinished(false, tr("Read-only connection: the RTK account cannot be changed"));
        return;
    }
    _pendingNtrip = ntrip;
    _linkMonitor->setSuppressLoss(true);    // not a link loss (需求说明 §4.2)
    _socket->disconnectFromHost();
}

// ---- Local bridge to QGC ------------------------------------------------------------------

void HHU4GLink::_startBridge()
{
    if (_server) {
        return;
    }
    _server = new QTcpServer(this);
    if (!_server->listen(QHostAddress::LocalHost, 0)) {
        qCWarning(HHU4GLog) << "cannot listen on localhost" << _server->errorString();
        _setState(QStringLiteral("failed"), tr("Internal error: %1").arg(_server->errorString()));
        return;
    }
    (void) connect(_server, &QTcpServer::newConnection, this, &HHU4GLink::_onBridgeClient);

    const QString name = QStringLiteral("4G %1").arg(_config(_activeIndex).value(QStringLiteral("name")).toString());
    auto *config = new TCPConfiguration(name);
    config->setHost(QStringLiteral("127.0.0.1"));
    config->setPort(_server->serverPort());
    config->setDynamic(true);
    SharedLinkConfigurationPtr shared = LinkManager::instance()->addConfiguration(config);
    _qgcConfig = config;
    (void) LinkManager::instance()->createConnectedLink(shared);
}

void HHU4GLink::_onBridgeClient()
{
    QTcpSocket *client = _server->nextPendingConnection();
    if (_client) {
        _client->abort();
    }
    _client = client;
    client->setSocketOption(QAbstractSocket::LowDelayOption, 1);
    (void) connect(client, &QTcpSocket::readyRead, this, [this, client]() {
        const QByteArray data = client->readAll();
        if (_loggedIn && _socket) {
            _socket->write(data);   // dropped while offline, like a radio out of range
        }
    });
    (void) connect(client, &QTcpSocket::disconnected, client, &QObject::deleteLater);
}

void HHU4GLink::_stopBridge()
{
    if (_qgcConfig) {
        LinkManager::instance()->disconnectLinkConfiguration(_qgcConfig);
        LinkManager::instance()->removeConfiguration(_qgcConfig);
    }
    if (_client) {
        _client->abort();
    }
    if (_server) {
        _server->close();
        _server->deleteLater();
        _server = nullptr;
    }
}
