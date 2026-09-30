#include "HHUFieldManager.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSaveFile>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtCore/QTimer>
#include <QtCore/QUuid>

#include <algorithm>

QGC_LOGGING_CATEGORY(HHUFieldLog, "Custom.HHUFieldManager")

namespace {
QString now() { return QDateTime::currentDateTime().toString(Qt::ISODate); }
}

HHUFieldManager::HHUFieldManager(QObject *parent)
    : QObject(parent)
{
    // The data folder depends on the application name, which is final only once the application runs
    QTimer::singleShot(0, this, [this]() {
        (void) QDir().mkpath(dataDir());
        _load();
        _currentId = QSettings().value(QStringLiteral("HHU/currentField")).toString();
        if (_indexOf(_currentId) < 0) {
            _currentId.clear();
        }
        qCDebug(HHUFieldLog) << "fields" << dataDir() << _fields.count();
        emit fieldsChanged();
        emit currentIdChanged();
    });
}

QString HHUFieldManager::dataDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/fields");
}

QString HHUFieldManager::planFile(const QString &id) const
{
    return id.isEmpty() ? QString() : QDir(dataDir()).filePath(id + QStringLiteral(".plan"));
}

bool HHUFieldManager::hasPlan(const QString &id) const
{
    return !id.isEmpty() && QFile::exists(planFile(id));
}

void HHUFieldManager::_load()
{
    QFile file(QDir(dataDir()).filePath(QStringLiteral("index.json")));
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonArray list = QJsonDocument::fromJson(file.readAll()).array();
    _fields.clear();
    for (const QJsonValue &v : list) {
        const QVariantMap f = v.toObject().toVariantMap();
        if (!f.value(QStringLiteral("id")).toString().isEmpty()) {
            _fields.append(f);
        }
    }
    _sort();
}

void HHUFieldManager::_save()
{
    QJsonArray list;
    for (const QVariant &f : std::as_const(_fields)) {
        list.append(QJsonObject::fromVariantMap(f.toMap()));
    }
    // Write-then-rename so a crash never leaves a half written index
    QSaveFile file(QDir(dataDir()).filePath(QStringLiteral("index.json")));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(list).toJson());
        if (!file.commit()) {
            qCWarning(HHUFieldLog) << "cannot write field index" << file.errorString();
        }
    }
}

void HHUFieldManager::_sort()
{
    std::stable_sort(_fields.begin(), _fields.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("modified")).toString() > b.toMap().value(QStringLiteral("modified")).toString();
    });
}

int HHUFieldManager::_indexOf(const QString &id) const
{
    for (int i = 0; i < _fields.count(); i++) {
        if (_fields[i].toMap().value(QStringLiteral("id")).toString() == id) {
            return i;
        }
    }
    return -1;
}

QVariantMap HHUFieldManager::field(const QString &id) const
{
    const int i = _indexOf(id);
    return i < 0 ? QVariantMap() : _fields[i].toMap();
}

void HHUFieldManager::_set(const QString &id, const char *key, const QVariant &value, bool touchModified)
{
    const int i = _indexOf(id);
    if (i < 0) {
        return;
    }
    QVariantMap f = _fields[i].toMap();
    f.insert(QString::fromLatin1(key), value);
    if (touchModified) {
        f.insert(QStringLiteral("modified"), now());
    }
    _fields[i] = f;
    _sort();
    _save();
    emit fieldsChanged();
    if (id == _currentId) {
        emit currentIdChanged();
    }
}

void HHUFieldManager::setCurrentId(const QString &id)
{
    if (id != _currentId) {
        _currentId = (_indexOf(id) >= 0) ? id : QString();
        QSettings().setValue(QStringLiteral("HHU/currentField"), _currentId);
        emit currentIdChanged();
    }
}

bool HHUFieldManager::nameExists(const QString &name, const QString &exceptId) const
{
    for (const QVariant &v : _fields) {
        const QVariantMap f = v.toMap();
        if (f.value(QStringLiteral("name")).toString() == name.trimmed() && f.value(QStringLiteral("id")).toString() != exceptId) {
            return true;
        }
    }
    return false;
}

QString HHUFieldManager::create(const QString &name, double swath)
{
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    QVariantMap f;
    f.insert(QStringLiteral("id"), id);
    f.insert(QStringLiteral("name"), name.trimmed());
    f.insert(QStringLiteral("swath"), swath);
    f.insert(QStringLiteral("area"), 0.0);
    f.insert(QStringLiteral("lastWork"), QString());
    f.insert(QStringLiteral("created"), now());
    f.insert(QStringLiteral("modified"), now());
    _fields.append(f);
    _sort();
    _save();
    emit fieldsChanged();
    return id;
}

void HHUFieldManager::rename(const QString &id, const QString &name)
{
    _set(id, "name", name.trimmed());
}

QString HHUFieldManager::duplicate(const QString &id)
{
    const QVariantMap src = field(id);
    if (src.isEmpty()) {
        return QString();
    }
    QString name = tr("%1 copy").arg(src.value(QStringLiteral("name")).toString());
    for (int n = 2; nameExists(name); n++) {
        name = tr("%1 copy %2").arg(src.value(QStringLiteral("name")).toString()).arg(n);
    }
    const QString newId = create(name, src.value(QStringLiteral("swath")).toDouble());
    (void) QFile::copy(planFile(id), planFile(newId));
    _set(newId, "area", src.value(QStringLiteral("area")));
    return newId;
}

void HHUFieldManager::remove(const QString &id)
{
    const int i = _indexOf(id);
    if (i < 0) {
        return;
    }
    _fields.removeAt(i);
    (void) QFile::remove(planFile(id));
    _save();
    emit fieldsChanged();
    if (id == _currentId) {
        setCurrentId(QString());
    }
}

void HHUFieldManager::setSwath(const QString &id, double swath)
{
    _set(id, "swath", std::max(0.0, swath));
}

void HHUFieldManager::setArea(const QString &id, double squareMeters)
{
    _set(id, "area", std::max(0.0, squareMeters), false);
}

void HHUFieldManager::markWorked(const QString &id)
{
    _set(id, "lastWork", now(), false);
}

void HHUFieldManager::touch(const QString &id)
{
    _set(id, "modified", now(), false);
}
