#include "HHUSecret.h"

#include <QtCore/QByteArray>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dpapi.h>
#endif

namespace HHUSecret {

QString protect(const QString &plain)
{
    if (plain.isEmpty()) {
        return QString();
    }
    const QByteArray data = plain.toUtf8();
#ifdef Q_OS_WIN
    DATA_BLOB in{ static_cast<DWORD>(data.size()), reinterpret_cast<BYTE *>(const_cast<char *>(data.data())) };
    DATA_BLOB out{};
    if (CryptProtectData(&in, L"HHU-GCS", nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)) {
        const QByteArray enc(reinterpret_cast<const char *>(out.pbData), static_cast<int>(out.cbData));
        LocalFree(out.pbData);
        return QStringLiteral("dpapi:") + QString::fromLatin1(enc.toBase64());
    }
#endif
    // Other platforms are not a target of this product; keep it at least not readable at a glance
    return QStringLiteral("b64:") + QString::fromLatin1(data.toBase64());
}

QString unprotect(const QString &stored)
{
    if (stored.startsWith(QStringLiteral("b64:"))) {
        return QString::fromUtf8(QByteArray::fromBase64(stored.mid(4).toLatin1()));
    }
#ifdef Q_OS_WIN
    if (stored.startsWith(QStringLiteral("dpapi:"))) {
        QByteArray enc = QByteArray::fromBase64(stored.mid(6).toLatin1());
        DATA_BLOB in{ static_cast<DWORD>(enc.size()), reinterpret_cast<BYTE *>(enc.data()) };
        DATA_BLOB out{};
        if (CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)) {
            const QString plain = QString::fromUtf8(reinterpret_cast<const char *>(out.pbData), static_cast<int>(out.cbData));
            SecureZeroMemory(out.pbData, out.cbData);
            LocalFree(out.pbData);
            return plain;
        }
    }
#endif
    return QString();
}

} // namespace HHUSecret
