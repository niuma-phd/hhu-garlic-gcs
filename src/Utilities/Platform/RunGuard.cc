#include "RunGuard.h"

#include <QtCore/QCryptographicHash>
#include <QtCore/QDebug>
#include <QtCore/QDir>
#include <QtCore/QStandardPaths>

RunGuard::RunGuard(const QString &key)
    : _key(key)
    , _lockFilePath(lockDir() + QLatin1String("/qgc-") + generateKeyHash(key, QLatin1String("_lock")) + QLatin1String(".lock"))
    , _lockFile(_lockFilePath)
{
    // Recover instantly from stale locks after crashes.
    _lockFile.setStaleLockTime(0);
}

RunGuard::~RunGuard()
{
    release();
}

bool RunGuard::isAnotherRunning()
{
    if (_lockFile.isLocked()) {
        return false;
    }

    if (_lockFile.tryLock(0)) {
        _lockFile.unlock();
        return false;
    }

    switch (_lockFile.error()) {
    case QLockFile::NoError:
        return false;
    case QLockFile::LockFailedError:
        return true;
    case QLockFile::PermissionError:
        qWarning() << "QLockFile PermissionError: Unable to access lock file at" << _lockFile.fileName();
        break;
    case QLockFile::UnknownError:
        qWarning() << "QLockFile UnknownError: An unknown error occurred with lock file at" << _lockFile.fileName();
        break;
    default:
        break;
    }

    return true;
}

bool RunGuard::tryToRun()
{
    if (_lockFile.isLocked()) {
        return true;
    }

    if (_lockFile.tryLock(0)) {
        return true;
    }

    // Only LockFailedError means another process really holds the lock. PermissionError
    // (the lock file cannot be created in the temp directory) and UnknownError mean the
    // lock file is unusable — that must not stop the application, since single-instance is
    // a convenience for the user, not a safety function. Report the real reason instead of
    // letting the caller turn every failure into "another instance is already running".
    if (_lockFile.error() != QLockFile::LockFailedError) {
        qWarning() << "RunGuard: unusable single-instance lock file" << _lockFile.fileName()
                   << "error" << int(_lockFile.error())
                   << "- continuing without single-instance protection";
        return true;
    }

    return false;
}

void RunGuard::release()
{
    if (_lockFile.isLocked()) {
        _lockFile.unlock();
    }
}

QString RunGuard::generateKeyHash(const QString &key, const QString &salt)
{
    QByteArray data;
    (void) data.append(key.toUtf8());
    (void) data.append(salt.toUtf8());
    const QByteArray hex = QCryptographicHash::hash(data, QCryptographicHash::Sha1).toHex();
    return QString::fromLatin1(hex);
}

QString RunGuard::lockDir()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (dir.isEmpty()) {
        dir = QDir::tempPath();
    }

    if (!QDir().mkpath(dir)) {
        qWarning() << "RunGuard: Failed to create lock directory:" << dir;
        return QString();
    }

    return dir;
}
