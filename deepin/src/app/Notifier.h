// Notifier.h — 系统通知（mac UNUserNotificationCenter 的 Linux 等价物：DNotifySender →
// org.freedesktop.Notifications）。
//
// 授权概念不存在（Linux 无 TCC），其余语义全保：
// · category「DIGEST」、所有通知都带 actions {"open","打开面板"}（mac 版全部通知可点进
//   面板；Linux 无默认点击语义，动作按钮即等价物）——notify() 传空 actions 也按默认补齐；
// · ActionInvoked→转发 openRequested（→bringToFront），归属按已知 id 集合判定；
// · 每条通知独立送达、互不顶替（mac 语义：通知中心并存）——不用 replaceId 顶掉前一条；
// · notifyOnce 按 key 去重（「提醒只在状态新变差时发」的去重由 AppModel 的 key 生成保证）；
// · 文案三态照 SPEC §3.2：引擎报什么说什么——没变不说已刷新、有备份必说路径、被停不报失败。
#pragma once
#include <QObject>
#include <QMap>
#include <QSet>
#include <QString>
#include <QStringList>

class Notifier : public QObject {
    Q_OBJECT
public:
    explicit Notifier(QObject *parent = nullptr);

    // 发一条通知；actions 为空时补默认 {"open","打开面板"}。
    void notify(const QString &title, const QString &body,
        const QStringList &actions = { QStringLiteral("open"), QStringLiteral("打开面板") });

    // dedupeKey 去重：同一 key 只发一次（进程生命周期内）。
    void notifyOnce(const QString &dedupeKey, const QString &title, const QString &body);

signals:
    // 用户点了通知/动作（actionKey=="open"）→ 上层 bringToFront()。
    void actionInvoked(const QString &actionKey);

private:
    // 通知类别（replaceId 归属）：同一类别的状态型通知互相顶替，其余不顶替
    QString categoryOf(const QString &title) const;

private slots:
    void onActionInvoked(uint id, const QString &actionKey);
    void onNotificationClosed(uint id, uint reason);

private:
    void send(const QString &title, const QString &body, const QStringList &actions);

    QSet<uint> m_knownIds; // 我们发出且尚未被关闭的通知 id（动作归属的唯一判据）
    QSet<QString> m_notifiedKeys;
    QMap<QString, uint> m_replaceIds; // 类别 → 该类别最新一条通知 id（下一条同类别顶替它）
};
