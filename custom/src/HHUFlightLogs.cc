#include "HHUFlightLogs.h"
#include "HHU4GLink.h"
#include "HHUTuning.h"
#include "AppSettings.h"
#include "FTPManager.h"
#include "MultiVehicleManager.h"
#include "QGCLoggingCategory.h"
#include "SettingsManager.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <algorithm>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QUrl>
#include <QtGui/QDesktopServices>

QGC_LOGGING_CATEGORY(HHUFlightLogsLog, "Custom.HHUFlightLogs")

namespace {
/// Log directory on the SD card (ChibiOS) and in the SITL working directory
const QStringList kDirectories = { QStringLiteral("/APM/LOGS"), QStringLiteral("logs") };
const QString kPart = QStringLiteral(".part");

QString ftpReason(const QString &error)
{
    const int dash = error.lastIndexOf(QStringLiteral(" - "));
    QString reason = dash >= 0 ? error.mid(dash + 3) : error;
    if (reason.contains(QStringLiteral("no response"), Qt::CaseInsensitive)) {
        return HHUFlightLogs::tr("no answer from the vehicle");
    }
    return reason;
}

int logNumber(const QString &name)
{
    bool ok = false;
    const int n = QFileInfo(name).completeBaseName().toInt(&ok);
    return ok ? n : -1;
}

QString sizeText(double bytes)
{
    if (bytes >= 1024.0 * 1024.0) return QStringLiteral("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    return QStringLiteral("%1 KB").arg(qMax(1.0, bytes / 1024.0), 0, 'f', 0);
}
} // namespace

HHUFlightLogs::HHUFlightLogs(HHU4GLink *link4G, HHUTuning *tuning, QObject *parent)
    : QObject(parent)
    , _link4G(link4G)
    , _tuning(tuning)
{
    (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, &HHUFlightLogs::_setVehicle);
    (void) connect(_link4G, &HHU4GLink::stateChanged, this, &HHUFlightLogs::stateChanged);
    _setVehicle(MultiVehicleManager::instance()->activeVehicle());
}

// ---- State --------------------------------------------------------------------------------------------

bool HHUFlightLogs::connected() const
{
    return _vehicle && !_vehicle->vehicleLinkManager()->communicationLost();
}

QString HHUFlightLogs::busyText() const
{
    if (!_busy) {
        return QString();
    }
    if (_queueTotal > 1) {
        return QStringLiteral("%1 (%2 / %3)").arg(_label).arg(_done + 1).arg(_queueTotal);
    }
    return _label;
}

QString HHUFlightLogs::speedText() const
{
    if (_progress < 0 || _wait != Wait::Download || !_fileClock.isValid() || _fileClock.elapsed() < 1000) {
        return QString();
    }
    const double size = static_cast<double>(_sizeOf(_current));
    const double done = _progress * size;
    const double speed = done / (_fileClock.elapsed() / 1000.0);
    if (speed <= 0) {
        return QString();
    }
    // the rest of this file and of the queue
    double rest = size - done;
    for (const QString &name : _queue) {
        rest += static_cast<double>(_sizeOf(name));
    }
    const int seconds = qRound(rest / speed);
    return tr("%1/s · %2:%3 left").arg(sizeText(speed)).arg(seconds / 60).arg(seconds % 60, 2, 10, QLatin1Char('0'));
}

bool HHUFlightLogs::canTransfer() const
{
    return connected() && !_busy && !_vehicle->armed();
}

QString HHUFlightLogs::blockReason() const
{
    if (!connected() || _busy) {
        return QString();
    }
    if (_vehicle->armed()) {
        return tr("Disarm the vehicle to download logs");
    }
    return QString();
}

int HHUFlightLogs::pendingCount() const
{
    return static_cast<int>(std::count_if(_files.cbegin(), _files.cend(), [](const QVariant &f) { return !f.toMap().value("downloaded").toBool(); }));
}

double HHUFlightLogs::pendingBytes() const
{
    double sum = 0;
    for (const QVariant &f : _files) {
        if (!f.toMap().value("downloaded").toBool()) {
            sum += f.toMap().value("size").toDouble();
        }
    }
    return sum;
}

qint64 HHUFlightLogs::_sizeOf(const QString &name) const
{
    for (const QVariant &f : _files) {
        if (f.toMap().value("name").toString() == name) {
            return f.toMap().value("size").toLongLong();
        }
    }
    return 0;
}

QString HHUFlightLogs::folder() const
{
    const QString savePath = SettingsManager::instance()->appSettings()->savePath()->rawValue().toString();
    QString name = _tuning ? _tuning->vehicleName() : QString();
    if (name.isEmpty()) {
        name = QStringLiteral("unknown");
    }
    return QDir(savePath).filePath(QStringLiteral("飞控日志/") + name);
}

void HHUFlightLogs::openFolder() const
{
    const QString dir = folder();
    (void) QDir().mkpath(dir);
    (void) QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}

void HHUFlightLogs::setActive(bool active)
{
    if (active == _active) {
        return;
    }
    _active = active;
    emit activeChanged();
    if (_active) {
        refresh();
    }
}

void HHUFlightLogs::_setVehicle(Vehicle *vehicle)
{
    if (vehicle == _vehicle) {
        return;
    }
    if (_vehicle) {
        (void) disconnect(_vehicle, nullptr, this, nullptr);
        (void) disconnect(_vehicle->vehicleLinkManager(), nullptr, this, nullptr);
        (void) disconnect(_vehicle->ftpManager(), nullptr, this, nullptr);
    }
    _vehicle = vehicle;
    _wait = Wait::None;
    _busy = false;
    _queue.clear();
    _directory.clear();
    _files.clear();
    _setMessage(QString(), false);

    if (_vehicle) {
        FTPManager *ftp = _vehicle->ftpManager();
        (void) connect(ftp, &FTPManager::listDirectoryComplete, this, &HHUFlightLogs::_onListComplete);
        (void) connect(ftp, &FTPManager::downloadComplete, this, &HHUFlightLogs::_onDownloadComplete);
        (void) connect(ftp, &FTPManager::deleteComplete, this, &HHUFlightLogs::_onDeleteComplete);
        (void) connect(ftp, &FTPManager::commandProgress, this, &HHUFlightLogs::_onProgress);
        (void) connect(_vehicle, &Vehicle::armedChanged, this, &HHUFlightLogs::stateChanged);
        (void) connect(_vehicle->vehicleLinkManager(), &VehicleLinkManager::communicationLostChanged, this, [this](bool lost) {
            // a running transfer fails by itself (no answer); list again once the link is back
            if (lost) {
                _listAfterReconnect = _active;
            } else if (_listAfterReconnect && !_busy) {
                _listAfterReconnect = false;
                _relist();
            }
            emit stateChanged();
        });
        if (_active) {
            refresh();
        }
    }
    emit filesChanged();
    emit stateChanged();
}

void HHUFlightLogs::_setMessage(const QString &text, bool error)
{
    _message = text;
    _messageError = error;
    emit messageChanged();
}

void HHUFlightLogs::_setBusy(bool busy, const QString &label)
{
    _busy = busy;
    _label = label;
    if (!busy) {
        _wait = Wait::None;
        _progress = -1;
        _queueTotal = 0;
        emit progressChanged();
    }
    emit stateChanged();
}

void HHUFlightLogs::_finish(const QString &text, bool error)
{
    if (error) {
        qCWarning(HHUFlightLogsLog) << text;
    }
    _queue.clear();
    _setBusy(false);
    _setMessage(text, error);
}

// ---- Listing ------------------------------------------------------------------------------------------

void HHUFlightLogs::refresh()
{
    if (!connected() || _busy) {
        return;
    }
    _setMessage(QString(), false);
    _relist();
}

/// Lists again keeping the message (after deleting, after reconnecting)
void HHUFlightLogs::_relist()
{
    if (!connected() || _busy) {
        return;
    }
    _setBusy(true, tr("Listing"));
    _list(0);
}

void HHUFlightLogs::_list(int candidate)
{
    QStringList directories = kDirectories;
    if (!_directory.isEmpty()) {
        directories.removeAll(_directory);
        directories.prepend(_directory);
    }
    if (candidate >= directories.count()) {
        _directory.clear();
        _files.clear();
        emit filesChanged();
        _finish(tr("No log directory on the autopilot (no SD card?)"), true);
        return;
    }
    _listCandidate = candidate;
    if (!_vehicle->ftpManager()->listDirectory(MAV_COMP_ID_AUTOPILOT1, directories.at(candidate))) {
        _finish(tr("File transfer busy, try again"), true);
        return;
    }
    _directory = directories.at(candidate);
    _wait = Wait::List;
}

void HHUFlightLogs::_onListComplete(const QStringList &entries, const QString &error)
{
    if (_wait != Wait::List) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty()) {
        if (!connected()) {
            _finish(tr("No answer from the vehicle"), true);
            return;
        }
        _list(_listCandidate + 1);
        return;
    }
    // "F<name>\t<size>[\t<time>]"; only the .BIN logs
    QVariantList files;
    int newest = -1;
    for (const QString &entry : entries) {
        if (!entry.startsWith(QLatin1Char('F'))) {
            continue;
        }
        const QStringList parts = entry.mid(1).split(QLatin1Char('\t'));
        const QString name = parts.value(0);
        if (!name.endsWith(QStringLiteral(".BIN"), Qt::CaseInsensitive)) {
            continue;
        }
        newest = std::max(newest, logNumber(name));
        files.append(QVariantMap{ { "name", name }, { "size", parts.value(1).toLongLong() } });
    }
    std::sort(files.begin(), files.end(), [](const QVariant &a, const QVariant &b) {
        return logNumber(a.toMap().value("name").toString()) > logNumber(b.toMap().value("name").toString());
    });
    for (QVariant &f : files) {
        QVariantMap m = f.toMap();
        m["newest"] = logNumber(m.value("name").toString()) == newest;
        f = m;
    }
    _files = files;
    _markDownloaded();
    qCDebug(HHUFlightLogsLog) << "listed" << _directory << _files.count() << "logs";
    _setBusy(false);
}

