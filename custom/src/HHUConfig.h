#pragma once

#include <QtCore/QHash>
#include <QtCore/QList>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>

#include <functional>

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
    /// features.returnHome: 返回起点 on the work panel (not used this phase, off by default)
    Q_PROPERTY(bool featureReturnHome READ featureReturnHome CONSTANT)
    /// abLine.abRequireRtkFixed: 记A / 记B only with RTK fixed (SITL: set false)
    Q_PROPERTY(bool abRequireRtkFixed READ abRequireRtkFixed CONSTANT)
    /// abLine.abWorkLink: false = AB lines are driven without lowering / raising the lift
    Q_PROPERTY(bool abWorkLink READ abWorkLink CONSTANT)
    Q_PROPERTY(int    abLiftTimeout  READ abLiftTimeout  CONSTANT)   ///< s
    Q_PROPERTY(double abAlignXtrack  READ abAlignXtrack  CONSTANT)   ///< m
    Q_PROPERTY(double abAlignHeading READ abAlignHeading CONSTANT)   ///< deg

public:
    explicit HHUConfig(QObject *parent = nullptr);

    QString source() const { return _source; }
    static QString buildDate();
    bool featureReturnHome() const { return _featureReturnHome; }

    /// AB line run settings (abLine in hhu_config.json, not shown in the UI)
    struct ABLine {
        double leadD        = 1.0;      ///< abLeadD: alignment point this far before the start (m)
        double leadLc       = 5.0;      ///< abLeadLc: length of the lead-in before the alignment point (m)
        double alignXtrack  = 0.20;     ///< abAlignXtrack: alignment OK below this cross-track error (m)
        double alignHeading = 8.0;      ///< abAlignHeading: alignment OK below this heading error (deg)
        int    liftTimeout  = 20;       ///< abLiftTimeout: wait for lowering / raising (s)
        bool   workLink     = true;     ///< abWorkLink
        bool   requireRtkFixed = true;  ///< abRequireRtkFixed
        double speedTransport = 1.39;   ///< abSpeedTransport: lift up, the VCU allows 5 km/h (m/s)
        double speedWork      = 0.55;   ///< abSpeedWork: lift down, the VCU allows 2 km/h (m/s)
    };
    const ABLine &abLine() const { return _abLine; }
    bool abRequireRtkFixed() const { return _abLine.requireRtkFixed; }
    bool abWorkLink() const { return _abLine.workLink; }
    int    abLiftTimeout() const { return _abLine.liftTimeout; }
    double abAlignXtrack() const { return _abLine.alignXtrack; }
    double abAlignHeading() const { return _abLine.alignHeading; }

    /// Customer wording for a vehicle STATUSTEXT, or an empty string when no entry matches.
    /// waypointNumber turns the mission sequence after the prefix into the waypoint number ({wp});
    /// a text whose sequence is no waypoint (0) counts as untranslated.
    QString translateStatusText(const QString &text, const std::function<int(int)> &waypointNumber = {}) const;

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
    bool            _featureReturnHome = false;
    ABLine          _abLine;
};
