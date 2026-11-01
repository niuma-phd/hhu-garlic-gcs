#include "HHUTuning.h"
#include "HHU4GLink.h"
#include "QGCLoggingCategory.h"
#include "AppSettings.h"
#include "LinkInterface.h"
#include "MAVLinkProtocol.h"
#include "MultiVehicleManager.h"
#include "ParameterManager.h"
#include "SettingsManager.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <algorithm>
#include <cmath>

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QRegularExpression>
#include <QtCore/QSaveFile>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>

QGC_LOGGING_CATEGORY(HHUTuningLog, "Custom.HHUTuning")

namespace {
constexpr int    kAckTimeoutMs   = 1500;    ///< wait for PARAM_VALUE before resending
constexpr int    kMaxAttempts    = 4;       ///< first send + 3 resends
constexpr int    kReadWindow     = 5;       ///< PARAM_REQUEST_READ in flight at a time
constexpr double kTolerance      = 1e-4;    ///< read back == target (float32)

bool sameFloat(float a, float b)
{
    return std::fabs(static_cast<double>(a) - static_cast<double>(b)) <= kTolerance;
}
}

HHUTuning::HHUTuning(HHU4GLink *link4G, QObject *parent)
    : QAbstractListModel(parent)
    , _link4G(link4G)
{
    _loadList();

    _readTimer.setInterval(250);
    (void) connect(&_readTimer, &QTimer::timeout, this, &HHUTuning::_checkReads);
    _writeTimer.setSingleShot(true);
    _writeTimer.setInterval(kAckTimeoutMs);
    (void) connect(&_writeTimer, &QTimer::timeout, this, &HHUTuning::_writeTimeout);

    (void) connect(MultiVehicleManager::instance(), &MultiVehicleManager::activeVehicleChanged, this, &HHUTuning::_setVehicle);
    (void) connect(_link4G, &HHU4GLink::stateChanged, this, &HHUTuning::stateChanged);
    _setVehicle(MultiVehicleManager::instance()->activeVehicle());
}

// ---------------------------------------------------------------------------------------------
// Parameter list

void HHUTuning::_loadList()
{
    const QString userFile = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("config/hhu_tuning_params.json"));
    if (QFile::exists(userFile) && _loadList(userFile)) {
        return;
    }
    (void) _loadList(QStringLiteral(":/hhu/config/hhu_tuning_params.json"));
}

bool HHUTuning::_loadList(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(HHUTuningLog) << "cannot open" << path;
        return false;
    }
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qCWarning(HHUTuningLog) << path << "is not valid JSON:" << error.errorString() << "at offset" << error.offset;
        return false;
    }

    QList<Row> rows;
    for (const QJsonValue &groupValue : doc.object().value(QStringLiteral("groups")).toArray()) {
        const QJsonObject group = groupValue.toObject();
        for (const QJsonValue &paramValue : group.value(QStringLiteral("params")).toArray()) {
            const QJsonObject param = paramValue.toObject();
            Row row;
            row.name    = param.value(QStringLiteral("name")).toString().trimmed();
            row.group   = group.value(QStringLiteral("name")).toString();
            row.min     = param.value(QStringLiteral("min")).toDouble();
            row.max     = param.value(QStringLiteral("max")).toDouble();
            row.step    = param.value(QStringLiteral("step")).toDouble(1);
            row.integer = param.value(QStringLiteral("integer")).toBool(false);
            row.reboot  = param.value(QStringLiteral("reboot")).toBool(false);
            if (row.name.isEmpty() || row.step <= 0 || row.max < row.min) {
                qCWarning(HHUTuningLog) << path << "skips" << param;
                continue;
            }
            // Decimals shown = decimals of the step (0.05 → 2)
            while (row.decimals < 6 && std::fabs(row.step * std::pow(10.0, row.decimals) - std::round(row.step * std::pow(10.0, row.decimals))) > 1e-9) {
                row.decimals++;
            }
            rows.append(row);
        }
    }
    if (rows.isEmpty()) {
        qCWarning(HHUTuningLog) << path << "has no parameters";
        return false;
    }
    beginResetModel();
    _rows = rows;
    endResetModel();
    qCDebug(HHUTuningLog) << "loaded" << path << _rows.count() << "parameters";
    return true;
}

// ---------------------------------------------------------------------------------------------
// Model

