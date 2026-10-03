#include "AutostartManager.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTextStream>

namespace {
constexpr char kKeyEnabled[] = "X-deepDolphin-Autostart-enabled";

// 开发树构建判定（M1-5，运行时、不作编译开关）：产物路径含 "/build/"（CMakeLists 把
// CMAKE_RUNTIME_OUTPUT_DIRECTORY 钉死在 <源>/build）= 未安装的开发构建，它依赖开发
// sysroot 的 LD_LIBRARY_PATH，登录会话里必然起不来。判定保守：只在明确像开发树时拒绝，
// 装到 /usr/bin 的构建照常写自启项。
bool isDevTreeBuild()
{
    return QCoreApplication::applicationFilePath().contains(QStringLiteral("/build/"));
}
} // namespace

QString AutostartManager::desktopFilePath()
{
    return QDir::homePath() + QStringLiteral("/.config/autostart/cn.deepdolphin.app.desktop");
}

bool AutostartManager::isEnabled()
{
    QFile f(desktopFilePath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (line.startsWith(QStringLiteral("%1=").arg(kKeyEnabled)))
            return line.section(QLatin1Char('='), 1).compare(QStringLiteral("false"),
                       Qt::CaseInsensitive)
                != 0;
    }
    return true; // 文件存在且无显式禁用键 = 启用
}

bool AutostartManager::setEnabled(bool enabled, QString *errOut)
{
    const QString path = desktopFilePath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    if (!enabled) {
        QFile f(path);
        if (!f.exists())
            return true;
        if (!f.remove()) {
            if (errOut)
                *errOut = QStringLiteral("无法删除自启文件 %1：%2").arg(path, f.errorString());
            return false;
        }
        return true;
    }

    // 开发树里**不许**开机自启（M1-5）：那种二进制依赖开发 sysroot 运行库，登录时必失败；
    // 与其写一条注定失败的自启项（还会把参数转给一个错误的实例），不如明说要先安装。
    if (isDevTreeBuild()) {
        if (errOut) {
            *errOut = QStringLiteral("当前是开发树里的构建（%1，依赖开发 sysroot），"
                                     "不能开机自启；请先安装（cmake --install）再开启。")
                          .arg(QCoreApplication::applicationFilePath());
        }
        return false;
    }

    // 以已安装 desktop 为底；Exec 策略：装在标准前缀 → 安装名（与主 desktop 的 Exec 同名，
    // 不写绝对路径——路径变了不会悬空）；其他情况退回绝对路径。
    QString icon = QStringLiteral("deepdolphin");
    QString exec = QCoreApplication::applicationFilePath();
    QString name = QStringLiteral("deepDolphin 面板");
    QString comment = QStringLiteral("moonGit/deepGit 项目群进度客户端");
    const QStringList candidates = {
        QStandardPaths::locate(QStandardPaths::ApplicationsLocation,
            QStringLiteral("cn.deepdolphin.app.desktop")),
        QStringLiteral("/usr/share/applications/cn.deepdolphin.app.desktop"),
    };
    for (const QString &c : candidates) {
        QFile f(c);
        if (!c.isEmpty() && f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&f);
            while (!in.atEnd()) {
                const QString line = in.readLine();
                if (line.startsWith(QStringLiteral("Icon=")))
                    icon = line.section(QLatin1Char('='), 1);
                else if (line.startsWith(QStringLiteral("Name[zh_CN]=")))
                    name = line.section(QLatin1Char('='), 1);
                else if (line.startsWith(QStringLiteral("Name=")) && name.isEmpty())
                    name = line.section(QLatin1Char('='), 1);
                else if (line.startsWith(QStringLiteral("Comment[zh_CN]=")))
                    comment = line.section(QLatin1Char('='), 1);
            }
            break;
        }
    }
    // 已安装构建：优先用安装名（PATH 可达，路径迁移不失效）
    if (exec.contains(QStringLiteral("/usr/")) || exec.contains(QStringLiteral("/usr/local/")))
        exec = QStringLiteral("deepDolphin");
    else if (exec.isEmpty())
        exec = QStringLiteral("deepDolphin");

    QFile out(path);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        if (errOut)
            *errOut = QStringLiteral("无法写入自启文件 %1：%2").arg(path, out.errorString());
        return false;
    }
    QTextStream ts(&out);
    ts << "[Desktop Entry]\n"
       << "Type=Application\n"
       << "Name=" << name << "\n"
       << "Icon=" << icon << "\n"
       << "Comment=" << comment << "\n"
       << "Exec=" << exec << "\n"
       << "Terminal=false\n"
       << "StartupNotify=true\n"
       << "StartupWMClass=deepDolphin\n"
       << "X-Deepin-Vendor=deepin\n"
       // XDG/深之度自启语义键（M1-5）：只在 DDE 会话自启（别在 GNOME/KDE 下被拉起），
       // 并声明自启阶段 Desktop（GNOME 规范键，DDE 同样认）。
       << "OnlyShowIn=Deepin;\n"
       << "X-GNOME-Autostart-enabled=true\n"
       << "X-GNOME-Autostart-phase=Desktop\n"
       << "X-Deepin-Autostart=true\n"
       << kKeyEnabled << "=true\n";
    return true;
}
