#include "CodeGraphBuild.h"

#include <QJsonArray>
#include <QSet>
#include <functional>
#include <algorithm>

namespace CodeGraphBuild {
namespace {

int intOf(const QJsonObject &o, const QString &key)
{
    return o.value(key).toInt(0);
}

QString strOf(const QJsonObject &o, const QString &key)
{
    return o.value(key).toString();
}

/// 疑点（confidence 侧与 functions 侧的字段集不同 —— 后者多 label/dim）。
GraphFinding findingFrom(const QJsonObject &o, const QString &file)
{
    GraphFinding f;
    f.kind = strOf(o, QStringLiteral("kind"));
    f.label = strOf(o, QStringLiteral("label"));
    f.dim = strOf(o, QStringLiteral("dim"));
    f.file = file.isEmpty() ? strOf(o, QStringLiteral("file")) : file;
    f.line = intOf(o, QStringLiteral("line"));
    f.weight = intOf(o, QStringLiteral("weight"));
    f.evidence = strOf(o, QStringLiteral("evidence"));
    return f;
}

} // namespace

QString symbolId(const QString &path, int line, const QString &name)
{
    // 引擎 `graph functions` 的 id 同形：f:<路径>:<行号>:<名字>
    return QStringLiteral("f:%1:%2:%3").arg(path).arg(line).arg(name);
}

QString findingKey(const QString &file, int line, const QString &kind)
{
    return file + QLatin1Char('#') + QString::number(line) + QLatin1Char('#') + kind;
}

Result build(const Source &src, const QString &projectName)
{
    Result r;
    // 必发键缺失 = 契约不认识（明说是哪一种，不回落成空图）。
    if (src.tree.isEmpty()) {
        r.error = QStringLiteral("缺少图树数据（graph tree 无输出或不是 JSON 对象）");
        return r;
    }
    if (src.confidence.isEmpty()) {
        r.error = QStringLiteral("缺少置信度数据（graph confidence 无输出或不是 JSON 对象）");
        return r;
    }
    if (src.functions.isEmpty()) {
        r.error = QStringLiteral("缺少函数级数据（graph functions 无输出或不是 JSON 对象）");
        return r;
    }

    // ── 置信度侧 ──
    r.score = intOf(src.confidence, QStringLiteral("score"));
    r.astNote = strOf(src.confidence, QStringLiteral("astNote"));
    r.astUsed = src.confidence.value(QStringLiteral("astUsed")).toBool(false);
    for (const QJsonValue &v : src.confidence.value(QStringLiteral("findings")).toArray())
        if (v.isObject())
            r.findings.append(findingFrom(v.toObject(), QString()));

    // ── 函数级侧：源码片段 + 符号级调用边 + 按符号归属的疑点 ──
    QHash<QString, QVector<GraphFinding>> fnFindings; // 符号 id → 疑点
    QSet<QString> attributed;                          // 已归属的疑点键（去重用）
    for (const QJsonValue &v : src.functions.value(QStringLiteral("functions")).toArray()) {
        if (!v.isObject())
            continue;
        const QJsonObject fo = v.toObject();
        const QString id = strOf(fo, QStringLiteral("id"));
        const QString file = strOf(fo, QStringLiteral("file"));
        for (const QJsonValue &fv : fo.value(QStringLiteral("findings")).toArray()) {
            if (!fv.isObject())
                continue;
            const GraphFinding f = findingFrom(fv.toObject(), file);
            fnFindings[id].append(f);
            attributed.insert(findingKey(f.file, f.line, f.kind));
        }
    }
    const QJsonObject snippets = src.functions.value(QStringLiteral("codeSnippets")).toObject();
    for (auto it = snippets.constBegin(); it != snippets.constEnd(); ++it)
        r.snippets.insert(it.key(), it.value().toString());
    for (const QJsonValue &v : src.functions.value(QStringLiteral("functionEdges")).toArray()) {
        if (!v.isObject())
            continue;
        const QJsonObject eo = v.toObject();
        GraphSymEdge e;
        e.from = strOf(eo, QStringLiteral("from"));
        e.to = strOf(eo, QStringLiteral("to"));
        e.weight = intOf(eo, QStringLiteral("w"));
        if (e.weight <= 0)
            e.weight = 1;
        e.tier = strOf(eo, QStringLiteral("tier"));
        if (e.tier.isEmpty())
            e.tier = QStringLiteral("resolved");
        if (!e.from.isEmpty() && !e.to.isEmpty())
            r.symEdges.append(e);
    }

    // ── 树骨架：根 → 目录 → 文件 → 符号 ──
    CodeGraph &g = r.graph;
    GraphNode root;
    root.kind = GraphNodeKind::root;
    root.id = QStringLiteral("root");
    const QString rootPath = strOf(src.tree, QStringLiteral("root"));
    QString rootName = rootPath;
    const int slash = rootName.lastIndexOf(QLatin1Char('/'));
    if (slash >= 0)
        rootName = rootName.mid(slash + 1);
    root.name = rootName.isEmpty() ? projectName : rootName;
    g.rootName = root.name;
    g.nodes.append(root);
    g.root = 0;
    g.indexById.insert(root.id, 0);

    // 目录节点缓存（按相对路径）
    QHash<QString, int> dirIndex;
    // 目录创建要自顶向下（父目录先存在）—— 递归用 std::function（auto 自引用推导不出来）
    std::function<int(const QStringList &, int)> dirNode
        = [&g, &dirIndex, &dirNode](const QStringList &segs, int rootIdx) {
            const QString path = segs.join(QLatin1Char('/'));
            auto it = dirIndex.constFind(path);
            if (it != dirIndex.constEnd())
                return it.value();
            const int parent
                = segs.size() == 1 ? rootIdx : dirNode(segs.mid(0, segs.size() - 1), rootIdx);
            GraphNode d;
            d.kind = GraphNodeKind::dir;
            d.id = QStringLiteral("d:") + path;
            d.name = segs.isEmpty() ? path : segs.last();
            d.path = path;
            d.parent = parent;
            g.nodes.append(d);
            const int idx = g.nodes.size() - 1;
            g.indexById.insert(d.id, idx);
            dirIndex.insert(path, idx);
            g.nodes[parent].kids.append(idx);
            return idx;
        };

    for (const QJsonValue &v : src.tree.value(QStringLiteral("files")).toArray()) {
        if (!v.isObject())
            continue;
        const QJsonObject fe = v.toObject();
        const QString path = strOf(fe, QStringLiteral("path"));
        if (path.isEmpty())
            continue;
        const QStringList segs = path.split(QLatin1Char('/'), Qt::SkipEmptyParts);
        if (segs.isEmpty())
            continue;
        const int parentDir
            = segs.size() == 1 ? g.root : dirNode(segs.mid(0, segs.size() - 1), g.root);

        GraphNode file;
        file.kind = GraphNodeKind::file;
        file.id = QStringLiteral("f:") + path;
        file.name = segs.last();
        file.path = path;
        file.lang = strOf(fe, QStringLiteral("lang"));
        file.lines = intOf(fe, QStringLiteral("lines"));
        file.parent = parentDir;
        g.nodes.append(file);
        const int fileIdx = g.nodes.size() - 1;
        g.indexById.insert(file.id, fileIdx);
        g.nodes[parentDir].kids.append(fileIdx);

        for (const QJsonValue &sv : fe.value(QStringLiteral("symbols")).toArray()) {
            if (!sv.isObject())
                continue;
            const QJsonObject so = sv.toObject();
            const QString sname = strOf(so, QStringLiteral("name"));
            const int sline = intOf(so, QStringLiteral("line"));
            // ⚠ symbols **不带 id** —— 客户端按引擎同形构造式造一个，
            //   这样才能与 `graph functions` 的 id 对上（关系页签全靠这个对上）。
            const QString sid = so.value(QStringLiteral("id")).toString();
            GraphNode sym;
            sym.kind = GraphNodeKind::sym;
            sym.id = sid.isEmpty() ? symbolId(path, sline, sname) : sid;
            sym.name = sname;
            sym.path = path;
            sym.lang = file.lang;
            sym.symKind = so.value(QStringLiteral("kind")).toString(QStringLiteral("func"));
            sym.declLine = sline;
            sym.parent = fileIdx;
            sym.ownFindings = fnFindings.value(sym.id);
            g.nodes.append(sym);
            const int symIdx = g.nodes.size() - 1;
            g.indexById.insert(sym.id, symIdx);
            g.nodes[fileIdx].kids.append(symIdx);
        }
    }

    // 文件上的「孤儿」疑点：置信度侧有、但没被任何符号体领走的那些。
    QHash<QString, QVector<GraphFinding>> fileOrphans;
    for (const GraphFinding &f : r.findings) {
        if (attributed.contains(findingKey(f.file, f.line, f.kind)))
            continue; // 已按符号体归属过，不重复数
        fileOrphans[f.file].append(f);
    }
    for (auto it = fileOrphans.constBegin(); it != fileOrphans.constEnd(); ++it) {
        const int fileIdx = g.indexById.value(QStringLiteral("f:") + it.key(), -1);
        if (fileIdx < 0)
            continue;
        g.nodes[fileIdx].ownFindings = it.value();
    }

    // ── 排序：目录在前、文件在后、符号按声明行（同一文件的符号保持源码顺序）──
    std::function<void(int)> sortKids = [&g, &sortKids](int idx) {
        QVector<int> &kids = g.nodes[idx].kids;
        std::stable_sort(kids.begin(), kids.end(), [&g](int a, int b) {
            const GraphNode &na = g.nodes.at(a);
            const GraphNode &nb = g.nodes.at(b);
            const int wa = na.kind == GraphNodeKind::dir ? 0
                : (na.kind == GraphNodeKind::file ? 1 : 2);
            const int wb = nb.kind == GraphNodeKind::dir ? 0
                : (nb.kind == GraphNodeKind::file ? 1 : 2);
            if (wa != wb)
                return wa < wb;
            if (na.kind == GraphNodeKind::sym && nb.kind == GraphNodeKind::sym)
                return na.declLine < nb.declLine;
            return QString::compare(na.name, nb.name) < 0;
        });
        for (int k : kids)
            sortKids(k);
    };
    if (g.root >= 0)
        sortKids(g.root);

    // ── 汇总卷积：rollN（子树疑点数）/ rollW（子树最高权重）/ fileCount ──
    const auto rollup = [&g](const auto &self, int idx) -> void {
        GraphNode &n = g.nodes[idx];
        int cnt = n.ownFindings.size();
        int w = 0;
        for (const GraphFinding &f : n.ownFindings)
            w = qMax(w, f.weight);
        int files = 0;
        for (int k : n.kids) {
            self(self, k);
            cnt += g.nodes[k].rollN;
            w = qMax(w, g.nodes[k].rollW);
            files += (g.nodes[k].kind == GraphNodeKind::file ? 1 : g.nodes[k].fileCount);
        }
        g.nodes[idx].rollN = cnt;
        g.nodes[idx].rollW = w;
        g.nodes[idx].fileCount = files;
    };
    if (g.root >= 0)
        rollup(rollup, g.root);

    // ── 文件级引用边（tree 侧；元素是 [from,to,w]）──
    for (const QJsonValue &v : src.tree.value(QStringLiteral("referenceEdges")).toArray()) {
        if (!v.isArray())
            continue;
        const QJsonArray e = v.toArray();
        if (e.size() < 3)
            continue;
        GraphFileEdge fe;
        fe.from = e.at(0).toString();
        fe.to = e.at(1).toString();
        fe.weight = e.at(2).toInt(1);
        if (fe.weight <= 0)
            fe.weight = 1;
        if (!fe.from.isEmpty() && !fe.to.isEmpty())
            r.fileEdges.append(fe);
    }

    // ── 截断披露（缺键不得当作「没有」）──
    r.truncatedPresent = src.tree.contains(QStringLiteral("truncated"));
    r.truncated = src.tree.value(QStringLiteral("truncated")).toBool(false);
    r.skippedPresent = src.tree.contains(QStringLiteral("skipped"));
    r.skipped = intOf(src.tree, QStringLiteral("skipped"));
    r.oversizeSkippedPresent = src.tree.contains(QStringLiteral("oversizeSkipped"));
    r.oversizeSkipped = intOf(src.tree, QStringLiteral("oversizeSkipped"));
    r.depth = intOf(src.tree, QStringLiteral("depth"));
    r.depthOmitted = src.tree.value(QStringLiteral("depthOmitted")).toBool(false);
    for (const QJsonValue &v : src.tree.value(QStringLiteral("unreadableDirs")).toArray())
        r.unreadableDirs << v.toString();
    r.unreadableDirsTruncated
        = src.tree.value(QStringLiteral("unreadableDirsTruncated")).toBool(false);

    r.ok = true;
    return r;
}

QVector<GraphTreeRow> visibleRows(const CodeGraph &g, const QStringList &expanded,
    const QString &query)
{
    QVector<GraphTreeRow> rows;
    if (g.root < 0)
        return rows;
    const QString q = query.trimmed().toLower();

    // 搜索态：命中自身或任一后代 → 可见
    QHash<int, bool> visible;
    const auto visibleInSearch = [&g, &visible, &q](const auto &self, int idx) -> bool {
        auto it = visible.constFind(idx);
        if (it != visible.constEnd())
            return it.value();
        const GraphNode *n = g.node(idx);
        bool hit = n && n->name.toLower().contains(q);
        if (n) {
            for (int k : n->kids) {
                if (self(self, k)) {
                    hit = true;
                    break;
                }
            }
        }
        visible.insert(idx, hit);
        return hit;
    };
    if (!q.isEmpty())
        visibleInSearch(visibleInSearch, g.root);

    const auto walk = [&g, &expanded, &q, &visible, &rows](const auto &self, int idx,
                            int depth) -> void {
        if (!q.isEmpty() && !visible.value(idx, false))
            return;
        rows.append(GraphTreeRow { idx, depth });
        const GraphNode *n = g.node(idx);
        if (!n || n->kids.isEmpty())
            return;
        // 展开判定：无搜索 = 展开集合里有；搜索态 = 有命中后代就展开（命中即见路径）
        bool open = false;
        if (q.isEmpty()) {
            open = expanded.contains(n->id);
        } else {
            for (int k : n->kids) {
                if (visible.value(k, false)) {
                    open = true;
                    break;
                }
            }
        }
        if (!open)
            return;
        for (int k : n->kids)
            self(self, k, depth + 1);
    };
    walk(walk, g.root, 0);
    return rows;
}

} // namespace CodeGraphBuild