int HHUTuning::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(_rows.count());
}

QVariant HHUTuning::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= _rows.count()) {
        return {};
    }
    const Row &row = _rows.at(index.row());
    switch (role) {
    case NameRole:          return row.name;
    case GroupRole:         return row.group;
    case GroupStartRole:    return index.row() == 0 || _rows.at(index.row() - 1).group != row.group;
    case MinRole:           return row.min;
    case MaxRole:           return row.max;
    case StepRole:          return row.step;
    case DecimalsRole:      return row.decimals;
    case RebootRole:        return row.reboot;
    case MissingRole:       return row.exists == 0;
    case CurrentTextRole:   return row.hasCurrent ? _format(row.current) : QString();
    case InputRole:         return row.input;
    case PendingRole:       return _isPending(row);
    case InvalidRole:       return _isInvalid(row);
    case StatusRole:        return row.status;
    case StatusTextRole:    return row.statusText;
    default:                return {};
    }
}

QHash<int, QByteArray> HHUTuning::roleNames() const
{
    return {
        { NameRole,         "name" },
        { GroupRole,        "group" },
        { GroupStartRole,   "groupStart" },
        { MinRole,          "min" },
        { MaxRole,          "max" },
        { StepRole,         "step" },
        { DecimalsRole,     "decimals" },
        { RebootRole,       "reboot" },
        { MissingRole,      "missing" },
        { CurrentTextRole,  "currentText" },
        { InputRole,        "input" },
        { PendingRole,      "pending" },
        { InvalidRole,      "invalid" },
        { StatusRole,       "status" },
        { StatusTextRole,   "statusText" },
    };
}

void HHUTuning::_rowChanged(int row)
{
    const QModelIndex i = index(row);
    emit dataChanged(i, i);
    emit rowsChanged();
}

void HHUTuning::_setStatus(int row, const QString &status, const QString &text)
{
    _rows[row].status = status;
    _rows[row].statusText = text;
    _rowChanged(row);
}

void HHUTuning::_setSummary(const QString &text, bool error)
{
    _summary = text;
    _summaryError = error;
    emit summaryChanged();
}

int HHUTuning::_rowOf(const QString &name) const
{
    for (int i = 0; i < _rows.count(); i++) {
        if (_rows.at(i).name == name) {
            return i;
        }
    }
    return -1;
}

/// Shortest decimal text that reads back as the same float (0.3, not 0.300000012)
QString HHUTuning::_format(float value)
{
    for (int decimals = 0; decimals < 9; decimals++) {
        const QString text = QString::number(static_cast<double>(value), 'f', decimals);
        if (text.toFloat() == value) {
            return text == QStringLiteral("-0") ? QStringLiteral("0") : text;
        }
    }
    return QString::number(static_cast<double>(value), 'g', 9);
}

bool HHUTuning::_inputValue(const Row &row, double &value) const
{
    bool ok = false;
    value = QString(row.input).replace(QLatin1Char(','), QLatin1Char('.')).trimmed().toDouble(&ok);
    return ok && std::isfinite(value);
}

bool HHUTuning::_isInvalid(const Row &row) const
{
    if (!row.edited || row.exists == 0) {
        return false;
    }
    double value = 0;
    if (!_inputValue(row, value)) {
        return true;
    }
    // The vehicle's own value is not written, even when the list's range excludes it (WP_ACCEL 0)
    if (row.hasCurrent && sameFloat(static_cast<float>(value), row.current)) {
        return false;
    }
    // A little slack for typed decimals (1.38 → 1.3799999)
    if (value < row.min - 1e-9 || value > row.max + 1e-9) {
        return true;
    }
    return row.integer && std::fabs(value - std::round(value)) > 1e-9;
}

bool HHUTuning::_isPending(const Row &row) const
{
    if (!row.edited || row.exists != 1 || _isInvalid(row)) {
        return false;
    }
    double value = 0;
    (void) _inputValue(row, value);
    return !row.hasCurrent || !sameFloat(static_cast<float>(value), row.current);
}

int HHUTuning::pendingCount() const
{
    return static_cast<int>(std::count_if(_rows.cbegin(), _rows.cend(), [this](const Row &row) { return _isPending(row); }));
}