void HHUFlightLogs::_markDownloaded()
{
    const QDir dir(folder());
    for (QVariant &f : _files) {
        QVariantMap m = f.toMap();
        const QFileInfo local(dir.filePath(m.value("name").toString()));
        m["downloaded"] = local.exists() && local.size() == m.value("size").toLongLong();
        f = m;
    }
    emit filesChanged();
}

// ---- Download -----------------------------------------------------------------------------------------

void HHUFlightLogs::download(const QStringList &names)
{
    if (!canTransfer()) {
        return;
    }
    QStringList queue = names;
    if (queue.isEmpty()) {
        // every log not downloaded yet, oldest first
        for (auto it = _files.crbegin(); it != _files.crend(); ++it) {
            if (!it->toMap().value("downloaded").toBool()) {
                queue << it->toMap().value("name").toString();
            }
        }
    }
    if (queue.isEmpty()) {
        _setMessage(tr("All logs are downloaded"), false);
        return;
    }
    if (!QDir().mkpath(folder())) {
        _setMessage(tr("Cannot create %1").arg(QDir::toNativeSeparators(folder())), true);
        return;
    }
    _queue = queue;
    _queueTotal = static_cast<int>(queue.size());
    _done = 0;
    _doneBytes = 0;
    _cancelled = false;
    _setMessage(QString(), false);
    _runClock.start();
    _setBusy(true, QString());
    _downloadNext();
}

