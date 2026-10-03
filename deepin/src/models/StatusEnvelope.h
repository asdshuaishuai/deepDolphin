// StatusEnvelope.h — `status --json` 恒三键 envelope {projects, summary, language}。
//
// CONTRACT §2.1：单项目/零项目/全部停用与多项目**同形状**；零项目时 summary
// 全零但完整。decodeEnvelopeOrBare 另兼容旧引擎的「裸单项目对象」（SPEC §2）。
#pragma once
#include "EngineSummary.h"
#include "ProjectStatus.h"
#include <QJsonDocument>
#include <QString>
#include <optional>
#include <vector>

struct StatusEnvelope {
    std::vector<ProjectStatus> projects;
    std::optional<EngineSummary> summary; // 缺 failedProjects/listedProjects ⇒ nullopt（契约过旧判据）
    std::optional<QString> language;      // "zh" | "en"（取自引擎 config）

    // 成功 → envelope；失败（非 JSON / 缺 projects 键且不是裸条目 / 条目缺键）→ nullopt
    static std::optional<StatusEnvelope> decodeEnvelopeOrBare(const QJsonDocument &doc);
};
