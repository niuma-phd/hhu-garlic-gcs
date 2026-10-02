#include "HHUConfig.h"
#include "QGCLoggingCategory.h"

#include <algorithm>

#include <QtCore/QCoreApplication>
#include <QtCore/QDate>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QLocale>

QGC_LOGGING_CATEGORY(HHUConfigLog, "Custom.HHUConfig")

HHUConfig::HHUConfig(QObject *parent)
    : QObject(parent)
{
    const QString userFile = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("config/hhu_config.json"));
    if (QFile::exists(userFile) && _load(userFile)) {
        return;
    }
    (void) _load(QStringLiteral(":/hhu/config/hhu_config.json"));
}

bool HHUConfig::_load(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(HHUConfigLog) << "cannot open" << path;
        return false;
    }
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qCWarning(HHUConfigLog) << path << "is not valid JSON:" << error.errorString() << "at offset" << error.offset;
        return false;
    }

    const QJsonObject root = doc.object();
    _statusText = _readEntries(root.value(QStringLiteral("statusText")));
    _preArm     = _readEntries(root.value(QStringLiteral("preArm")));
    _faults.clear();
    const QJsonObject faults = root.value(QStringLiteral("faultCodes")).toObject();
    for (auto it = faults.begin(); it != faults.end(); ++it) {
        bool ok = false;
        const int code = it.key().toInt(&ok, 0);   // "0x1A" or "26"
        if (ok) {
            _faults.insert(code, it.value().toString());
        }
    }
    _ntripProviders = root.value(QStringLiteral("ntripProviders")).toArray().toVariantList();
    _serverBaseUrl = root.value(QStringLiteral("server")).toObject().value(QStringLiteral("baseUrl")).toString().trimmed();
    _source = path;
    qCDebug(HHUConfigLog) << "loaded" << path << _statusText.count() << "statustext" << _preArm.count() << "prearm" << _faults.count() << "faults";
    return true;
}

QList<HHUConfig::Entry> HHUConfig::_readEntries(const QJsonValue &value)
{
    QList<Entry> entries;
    for (const QJsonValue &v : value.toArray()) {
        const QJsonObject o = v.toObject();
        Entry e{ o.value(QStringLiteral("prefix")).toString(), o.value(QStringLiteral("text")).toString() };
        if (!e.prefix.isEmpty() && !e.text.isEmpty()) {
            entries.append(e);
        }
    }
    // Longest prefix first, so specific entries win over general ones
    std::stable_sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) { return a.prefix.size() > b.prefix.size(); });
    return entries;
}

const HHUConfig::Entry *HHUConfig::_match(const QList<Entry> &entries, const QString &text)
{
    for (const Entry &e : entries) {
        if (text.startsWith(e.prefix, Qt::CaseInsensitive)) {
            return &e;
        }
    }
    return nullptr;
}

QString HHUConfig::translateStatusText(const QString &text) const
{
    const Entry *e = _match(_statusText, text);
    if (!e) {
        return QString();
    }

    const QString rest = text.mid(e->prefix.size()).trimmed();
    QString result = e->text;

    if (result.contains(QStringLiteral("{reason}"))) {
        // PreArm / Arm: translate the reason itself, keep the original when unknown
        const Entry *r = _match(_preArm, rest);
        result.replace(QStringLiteral("{reason}"), r ? r->text : rest);
    }
    if (result.contains(QStringLiteral("{fault}"))) {
        // "VCU: fault 0x1A" -> "0x1A 电机过流" (description from faultCodes when known)
        const QString hex = rest.section(QLatin1Char(' '), 0, 0);
        bool ok = false;
        const int code = hex.toInt(&ok, 16);
        QString fault = QStringLiteral("0x") + hex.toUpper();
        if (ok && !faultText(code).isEmpty()) {
            fault += QStringLiteral(" ") + faultText(code);
        }
        result.replace(QStringLiteral("{fault}"), fault);
    }
    result.replace(QStringLiteral("{first}"), rest.section(QLatin1Char(' '), 0, 0));
    result.replace(QStringLiteral("{rest}"), rest);
    return result;
}

QString HHUConfig::buildDate()
{
    // __DATE__ is "Sep 25 2026" (day padded with a space below 10)
    const QDate date = QLocale::c().toDate(QString::fromLatin1(__DATE__).simplified(), QStringLiteral("MMM d yyyy"));
    return date.isValid() ? date.toString(Qt::ISODate) : QString::fromLatin1(__DATE__);
}

QString HHUConfig::faultText(int code) const
{
    return _faults.value(code);
}
