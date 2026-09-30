#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>

class HHUConfig;
class QTcpSocket;

/// RTK 差分 account (需求说明 V1.0 §3.5).
/// - Provider presets from hhu_config.json ("ntripProviders").
/// - 测试连接: logs in to the caster directly and classifies the answer.
/// - Account kept here with the password encrypted (HHUSecret). For serial / UDP / TCP / Bluetooth links
///   it is handed to QGC's own NTRIP client (RTCM forwarding, GGA every 5 s, reconnect) at start-up;
///   QGC's stored copy of the password is wiped again when the program closes.
/// - With a 4G connection the ground station does not forward corrections; the account goes to the
///   server instead (HHU4GLink::updateNtrip, done by the QML page).
/// Exposed to QML as hhuNtrip.
class HHUNtrip : public QObject
{
    Q_OBJECT
    /// [{ name, host, port }] 千寻 / 六分 / 中国移动 …, the page adds 自定义
    Q_PROPERTY(QVariantList providers   READ providers  CONSTANT)
    /// Saved account: { provider, host, port, user, mount, hasPassword } (empty map = none)
    Q_PROPERTY(QVariantMap  account     READ account    NOTIFY accountChanged)
    Q_PROPERTY(bool         testing     READ testing    NOTIFY testingChanged)
    Q_PROPERTY(QStringList  mountpoints READ mountpoints NOTIFY mountpointsChanged)

public:
    HHUNtrip(HHUConfig *config, QObject *parent = nullptr);

    QVariantList providers() const { return _providers; }
    QVariantMap account() const;
    bool testing() const { return !_socket.isNull(); }
    QStringList mountpoints() const { return _mountpoints; }

    /// Result through testFinished(code, message); code: "ok", "auth", "mount", "network"
    Q_INVOKABLE void test(const QString &host, int port, const QString &user, const QString &password, const QString &mount);
    /// Mountpoint list of a caster through mountpointsChanged / testFinished on error
    Q_INVOKABLE void fetchMountpoints(const QString &host, int port, const QString &user, const QString &password);
    Q_INVOKABLE void cancel();
    /// Stores the account (password "" keeps the saved one)
    Q_INVOKABLE void save(const QVariantMap &account);
    /// Removes the saved account and stops QGC's NTRIP client
    Q_INVOKABLE void clear();
    /// Password of the saved account (for the 4G server update)
    Q_INVOKABLE QString password() const;
    /// Serial / UDP / TCP / Bluetooth: forward corrections from this computer; 4G: the server does it
    Q_INVOKABLE void applyForwarding(bool forwardHere);

signals:
    void accountChanged();
    void testingChanged();
    void mountpointsChanged();
    void testFinished(const QString &code, const QString &message);

private:
    void _request(const QString &host, int port, const QString &user, const QString &password, const QString &path, bool listMode);
    void _finish(const QString &code, const QString &message);
    void _wipeQgcPassword();

    QVariantList            _providers;
    QStringList             _mountpoints;
    QPointer<QTcpSocket>    _socket;
    QByteArray              _reply;
    bool                    _listMode = false;
    QTimer                  _timeout;
};
