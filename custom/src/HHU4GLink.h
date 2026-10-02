#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtNetwork/QSslSocket>

class HHULinkMonitor;
class LinkConfiguration;
class QTcpServer;
class QTcpSocket;

/// 4G 连接 (需求说明 V1.0 §4.2): TCP (optionally TLS) to the relay server, one JSON login line,
/// then a raw MAVLink v2 byte stream.
///
/// QGC itself is not changed: once logged in, this class listens on 127.0.0.1 and creates a QGC
/// TCP link named "4G …" to that port, relaying bytes in both directions. When the server
/// connection drops, the local link stays and simply goes quiet (QGC / hhuLink report the loss),
/// while this class re-connects with back-off 2, 4, 8 … 30 s and logs in again each time.
/// Exposed to QML as hhu4G.
class HHU4GLink : public QObject
{
    Q_OBJECT
    /// Saved connection settings: [{ name, host, port, tls, caFile, vehicle, hasPassword }]
    Q_PROPERTY(QVariantList configs     READ configs        NOTIFY configsChanged)
    /// Index of the config in use, -1 when the 4G connection is off
    Q_PROPERTY(int          activeIndex READ activeIndex    NOTIFY stateChanged)
    /// "idle", "connecting", "online", "retrying", "failed"
    Q_PROPERTY(QString      state       READ state          NOTIFY stateChanged)
    /// Customer text for the current state / last error
    Q_PROPERTY(QString      statusText  READ statusText     NOTIFY stateChanged)
    /// Server granted read-only access (another GCS controls the vehicle)
    Q_PROPERTY(bool         readOnly    READ readOnly       NOTIFY stateChanged)
    Q_PROPERTY(bool         active      READ active         NOTIFY stateChanged)
    /// Seconds until the next reconnect attempt (state "retrying")
    Q_PROPERTY(int          retryInSec  READ retryInSec     NOTIFY retryChanged)

public:
    HHU4GLink(HHULinkMonitor *linkMonitor, QObject *parent = nullptr);
    ~HHU4GLink() override;

    QVariantList configs() const;
    int     activeIndex() const { return _activeIndex; }
    QString state() const { return _state; }
    QString statusText() const { return _statusText; }
    bool    readOnly() const { return _readOnly; }
    bool    active() const { return _activeIndex >= 0; }
    int     retryInSec() const;

    /// index -1 adds a new config. config: name, host, port, tls, caFile, vehicle, password
    /// (password "" keeps the saved one). Returns the index.
    Q_INVOKABLE int saveConfig(int index, const QVariantMap &config);
    Q_INVOKABLE void removeConfig(int index);
    Q_INVOKABLE void connectTo(int index);
    Q_INVOKABLE void disconnectLink();
    /// Re-logs in with the RTK account attached (fields host, port, user, password, mount);
    /// the result arrives as ntripUpdateFinished
    Q_INVOKABLE void updateNtrip(const QVariantMap &ntrip);
    /// Server host of the active (or first) config, for the update / log upload service
    Q_INVOKABLE QString serverHost() const;
    /// CA certificate file of the active (or first) config, so the update / log upload service
    /// trusts the same server certificate as the 4G connection ("" = no TLS). Without an own file
    /// the relay server CA built into the program is used.
    Q_INVOKABLE QString caFile() const;
    /// The relay server CA built into the program (出厂预设)
    static QString builtInCa() { return QStringLiteral(":/hhu/config/relay_ca.crt"); }
    Q_INVOKABLE QVariantMap credentials() const;

    /// Connects the last used 4G config if the 4G connection was on when the GCS closed
    void autoStart();

signals:
    void configsChanged();
    void stateChanged();
    void retryChanged();
    void ntripUpdateFinished(bool ok, const QString &message);

private:
    void _setState(const QString &state, const QString &text);
    void _openSocket();
    void _onConnected();
    void _onReadyRead();
    void _onDisconnected();
    void _onLoginTimeout();
    void _handleLoginResult(const QByteArray &line);
    void _scheduleRetry();
    void _startBridge();
    void _stopBridge();
    void _onBridgeClient();
    void _loadConfigs();
    void _saveConfigs();
    QVariantMap _config(int index) const;

    HHULinkMonitor         *_linkMonitor = nullptr;
    QVariantList            _configs;       ///< stored form (password protected)
    int                     _activeIndex = -1;
    QString                 _state = QStringLiteral("idle");
    QString                 _statusText;
    bool                    _readOnly = false;
    bool                    _loggedIn = false;
    bool                    _userStop = false;
    bool                    _lossHandled = false;
    QVariantMap             _pendingNtrip;
    int                     _retryDelaySec = 0;
    QByteArray              _lineBuffer;
    QString                 _clientId;

    QSslSocket             *_socket = nullptr;
    QTimer                  _loginTimer;
    QTimer                  _retryTimer;
    QTimer                  _retryTick;
    QTcpServer             *_server = nullptr;
    QPointer<QTcpSocket>    _client;
    QPointer<LinkConfiguration> _qgcConfig;
};
