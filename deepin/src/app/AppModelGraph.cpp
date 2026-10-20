// AppModelGraph.cpp — AppModel 的**图谱/索引/概览/符号/影响**取数。
//
// ⚠ 为什么拆出来（批 AL · M4a）：`AppModel.cpp` 原本 1948 行，是全仓第二大的文件
//   （第一是 SelfCheck.cpp，已在批 AJ/AK 拆完）⇒ 改一处取数要跟一千多行挤在一起。
// ⚠ 为什么这个拆分**零风险**：同一类的成员函数**天然可以分文件定义**
//   （不像 SelfCheck 那个 3800 行大函数要拆成多个自由函数 + 共享底座）。
//   ⚠ 跨片共用的文件内辅助函数走 `AppModelInternal.h`（inline ⇒ 只有一份实现）。
#include "AppModel.h"
#include "AppModelInternal.h"
#include "EngineCli.h"
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QString>
#include <QStringList>

#include "AppModel.h"
#include "AppModelInternal.h"
#include "EngineCli.h"
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QString>
#include <QStringList>
using AppModelInternal::kQuiet;
using AppModelInternal::loadAiConfigWithFallbackKey;
using AppModelInternal::loadAiKeyInWorker;
using AppModelInternal::sortProjects;

void AppModel::loadOverview(const QString &name)
{
    m_insightStates[name] = { LoadState::loading, QString() };
    emit overviewChanged(name);
    m_cli->callJson({ QStringLiteral("graph"), QStringLiteral("overview"), name,
                        QStringLiteral("--json") },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                m_insightStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("图谱概览输出不是 JSON 对象")
                             : res.error.userMessage() };
                emit overviewChanged(name);
                return;
            }
            const GraphInsight::Overview ov = GraphInsight::parseOverview(res.payload->object());
            if (!ov.ok) {
                m_insightStates[name] = { LoadState::failed, ov.error };
                emit overviewChanged(name);
                return;
            }
            m_overviews[name] = ov;
            m_insightStates[name] = { LoadState::loaded, QString() };
            emit overviewChanged(name);
        });
}

void AppModel::loadSymbolDetail(const QString &name, const QString &symbolName)
{
    const QString key = name + QLatin1Char('\n') + symbolName;
    m_cli->callJson({ QStringLiteral("graph"), QStringLiteral("symbol"), name, symbolName,
                        QStringLiteral("--json") },
        EngineTimeouts::Graph, [this, name, symbolName, key](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                m_insightStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("图谱符号输出不是 JSON 对象")
                             : res.error.userMessage() };
                emit symbolDetailChanged(name, symbolName);
                return;
            }
            const GraphInsight::SymbolDetail sd
                = GraphInsight::parseSymbol(res.payload->object());
            if (!sd.ok) {
                m_insightStates[name] = { LoadState::failed, sd.error };
                emit symbolDetailChanged(name, symbolName);
                return;
            }
            m_symbolDetails[key] = sd;
            emit symbolDetailChanged(name, symbolName);
        });
}

void AppModel::loadImpact(const QString &name, const QString &symbolName)
{
    const QString key = name + QLatin1Char('\n') + symbolName;
    m_cli->callJson({ QStringLiteral("graph"), QStringLiteral("impact"), name, symbolName,
                        QStringLiteral("--json") },
        EngineTimeouts::Graph, [this, name, symbolName, key](const EngineCli::EngineResult &res) {
            if (!res.ok() || !res.payload.has_value() || !res.payload->isObject()) {
                m_insightStates[name] = { LoadState::failed,
                    res.ok() ? QStringLiteral("图谱影响面输出不是 JSON 对象")
                             : res.error.userMessage() };
                emit impactChanged(name, symbolName);
                return;
            }
            const GraphInsight::Impact im = GraphInsight::parseImpact(res.payload->object());
            if (!im.ok) {
                m_insightStates[name] = { LoadState::failed, im.error };
                emit impactChanged(name, symbolName);
                return;
            }
            m_impacts[key] = im;
            emit impactChanged(name, symbolName);
        });
}

void AppModel::loadPatchSkill(const QString &name)
{
    // --skill 输出的**不是 JSON**，是给 agent/人看的 markdown 任务书 → 走 Text 契约。
    QString err;
    const QString diff = workingDiff(name, &err);
    if (!err.isEmpty() || diff.trimmed().isEmpty()) {
        m_patchStates[name] = { LoadState::failed,
            err.isEmpty() ? QStringLiteral("工作区没有未提交改动（补丁体检没有输入）") : err };
        emit patchCheckChanged(name);
        return;
    }
    QTemporaryDir tmpDir;
    if (!tmpDir.isValid()) {
        m_patchStates[name] = { LoadState::failed, QStringLiteral("临时目录建不起来，任务书未生成") };
        emit patchCheckChanged(name);
        return;
    }
    const QString diffPath = tmpDir.filePath(QStringLiteral("patch.diff"));
    {
        QFile f(diffPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            m_patchStates[name] = { LoadState::failed, QStringLiteral("临时 diff 写不下去，任务书未生成") };
            emit patchCheckChanged(name);
            return;
        }
        f.write(diff.toUtf8());
    }
    m_cli->callText({ QStringLiteral("graph"), QStringLiteral("patchconf"), name,
                        QStringLiteral("--patch"), diffPath, QStringLiteral("--skill") },
        EngineTimeouts::Graph, [this, name](const EngineCli::EngineResult &res) {
            if (!res.ok()) {
                m_patchStates[name] = { LoadState::failed, res.error.userMessage() };
                emit patchCheckChanged(name);
                return;
            }
            emit patchSkillReady(name, res.receipt);
        });
}

// ── 更新动作 ──