int HHUTuning::invalidCount() const
{
    return static_cast<int>(std::count_if(_rows.cbegin(), _rows.cend(), [this](const Row &row) { return _isInvalid(row); }));
}

// ---------------------------------------------------------------------------------------------
// Vehicle state

bool HHUTuning::connected() const
{
    return _vehicle && !_vehicle->vehicleLinkManager()->communicationLost();
}

bool HHUTuning::armed() const
{
    return _vehicle && _vehicle->armed();
}

bool HHUTuning::canWrite() const
{
    if (!connected() || _reading || _writing || _link4G->readOnly()) {
        return false;
    }
    return !_vehicle->armed() || _vehicle->flightMode() == _vehicle->pauseFlightMode();
}

QString HHUTuning::blockReason() const
{
    if (!connected() || _reading || _writing) {
        return QString();
    }
    if (_link4G->readOnly()) {
        return tr("Read-only connection");
    }
    if (_vehicle->armed() && _vehicle->flightMode() != _vehicle->pauseFlightMode()) {
        return tr("Cannot write while driving");
    }
    return QString();
}

QString HHUTuning::vehicleName() const
{
    QString name;
    if (_link4G->active()) {
        const QVariantList configs = _link4G->configs();
        if (_link4G->activeIndex() < configs.count()) {
            name = configs.at(_link4G->activeIndex()).toMap().value(QStringLiteral("vehicle")).toString().trimmed();
        }
    }
    if (name.isEmpty() && _vehicle) {
        name = QStringLiteral("SYSID%1").arg(_vehicle->id());
    }
    // Used as a folder name
    return name.replace(QRegularExpression(QStringLiteral("[\\\\/:*?\"<>|]")), QStringLiteral("_"));
}

void HHUTuning::setActive(bool active)
{
    if (active == _active) {
        return;
    }
    _active = active;
    emit activeChanged();
    if (_active && connected() && !_writing) {
        read();
    }
}

void HHUTuning::_setVehicle(Vehicle *vehicle)
{
    if (vehicle == _vehicle) {
        return;
    }
    if (_writing) {
        _finishWrite(true);
    }
    _abortRead();
    if (_vehicle) {
        (void) disconnect(_vehicle, nullptr, this, nullptr);
        (void) disconnect(_vehicle->vehicleLinkManager(), nullptr, this, nullptr);
        (void) disconnect(_vehicle->parameterManager(), nullptr, this, nullptr);
    }
    _vehicle = vehicle;
    _rebootNeeded = false;
    _intBytewise = false;

    // Another vehicle (or the same one connected again): nothing of the old values is valid
    for (Row &row : _rows) {
        row.exists = -1;
        row.hasCurrent = false;
        row.type = MAV_PARAM_TYPE_REAL32;
        if (!row.edited) {
            row.input.clear();
        }
        if (row.status != QStringLiteral("unconfirmed")) {
            row.status.clear();
            row.statusText.clear();
        }
    }
    if (!_rows.isEmpty()) {
        emit dataChanged(index(0), index(static_cast<int>(_rows.count()) - 1));
        emit rowsChanged();
    }

    if (_vehicle) {
        (void) connect(_vehicle, &Vehicle::armedChanged, this, &HHUTuning::stateChanged);
        (void) connect(_vehicle, &Vehicle::flightModeChanged, this, &HHUTuning::stateChanged);
        (void) connect(_vehicle->vehicleLinkManager(), &VehicleLinkManager::communicationLostChanged, this, &HHUTuning::_onCommunicationLost);
        (void) connect(_vehicle->parameterManager(), &ParameterManager::parametersReadyChanged, this, [this](bool ready) {
            if (!ready) {
                return;
            }
            _updateExists();
            if ((_active || _readAfterReconnect) && !_reading && !_writing) {
                _startRead(true, _readAfterReconnect);
                _readAfterReconnect = false;
            }
        });
        _updateExists();
        if ((_active || _readAfterReconnect) && _vehicle->parameterManager()->parametersReady()) {
            _startRead(true, _readAfterReconnect);
            _readAfterReconnect = false;
        }
    }
    emit stateChanged();
}

