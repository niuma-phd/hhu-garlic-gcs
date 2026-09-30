#pragma once

#include <QtCore/QObject>
#include <QtCore/QVariantList>

/// 地块管理 (需求说明 V1.0 §3.3). A field has a name, a work width (作业幅宽) and a QGC .plan file
/// holding its geofence and route. Stored under <AppData>/fields (kept by upgrades):
/// index.json with the field list, <id>.plan per field. Exposed to QML as hhuFields.
class HHUFieldManager : public QObject
{
    Q_OBJECT
    /// [{ id, name, swath, area, lastWork, created, modified }], most recently changed first
    Q_PROPERTY(QVariantList fields      READ fields                         NOTIFY fieldsChanged)
    /// Field currently open on the 航线 page ("" = none)
    Q_PROPERTY(QString      currentId   READ currentId  WRITE setCurrentId  NOTIFY currentIdChanged)
    Q_PROPERTY(QVariantMap  current     READ current                        NOTIFY currentIdChanged)

public:
    explicit HHUFieldManager(QObject *parent = nullptr);

    static QString dataDir();

    QVariantList fields() const { return _fields; }
    QString currentId() const { return _currentId; }
    QVariantMap current() const { return field(_currentId); }
    void setCurrentId(const QString &id);

    Q_INVOKABLE QVariantMap field(const QString &id) const;
    /// New empty field; returns its id
    Q_INVOKABLE QString create(const QString &name, double swath);
    Q_INVOKABLE void rename(const QString &id, const QString &name);
    /// Copy with name "<name> 副本"; returns the new id
    Q_INVOKABLE QString duplicate(const QString &id);
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE void setSwath(const QString &id, double swath);
    /// Geofence area in m², updated whenever the field's plan is saved
    Q_INVOKABLE void setArea(const QString &id, double squareMeters);
    Q_INVOKABLE void markWorked(const QString &id);
    Q_INVOKABLE void touch(const QString &id);
    /// Absolute path of the field's .plan file (may not exist yet for a new field)
    Q_INVOKABLE QString planFile(const QString &id) const;
    /// The field has a saved route / fence
    Q_INVOKABLE bool hasPlan(const QString &id) const;
    Q_INVOKABLE bool nameExists(const QString &name, const QString &exceptId = QString()) const;

signals:
    void fieldsChanged();
    void currentIdChanged();

private:
    int _indexOf(const QString &id) const;
    void _set(const QString &id, const char *key, const QVariant &value, bool touchModified = true);
    void _load();
    void _save();
    void _sort();

    QVariantList _fields;
    QString      _currentId;
};
