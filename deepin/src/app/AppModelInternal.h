// AppModelInternal.h — AppModel 各**分片**之间的文件内辅助函数（批 AL · M4a 拆分）。
//
// 【为什么要有这个文件】⚠ `AppModel.cpp` 原本 1948 行，拆成
//   `AppModel.cpp` / `AppModelGraph.cpp` / `AppModelUpdate.cpp` 三片时，
//   原来文件顶部的**匿名 namespace 辅助函数**只有本文件可见 ⇒ 跨片就用不到了。
//   ⚠ 逐个查过：这 4 个**主片与分片都在用**（`kQuiet` 与 AI 快照被刷新链和更新链共用，
//   `sortProjects` 被状态应用用）⇒ 只能上内部头。
//   ⚠ 而 `milestoneActionLabel` **只有更新分片用** ⇒ 留在那个分片里，不进这里
//   （**能不放共享头就不放** —— 共享面越小越好）。
//
// 【为什么是 inline】分片之间共享的必须是**同一份实现**
//   （否则「同名两处互相顶替」⇒ 改一处漏一处）。C++17 的 inline 变量/函数正好。
#pragma once
#include "../ai/AIConfig.h"
#include "../ai/SecretStore.h"
#include "Settings.h"
#include "../models/ProjectStatus.h"
#include <QString>
#include <QStringList>
#include <algorithm>
#include <vector>

namespace AppModelInternal {

/// status/update/deep 的全局静默旗标（叙述层走 stderr，--json 载荷干净）
inline const QStringList kQuiet = { QStringLiteral("--json"), QStringLiteral("--quiet") };

/// AI 配置快照（M0-4 拆两半）：本函数**GUI 线程专用**——只读 Settings（身份 + 明文回退键，
/// 仅 mock/headless 有值）；同步 libsecret 读在 worker 侧用 loadAiKeyInWorker 补齐。
/// worker 不得直接碰 Settings 单例（QSettings/QObject 跨线程访问告警的根因）。
inline AIConfig loadAiConfigWithFallbackKey()
{
    AIConfig cfg = AIConfig::load();
    cfg.apiKey = Settings::instance().aiApiKeyPlaintext();
    return cfg;
}

/// worker 线程专用：同步 libsecret 读（阻塞不进 GUI 线程，PLAN §2.5）；
/// 明文回退键用 GUI 线程快照带进来的那份。
inline void loadAiKeyInWorker(AIConfig *cfg)
{
    SecretStore store;
    cfg->apiKey = AIConfig::loadKey(&store, cfg->apiKey);
}

/// 项目按系统本地化排序（QString::localeAwareCompare，mac localizedStandardCompare 对位）
inline void sortProjects(std::vector<ProjectStatus> &projects)
{
    std::sort(projects.begin(), projects.end(),
        [](const ProjectStatus &a, const ProjectStatus &b) {
            return a.name.localeAwareCompare(b.name) < 0;
        });
}

} // namespace AppModelInternal