/// "无此参数" from the parameter list QGC loaded at connection. That list leaves out parameters of
/// disabled groups (GPS1_MB_OFS_* while GPS1_MB_TYPE = 0) which still answer a read by name, so a
/// row is only marked missing when it is not in the list and did not answer either.
void HHUTuning::_updateExists()
{
    if (!_vehicle || !_vehicle->parameterManager()->parametersReady()) {
        return;
    }
    ParameterManager *params = _vehicle->parameterManager();
    for (int i = 0; i < _rows.count(); i++) {
        Row &row = _rows[i];
        if (row.hasCurrent) {
            continue;
        }
        const bool exists = params->parameterExists(ParameterManager::defaultComponentId, row.name);
        if (exists && row.exists != 1) {
            row.exists = 1;
            _rowChanged(i);
        }
    }
}

/// No answer to a read by name and not in QGC's list
void HHUTuning::_markMissing(int i)
{
    Row &row = _rows[i];
    row.exists = 0;
    row.edited = false;
    row.input.clear();
    row.status.clear();
    row.statusText.clear();
    _rowChanged(i);
}

void HHUTuning::_onCommunicationLost(bool lost)
{
    if (lost) {
        if (_writing) {
            _finishWrite(true);
        }
        if (_reading) {
            _abortRead();
            _readAfterReconnect = true;
        }
    } else if ((_active || _readAfterReconnect) && !_reading && !_writing) {
        // Back again: the vehicle's values count
        _startRead(true, _readAfterReconnect);
        _readAfterReconnect = false;
    }
    emit stateChanged();
}

// ---------------------------------------------------------------------------------------------
// Inputs

void HHUTuning::setInput(int row, const QString &text)
{
    if (row < 0 || row >= _rows.count() || _writing || _rows.at(row).exists == 0) {
        return;
    }
    Row &r = _rows[row];
    if (r.input == text && r.edited) {
        return;
    }
    r.input = text;
    r.edited = true;
    if (r.status == QStringLiteral("ok") || r.status == QStringLiteral("fail") || r.status == QStringLiteral("unconfirmed")) {
        r.status.clear();
        r.statusText.clear();
    }
    _rowChanged(row);
}

void HHUTuning::stepInput(int row, int direction)
{
    if (row < 0 || row >= _rows.count()) {
        return;
    }
    const Row &r = _rows.at(row);
    double base = 0;
    if (!_inputValue(r, base)) {
        if (!r.hasCurrent) {
            return;
        }
        base = r.current;
    }
    const double value = std::clamp(base + direction * r.step, r.min, r.max);
    setInput(row, QString::number(value, 'f', r.decimals));
}

