// EngineConfig.h — 引擎配置（`moongit config list --json`）的判定层（纯函数，零 QWidget 头）。
//
// 【为什么值得接】
// 引擎的 `update.maxShallowBranches`（浅更新只记前 N 个分支的进度）与
// `update.backupKeep`（文档备份留 N 份）是**用户能直接看到后果**的策略：
// 「这个分支怎么没更新」= 撞上了上限；「备份怎么不见了」= 留份数到了。
// 客户端此前一处没读，用户只能靠猜 —— 而猜错就会去改代码。
//
// 【三处容易错得毫无声响的口径】
//   ① **`backupKeep: 0` 是合法值**（明确不保留备份），**不是**「引擎没发这个键」。
//      所以缺失必须用 -1 哨兵 + present 标志 —— 拿 0 当缺失会把
//      「明确不要备份」说成「不知道留几份」，界面上两句话的意思完全相反。
//   ② **引擎的 `ai` 恒为空对象**（引擎自报「AI 由客户端层负责，引擎保持 AI 无关」）。
//      客户端**不许**从引擎 config 读 AI 设置 —— 那会与客户端自己的 AI 设置
//      （app/Settings）形成两个真相源，用户改哪边都可能不生效。
//      故本层**不解析** `ai`，也不提供任何 AI 相关的出口。
//   ③ **可写键只有四个**（language / update.backupKeep / update.maxShallowBranches /
//      roots），其余键（`update.docs` / `update.agentDocCandidates`）**只读**。
//      引擎对未知键报「未知配置键」并列出可用键 —— 客户端要认**同一份清单**，
//      否则界面会给用户一个引擎根本不认的键，点下去必然报错。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QStringList>

namespace EngineConfig {

/// 引擎配置。
struct Config {
    bool ok = false; ///< 载荷形状对不对（不是「配置有没有问题」！）
    QString error;
    int version = -1; ///< 配置版本（-1 = 引擎没发这个键）
    QString language; ///< 引擎侧界面语言（引擎自己的事，**不是**客户端的 i18n）
    QStringList roots;///< 扫描根
    QStringList docs; ///< 受管文档（引擎校验/托管的那批 —— verify 用的就是它）
    QStringList agentDocCandidates; ///< agent 文档候选（只读）
    int backupKeep = -1;         ///< 文档备份保留份数（**-1 = 没发；0 是合法值**）
    int maxShallowBranches = -1; ///< 浅更新记多少个分支的进度（**-1 = 没发；0 是合法值**）

    bool hasBackupKeep() const { return backupKeep >= 0; }
    bool hasMaxShallowBranches() const { return maxShallowBranches >= 0; }
};

/// 解析 `config list --json` 的载荷。
Config parse(const QJsonObject &o);

/// 引擎认的**可写键**清单（**与引擎同一份**：`language` / `update.backupKeep` /
/// `update.maxShallowBranches` / `roots`）。引擎对未知键报错并列出可用键，
/// 客户端的键集必须与之一致 —— 否则界面会给用户一个引擎根本不认的键。
QStringList writableKeys();

/// 这个键能不能写（可写键清单内的才行）。
bool isWritable(const QString &key);

/// 一行摘要（如「语言 zh · 分支上限 6 · 备份 20 份」）。
/// 缺项不占位（不写「分支上限 0」这种会误导的文案）。
QString summary(const Config &c);

} // namespace EngineConfig
