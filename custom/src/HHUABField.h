#pragma once

#include <QtCore/QDateTime>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtPositioning/QGeoCoordinate>

#include <vector>

#include "HHUABGeometry.h"

class HHUConfig;
class Vehicle;

/// AB 线地块 (规划页 AB线 mode). A and B are recorded from the vehicle position, the lines are AB moved
/// sideways by whole row widths (line 1 = AB, odd lines A→B, even lines B→A). Each line is 未走 / 完成 /
/// 跳过. Saved as <save path>/ABFields/<name>.json. Exposed to QML as hhuAB.
class HHUABField : public QObject
{
    Q_OBJECT
    /// 0 手工航点, 1 AB线 (the 规划 page mode, remembered)
    Q_PROPERTY(int      planMode    READ planMode   WRITE setPlanMode   NOTIFY planModeChanged)

    Q_PROPERTY(QString  name        READ name                           NOTIFY fieldChanged)    ///< "" = not saved yet
    Q_PROPERTY(bool     dirty       READ dirty                          NOTIFY fieldChanged)
    Q_PROPERTY(bool     hasA        READ hasA                           NOTIFY fieldChanged)
    Q_PROPERTY(bool     hasB        READ hasB                           NOTIFY fieldChanged)
    Q_PROPERTY(QGeoCoordinate a     READ a                              NOTIFY fieldChanged)
    Q_PROPERTY(QGeoCoordinate b     READ b                              NOTIFY fieldChanged)
    Q_PROPERTY(double   abLength    READ abLength                       NOTIFY fieldChanged)    ///< m, NaN without A and B
    Q_PROPERTY(double   abBearing   READ abBearing                      NOTIFY fieldChanged)    ///< deg A→B, NaN without A and B
    Q_PROPERTY(double   rowWidth    READ rowWidth   WRITE setRowWidth   NOTIFY fieldChanged)    ///< 垄宽 m
    Q_PROPERTY(bool     left        READ left       WRITE setLeft       NOTIFY fieldChanged)    ///< lines to the left of A→B
    Q_PROPERTY(int      count       READ count      WRITE setCount      NOTIFY fieldChanged)    ///< 条数
    /// [{ n, start, end, status }] with status 0 未走, 1 完成, 2 跳过
    Q_PROPERTY(QVariantList lines   READ lines                          NOTIFY fieldChanged)
    Q_PROPERTY(int      doneCount   READ doneCount                      NOTIFY fieldChanged)
    /// line to start from (0-based), -1 = none
    Q_PROPERTY(int      selected    READ selected   WRITE setSelected   NOTIFY fieldChanged)

    /// AB 线运行设置: 所有地块共用, 存本机设置 (QSettings), 没改过时用 hhu_config.json 的值
    Q_PROPERTY(double   leadD          READ leadD          WRITE setLeadD          NOTIFY runSettingsChanged)  ///< 对准点在起点前 m
    Q_PROPERTY(double   leadLc         READ leadLc         WRITE setLeadLc         NOTIFY runSettingsChanged)  ///< 对准引导段 m
    Q_PROPERTY(double   speedTransport READ speedTransport WRITE setSpeedTransport NOTIFY runSettingsChanged)  ///< 杆收着 (对准) m/s
    Q_PROPERTY(double   speedWork      READ speedWork      WRITE setSpeedWork      NOTIFY runSettingsChanged)  ///< 杆放下 (作业) m/s

    /// 记A / 记B in progress: 0 none, 1 A, 2 B
    Q_PROPERTY(int      recording   READ recording                      NOTIFY recordingChanged)
    /// last 记A / 记B failure: "" | "rtk" (RTK fixed lost while averaging) | "nodata"
    Q_PROPERTY(QString  recordError READ recordError                    NOTIFY recordingChanged)

public:
    enum LineStatus { Pending = 0, Done = 1, Skipped = 2 };
    Q_ENUM(LineStatus)

    HHUABField(HHUConfig *config, QObject *parent = nullptr);

