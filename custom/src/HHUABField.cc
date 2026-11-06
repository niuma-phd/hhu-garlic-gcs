#include "HHUABField.h"
#include "HHUConfig.h"
#include "QGCLoggingCategory.h"
#include "AppSettings.h"
#include "SettingsManager.h"
#include "MultiVehicleManager.h"
#include "Vehicle.h"
#include "VehicleGPSFactGroup.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSaveFile>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>

#include <cmath>

QGC_LOGGING_CATEGORY(HHUABFieldLog, "Custom.HHUABField")

namespace {
constexpr int    kRecordMs = 2000;      // 记A / 记B: average over 2 s
constexpr int    kSampleMs = 100;
constexpr int    kFileVersion = 1;
constexpr int    kRtkFixed = 6;         // GPS_FIX_TYPE_RTK_FIXED
const char      *kSettingsGroup = "HHU";
const char      *kKeyPlanMode = "abPlanMode";
const char      *kKeyLastField = "abLastField";
// AB 线运行设置 (所有地块共用); 范围与 hhu_config.json 的读取范围一致
const char      *kKeyLeadD = "abLeadD";
const char      *kKeyLeadLc = "abLeadLc";
const char      *kKeySpeedTransport = "abSpeedTransport";
const char      *kKeySpeedWork = "abSpeedWork";

const char *statusName(int s)
{
    switch (s) {
    case HHUABField::Done:      return "done";
    case HHUABField::Skipped:   return "skipped";
    default:                    return "pending";
    }
}

int statusFromName(const QString &s)
{
    if (s == QStringLiteral("done"))    return HHUABField::Done;
    if (s == QStringLiteral("skipped")) return HHUABField::Skipped;
    return HHUABField::Pending;
}
} // namespace

HHUABField::HHUABField(HHUConfig *config, QObject *parent)
    : QObject(parent)
    , _config(config)
{
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    _planMode = qBound(0, settings.value(kKeyPlanMode, 0).toInt(), 1);
    // 改过的值存本机设置, 没改过用 hhu_config.json. 不再跟地块文件走 (以前新建地块时拷进文件, 改配置对已有地块不生效)
    const HHUConfig::ABLine &ab = _config->abLine();
    _leadD = qBound(0.0, settings.value(kKeyLeadD, ab.leadD).toDouble(), 20.0);
    _leadLc = qBound(1.0, settings.value(kKeyLeadLc, ab.leadLc).toDouble(), 50.0);
    _speedTransport = qBound(0.1, settings.value(kKeySpeedTransport, ab.speedTransport).toDouble(), 5.0);
    _speedWork = qBound(0.1, settings.value(kKeySpeedWork, ab.speedWork).toDouble(), 5.0);

    _recordTimer.setSingleShot(true);
    _recordTimer.setInterval(kRecordMs);
    (void) connect(&_recordTimer, &QTimer::timeout, this, &HHUABField::_finishRecord);
    _sampleTimer.setInterval(kSampleMs);
    (void) connect(&_sampleTimer, &QTimer::timeout, this, &HHUABField::_onSample);
    _status.assign(_count, Pending);
}

void HHUABField::setPlanMode(int mode)
{
    mode = qBound(0, mode, 1);
    if (mode == _planMode) {
        return;
    }
    _planMode = mode;
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    settings.setValue(kKeyPlanMode, mode);
    emit planModeChanged();
}

void HHUABField::_setRunSetting(double &member, double value, double lo, double hi, const char *key)
{
    value = std::round(qBound(lo, value, hi) * 100.0) / 100.0;
    if (qFuzzyCompare(value, member)) {
        return;
    }
    member = value;
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    settings.setValue(key, value);
    emit runSettingsChanged();
}

void HHUABField::setLeadD(double value)          { _setRunSetting(_leadD, value, 0.0, 20.0, kKeyLeadD); }
void HHUABField::setLeadLc(double value)         { _setRunSetting(_leadLc, value, 1.0, 50.0, kKeyLeadLc); }
void HHUABField::setSpeedTransport(double value) { _setRunSetting(_speedTransport, value, 0.1, 5.0, kKeySpeedTransport); }
void HHUABField::setSpeedWork(double value)      { _setRunSetting(_speedWork, value, 0.1, 5.0, kKeySpeedWork); }