void HHUFlightLogs::_downloadNext()
{
    if (_queue.isEmpty()) {
        const double seconds = qMax(1.0, _runClock.elapsed() / 1000.0);
        _finish(tr("%1 logs downloaded (%2, %3/s)").arg(_done).arg(sizeText(_doneBytes)).arg(sizeText(_doneBytes / seconds)), false);
        return;
    }
    if (!connected()) {
        _finish(tr("Connection lost, %1 of %2 logs downloaded").arg(_done).arg(_queueTotal), true);
        return;
    }
    _current = _queue.takeFirst();
    _label = tr("Downloading %1").arg(_current);
    _partFile = QDir(folder()).absoluteFilePath(_current + kPart);
    QFile::remove(_partFile);
    _progress = 0;
    _fileClock.start();
    if (!_vehicle->ftpManager()->download(MAV_COMP_ID_AUTOPILOT1, _directory + QLatin1Char('/') + _current, folder(), _current + kPart, true)) {
        _finish(tr("File transfer busy, try again"), true);
        return;
    }
    _wait = Wait::Download;
    emit stateChanged();
    emit progressChanged();
}

void HHUFlightLogs::_onDownloadComplete(const QString &file, const QString &error)
{
    if (_wait != Wait::Download || QFileInfo(file).absoluteFilePath() != _partFile) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty() || _cancelled) {
        QFile::remove(_partFile);
        _markDownloaded();
        if (_cancelled) {
            _finish(tr("Cancelled, %1 of %2 logs downloaded").arg(_done).arg(_queueTotal), false);
        } else {
            _finish(tr("%1: download failed (%2), %3 of %4 logs downloaded").arg(_current, ftpReason(error)).arg(_done).arg(_queueTotal), true);
        }
        return;
    }
    const qint64 expected = _sizeOf(_current);
    const qint64 got = QFileInfo(_partFile).size();
    if (expected > 0 && got != expected) {
        QFile::remove(_partFile);
        _finish(tr("%1: size %2 instead of %3 bytes, not kept").arg(_current).arg(got).arg(expected), true);
        _markDownloaded();
        return;
    }
    const QString target = QDir(folder()).absoluteFilePath(_current);
    QFile::remove(target);
    if (!QFile::rename(_partFile, target)) {
        _finish(tr("Cannot write %1").arg(QDir::toNativeSeparators(target)), true);
        return;
    }
    _done++;
    _doneBytes += got;
    qCDebug(HHUFlightLogsLog) << "downloaded" << _current << got << "bytes in" << _fileClock.elapsed() << "ms";
    _markDownloaded();
    _downloadNext();
}

