// AppService.h — 会话总线服务（M2-3：`cn.deepdolphin.app`，D-Bus 可激活）。
//
// 为什么要有它：没有总线名字时，命令行/脚本/别的应用想叫醒面板只能靠"再启动一个进程"，
// 而单实例会让第二个进程把参数转给首实例——能用，但外部无法**探活**（"面板起来了没？"）、
// 也无法在面板没起来时让它起来（DBus 激活）。注册 `cn.deepdolphin.app` 后：
//   · `dbus-send … cn.deepdolphin.app /cn/deepdolphin/app cn.deepdolphin.app.Activate` 叫醒面板
//   · `Ping()` 探活（返回 "ok"）
//   · `OpenProject(name)` / `OpenPath(dir)` 直达某项目/预填扫描面板
//   · desktop 项 `DBusActivatable=true` + `cn.deepdolphin.app.service` → 面板没起时自动拉起
//
// 总线名与 DTK 单实例不冲突：`DApplication::setSingleInstance(key)` 用的是
// `com.deepin.SingleInstance.<key>`（dtk6widget 符号实证），本服务用的是 app id 本身。
#pragma once
#include <QObject>
#include <QString>

class AppService : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "cn.deepdolphin.app")
public:
    explicit AppService(QObject *parent = nullptr);

    // 注册到会话总线；失败原因写 errOut（已有实例占用名字时如实返回，不静默）
    bool registerOnBus(QString *errOut = nullptr);

    static QString busName() { return QStringLiteral("cn.deepdolphin.app"); }
    static QString objectPath() { return QStringLiteral("/cn/deepdolphin/app"); }

signals:
    void activateRequested();
    void openProjectRequested(const QString &name);
    void openPathRequested(const QString &path);

public slots:
    QString Ping(); // 探活：外部可确认服务在
    void Activate();
    void OpenProject(const QString &name);
    void OpenPath(const QString &path);
};
