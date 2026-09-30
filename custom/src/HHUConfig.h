#pragma once

#include <QtCore/QHash>
#include <QtCore/QList>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>

/// Editable product tables (需求说明 V1.0 §3.6, §5 配置文件): vehicle STATUSTEXT translations,
/// PreArm reasons and VCU fault codes. Read from <exe dir>/config/hhu_config.json so they can be
/// changed without rebuilding; the copy built into the program is used when that file is missing
/// or broken. Exposed to QML as hhuConfig.
class HHUConfig : public QObject
{
    Q_OBJECT
    /// File the tables were loaded from (shown on the 关于 page)
    Q_PROPERTY(QString source READ source CONSTANT)
    /// Compile date of the HHU plugin, yyyy-MM-dd (关于 page)
    Q_PROPERTY(QString buildDate READ buildDate CONSTANT)

public:
    explicit HHUConfig(QObject *parent = nullptr);

    QString source() const { return _source; }
    static QString buildDate();

    /// Customer wording for a vehicle STATUSTEXT, or an empty string when no entry matches
    QString translateStatusText(const QString &text) const;

    /// Chinese description of a VCU fault code, empty when the code is not in the table
    Q_INVOKABLE QString faultText(int code) const;

    /// RTK service presets [{ name, host, port }]
    QVariantList ntripProviders() const { return _ntripProviders; }
    /// Base URL of the update / log upload service ("" = derive from the 4G server)
    QString serverBaseUrl() const { return _serverBaseUrl; }

private:
    struct Entry {
        QString prefix;
        QString text;
    };

    bool _load(const QString &path);
    static QList<Entry> _readEntries(const QJsonValue &value);
    static const Entry *_match(const QList<Entry> &entries, const QString &text);

    QString         _source;
    QList<Entry>    _statusText;
    QList<Entry>    _preArm;
    QHash<int, QString> _faults;
    QVariantList    _ntripProviders;
    QString         _serverBaseUrl;
};
