#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtPositioning/QGeoCoordinate>

#include "HHUABGeometry.h"
#include "MAVLinkLib.h"

class HHUTuning;
class Vehicle;

/// 直线测试 (工程调参, engineeringTuning only): drives the vehicle straight ahead to tune its motion
/// parameters. The line starts at the vehicle and runs along its heading at the moment of the start; the
/// vehicle drives to the line's end in GUIDED at the chosen ground speed (DO_CHANGE_SPEED), optionally back
/// (往返). While it drives the cross-track / heading error, speed and position along the line are shown
/// live; every run is scored per leg (cross-track RMS / max / steady part / bias / crossings, heading RMS,
/// speed, stop overshoot) and logged with the values of the tuning list's parameters, so runs before and
/// after a parameter change can be compared:
///   <save path>/直线测试/<vehicle>/<time>_明细.csv   every position message of the run
///   <save path>/直线测试/<vehicle>/汇总.csv          one row per leg, with the parameter values
/// Ends with HOLD + disarm. Disarming (急停), leaving GUIDED or losing the link aborts the run; what was
/// driven is still scored and logged as aborted.
class HHUStraightTest : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int      phase       READ phase      NOTIFY stateChanged)
    Q_PROPERTY(bool     active      READ active     NOTIFY stateChanged)
    Q_PROPERTY(int      leg         READ leg        NOTIFY stateChanged)    ///< 1 去, 2 回
    Q_PROPERTY(bool     roundTrip   READ roundTrip  NOTIFY stateChanged)
    Q_PROPERTY(double   length      READ length     NOTIFY stateChanged)    ///< m
    Q_PROPERTY(double   speedSet    READ speedSet   NOTIFY stateChanged)    ///< m/s
    Q_PROPERTY(QGeoCoordinate lineStart READ lineStart NOTIFY stateChanged)
    Q_PROPERTY(QGeoCoordinate lineEnd   READ lineEnd   NOTIFY stateChanged)
    Q_PROPERTY(QString  message     READ message    NOTIFY stateChanged)    ///< why the last run stopped early
    Q_PROPERTY(double   xtrack      READ xtrack     NOTIFY sampleChanged)   ///< m, + = left of the line, NaN unknown
    Q_PROPERTY(double   headingErr  READ headingErr NOTIFY sampleChanged)   ///< deg
    Q_PROPERTY(double   speed       READ speed      NOTIFY sampleChanged)   ///< m/s
    Q_PROPERTY(double   along       READ along      NOTIFY sampleChanged)   ///< m from the leg's start
    /// current leg for the chart: [{ s: along m, x: cross-track m }]
    Q_PROPERTY(QVariantList chart   READ chart      NOTIFY sampleChanged)
    /// results of the last run, one map per leg (see _legResult); [] while none
    Q_PROPERTY(QVariantList results READ results    NOTIFY resultsChanged)
    /// the run before it (same vehicle, from 汇总.csv), for the comparison
    Q_PROPERTY(QVariantList previous READ previous  NOTIFY resultsChanged)
    /// tuning list parameters that differ from the run before: ["NAME old → new"]
    Q_PROPERTY(QStringList changedParams READ changedParams NOTIFY resultsChanged)
    Q_PROPERTY(QString  folder      READ folder     NOTIFY resultsChanged)

public:
    enum Phase { Idle, Starting, Driving, Stopping };
    Q_ENUM(Phase)

    explicit HHUStraightTest(HHUTuning *tuning, QObject *parent = nullptr);

    int     phase() const { return _phase; }
    bool    active() const { return _phase != Idle; }
    int     leg() const { return _leg; }
    bool    roundTrip() const { return _roundTrip; }
    double  length() const { return _length; }
    double  speedSet() const { return _speedSet; }
    QGeoCoordinate lineStart() const { return _start; }
    QGeoCoordinate lineEnd() const { return _end; }
    QString message() const { return _message; }
    double  xtrack() const { return _xtrack; }
    double  headingErr() const { return _headingErr; }
    double  speed() const { return _speed; }
    double  along() const { return _along; }
    QVariantList chart() const { return _chart; }
    QVariantList results() const { return _results; }
    QVariantList previous() const { return _previous; }
    QStringList changedParams() const { return _changedParams; }
    QString folder() const;

    /// Starts a run from the vehicle's position along its heading. Returns "" or why it cannot start
    /// (the drive checks — chassis, Ready, position — are done in QML before).
    Q_INVOKABLE QString start(double length, double speed, bool roundTrip);
    /// Stops the run: HOLD + disarm (what was driven is logged as aborted)
    Q_INVOKABLE void stop();
    Q_INVOKABLE void clearResults();
    /// The last summary rows of this vehicle, newest first (for the 工程调参 page)
    Q_INVOKABLE QVariantList history(int count) const;
    Q_INVOKABLE void openFolder() const;

    void handleMessage(Vehicle *vehicle, const mavlink_message_t &message);

signals:
    void stateChanged();
    void sampleChanged();
    void resultsChanged();
    /// a run ended (normally or aborted): results are ready
    void finished();

private:
    struct Sample {
        double t = 0;           ///< s since the start of the run
        int    leg = 1;
        double lat = 0, lon = 0;
        double along = 0, xtrack = 0;
        double heading = 0, headingErr = 0;
        double speed = 0;
        int    throttle = 0;
        double fcXtrack = qQNaN();
        int    servo1 = 0, servo3 = 0;
    };

    void _setPhase(Phase phase);
    void _setRates(bool fast);
    void _onArmedChanged(bool armed);
    void _onFlightModeChanged(const QString &mode);
    void _onTick();
    void _sendGoto();
    void _startLeg(int leg);
    void _finishLeg(bool aborted, const QString &reason);
    void _finishRun(bool aborted, const QString &reason);
    QVariantMap _legResult(int leg, bool aborted) const;
    QVariantMap _paramSnapshot() const;
    void _writeFiles(const QVariantMap &params);
    QVariantList _readSummary(int count) const;
    QString _vehicleName() const;

    HHUTuning           *_tuning = nullptr;
    QPointer<Vehicle>   _vehicle;
    Phase   _phase = Idle;
    int     _leg = 1;
    bool    _roundTrip = false;
    double  _length = 0;
    double  _speedSet = 0;
    QGeoCoordinate _start, _end;
    hhuab::Line     _line;          ///< current leg, in the frame of _start
    hhuab::LatLon   _origin;
    QString _message;
    bool    _abortedRun = false;

    double  _lastHeading = qQNaN();  ///< deg, GLOBAL_POSITION_INT.hdg
    double  _xtrack = qQNaN();
    double  _headingErr = qQNaN();
    double  _speed = qQNaN();
    double  _along = qQNaN();
    int     _throttle = 0;
    double  _fcXtrack = qQNaN();
    int     _servo1 = 0, _servo3 = 0;
    QVariantList _chart;

    QList<Sample> _samples;         ///< whole run
    QElapsedTimer _runClock;
    QElapsedTimer _legClock;
    QElapsedTimer _stillSince;
    QElapsedTimer _lastPosition;
    int     _gotoSends = 0;

    QVariantList _results;
    QVariantList _previous;
    QStringList  _changedParams;
    QString      _runStamp;
    QTimer       _tick;
};
