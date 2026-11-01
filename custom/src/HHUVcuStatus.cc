#include "HHUVcuStatus.h"
#include "MultiVehicleManager.h"
#include "ParameterManager.h"
#include "Fact.h"
#include "Vehicle.h"

#include <cmath>

namespace {
constexpr qint64 kTimeoutMs = 3000;
}

HHUVcuStatus::HHUVcuStatus(QObject *parent)
    : QObject(parent)
{
    _timeoutTimer.setInterval(1000);
    (void) connect(&_timeoutTimer, &QTimer::timeout, this, &HHUVcuStatus::_checkTimeout);
    _timeoutTimer.start();
}

void HHUVcuStatus::handleMessage(const mavlink_message_t &message)
{
    if (message.msgid == MAVLINK_MSG_ID_STATUSTEXT) {
        _handleStatusText(message);
        return;
    }
    if (message.msgid != MAVLINK_MSG_ID_NAMED_VALUE_FLOAT) {
        return;
    }

    mavlink_named_value_float_t nvf{};
    mavlink_msg_named_value_float_decode(&message, &nvf);
    // name is char[10] and not NUL terminated when all 10 chars are used
    const QString name = QString::fromLatin1(nvf.name, static_cast<int>(strnlen(nvf.name, sizeof(nvf.name))));
    if (!name.startsWith(QStringLiteral("VCU_"))) {
        return;
    }

    const double value = nvf.value;
    if (name == QStringLiteral("VCU_OK")) {
        _ok = value >= 0.5;
    } else if (name == QStringLiteral("VCU_MODE")) {
        _mode = static_cast<int>(std::lround(value));
        if (_mode != 2) {
            _rcStart = 0;   // a new handover starts with "wait RC start" again
        }
    } else if (name == QStringLiteral("VCU_FAULT")) {
        _fault = static_cast<int>(std::lround(value));
    } else if (name == QStringLiteral("VCU_SOC")) {
        if (std::isfinite(value) && value >= 0 && value <= 100) {
            _lastSocRx.restart();
            _soc = value;
            _batteryValid = true;
            emit batteryChanged();
        } else if (_batteryValid) {
            _clearBattery();
        }
        return;
    } else if (name == QStringLiteral("VCU_BATV")) {
        _batV = value;
        emit batteryChanged();
        return;
    } else if (name == QStringLiteral("VCU_WORKFB")) {
        _lastWorkFbRx.restart();
        _workFb = static_cast<int>(std::lround(value));
        _workFbValid = true;
        emit workChanged();
        return;
    } else if (name == QStringLiteral("VCU_WREQ")) {
        _lastWorkReqRx.restart();
        _workReq = value >= 0.5 ? 1 : 0;
        _workReqValid = true;
        emit workChanged();
        return;
    } else {
        return; // VCU_V / VCU_W / VCU_CMD_*: engineer data, viewed in Mission Planner
    }

    _lastRx.restart();
    _valid = true;
    _seen = true;
    emit changed();
}

void HHUVcuStatus::_handleStatusText(const mavlink_message_t &message)
{
    mavlink_statustext_t st{};
    mavlink_msg_statustext_decode(&message, &st);
    const QString text = QString::fromUtf8(st.text, static_cast<int>(strnlen(st.text, sizeof(st.text))));
    int rcStart = _rcStart;
    if (text == QStringLiteral("VCU: RC start OK")) {
        rcStart = 2;
    } else if (text == QStringLiteral("VCU: wait RC start") || text == QStringLiteral("VCU: handover failed")
               || text == QStringLiteral("VCU: RC link lost")) {
        rcStart = 1;
    }
    if (rcStart != _rcStart) {
        _rcStart = rcStart;
        emit changed();
    }
}

void HHUVcuStatus::_readParams()
{
    int rtkReq = -1;
    bool bridgeEnabled = true;
    Vehicle *v = MultiVehicleManager::instance()->activeVehicle();
    ParameterManager *params = v ? v->parameterManager() : nullptr;
    if (params && params->parametersReady()) {
        const int comp = ParameterManager::defaultComponentId;
        if (params->parameterExists(comp, QStringLiteral("VCU_RTK_REQ"))) {
            rtkReq = params->getParameter(comp, QStringLiteral("VCU_RTK_REQ"))->rawValue().toInt();
        }
        if (params->parameterExists(comp, QStringLiteral("VCU_ENABLE"))) {
            bridgeEnabled = params->getParameter(comp, QStringLiteral("VCU_ENABLE"))->rawValue().toInt() > 0;
        }
    }
    if (rtkReq != _rtkReq || bridgeEnabled != _bridgeEnabled) {
        _rtkReq = rtkReq;
        _bridgeEnabled = bridgeEnabled;
        emit paramsChanged();
    }
}

void HHUVcuStatus::_checkTimeout()
{
    _readParams();
    if (_valid && _lastRx.elapsed() > kTimeoutMs) {
        _valid = false;
        emit changed();
    }
    if (_batteryValid && _lastSocRx.elapsed() > kTimeoutMs) {
        _clearBattery();
    }
    // the last values are kept (the AB line run needs WorkFb also while it is stale)
    if ((_workFbValid && _lastWorkFbRx.elapsed() > kTimeoutMs) || (_workReqValid && _lastWorkReqRx.elapsed() > kTimeoutMs)) {
        _workFbValid = _workFbValid && _lastWorkFbRx.elapsed() <= kTimeoutMs;
        _workReqValid = _workReqValid && _lastWorkReqRx.elapsed() <= kTimeoutMs;
        emit workChanged();
    }
}

void HHUVcuStatus::_clearWork()
{
    _workFbValid = false;
    _workFb = -1;
    _workReqValid = false;
    _workReq = -1;
    _lastWorkFbRx.invalidate();
    _lastWorkReqRx.invalidate();
    emit workChanged();
}

void HHUVcuStatus::_clearBattery()
{
    _batteryValid = false;
    _soc = qQNaN();
    _batV = qQNaN();
    _lastSocRx.invalidate();
    emit batteryChanged();
}

void HHUVcuStatus::reset()
{
    _valid = false;
    _seen = false;
    _ok = false;
    _mode = 0;
    _fault = 0;
    _rcStart = 0;
    emit changed();
    _clearBattery();
    _clearWork();
}
