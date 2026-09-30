#pragma once

#include <QtCore/QString>

/// Passwords stored on this computer (需求说明 V1.0 §5 安全: 所有密码加密保存在本机).
/// Windows: DPAPI, bound to the current Windows user; the result is base64 text for QSettings.
namespace HHUSecret {

QString protect(const QString &plain);
/// Empty string when the text cannot be decrypted (other user / other computer / damaged)
QString unprotect(const QString &stored);

} // namespace HHUSecret
