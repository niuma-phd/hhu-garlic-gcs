#include "HHUVcuStatus.h"

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
    } else if (name == QStringLiteral("VCU_FAULT")) {
        _fault = static_cast<int>(std::lround(value));
    } else if (name == QStringLiteral("VCU_BATV")) {
        _batV = value;
    } else if (name == QStringLiteral("VCU_SOC")) {
        _soc = value;
    } else {
        return; // VCU_V / VCU_W / VCU_CMD_*: engineer data, viewed in Mission Planner
    }

    _lastRx.restart();
    _valid = true;
    _seen = true;
    emit changed();
}

void HHUVcuStatus::_checkTimeout()
{
    if (_valid && _lastRx.elapsed() > kTimeoutMs) {
        _valid = false;
        emit changed();
    }
}

void HHUVcuStatus::reset()
{
    _valid = false;
    _seen = false;
    _ok = false;
    _mode = 0;
    _fault = 0;
    _batV = qQNaN();
    _soc = qQNaN();
    emit changed();
}
