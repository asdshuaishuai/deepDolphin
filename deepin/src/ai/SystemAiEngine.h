// SystemAiEngine.h — 系统级 AI 默认后端（UOS AI / uos-ai-assistant，PLAN §5.3）。
//
// 【能力边界——env.md §4 与 busctl 实测结论，2026-10-03】
// 会话总线 com.deepin.copilot（对象 /org/deepin/copilot/chat，接口
// org.deepin.copilot.chat）只暴露 `inputPrompt(s question, a{ss} params)`
// —— **无返回值**（fire-and-forget 的「唤起对话窗口」）；主对象
// /com/deepin/copilot 上全是 UI 唤起/状态方法。即：系统级 AI **没有程序化
// 文本补全出口**。因此本引擎的定位 =
//   · 唯一真实能力：launchChat() 唤起 UOS AI 对话窗口（把问题交给人机界面）；
//   · generate() 恒返回**明确错误**（可插拔降级的报错原文，不许改成模糊的
//     「AI 失败」）——服务不可用/能力不足都要如实说，不许静默假装成功。
// 未来 UOS AI 若暴露补全接口：扩展本引擎（或新增后端）即可，UI 不动。
#pragma once
#include "AIEngine.h"
#include <QMutex>
#include <QVariantMap>

class SystemAiEngine final : public AIEngine {
public:
    enum class Cap {
        Unknown, // 还没探测
        Absent,  // 会话总线上找不到 com.deepin.copilot
        Present, // 服务在（运行中或可激活）
    };

    QString backendId() const override { return QStringLiteral("system-uos-ai"); }
    bool isConfigured(QString *whyNot = nullptr) const override;
    GenerateResult generate(const GenerateRequest &req) override;

    // 唯一真实能力：唤起 UOS AI 对话窗口。返回是否已把请求交给会话总线
    // （M1-6 起异步发出：不再同步等回包，回包由 watcher 落回发起线程只记日志）。
    bool launchChat(const QString &question, const QVariantMap &params = {});

    // 运行时探测（进程内缓存，加锁防并发重复探测）：总线名在运行 → Present；
    // 可激活名单里有 → Present。首次探测到服务**运行中**时，顺带把它可
    // Introspect 到的接口名 dump 进日志（M1-6：未来冒出程序化补全出口第一时间可见）。
    Cap probe() const;

private:
    // 缓存会被 GUI（AgentDialog）与 worker（AgentCore/AiDigests）两条线触达：
    // 加锁串行化「查缓存 → 探测 → dump」，并发第二次只等第一次落缓存。
    mutable QMutex m_probeMutex;
    mutable Cap m_cap = Cap::Unknown; // 受 m_probeMutex 保护
};
