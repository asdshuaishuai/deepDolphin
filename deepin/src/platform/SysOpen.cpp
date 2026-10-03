#include "SysOpen.h"
#include <DStandardPaths>
#include <QDesktopServices>
#include <QFileInfo>
#include <QProcess>

DCORE_USE_NAMESPACE

namespace SysOpen {

void revealInFileManager(const QString &path)
{
    const QString dir = QFileInfo(path).isDir() ? path : QFileInfo(path).absolutePath();
    const QString fm = DStandardPaths::findExecutable(QStringLiteral("dde-file-manager"));
    if (!fm.isEmpty()) {
        QProcess::startDetached(fm, { QStringLiteral("--show-folder"), dir });
        return;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}

void openTerminal(const QString &path)
{
    const QString deepinTerm = DStandardPaths::findExecutable(QStringLiteral("deepin-terminal"));
    if (!deepinTerm.isEmpty()) {
        QProcess::startDetached(deepinTerm, { QStringLiteral("-w"), path });
        return;
    }
    const QString fallback = DStandardPaths::findExecutable(QStringLiteral("x-terminal-emulator"));
    if (!fallback.isEmpty()) {
        QProcess::startDetached(fallback, { QStringLiteral("-w"), path });
        return;
    }
    // 都没有：用文件管理器打开目录也不对——诚实退化为桌面打开目录
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void openUrl(const QUrl &url)
{
    QDesktopServices::openUrl(url);
}

} // namespace SysOpen