// ---- Geometry -----------------------------------------------------------------------------------

double HHUABField::abLength() const
{
    if (!hasA() || !hasB()) {
        return qQNaN();
    }
    const hhuab::EN b = toEN(_b);
    return std::hypot(b.e, b.n);
}

double HHUABField::abBearing() const
{
    if (!hasA() || !hasB() || abLength() <= 0) {
        return qQNaN();
    }
    return hhuab::bearingDeg(hhuab::Line{ {}, toEN(_b) });
}

QGeoCoordinate HHUABField::toCoordinate(const hhuab::EN &p) const
{
    const hhuab::LatLon ll = _frame.toLatLon(p);
    return QGeoCoordinate(ll.lat, ll.lon);
}

hhuab::EN HHUABField::toEN(const QGeoCoordinate &c) const
{
    return _frame.toEN({ c.latitude(), c.longitude() });
}

void HHUABField::_rebuild()
{
    _lines.clear();
    if (hasA()) {
        _frame = hhuab::LocalFrame({ _a.latitude(), _a.longitude() });
    }
    if (hasA() && hasB()) {
        _lines = hhuab::makeLines({ 0, 0 }, toEN(_b), _rowWidth, _left, _count);
    }
    _status.resize(_count, Pending);
    if (_selected >= _count) {
        _selected = _count - 1;
    }
}

void HHUABField::_changed()
{
    _dirty = true;
    _modified = QDateTime::currentDateTime();
    emit fieldChanged();
}

QVariantList HHUABField::lines() const
{
    QVariantList out;
    for (size_t i = 0; i < _lines.size(); i++) {
        out.append(QVariantMap{
            { QStringLiteral("n"),      static_cast<int>(i) + 1 },
            { QStringLiteral("start"),  QVariant::fromValue(toCoordinate(_lines[i].start)) },
            { QStringLiteral("end"),    QVariant::fromValue(toCoordinate(_lines[i].end)) },
            { QStringLiteral("status"), lineStatus(static_cast<int>(i)) },
        });
    }
    return out;
}

int HHUABField::doneCount() const
{
    int n = 0;
    for (int i = 0; i < _count; i++) {
        n += lineStatus(i) == Done ? 1 : 0;
    }
    return n;
}

int HHUABField::lineStatus(int index) const
{
    return (index >= 0 && index < static_cast<int>(_status.size())) ? _status[index] : Pending;
}

void HHUABField::setRowWidth(double value)
{
    value = std::round(qBound(0.1, value, 5.0) * 100.0) / 100.0;
    if (qFuzzyCompare(value, _rowWidth)) {
        return;
    }
    _rowWidth = value;
    _rebuild();
    _changed();
}

void HHUABField::setLeft(bool value)
{
    if (value == _left) {
        return;
    }
    _left = value;
    _rebuild();
    _changed();
}

void HHUABField::setCount(int value)
{
    value = qBound(1, value, 200);
    if (value == _count) {
        return;
    }
    _count = value;
    _rebuild();
    _changed();
}

void HHUABField::setSelected(int index)
{
    index = qBound(0, index, _count - 1);
    if (index == _selected) {
        return;
    }
    _selected = index;
    _changed();
}

void HHUABField::setLineStatus(int index, int status)
{
    if (index < 0 || index >= _count || lineStatus(index) == status) {
        return;
    }
    _status[index] = qBound(0, status, 2);
    _changed();
}

int HHUABField::nextPending(int after) const
{
    for (int k = 1; k <= _count; k++) {
        const int i = (after + k) % _count;
        if (i >= 0 && lineStatus(i) == Pending) {
            return i;
        }
    }
    return -1;
}

// ---- 记A / 记B ------------------------------------------------------------------------------------

void HHUABField::record(int which)
{
    Vehicle *vehicle = MultiVehicleManager::instance()->activeVehicle();
    if (!vehicle || (which != 1 && which != 2) || _recording != 0) {
        return;
    }
    _recordVehicle = vehicle;
    _recording = which;
    _recordError.clear();
    _sumLat = _sumLon = 0;
    _samples = 0;
    _onSample();
    _sampleTimer.start();
    _recordTimer.start();
    emit recordingChanged();
}

void HHUABField::cancelRecord()
{
    _sampleTimer.stop();
    _recordTimer.stop();
    if (_recording != 0) {
        _recording = 0;
        emit recordingChanged();
    }
}