    int     planMode() const { return _planMode; }
    void    setPlanMode(int mode);

    QString name() const { return _name; }
    bool    dirty() const { return _dirty; }
    bool    hasA() const { return _a.isValid(); }
    bool    hasB() const { return _b.isValid(); }
    QGeoCoordinate a() const { return _a; }
    QGeoCoordinate b() const { return _b; }
    double  abLength() const;
    double  abBearing() const;
    double  rowWidth() const { return _rowWidth; }
    bool    left() const { return _left; }
    int     count() const { return _count; }
    QVariantList lines() const;
    int     doneCount() const;
    int     selected() const { return _selected; }
    int     recording() const { return _recording; }
    QString recordError() const { return _recordError; }

    void setRowWidth(double value);
    void setLeft(bool value);
    void setCount(int value);
    void setSelected(int index);

    /// Lines in the frame of A (empty without A and B)
    const std::vector<hhuab::Line> &geometry() const { return _lines; }
    const hhuab::LocalFrame &frame() const { return _frame; }
    QGeoCoordinate toCoordinate(const hhuab::EN &p) const;
    hhuab::EN toEN(const QGeoCoordinate &c) const;
    int lineStatus(int index) const;
    double leadD() const { return _leadD; }
    double leadLc() const { return _leadLc; }
    double speedTransport() const { return _speedTransport; }
    double speedWork() const { return _speedWork; }
    void   setLeadD(double value);
    void   setLeadLc(double value);
    void   setSpeedTransport(double value);
    void   setSpeedWork(double value);

    /// Averages the vehicle position (EKF, the position shown on the map) over 2 s
    Q_INVOKABLE void record(int which);     ///< 1 = A, 2 = B
    Q_INVOKABLE void cancelRecord();

    Q_INVOKABLE void setLineStatus(int index, int status);
    /// First line after `after` (wrapping round) that is neither done nor skipped; -1 when there is none
    Q_INVOKABLE int nextPending(int after) const;

    /// New empty field (A / B / lines cleared, row settings kept)
    Q_INVOKABLE void newField();
    /// Saved fields, newest first: [{ name, modified, done, count }]
    Q_INVOKABLE QVariantList fieldList() const;
    Q_INVOKABLE bool open(const QString &name);
    /// Save under the current name (false when there is none or writing failed)
    Q_INVOKABLE bool save();
    Q_INVOKABLE bool saveAs(const QString &name);
    Q_INVOKABLE bool fieldExists(const QString &name) const;
    /// Opens the field used last (at start-up), the progress of its lines included
    void restoreLast();
    /// Folder of the field files (<save path>/ABFields)
    Q_INVOKABLE QString folder() const;

signals:
    void planModeChanged();
    void fieldChanged();
    void runSettingsChanged();
    void recordingChanged();

private:
    void _rebuild();
    void _changed();
    void _onSample();
    void _finishRecord();
    void _setRunSetting(double &member, double value, double lo, double hi, const char *key);
    QString _path(const QString &name) const;
    bool _write(const QString &path);
    static bool _validName(const QString &name);

    HHUConfig *_config = nullptr;
    int        _planMode = 0;

    QString    _name;
    bool       _dirty = false;
    QDateTime  _created;
    QDateTime  _modified;
    QGeoCoordinate _a;
    QGeoCoordinate _b;
    double     _rowWidth = 0.25;
    bool       _left = true;
    int        _count = 10;
    double     _leadD = 1.0;
    double     _leadLc = 5.0;
    double     _speedTransport = 1.39;
    double     _speedWork = 0.55;
    std::vector<int> _status;
    int        _selected = 0;

    hhuab::LocalFrame _frame { hhuab::LatLon{} };
    std::vector<hhuab::Line> _lines;

    int        _recording = 0;
    QString    _recordError;
    QPointer<Vehicle> _recordVehicle;
    QTimer     _recordTimer;
    QTimer     _sampleTimer;
    double     _sumLat = 0;
    double     _sumLon = 0;
    int        _samples = 0;
};
