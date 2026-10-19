#include "PatchCheck.h"

#include <QJsonArray>
#include <QJsonValue>
#include <QRegularExpression>

#include <algorithm>

namespace PatchCheck {
namespace {

/// 引擎约定的信号键（S1..S10）。缺键要在界面上说「没有」，不能当成 0。
const char *const kSignalKeys[] = { "S1", "S2", "S3", "S4", "S5",
    "S6", "S7", "S8", "S9", "S10" };

/// 读一个「可能是 null 的数字」：null 与缺键都要标成「没有值」。
bool readNumber(const QJsonValue &v, double &out)
{
    if (!v.isDouble())
        return false;
    out = v.toDouble();
    return true;
}

} // namespace

ScoreBand bandOf(double score)
{
    if (score >= 0.8)
        return ScoreBand::high;
    if (score >= 0.5)
        return ScoreBand::mid;
    return ScoreBand::low;
}

PatchLayer1 parseLayer1(const QJsonObject &o)
{
    PatchLayer1 r;
    if (!o.contains(QStringLiteral("schema"))) {
        r.error = QStringLiteral("补丁体检载荷缺 schema 键（契约可能过旧）");
        return r;
    }
    r.schema = o.value(QStringLiteral("schema")).toString();
    if (r.schema != QLatin1String("moongit-patch-confidence/1")) {
        r.error = QStringLiteral("补丁体检契约版本不认识：%1（当前只认 moongit-patch-confidence/1）")
                      .arg(r.schema);
        return r;
    }
    if (!o.contains(QStringLiteral("signals"))) {
        r.error = QStringLiteral("补丁体检载荷缺 signals 键（契约可能过旧）");
        return r;
    }

    double overall = 0;
    r.overallPresent = readNumber(o.value(QStringLiteral("overall")), overall);
    r.overall = overall;

    // signals：逐个固定键读 —— 缺键与 null 都标成「算不出」，但**键本身要列全**
    //（少了 S7 用户不知道是引擎没发还是这一项没算）。
    const QJsonObject sig = o.value(QStringLiteral("signals")).toObject();
    for (const char *key : kSignalKeys) {
        PatchSignal s;
        s.key = QLatin1String(key);
        const QString k = QLatin1String(key);
        if (sig.contains(k)) {
            double v = 0;
            if (readNumber(sig.value(k), v)) {
                s.hasValue = true;
                s.value = v;
            }
        }
        r.signalList << s;
    }

    const QJsonArray ents = o.value(QStringLiteral("entities")).toArray();
    for (const QJsonValue &ev : ents) {
        const QJsonObject eo = ev.toObject();
        PatchEntity e;
        e.id = eo.value(QStringLiteral("id")).toString();
        e.kind = eo.value(QStringLiteral("kind")).toString();
        e.confidencePresent = readNumber(eo.value(QStringLiteral("confidence")), e.confidence);
        e.file = eo.value(QStringLiteral("file")).toString();
        e.line = eo.value(QStringLiteral("line")).toInt();
        r.entities << e;
    }

    const QJsonArray unc = o.value(QStringLiteral("uncertain")).toArray();
    for (const QJsonValue &uv : unc) {
        const QJsonObject uo = uv.toObject();
        PatchUncertain u;
        u.id = uo.value(QStringLiteral("id")).toString();
        u.issue = uo.value(QStringLiteral("issue")).toString();
        u.detail = uo.value(QStringLiteral("detail")).toString();
        for (const QJsonValue &cv : uo.value(QStringLiteral("candidates")).toArray())
            u.candidates << cv.toString();
        if (uo.contains(QStringLiteral("context_ref"))) {
            const QJsonObject co = uo.value(QStringLiteral("context_ref")).toObject();
            u.file = co.value(QStringLiteral("file")).toString();
            u.line = co.value(QStringLiteral("line")).toInt();
            u.hasContext = co.contains(QStringLiteral("file")) && co.contains(QStringLiteral("line"));
        }
        r.uncertain << u;
    }

    if (o.contains(QStringLiteral("diagnostics"))) {
        const QJsonObject d = o.value(QStringLiteral("diagnostics")).toObject();
        r.diagnostics.present = true;
        r.diagnostics.totalEntities = d.value(QStringLiteral("total_entities")).toInt();
        r.diagnostics.totalRelations = d.value(QStringLiteral("total_relations")).toInt();
        r.diagnostics.parseErrors = d.value(QStringLiteral("parse_errors")).toInt();
        r.diagnostics.patchFiles = d.value(QStringLiteral("patch_files")).toInt();
        r.diagnostics.addedLines = d.value(QStringLiteral("added_lines")).toInt();
        for (const QJsonValue &nv : d.value(QStringLiteral("null_signals")).toArray())
            r.diagnostics.nullSignals << nv.toString();
        r.diagnostics.nullSignalsNote = d.value(QStringLiteral("null_signals_note")).toString();
    }

    r.ok = true;
    return r;
}

PatchMerged parseMerged(const QJsonObject &o)
{
    PatchMerged r;
    if (!o.contains(QStringLiteral("schema"))) {
        r.error = QStringLiteral("补丁体检终稿缺 schema 键（契约可能过旧）");
        return r;
    }
    r.schema = o.value(QStringLiteral("schema")).toString();
    if (r.schema != QLatin1String("moongit-patch-confidence-merged/1")) {
        r.error = QStringLiteral("补丁体检终稿契约版本不认识：%1（当前只认 moongit-patch-confidence-merged/1）")
                      .arg(r.schema);
        return r;
    }
    double overall = 0;
    r.overallPresent = readNumber(o.value(QStringLiteral("overall")), overall);
    r.overall = overall;

    for (const QJsonValue &av : o.value(QStringLiteral("alerts")).toArray()) {
        const QJsonObject ao = av.toObject();
        PatchAlert a;
        a.level = ao.value(QStringLiteral("level")).toString();
        a.type = ao.value(QStringLiteral("type")).toString();
        a.detail = ao.value(QStringLiteral("detail")).toString();
        r.alerts << a;
    }

    if (o.contains(QStringLiteral("sources"))) {
        const QJsonObject s = o.value(QStringLiteral("sources")).toObject();
        r.sourcesAlgorithm = s.value(QStringLiteral("algorithm")).toBool();
        r.sourcesAgent = s.value(QStringLiteral("agent")).toBool();
    }
    if (o.contains(QStringLiteral("diagnostics"))) {
        const QJsonObject d = o.value(QStringLiteral("diagnostics")).toObject();
        r.diagnosticsPresent = true;
        r.certainFromAlgorithm = d.value(QStringLiteral("certain_from_algorithm")).toInt();
        // ⚠ 复核数在 diagnostics.reviewed_by_agent，**不在**顶层 `reviewed` 键上
        //   （引擎实测；mac 读的是顶层 reviewed → 那句「已复核 N 条」永远不显示）。
        r.reviewedByAgent = d.value(QStringLiteral("reviewed_by_agent")).toInt();
        r.deferred = d.value(QStringLiteral("deferred")).toInt();
    }

    r.ok = true;
    return r;
}

QVector<PatchEntity> lowConfidenceEntities(const PatchLayer1 &l1, double threshold)
{
    QVector<PatchEntity> out;
    for (const PatchEntity &e : l1.entities) {
        // 置信度未知（缺键）不算「低置信度」—— 不知道 ≠ 不可信。
        if (!e.confidencePresent)
            continue;
        if (e.confidence < threshold)
            out << e;
    }
    // 升序：最不可信的排最前（用户先看最该看的）
    std::stable_sort(out.begin(), out.end(),
        [](const PatchEntity &a, const PatchEntity &b) { return a.confidence < b.confidence; });
    return out;
}

QVector<PatchVerdict> defaultVerdicts(const PatchLayer1 &l1)
{
    QVector<PatchVerdict> out;
    for (const PatchUncertain &u : l1.uncertain) {
        PatchVerdict v;
        v.id = u.id;
        v.verdict = QLatin1String(Verdict::Ambiguous);
        v.confidence = 0.5;
        v.reason = QStringLiteral("deepDolphin 人工裁决");
        out << v;
    }
    return out;
}

QJsonObject agentPayload(const QVector<PatchVerdict> &verdicts)
{
    QJsonArray items;
    for (const PatchVerdict &v : verdicts) {
        // id **原样回填** —— 引擎按 id 对回 uncertain 项；改一个字就匹配不上，
        // 裁决会被静默丢掉（终稿里那条仍是「未裁决」）。
        QJsonObject o;
        o.insert(QStringLiteral("id"), v.id);
        QString verdict = v.verdict;
        if (verdict != QLatin1String(Verdict::Resolved)
            && verdict != QLatin1String(Verdict::Unresolved)
            && verdict != QLatin1String(Verdict::Ambiguous))
            verdict = QLatin1String(Verdict::Ambiguous); // 越界值归一，不猜
        o.insert(QStringLiteral("verdict"), verdict);
        o.insert(QStringLiteral("confidence"), v.confidence);
        o.insert(QStringLiteral("reason"), v.reason);
        items.append(o);
    }
    QJsonObject root;
    root.insert(QStringLiteral("task"), QStringLiteral("layer2_review"));
    root.insert(QStringLiteral("items"), items);
    return root;
}

int parseNewStart(const QString &hunkHeader)
{
    // 形如 @@ -3,7 +41,9 @@ …：取 + 之后的数字
    const int plus = hunkHeader.indexOf(QLatin1Char('+'));
    if (plus < 0)
        return 0;
    int i = plus + 1;
    QString digits;
    while (i < hunkHeader.size() && hunkHeader.at(i).isDigit()) {
        digits += hunkHeader.at(i);
        ++i;
    }
    return digits.toInt();
}

QStringList diffSnippet(const QString &diffText, const QString &file, int line, int context)
{
    QStringList out;
    if (diffText.isEmpty() || file.isEmpty() || line <= 0)
        return out;

    const QStringList lines = diffText.split(QLatin1Char('\n'));
    QString currentFile;
    QStringList hunk; ///< 命中 hunk 里的行（带行号前缀）
    int hitIndex = -1;
    int newLine = 0;
    bool inTargetHunk = false;

    for (const QString &l : lines) {
        if (l.startsWith(QLatin1String("diff --git")) || l.startsWith(QLatin1String("index "))) {
            currentFile.clear();
            inTargetHunk = false;
            continue;
        }
        if (l.startsWith(QLatin1String("+++ "))) {
            QString f = l.mid(4).trimmed();
            if (f.startsWith(QLatin1String("b/")))
                f = f.mid(2);
            currentFile = f;
            continue;
        }
        if (l.startsWith(QLatin1String("@@"))) {
            newLine = parseNewStart(l);
            // hunk 的起点可能早于目标行 —— 用「+400」的宽容窗口（mac 同款）：
            // 命中与否最终由「行号 == 目标行」判定，不靠这里猜。
            inTargetHunk = (currentFile == file) && line >= newLine - context
                && line <= newLine + 400;
            if (inTargetHunk) {
                hunk.clear();
                hitIndex = -1;
            }
            continue;
        }
        if (!inTargetHunk || currentFile != file)
            continue;
        if (l.startsWith(QLatin1Char('+'))) {
            hunk << QStringLiteral("%1\t%2").arg(newLine).arg(l.mid(1));
            if (newLine == line)
                hitIndex = hunk.size() - 1;
            ++newLine;
        } else if (l.startsWith(QLatin1Char(' '))) {
            hunk << QStringLiteral("%1\t%2").arg(newLine).arg(l.mid(1));
            ++newLine;
        }
        // '-' 行跳过（旧版本内容，不进新文件行号流）
    }
    if (hunk.isEmpty())
        return out;
    if (hitIndex < 0)
        return hunk; // hunk 命中了但目标行不在里面 → 整块给出去
    const int lo = qMax(0, hitIndex - context);
    const int hi = qMin(hunk.size() - 1, hitIndex + context);
    for (int i = lo; i <= hi; ++i)
        out << hunk.at(i);
    return out;
}

} // namespace PatchCheck