void HHUABField::_onSample()
{
    Vehicle *vehicle = _recordVehicle.data();
    if (!vehicle || vehicle != MultiVehicleManager::instance()->activeVehicle()) {
        _recordError = QStringLiteral("nodata");
        cancelRecord();
        return;
    }
    if (_config->abRequireRtkFixed()) {
        auto *gps = qobject_cast<VehicleGPSFactGroup *>(vehicle->gpsFactGroup());
        if (!gps || gps->lock()->rawValue().toInt() < kRtkFixed) {
            _recordError = QStringLiteral("rtk");
            cancelRecord();
            return;
        }
    }
    const QGeoCoordinate c = vehicle->coordinate();
    if (c.isValid()) {
        _sumLat += c.latitude();
        _sumLon += c.longitude();
        _samples++;
    }
}

void HHUABField::_finishRecord()
{
    _sampleTimer.stop();
    const int which = _recording;
    _recording = 0;
    if (_samples == 0) {
        _recordError = QStringLiteral("nodata");
        emit recordingChanged();
        return;
    }
    const QGeoCoordinate c(_sumLat / _samples, _sumLon / _samples);
    qCDebug(HHUABFieldLog) << "recorded" << (which == 1 ? "A" : "B") << qSetRealNumberPrecision(12) << c << _samples << "samples";
    if (which == 1) {
        _a = c;
    } else {
        _b = c;
    }
    _rebuild();
    emit recordingChanged();
    _changed();
}

// ---- Files ----------------------------------------------------------------------------------------

QString HHUABField::folder() const
{
    QString base = SettingsManager::instance()->appSettings()->savePath()->rawValue().toString();
    if (base.isEmpty()) {
        base = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    }
    return QDir(base).filePath(QStringLiteral("ABFields"));
}

QString HHUABField::_path(const QString &name) const
{
    return QDir(folder()).filePath(name + QStringLiteral(".json"));
}

bool HHUABField::_validName(const QString &name)
{
    static const QString bad = QStringLiteral("\\/:*?\"<>|");
    if (name.trimmed().isEmpty() || name != name.trimmed() || name.size() > 60) {
        return false;
    }
    for (const QChar c : name) {
        if (bad.contains(c) || c.unicode() < 0x20) {
            return false;
        }
    }
    return true;
}

bool HHUABField::fieldExists(const QString &name) const
{
    return _validName(name) && QFile::exists(_path(name));
}

void HHUABField::newField()
{
    cancelRecord();
    _name.clear();
    _a = QGeoCoordinate();
    _b = QGeoCoordinate();
    _status.assign(_count, Pending);
    _selected = 0;
    _created = QDateTime::currentDateTime();
    _rebuild();
    _changed();
    _dirty = false;
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    settings.remove(kKeyLastField);
    emit fieldChanged();
}

QVariantList HHUABField::fieldList() const
{
    QVariantList out;
    const QFileInfoList files = QDir(folder()).entryInfoList({ QStringLiteral("*.json") }, QDir::Files, QDir::Time);
    for (const QFileInfo &info : files) {
        QFile file(info.absoluteFilePath());
        if (!file.open(QIODevice::ReadOnly)) {
            continue;
        }
        const QJsonObject o = QJsonDocument::fromJson(file.readAll()).object();
        int done = 0;
        const QJsonArray lines = o.value(QStringLiteral("lines")).toArray();
        for (const QJsonValue &l : lines) {
            done += l.toObject().value(QStringLiteral("status")).toString() == QStringLiteral("done") ? 1 : 0;
        }
        out.append(QVariantMap{
            { QStringLiteral("name"),     info.completeBaseName() },
            { QStringLiteral("modified"), info.lastModified().toString(QStringLiteral("yyyy-MM-dd HH:mm")) },
            { QStringLiteral("done"),     done },
            { QStringLiteral("count"),    o.value(QStringLiteral("count")).toInt() },
        });
    }
    return out;
}

