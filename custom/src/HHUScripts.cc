#include "HHUScripts.h"
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

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QRegularExpression>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtGui/QDesktopServices>

QGC_LOGGING_CATEGORY(HHUScriptsLog, "Custom.HHUScripts")

namespace {
/// FTPManager's error ("Upload failed for: <path> - no response from vehicle") without the repeated
/// operation and path
QString ftpReason(const QString &error)
{
    const int dash = error.lastIndexOf(QStringLiteral(" - "));
    QString reason = dash >= 0 ? error.mid(dash + 3) : error;
    if (reason.contains(QStringLiteral("no response"), Qt::CaseInsensitive)) {
        return HHUScripts::tr("no answer from the vehicle");
    }
    return reason;
}

/// Scripts directory on the SD card (ChibiOS) and in the SITL working directory
const QStringList kDirectories = { QStringLiteral("/APM/scripts"), QStringLiteral("scripts") };
constexpr qint64 kMaxSize = 512 * 1024;
const QString kNewSuffix = QStringLiteral(".new");

QString localPath(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}

QString timeStamp()
{
    return QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
}
}

HHUScripts::HHUScripts(HHU4GLink *link4G, HHUTuning *tuning, QObject *parent)
    : QObject(parent)
    , _link4G(link4G)
    , _tuning(tuning)
{
    (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, &HHUScripts::_setVehicle);
    (void) connect(_link4G, &HHU4GLink::stateChanged, this, &HHUScripts::stateChanged);
    _setVehicle(MultiVehicleManager::instance()->activeVehicle());
}

// ---------------------------------------------------------------------------------------------
// State

bool HHUScripts::connected() const
{
    return _vehicle && !_vehicle->vehicleLinkManager()->communicationLost();
}

QString HHUScripts::busyText() const
{
    if (!_busy) {
        return QString();
    }
    return _progress >= 0 ? QStringLiteral("%1 %2%").arg(_label).arg(qRound(_progress * 100)) : _label;
}

bool HHUScripts::canModify() const
{
    return connected() && !_busy && !_link4G->readOnly() && !_vehicle->armed();
}

QString HHUScripts::blockReason() const
{
    if (!connected() || _busy) {
        return QString();
    }
    if (_link4G->readOnly()) {
        return tr("Read-only connection");
    }
    if (_vehicle->armed()) {
        return tr("Disarm the vehicle to change scripts");
    }
    return QString();
}

void HHUScripts::setActive(bool active)
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

