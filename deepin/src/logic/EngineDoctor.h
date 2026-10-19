// EngineDoctor.h — 引擎自检（`moongit doctor --json`）的判定层（纯函数，零 QWidget 头）。
//
// 【三处容易错得毫无声响的口径】
//   ① **「自检发现问题」不是「自检失败」**：引擎的 doctor 在 `problems > 0` 时
//      **退出码是 1**（引擎自己注释写了「自检命令必须能失败」——原来两条路径都
//      恒返回 0，脚本/CI 没法据此判断环境是否可用），但 stdout 仍是**合法 JSON**。
//      客户端若把非零退出当「命令崩了」，用户看到的会是「引擎调用失败」而不是
//      「环境有 2 个问题」—— 自检工具最该说清的事反而没说。
//      故判定层把「退出码」与「报告内容」分开：报告有效 ≠ 一切正常。
//   ② **`result` 是自由文本，不是布尔**：引擎的检查项结果有「OK」「1 个」
//      「无」「项目内」等多种取值 —— 后几种都是**正常**的。按 `result == "OK"`
//      判健康会把「注册项目 1 个」误报成故障。
//   ③ **「临时残留」不计入 problems**（引擎口径：残留要清理但不影响可用性）。
//      客户端若自己数「非 OK 的项」当问题数，会与引擎的 problems 不一致。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QVector>

namespace EngineDoctor {

/// 一条检查项。
struct Check {
    QString name;   ///< 检查项名（引擎给的是中文/英文，按引擎语言）
    QString result; ///< 结果**文本**（"OK" / "1 个" / "无" / "项目内" …）
    QString detail; ///< 详情
};

/// 自检报告。
struct Report {
    bool ok = false; ///< 载荷形状对不对（不是「环境有没有问题」！）
    QString error;
    /// 引擎口径的问题数（临时残留不计入）；**-1 = 引擎没发这个键**（不回落成 0）
    int problems = 0;
    QVector<Check> checks;

    /// 环境有没有问题（按引擎口径，不是按「非 OK 的项数」）。
    bool hasProblems() const { return problems > 0; }
    /// 问题数是不是**未知**（引擎没发 problems 键 —— 不是「0 个问题」）。
    bool problemsUnknown() const { return problems < 0; }
};

/// 自检结论的档。
/// 判定层只给**档**，不给色 —— 颜色由视图层映射（与 DocumentIntegrity 同款纪律）。
enum class Tone {
    ok,         ///< 报告有效且 0 个问题
    problem,    ///< 报告有效但有 N 个问题
    unknown,    ///< 报告有效但问题数未知（引擎没发 problems 键 → 契约可能过旧）
    unreadable, ///< 报告读不出来（引擎没回 / 载荷不是对象 / 契约形状不对）
};

/// 报告 → 档。
Tone toneOf(const Report &r);

/// 解析 `doctor --json` 的载荷。
Report parse(const QJsonObject &o);

/// 一行摘要（如「6 项检查 · 0 个问题」/「6 项检查 · 2 个问题」）。
QString summary(const Report &r);

/// 一条检查项的**一行**文字（「检查项 · 结果 · 详情」，缺的部分不占位）。
/// 详情可能为空（引擎对某些项给空串），空详情时不要留一个悬空的「·」。
QString checkLine(const Check &c);

} // namespace EngineDoctor