void HHUTuning::discard()
{
    if (_writing) {
        return;
    }
    _setSummary(QString(), false);
    for (int i = 0; i < _rows.count(); i++) {
        Row &row = _rows[i];
        if (row.edited) {
            row.edited = false;
            row.input = row.hasCurrent ? _format(row.current) : QString();
            _rowChanged(i);
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Reading

void HHUTuning::read()
{
    if (!connected() || _reading || _writing) {
        return;
    }
    _setSummary(QString(), false);
    _startRead(false, false);
}

void HHUTuning::_startRead(bool keepStatus, bool resetInputs)
{
    if (!connected()) {
        _readAfterReconnect = _readAfterReconnect || resetInputs;
        return;
    }
    _updateExists();
    _readQueue.clear();
    _readInFlight.clear();
    for (int i = 0; i < _rows.count(); i++) {
        Row &row = _rows[i];
        _readQueue.append(row.name);
        if (!keepStatus || row.status == QStringLiteral("unread")) {
            row.status = QStringLiteral("reading");
            row.statusText.clear();
            _rowChanged(i);
        }
    }
    _resetInputsAfterRead = resetInputs;
    _reading = true;
    emit stateChanged();
    _sendReads();
    _readTimer.start();
    if (_readQueue.isEmpty() && _readInFlight.isEmpty()) {
        _finishRead();
    }
}

void HHUTuning::_sendReads()
{
    while (!_readQueue.isEmpty() && _readInFlight.count() < kReadWindow) {
        const QString name = _readQueue.takeFirst();
        ReadRequest request;
        request.attempts = 1;
        request.sent.start();
        _readInFlight.insert(name, request);
        (void) _sendParamRequestRead(name);
    }
}

void HHUTuning::_checkReads()
{
    if (!_reading) {
        _readTimer.stop();
        return;
    }
    for (auto it = _readInFlight.begin(); it != _readInFlight.end();) {
        if (it->sent.elapsed() < kAckTimeoutMs) {
            ++it;
            continue;
        }
        if (it->attempts < kMaxAttempts) {
            it->attempts++;
            it->sent.restart();
            (void) _sendParamRequestRead(it.key());
            ++it;
            continue;
        }
        const int row = _rowOf(it.key());
        if (row >= 0) {
            ParameterManager *params = _vehicle ? _vehicle->parameterManager() : nullptr;
            if (params && params->parametersReady() && !params->parameterExists(ParameterManager::defaultComponentId, it.key())) {
                _markMissing(row);
            } else {
                _setStatus(row, QStringLiteral("unread"), tr("Not read"));
            }
        }
        it = _readInFlight.erase(it);
    }
    _sendReads();
    if (_readQueue.isEmpty() && _readInFlight.isEmpty()) {
        _finishRead();
    }
}

void HHUTuning::_finishRead()
{
    _readTimer.stop();
    _reading = false;
    if (_resetInputsAfterRead) {
        _resetInputsAfterRead = false;
        for (int i = 0; i < _rows.count(); i++) {
            Row &row = _rows[i];
            if (row.edited && row.hasCurrent) {
                row.edited = false;
                row.input = _format(row.current);
                _rowChanged(i);
            }
        }
    }
    emit stateChanged();
}

void HHUTuning::_abortRead()
{
    _readTimer.stop();
    _readQueue.clear();
    _readInFlight.clear();
    for (int i = 0; i < _rows.count(); i++) {
        if (_rows.at(i).status == QStringLiteral("reading")) {
            _setStatus(i, QString(), QString());
        }
    }
    if (_reading) {
        _reading = false;
        emit stateChanged();
    }
}

// ---------------------------------------------------------------------------------------------
// Writing

void HHUTuning::write()
{
    if (!canWrite() || invalidCount() > 0) {
        return;
    }
    _writeQueue.clear();
    for (int i = 0; i < _rows.count(); i++) {
        if (_isPending(_rows.at(i))) {
            _writeQueue.append(i);
        }
    }
    if (_writeQueue.isEmpty()) {
        return;
    }

    QString error;
    if (!_saveSnapshot(error)) {
        _writeQueue.clear();
        _setSummary(tr("Snapshot not saved, nothing written: %1").arg(error), true);
        return;
    }

    for (int i = 0; i < _rows.count(); i++) {
        Row &row = _rows[i];
        if (!row.status.isEmpty() && row.status != QStringLiteral("unread")) {
            row.status.clear();
            row.statusText.clear();
            _rowChanged(i);
        }
    }
    _okCount = _failCount = _unconfirmedCount = 0;
    _writing = true;
    _setSummary(QString(), false);
    emit stateChanged();
    _writeNext();
}

void HHUTuning::_writeNext()
{
    if (_writeQueue.isEmpty()) {
        _finishWrite(false);
        return;
    }
    _writeRow = _writeQueue.takeFirst();
    const Row &row = _rows.at(_writeRow);
    double value = 0;
    (void) _inputValue(row, value);
    _writeTarget = static_cast<float>(value);
    _writeAttempts = 0;
    _writeMismatch = false;
    _writeOldText = row.hasCurrent ? _format(row.current) : QString();
    _setStatus(_writeRow, QStringLiteral("writing"), tr("Writing"));
    _sendWrite();
}

void HHUTuning::_sendWrite()
{
    _writeAttempts++;
    (void) _sendParamSet(_rows.at(_writeRow), _writeTarget);
    _writeTimer.start();
}

void HHUTuning::_writeTimeout()
{
    if (!_writing || _writeRow < 0) {
        return;
    }
    if (_writeAttempts < kMaxAttempts) {
        _sendWrite();
        return;
    }
    if (_writeMismatch) {
        _finishItem(QStringLiteral("fail"), tr("✗ Failed (read back %1)").arg(_format(_writeReadBack)));
    } else {
        _finishItem(QStringLiteral("unconfirmed"), tr("? Unconfirmed"));
    }
    _writeNext();
}

void HHUTuning::_finishItem(const QString &status, const QString &text)
{
    _writeTimer.stop();
    const int row = _writeRow;
    _writeRow = -1;
    if (status == QStringLiteral("ok")) {
        _okCount++;
        if (_rows.at(row).reboot) {
            _rebootNeeded = true;
        }
    } else if (status == QStringLiteral("fail")) {
        _failCount++;
    } else {
        _unconfirmedCount++;
    }
    _setStatus(row, status, text);
    _log(_rows.at(row), _writeOldText, _format(_writeTarget), text);
}

void HHUTuning::_finishWrite(bool interrupted)
{
    if (!_writing) {
        return;
    }
    _writeTimer.stop();
    if (_writeRow >= 0) {
        _finishItem(QStringLiteral("unconfirmed"), tr("? Unconfirmed"));
    }
    const int notWritten = static_cast<int>(_writeQueue.count());
    _writeQueue.clear();
    _writing = false;

    QString text = tr("%1 succeeded, %2 failed").arg(_okCount).arg(_failCount + _unconfirmedCount);
    if (_unconfirmedCount > 0) {
        text += tr(" (%1 unconfirmed)").arg(_unconfirmedCount);
    }
    if (interrupted) {
        text = tr("Connection lost: ") + text + tr(", %1 not written").arg(notWritten);
    }
    _setSummary(text, _failCount + _unconfirmedCount > 0 || interrupted);
    emit stateChanged();

    if (interrupted) {
        _readAfterReconnect = true;
    } else {
        // The vehicle's actual values into "当前值" and the inputs
        _startRead(true, true);
    }
}

// ---------------------------------------------------------------------------------------------
// MAVLink

void HHUTuning::handleMessage(Vehicle *vehicle, const mavlink_message_t &message)
{
    if (!_vehicle || vehicle != _vehicle || message.sysid != _vehicle->id() || message.compid != MAV_COMP_ID_AUTOPILOT1) {
        return;
    }

    if (message.msgid == MAVLINK_MSG_ID_PARAM_ERROR) {
        mavlink_param_error_t paramError{};
        mavlink_msg_param_error_decode(&message, &paramError);
        char id[MAVLINK_MSG_PARAM_ERROR_FIELD_PARAM_ID_LEN + 1] = {};
        (void) strncpy(id, paramError.param_id, MAVLINK_MSG_PARAM_ERROR_FIELD_PARAM_ID_LEN);
        if (_writing && _writeRow >= 0 && _rows.at(_writeRow).name == QString::fromLatin1(id)) {
            _finishItem(QStringLiteral("fail"), tr("✗ Failed (error %1)").arg(paramError.error));
            _writeNext();
        }
        return;
    }
    if (message.msgid != MAVLINK_MSG_ID_PARAM_VALUE) {
        return;
    }

    mavlink_param_value_t paramValue{};
    mavlink_msg_param_value_decode(&message, &paramValue);
    char id[MAVLINK_MSG_PARAM_VALUE_FIELD_PARAM_ID_LEN + 1] = {};
    (void) strncpy(id, paramValue.param_id, MAVLINK_MSG_PARAM_VALUE_FIELD_PARAM_ID_LEN);
    const QString name = QString::fromLatin1(id);
    const int rowIndex = _rowOf(name);
    if (rowIndex < 0) {
        return;
    }

    bool bytewise = false;
    const float value = _decode(paramValue, bytewise);
    Row &row = _rows[rowIndex];
    row.exists = 1;
    row.hasCurrent = true;
    row.current = value;
    row.type = paramValue.param_type;
    row.bytewise = bytewise;
    _intBytewise = _intBytewise || bytewise;
    if (!row.edited) {
        row.input = _format(value);
    }

    if (_readInFlight.remove(name) && row.status == QStringLiteral("reading")) {
        row.status.clear();
        row.statusText.clear();
    } else if (row.status == QStringLiteral("unread")) {
        row.status.clear();
        row.statusText.clear();
    }
    _rowChanged(rowIndex);

    if (_writing && _writeRow == rowIndex) {
        if (sameFloat(value, _writeTarget)) {
            _finishItem(QStringLiteral("ok"), tr("✓ Written"));
            _writeNext();
        } else {
            // Possibly an older PARAM_VALUE: wait for the read back of the resend
            _writeMismatch = true;
            _writeReadBack = value;
        }
    }
    if (_reading) {
        _sendReads();
        if (_readQueue.isEmpty() && _readInFlight.isEmpty()) {
            _finishRead();
        }
    }
}

/// Integer types: a whole number in the float is a cast value, anything else (a denormal such as
/// 1.4e-45) is the integer in the float's bytes
float HHUTuning::_decode(const mavlink_param_value_t &paramValue, bool &bytewise)
{
    const float f = paramValue.param_value;
    bytewise = false;
    if (paramValue.param_type == MAV_PARAM_TYPE_REAL32 || (std::isfinite(f) && f == std::round(f) && std::fabs(f) < 16777216.0f)) {
        return f;
    }
    mavlink_param_union_t u{};
    u.param_float = f;
    u.type = paramValue.param_type;
    bytewise = true;
    switch (paramValue.param_type) {
    case MAV_PARAM_TYPE_UINT8:  return u.param_uint8;
    case MAV_PARAM_TYPE_INT8:   return u.param_int8;
    case MAV_PARAM_TYPE_UINT16: return u.param_uint16;
    case MAV_PARAM_TYPE_INT16:  return u.param_int16;
    case MAV_PARAM_TYPE_UINT32: return static_cast<float>(u.param_uint32);
    case MAV_PARAM_TYPE_INT32:  return static_cast<float>(u.param_int32);
    default:
        bytewise = false;
        return f;
    }
}

bool HHUTuning::_sendParamRequestRead(const QString &name)
{
    if (!_vehicle) {
        return false;
    }
    const SharedLinkInterfacePtr link = _vehicle->vehicleLinkManager()->primaryLink().lock();
    if (!link) {
        return false;
    }
    char id[MAVLINK_MSG_PARAM_REQUEST_READ_FIELD_PARAM_ID_LEN + 1] = {};
    (void) strncpy(id, name.toLatin1().constData(), MAVLINK_MSG_PARAM_REQUEST_READ_FIELD_PARAM_ID_LEN);
    mavlink_message_t message{};
    (void) mavlink_msg_param_request_read_pack_chan(
        MAVLinkProtocol::instance()->getSystemId(),
        MAVLinkProtocol::getComponentId(),
        link->mavlinkChannel(),
        &message,
        static_cast<uint8_t>(_vehicle->id()),
        MAV_COMP_ID_AUTOPILOT1,
        id,
        -1);
    return _vehicle->sendMessageOnLinkThreadSafe(link.get(), message);
}

bool HHUTuning::_sendParamSet(const Row &row, float value)
{
    if (!_vehicle) {
        return false;
    }
    const SharedLinkInterfacePtr link = _vehicle->vehicleLinkManager()->primaryLink().lock();
    if (!link) {
        return false;
    }
    char id[MAVLINK_MSG_PARAM_SET_FIELD_PARAM_ID_LEN + 1] = {};
    (void) strncpy(id, row.name.toLatin1().constData(), MAVLINK_MSG_PARAM_SET_FIELD_PARAM_ID_LEN);
    float encoded = value;
    if (row.bytewise || (_intBytewise && row.type != MAV_PARAM_TYPE_REAL32)) {
        mavlink_param_union_t u{};
        const long n = std::lround(value);
        switch (row.type) {
        case MAV_PARAM_TYPE_UINT8:  u.param_uint8  = static_cast<uint8_t>(n);  break;
        case MAV_PARAM_TYPE_INT8:   u.param_int8   = static_cast<int8_t>(n);   break;
        case MAV_PARAM_TYPE_UINT16: u.param_uint16 = static_cast<uint16_t>(n); break;
        case MAV_PARAM_TYPE_INT16:  u.param_int16  = static_cast<int16_t>(n);  break;
        case MAV_PARAM_TYPE_UINT32: u.param_uint32 = static_cast<uint32_t>(n); break;
        case MAV_PARAM_TYPE_INT32:  u.param_int32  = static_cast<int32_t>(n);  break;
        default:                    u.param_float  = value;                    break;
        }
        encoded = u.param_float;
    }
    mavlink_message_t message{};
    (void) mavlink_msg_param_set_pack_chan(
        MAVLinkProtocol::instance()->getSystemId(),
        MAVLinkProtocol::getComponentId(),
        link->mavlinkChannel(),
        &message,
        static_cast<uint8_t>(_vehicle->id()),
        MAV_COMP_ID_AUTOPILOT1,
        id,
        encoded,
        row.type);
    qCDebug(HHUTuningLog) << "PARAM_SET" << row.name << value << "attempt" << _writeAttempts;
    return _vehicle->sendMessageOnLinkThreadSafe(link.get(), message);
}

void HHUTuning::rebootAutopilot()
{
    if (!connected() || _vehicle->armed() || _writing) {
        return;
    }
    _vehicle->rebootVehicle();
    _rebootNeeded = false;
    _readAfterReconnect = true;
    emit stateChanged();
}

// ---------------------------------------------------------------------------------------------
// Files: <save path>/调参记录/<车号>/

QString HHUTuning::_folder() const
{
    const QString savePath = SettingsManager::instance()->appSettings()->savePath()->rawValue().toString();
    return QDir(savePath).filePath(QStringLiteral("调参记录/") + vehicleName());
}

bool HHUTuning::_saveSnapshot(QString &error)
{
    const QString folder = _folder();
    if (!QDir().mkpath(folder)) {
        error = tr("cannot create %1").arg(QDir::toNativeSeparators(folder));
        return false;
    }
    const QString path = QDir(folder).filePath(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss")) + QStringLiteral("_写前.param"));
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        error = file.errorString();
        return false;
    }
    QTextStream out(&file);
    for (const Row &row : std::as_const(_rows)) {
        if (row.exists != 0 && row.hasCurrent) {
            out << row.name << ',' << _format(row.current) << '\n';
        }
    }
    out.flush();
    if (!file.commit()) {
        error = file.errorString();
        return false;
    }
    qCDebug(HHUTuningLog) << "snapshot" << path;
    return true;
}

void HHUTuning::_log(const Row &row, const QString &oldValue, const QString &newValue, const QString &result)
{
    const QString folder = _folder();
    (void) QDir().mkpath(folder);
    QFile file(QDir(folder).filePath(QStringLiteral("调参日志.csv")));
    const bool isNew = !file.exists();
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        qCWarning(HHUTuningLog) << "cannot write" << file.fileName() << file.errorString();
        return;
    }
    QTextStream out(&file);
    if (isNew) {
        // BOM so that Excel shows the Chinese header
        out << QChar(0xFEFF) << QStringLiteral("时间,车号,参数,原值,新值,结果") << '\n';
    }
    QString resultText = result;
    resultText.replace(QLatin1Char(','), QStringLiteral("，"));
    out << QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")) << ','
        << vehicleName() << ',' << row.name << ',' << oldValue << ',' << newValue << ',' << resultText << '\n';
}

QVariantList HHUTuning::snapshots() const
{
    QVariantList list;
    QDir dir(_folder());
    const QStringList files = dir.entryList({ QStringLiteral("*.param") }, QDir::Files, QDir::Name | QDir::Reversed);
    for (const QString &file : files) {
        const QDateTime time = QDateTime::fromString(file.left(15), QStringLiteral("yyyyMMdd_HHmmss"));
        list.append(QVariantMap{
            { QStringLiteral("path"),  dir.filePath(file) },
            { QStringLiteral("label"), time.isValid() ? time.toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")) : file },
        });
    }
    return list;
}

int HHUTuning::loadParamFile(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    const QString path = url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
    QFile file(path);
    if (_writing || !file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        _setSummary(tr("Cannot read %1").arg(QDir::toNativeSeparators(path)), true);
        return -1;
    }

    // Mission Planner "NAME,VALUE" (also "NAME VALUE"); QGC "sysid compid NAME VALUE type"
    static const QRegularExpression separators(QStringLiteral("[,\\s]+"));
    int count = 0;
    QTextStream in(&file);
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        const QStringList parts = line.split(separators, Qt::SkipEmptyParts);
        QString name;
        QString value;
        bool isInt = false;
        if (parts.count() >= 4 && (parts.at(0).toInt(&isInt), isInt)) {
            name = parts.at(2);
            value = parts.at(3);
        } else if (parts.count() >= 2) {
            name = parts.at(0);
            value = parts.at(1);
        }
        const int row = _rowOf(name);
        bool ok = false;
        const float number = value.toFloat(&ok);
        if (row < 0 || !ok || _rows.at(row).exists == 0) {
            continue;
        }
        setInput(row, _format(number));
        count++;
    }
    _setSummary(tr("%1 parameters taken from %2").arg(count).arg(QFileInfo(path).fileName()), false);
    return count;
}