void HHUScripts::_setVehicle(Vehicle *vehicle)
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
    _steps.clear();
    _wait = Wait::None;
    _busy = false;
    _restartNeeded = false;
    _directory.clear();
    _files.clear();
    _setMessage(QString(), false);

    if (_vehicle) {
        FTPManager *ftp = _vehicle->ftpManager();
        (void) connect(ftp, &FTPManager::listDirectoryComplete, this, &HHUScripts::_onListComplete);
        (void) connect(ftp, &FTPManager::downloadComplete, this, &HHUScripts::_onDownloadComplete);
        (void) connect(ftp, &FTPManager::uploadComplete, this, &HHUScripts::_onUploadComplete);
        (void) connect(ftp, &FTPManager::deleteComplete, this, &HHUScripts::_onDeleteComplete);
        (void) connect(ftp, &FTPManager::renameComplete, this, &HHUScripts::_onRenameComplete);
        (void) connect(ftp, &FTPManager::commandProgress, this, &HHUScripts::_onProgress);
        (void) connect(_vehicle, &Vehicle::armedChanged, this, &HHUScripts::stateChanged);
        (void) connect(_vehicle->vehicleLinkManager(), &VehicleLinkManager::communicationLostChanged, this, [this](bool lost) {
            // A running operation fails by itself (no answer); list again once the link is back
            if (lost) {
                _listAfterReconnect = _active;
            } else if (_listAfterReconnect && !_busy) {
                // Keeps the message (the change that failed when the link went)
                _listAfterReconnect = false;
                _quiet = true;
                _start(tr("Listing"), { [this]() { _list(0); } });
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

void HHUScripts::_setMessage(const QString &text, bool error)
{
    _message = text;
    _messageError = error;
    emit messageChanged();
}

bool HHUScripts::exists(const QString &name) const
{
    return std::any_of(_files.cbegin(), _files.cend(), [&name](const QVariant &file) {
        return file.toMap().value(QStringLiteral("name")).toString() == name;
    });
}

QString HHUScripts::localPath(const QString &localPathOrUrl) const
{
    return QDir::toNativeSeparators(::localPath(localPathOrUrl));
}

QString HHUScripts::fileName(const QString &localPathOrUrl) const
{
    return QFileInfo(localPath(localPathOrUrl)).fileName();
}

/// FAT on the SD card, the path goes into one MAVFTP request: plain ASCII names
QString HHUScripts::checkName(const QString &name) const
{
    static const QRegularExpression valid(QStringLiteral("^[A-Za-z0-9_.-]{1,60}$"));
    if (!valid.match(name).hasMatch()) {
        return tr("File names may only contain letters, digits, _ . -");
    }
    if (!name.endsWith(QStringLiteral(".lua"), Qt::CaseInsensitive)) {
        return tr("Only .lua files");
    }
    return QString();
}

QString HHUScripts::_path(const QString &name) const
{
    return _directory + QLatin1Char('/') + name;
}

// ---------------------------------------------------------------------------------------------
// Operations: a list of steps, each one MAVFTP command whose completion runs the next step

void HHUScripts::_start(const QString &label, const QList<Step> &steps)
{
    _busy = true;
    _label = label;
    _progress = -1;
    _steps = steps;
    emit stateChanged();
    _next();
}

void HHUScripts::_next()
{
    _wait = Wait::None;
    _ignoreError = false;
    _progress = -1;
    if (_steps.isEmpty()) {
        _busy = false;
        _quiet = false;
        emit stateChanged();
        return;
    }
    const Step step = _steps.takeFirst();
    step();
    emit stateChanged();
}

void HHUScripts::_fail(const QString &text)
{
    qCWarning(HHUScriptsLog) << "failed:" << text;
    _steps.clear();
    _wait = Wait::None;
    _busy = false;
    if (!_quiet) {
        _setMessage(text, true);
    }
    _quiet = false;
    if (!_logAction.isEmpty()) {
        _log(_logAction, _logName, _logSize, text);
        _logAction.clear();
        // What is on the vehicle now (a left over .new, the old file gone), keeping the message
        if (connected() && !_directory.isEmpty()) {
            _quiet = true;
            _start(tr("Listing"), { [this]() { _list(0); } });
            return;
        }
    }
    emit stateChanged();
}

void HHUScripts::_done(const QString &text)
{
    _setMessage(text, false);
    _next();
}

void HHUScripts::refresh()
{
    if (!connected() || _busy) {
        return;
    }
    _setMessage(QString(), false);
    _start(tr("Listing"), { [this]() { _list(0); } });
}

void HHUScripts::_list(int candidate)
{
    // The directory found before first, then the others
    QStringList directories = kDirectories;
    if (!_directory.isEmpty()) {
        directories.removeAll(_directory);
        directories.prepend(_directory);
    }
    if (candidate >= directories.count()) {
        _directory.clear();
        _files.clear();
        emit filesChanged();
        _fail(tr("No scripts directory on the autopilot (SCR_ENABLE = 1 and a reboot create it)"));
        return;
    }
    _listCandidate = candidate;
    _label = tr("Listing");
    if (!_vehicle->ftpManager()->listDirectory(MAV_COMP_ID_AUTOPILOT1, directories.at(candidate))) {
        _fail(tr("File transfer busy, try again"));
        return;
    }
    _directory = directories.at(candidate);
    _wait = Wait::List;
}

void HHUScripts::_onListComplete(const QStringList &entries, const QString &error)
{
    if (_wait != Wait::List) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty()) {
        qCDebug(HHUScriptsLog) << "list" << _directory << error;
        if (!connected()) {
            _fail(tr("No answer from the vehicle"));
            return;
        }
        _list(_listCandidate + 1);
        return;
    }
    // "F<name>\t<size>[\t<time>]", "D<name>", "S" (skipped)
    QVariantList files;
    for (const QString &entry : entries) {
        if (!entry.startsWith(QLatin1Char('F'))) {
            continue;
        }
        const QStringList parts = entry.mid(1).split(QLatin1Char('\t'));
        files.append(QVariantMap{
            { QStringLiteral("name"), parts.value(0) },
            { QStringLiteral("size"), parts.value(1).toLongLong() },
        });
    }
    std::sort(files.begin(), files.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("name")).toString().compare(b.toMap().value(QStringLiteral("name")).toString(), Qt::CaseInsensitive) < 0;
    });
    _files = files;
    qCDebug(HHUScriptsLog) << "listed" << _directory << _files.count() << "files";
    emit filesChanged();
    _next();
}

bool HHUScripts::_download(const QString &name, const QString &toDir, const QString &toName)
{
    _label = tr("Downloading %1").arg(name);
    _expectedFile = QDir(toDir).absoluteFilePath(toName);
    if (!_vehicle->ftpManager()->download(MAV_COMP_ID_AUTOPILOT1, _path(name), toDir, toName, true)) {
        _fail(tr("File transfer busy, try again"));
        return false;
    }
    _wait = Wait::Download;
    return true;
}

void HHUScripts::_onDownloadComplete(const QString &file, const QString &error)
{
    if (_wait != Wait::Download || QFileInfo(file).absoluteFilePath() != _expectedFile) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty()) {
        _fail(tr("Download failed: %1").arg(ftpReason(error)));
        return;
    }
    _next();
}

