#include "AppService.h"
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDebug>

AppService::AppService(QObject *parent)
    : QObject(parent)
{
}

bool AppService::registerOnBus(QString *errOut)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        if (errOut)
            *errOut = QStringLiteral("会话总线不可用");
        return false;
    }
    // 只导出自定义接口的 slots/signals（QObject 自身方法不导出，避免污染 D-Bus 命名空间）
    if (!bus.registerObject(objectPath(), QStringLiteral("cn.deepdolphin.app"), this,
            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        if (errOut)
            *errOut = bus.lastError().message();
        return false;
    }
    qInfo() << "DBus 连接 baseService=" << bus.baseService() << "env=" << qEnvironmentVariable("DBUS_SESSION_BUS_ADDRESS");
    if (!bus.registerService(busName())) {
        // 已有实例占着名字 = 正常竞态（第二个实例走单实例转发那套）；如实告知调用方
        if (errOut)
            *errOut = QStringLiteral("总线名 %1 已被占用（可能是另一个实例正在运行）")
                          .arg(busName());
        return false;
    }
    return true;
}

QString AppService::Ping()
{
    return QStringLiteral("ok");
}

void AppService::Activate()
{
    emit activateRequested();
}

void AppService::OpenProject(const QString &name)
{
    emit openProjectRequested(name);
}

void AppService::OpenPath(const QString &path)
{
    emit openPathRequested(path);
}