void HHUFlightLogs::cancel()
{
    if (_wait == Wait::Download && _vehicle) {
        _cancelled = true;
        _queue.clear();
        _vehicle->ftpManager()->cancelDownload();
    }
}

void HHUFlightLogs::_onProgress(float value)
{
    if (_wait != Wait::Download) {
        return;
    }
    _progress = qBound(0.0, static_cast<double>(value), 1.0);
    emit progressChanged();
}

// ---- Delete -------------------------------------------------------------------------------------------

void HHUFlightLogs::removeDownloaded(const QStringList &names)
{
    if (!canTransfer() || _link4G->readOnly()) {
        if (_link4G->readOnly()) _setMessage(tr("Read-only connection"), true);
        return;
    }
    QStringList queue;
    for (const QVariant &f : _files) {
        const QVariantMap m = f.toMap();
        const QString name = m.value("name").toString();
        if ((names.isEmpty() || names.contains(name)) && m.value("downloaded").toBool() && !m.value("newest").toBool()) {
            queue << name;
        }
    }
    if (queue.isEmpty()) {
        _setMessage(tr("Nothing to delete: only downloaded logs, never the newest one"), false);
        return;
    }
    _queue = queue;
    _queueTotal = static_cast<int>(queue.size());
    _done = 0;
    _setMessage(QString(), false);
    _setBusy(true, QString());
    _deleteNext();
}

void HHUFlightLogs::_deleteNext()
{
    if (_queue.isEmpty()) {
        const int deleted = _done;
        _setBusy(false);
        _setMessage(tr("%1 logs deleted on the vehicle").arg(deleted), false);
        _relist();
        return;
    }
    _current = _queue.takeFirst();
    _label = tr("Deleting %1").arg(_current);
    if (!_vehicle->ftpManager()->deleteFile(MAV_COMP_ID_AUTOPILOT1, _directory + QLatin1Char('/') + _current)) {
        _finish(tr("File transfer busy, try again"), true);
        return;
    }
    _wait = Wait::Delete;
    emit stateChanged();
}

void HHUFlightLogs::_onDeleteComplete(const QString &, const QString &error)
{
    if (_wait != Wait::Delete) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty()) {
        const int deleted = _done;
        _finish(tr("%1: delete failed (%2), %3 deleted").arg(_current, ftpReason(error)).arg(deleted), true);
        _relist();
        return;
    }
    _done++;
    _deleteNext();
}