bool HHUABField::open(const QString &name)
{
    QFile file(_path(name));
    if (!_validName(name) || !file.open(QIODevice::ReadOnly)) {
        qCWarning(HHUABFieldLog) << "cannot open field" << name;
        return false;
    }
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qCWarning(HHUABFieldLog) << name << "is not valid JSON:" << error.errorString();
        return false;
    }
    const QJsonObject o = doc.object();
    auto coord = [](const QJsonValue &v) {
        const QJsonObject p = v.toObject();
        if (!p.contains(QStringLiteral("lat")) || !p.contains(QStringLiteral("lon"))) {
            return QGeoCoordinate();
        }
        return QGeoCoordinate(p.value(QStringLiteral("lat")).toDouble(), p.value(QStringLiteral("lon")).toDouble());
    };

    cancelRecord();
    _name = name;
    _a = coord(o.value(QStringLiteral("a")));
    _b = coord(o.value(QStringLiteral("b")));
    _rowWidth = qBound(0.1, o.value(QStringLiteral("rowWidth")).toDouble(0.25), 5.0);
    _left = o.value(QStringLiteral("side")).toString() != QStringLiteral("right");
    _count = qBound(1, o.value(QStringLiteral("count")).toInt(10), 200);
    // 旧版地块文件里的 "d" / "Lc" 不再使用: 引导段用全局 AB 线设置
    _created = QDateTime::fromString(o.value(QStringLiteral("created")).toString(), Qt::ISODate);
    _modified = QDateTime::fromString(o.value(QStringLiteral("modified")).toString(), Qt::ISODate);
    _status.assign(_count, Pending);
    const QJsonArray lines = o.value(QStringLiteral("lines")).toArray();
    for (const QJsonValue &v : lines) {
        const QJsonObject l = v.toObject();
        const int i = l.value(QStringLiteral("n")).toInt() - 1;
        if (i >= 0 && i < _count) {
            _status[i] = statusFromName(l.value(QStringLiteral("status")).toString());
        }
    }
    _selected = qBound(0, o.value(QStringLiteral("startLine")).toInt(1) - 1, _count - 1);
    _rebuild();
    _dirty = false;
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    settings.setValue(kKeyLastField, name);
    emit fieldChanged();
    return true;
}

void HHUABField::restoreLast()
{
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    const QString last = settings.value(kKeyLastField).toString();
    if (!last.isEmpty() && fieldExists(last)) {
        (void) open(last);
    }
}

bool HHUABField::_write(const QString &path)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        return false;
    }
    auto coord = [](const QGeoCoordinate &c) {
        return c.isValid() ? QJsonValue(QJsonObject{ { QStringLiteral("lat"), c.latitude() }, { QStringLiteral("lon"), c.longitude() } })
                           : QJsonValue();
    };
    QJsonArray lines;
    for (int i = 0; i < _count; i++) {
        lines.append(QJsonObject{ { QStringLiteral("n"), i + 1 }, { QStringLiteral("status"), QString::fromLatin1(statusName(lineStatus(i))) } });
    }
    if (!_created.isValid()) {
        _created = QDateTime::currentDateTime();
    }
    _modified = QDateTime::currentDateTime();
    const QJsonObject o {
        { QStringLiteral("version"),   kFileVersion },
        { QStringLiteral("a"),         coord(_a) },
        { QStringLiteral("b"),         coord(_b) },
        { QStringLiteral("rowWidth"),  _rowWidth },
        { QStringLiteral("side"),      _left ? QStringLiteral("left") : QStringLiteral("right") },
        { QStringLiteral("count"),     _count },
        { QStringLiteral("startLine"), _selected + 1 },
        { QStringLiteral("lines"),     lines },
        { QStringLiteral("created"),   _created.toString(Qt::ISODateWithMs) },
        { QStringLiteral("modified"),  _modified.toString(Qt::ISODateWithMs) },
    };
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    (void) file.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
    return file.commit();
}

bool HHUABField::save()
{
    if (_name.isEmpty()) {
        return false;
    }
    if (!_write(_path(_name))) {
        qCWarning(HHUABFieldLog) << "cannot write field" << _path(_name);
        return false;
    }
    _dirty = false;
    emit fieldChanged();
    return true;
}

bool HHUABField::saveAs(const QString &name)
{
    if (!_validName(name)) {
        return false;
    }
    const QString old = _name;
    _name = name;
    if (!save()) {
        _name = old;
        emit fieldChanged();
        return false;
    }
    QSettings settings;
    settings.beginGroup(kSettingsGroup);
    settings.setValue(kKeyLastField, name);
    return true;
}