void HHUScripts::_onUploadComplete(const QString &, const QString &error)
{
    if (_wait != Wait::Upload) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty()) {
        _fail(tr("Upload failed: %1").arg(ftpReason(error)));
        return;
    }
    _next();
}

void HHUScripts::_onDeleteComplete(const QString &, const QString &error)
{
    if (_wait != Wait::Delete) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty() && !_ignoreError) {
        _fail(tr("Delete failed: %1").arg(ftpReason(error)));
        return;
    }
    _next();
}

void HHUScripts::_onRenameComplete(const QString &, const QString &error)
{
    if (_wait != Wait::Rename) {
        return;
    }
    _wait = Wait::None;
    if (!error.isEmpty()) {
        _fail(tr("Rename failed: %1").arg(ftpReason(error)));
        return;
    }
    _next();
}

void HHUScripts::_onProgress(float value)
{
    if (_wait == Wait::Download || _wait == Wait::Upload) {
        _progress = value;
        emit stateChanged();
    }
}

// ---------------------------------------------------------------------------------------------
// Changes

void HHUScripts::upload(const QString &localPathOrUrl, const QString &targetName)
{
    if (!canModify()) {
        return;
    }
    if (_directory.isEmpty()) {
        _setMessage(tr("No scripts directory on the autopilot (SCR_ENABLE = 1 and a reboot create it)"), true);
        return;
    }
    const QString local = ::localPath(localPathOrUrl);
    const QFileInfo info(local);
    const QString name = targetName.isEmpty() ? info.fileName() : targetName;
    const QString nameError = checkName(name);
    if (!nameError.isEmpty()) {
        _setMessage(nameError, true);
        return;
    }
    if (!info.isFile() || info.size() == 0 || info.size() > kMaxSize) {
        _setMessage(tr("Cannot upload %1 (empty, missing or larger than 512 KB)").arg(info.fileName()), true);
        return;
    }
    QFile file(local);
    if (!file.open(QIODevice::ReadOnly)) {
        _setMessage(file.errorString(), true);
        return;
    }
    const QByteArray content = file.readAll();

    const bool replace = exists(name);
    const QString newName = name + kNewSuffix;
    const QString backupDir = backupFolder();
    const QString backupName = timeStamp() + QLatin1Char('_') + name;
    if (replace && !QDir().mkpath(backupDir)) {
        _setMessage(tr("Cannot create %1").arg(QDir::toNativeSeparators(backupDir)), true);
        return;
    }
    _tempDir = std::make_unique<QTemporaryDir>();
    if (!_tempDir->isValid()) {
        _setMessage(_tempDir->errorString(), true);
        return;
    }
    _setMessage(QString(), false);

    QList<Step> steps;
    if (replace) {
        steps.append([this, name, backupDir, backupName]() { (void) _download(name, backupDir, backupName); });
    }
    if (exists(newName)) {
        // Left over from an earlier upload that did not finish
        steps.append([this, newName]() {
            _label = tr("Deleting %1").arg(newName);
            if (!_vehicle->ftpManager()->deleteFile(MAV_COMP_ID_AUTOPILOT1, _path(newName))) {
                _fail(tr("File transfer busy, try again"));
                return;
            }
            _wait = Wait::Delete;
            _ignoreError = true;
        });
    }
    steps.append([this, local, name, newName]() {
        _label = tr("Uploading %1").arg(name);
        if (!_vehicle->ftpManager()->upload(MAV_COMP_ID_AUTOPILOT1, _path(newName), local)) {
            _fail(tr("File transfer busy, try again"));
            return;
        }
        _wait = Wait::Upload;
    });
    // Read back and compare before the old file is touched
    steps.append([this, newName]() { (void) _download(newName, _tempDir->path(), newName); });
    steps.append([this, name, newName, content]() {
        _label = tr("Checking %1").arg(name);
        QFile readBack(QDir(_tempDir->path()).filePath(newName));
        if (!readBack.open(QIODevice::ReadOnly) || readBack.readAll() != content) {
            _fail(tr("%1: the file read back differs from the upload, the old script is unchanged").arg(name));
            return;
        }
        _next();
    });
    if (replace) {
        steps.append([this, name]() {
            _label = tr("Deleting %1").arg(name);
            if (!_vehicle->ftpManager()->deleteFile(MAV_COMP_ID_AUTOPILOT1, _path(name))) {
                _fail(tr("File transfer busy, try again"));
                return;
            }
            _wait = Wait::Delete;
        });
    }
    steps.append([this, name, newName]() {
        _label = tr("Renaming %1").arg(newName);
        if (!_vehicle->ftpManager()->renameFile(MAV_COMP_ID_AUTOPILOT1, _path(newName), _path(name))) {
            _fail(tr("File transfer busy, try again"));
            return;
        }
        _wait = Wait::Rename;
    });
    steps.append([this, name, replace, content, backupDir, backupName]() {
        _tempDir.reset();
        _restartNeeded = true;
        _logAction.clear();
        _log(replace ? tr("Replace") : tr("Upload"), name, content.size(), tr("OK"));
        _done(replace ? tr("%1 replaced (%2 bytes), old file saved as %3. Restart the scripts to run it.")
                            .arg(name).arg(content.size()).arg(QDir::toNativeSeparators(QDir(backupDir).filePath(backupName)))
                      : tr("%1 uploaded (%2 bytes). Restart the scripts to run it.").arg(name).arg(content.size()));
    });
    steps.append([this]() { _list(0); });

    _logAction = replace ? tr("Replace") : tr("Upload");
    _logName = name;
    _logSize = content.size();
    _start(tr("Uploading %1").arg(name), steps);
}

void HHUScripts::remove(const QString &name)
{
    if (!canModify() || !exists(name)) {
        return;
    }
    const QString backupDir = backupFolder();
    const QString backupName = timeStamp() + QLatin1Char('_') + name;
    if (!QDir().mkpath(backupDir)) {
        _setMessage(tr("Cannot create %1").arg(QDir::toNativeSeparators(backupDir)), true);
        return;
    }
    _setMessage(QString(), false);
    _logAction = tr("Delete");
    _logName = name;
    _logSize = 0;
    _start(tr("Deleting %1").arg(name), {
        [this, name, backupDir, backupName]() { (void) _download(name, backupDir, backupName); },
        [this, name]() {
            _label = tr("Deleting %1").arg(name);
            if (!_vehicle->ftpManager()->deleteFile(MAV_COMP_ID_AUTOPILOT1, _path(name))) {
                _fail(tr("File transfer busy, try again"));
                return;
            }
            _wait = Wait::Delete;
        },
        [this, name, backupDir, backupName]() {
            _restartNeeded = name.endsWith(QStringLiteral(".lua"), Qt::CaseInsensitive);
            _logAction.clear();
            _log(tr("Delete"), name, QFileInfo(QDir(backupDir).filePath(backupName)).size(), tr("OK"));
            _done(tr("%1 deleted, saved as %2").arg(name, QDir::toNativeSeparators(QDir(backupDir).filePath(backupName))));
        },
        [this]() { _list(0); },
    });
}

void HHUScripts::backup(const QString &name)
{
    if (!connected() || _busy || !exists(name)) {
        return;
    }
    const QString backupDir = backupFolder();
    const QString backupName = timeStamp() + QLatin1Char('_') + name;
    if (!QDir().mkpath(backupDir)) {
        _setMessage(tr("Cannot create %1").arg(QDir::toNativeSeparators(backupDir)), true);
        return;
    }
    _setMessage(QString(), false);
    _start(tr("Downloading %1").arg(name), {
        [this, name, backupDir, backupName]() { (void) _download(name, backupDir, backupName); },
        [this, backupDir, backupName]() { _done(tr("Saved as %1").arg(QDir::toNativeSeparators(QDir(backupDir).filePath(backupName)))); },
    });
}

void HHUScripts::restartScripts()
{
    if (!canModify()) {
        return;
    }
    _vehicle->sendMavCommand(MAV_COMP_ID_AUTOPILOT1, MAV_CMD_SCRIPTING, true /* showError */, SCRIPTING_CMD_STOP_AND_RESTART);
    _restartNeeded = false;
    _log(tr("Restart scripts"), QString(), 0, tr("Sent"));
    _setMessage(tr("Scripts restarted"), false);
    emit stateChanged();
}

// ---------------------------------------------------------------------------------------------
// Files: <save path>/调参记录/<车号>/

QString HHUScripts::_logFolder() const
{
    const QString savePath = SettingsManager::instance()->appSettings()->savePath()->rawValue().toString();
    return QDir(savePath).filePath(QStringLiteral("调参记录/") + _tuning->vehicleName());
}

QString HHUScripts::backupFolder() const
{
    return QDir(_logFolder()).filePath(QStringLiteral("脚本备份"));
}

void HHUScripts::openBackupFolder() const
{
    const QString folder = backupFolder();
    (void) QDir().mkpath(folder);
    (void) QDesktopServices::openUrl(QUrl::fromLocalFile(folder));
}

void HHUScripts::_log(const QString &action, const QString &name, qint64 size, const QString &result)
{
    const QString folder = _logFolder();
    (void) QDir().mkpath(folder);
    QFile file(QDir(folder).filePath(QStringLiteral("脚本日志.csv")));
    const bool isNew = !file.exists();
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        qCWarning(HHUScriptsLog) << "cannot write" << file.fileName() << file.errorString();
        return;
    }
    QTextStream out(&file);
    if (isNew) {
        // BOM so that Excel shows the Chinese header
        out << QChar(0xFEFF) << QStringLiteral("时间,车号,操作,文件,字节,结果") << '\n';
    }
    QString resultText = result;
    resultText.replace(QLatin1Char(','), QStringLiteral("，"));
    out << QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")) << ','
        << _tuning->vehicleName() << ',' << action << ',' << name << ',' << (size > 0 ? QString::number(size) : QString()) << ',' << resultText << '\n';
}
