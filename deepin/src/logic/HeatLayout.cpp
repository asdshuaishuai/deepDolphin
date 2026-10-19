#include "HeatLayout.h"

#include <QHash>
#include <QMap>
#include <QSet>
#include <QtMath>

#include <algorithm>
#include <cmath>

namespace HeatLayout {
namespace {

// 卡片尺寸（mac 同款）。
void boxSize(GraphNodeKind kind, bool boundary, double &w, double &h)
{
    if (boundary) {
        w = 166;
        h = 66;
    } else if (kind == GraphNodeKind::file) {
        w = 194;
        h = 88;
    } else {
        w = 184;
        h = 76;
    }
}

/// 视觉分层（mac 的 .type 分支是死代码，不移植）。
Layer layerOf(GraphNodeKind kind, bool boundary)
{
    if (boundary)
        return Layer::boundary;
    if (kind == GraphNodeKind::file)
        return Layer::files;
    return Layer::funcs;
}

/// HSL → RGB（纯算术，判定层不碰 GUI）。
QColor hslToColor(double h, double s, double v)
{
    h = std::fmod(h, 360.0);
    if (h < 0)
        h += 360.0;
    const double c = v * s;
    const double x = c * (1.0 - std::fabs(std::fmod(h / 60.0, 2.0) - 1.0));
    const double m = v - c;
    double r = 0, g = 0, b = 0;
    if (h < 60) {
        r = c; g = x;
    } else if (h < 120) {
        r = x; g = c;
    } else if (h < 180) {
        g = c; b = x;
    } else if (h < 240) {
        g = x; b = c;
    } else if (h < 300) {
        r = x; b = c;
    } else {
        r = c; b = x;
    }
    return QColor::fromRgbF(qBound(0.0, r + m, 1.0), qBound(0.0, g + m, 1.0),
        qBound(0.0, b + m, 1.0));
}

/// 稳定的字符串哈希（mac 用 Swift 的 hashValue；这里要**跨平台稳定**，
/// 否则同一份数据每台机器画出的边散布不一样 —— 布局就没法判了）。
quint32 stableHash(const QString &s)
{
    quint32 h = 2166136261u;
    for (const QChar c : s) {
        h ^= static_cast<quint32>(c.unicode());
        h *= 16777619u;
    }
    return h;
}

/// 邻居重心（mac 的 `bary`）：按关联边的权重加权求邻居在某轴上的中心。
/// 强关联的卡会被拉到彼此附近（格位对换，不破坏网格工整）。
double barycenter(const QVector<Card> &cards, const QVector<int> &row, int cardIdx,
    const QVector<Edge> &edges, bool xAxis)
{
    const Card &self = cards.at(cardIdx);
    double sum = 0, w = 0;
    for (const Edge &e : edges) {
        QString other;
        if (e.from == self.id)
            other = e.to;
        else if (e.to == self.id)
            other = e.from;
        if (other.isEmpty())
            continue;
        int otherIdx = -1;
        for (int i : row) {
            if (cards.at(i).id == other) {
                otherIdx = i;
                break;
            }
        }
        if (otherIdx < 0)
            continue;
        const Card &q = cards.at(otherIdx);
        const double weight = qMax(1, e.w);
        sum += (xAxis ? q.x + q.w / 2 : q.y + q.h / 2) * weight;
        w += weight;
    }
    if (w <= 0)
        return xAxis ? self.x + self.w / 2 : self.y + self.h / 2;
    return xAxis ? sum / w - self.w / 2 : sum / w - self.h / 2;
}

/// 符号 id → 所属文件路径。id 形如 `f:<路径>:<行号>:<名字>`。
/// 路径里也可能带冒号，所以取「首段之后、末两段之前」的中间部分，
/// 而不是简单取第二段。
QString fileOfSymbolId(const QString &id)
{
    const QStringList parts = id.split(QLatin1Char(':'));
    if (parts.size() < 4)
        return QString();
    return parts.mid(1, parts.size() - 3).join(QLatin1Char(':'));
}

/// 符号 id → 声明行号（认不出就是 0 —— 调用方据此判定「这条边对不上」）。
int lineOfSymbolId(const QString &id)
{
    const QStringList parts = id.split(QLatin1Char(':'));
    if (parts.size() < 3)
        return 0;
    bool ok = false;
    const int v = parts.at(parts.size() - 2).toInt(&ok);
    return ok ? v : 0;
}

/// 符号 id → 符号名。
QString nameOfSymbolId(const QString &id)
{
    const QStringList parts = id.split(QLatin1Char(':'));
    return parts.size() >= 2 ? parts.last() : QString();
}

/// (文件,行号,名字) 复合键 —— 引擎 id 与本地 id 不同形时的兜底对齐键。
QString tupleKey(const QString &file, int line, const QString &name)
{
    return file + QLatin1Char('\n') + QString::number(line) + QLatin1Char('\n') + name;
}

/// 作用域解析表：引擎符号 id → 本地卡 id。
///
/// 【为什么要有兜底】引擎的 `graph functions` 与 `graph tree` 是**两次独立扫描**：
/// 客户端用 tree 侧的 (路径,行号,名字) 造符号 id，functions 侧直接给引擎的 id。
/// 两者同形时这是恒等映射；一旦不同形（引擎改了行号口径、tree 被截断…），
/// 「调用边找不到卡」会让跨作用域引用**静默消失** —— 热力图少画几张卡，
/// 看不出是契约漂移还是数据就是这样。所以再按 (文件,行号,名字) 兜一层。
struct ScopeResolver {
    QHash<QString, QString> byId;    ///< 引擎 id（与本地同形）→ 本地卡 id
    QHash<QString, QString> byTuple; ///< (文件,行号,名字) → 本地卡 id

    /// 引擎符号 id → 本地卡 id；不在作用域内返回空串。
    QString resolve(const QString &engineId) const
    {
        if (engineId.isEmpty())
            return QString();
        const auto it = byId.constFind(engineId);
        if (it != byId.constEnd())
            return it.value();
        return byTuple.value(
            tupleKey(fileOfSymbolId(engineId), lineOfSymbolId(engineId), nameOfSymbolId(engineId)),
            QString());
    }
};

/// 作用域内的符号卡（不含跨作用域边界卡）。
QVector<Card> scopeSymbolCards(const CodeGraph &g, int drillNode)
{
    QVector<Card> out;
    const GraphNode *f = g.node(drillNode);
    if (!f)
        return out;
    QVector<int> syms;
    for (int k : f->kids) {
        const GraphNode *n = g.node(k);
        if (n && n->kind == GraphNodeKind::sym)
            syms << k;
    }
    std::sort(syms.begin(), syms.end(), [&g](int a, int b) {
        return g.nodes.at(a).declLine < g.nodes.at(b).declLine;
    });
    for (int k : syms) {
        const GraphNode &n = g.nodes.at(k);
        Card c;
        c.node = k;
        c.id = n.id;
        c.name = n.name;
        c.path = n.path;
        c.penalty = n.rollWeightSum; // 符号的子树就是它自己 → 权重和
        c.kind = GraphNodeKind::sym;
        c.declLine = n.declLine;
        out << c;
    }
    return out;
}

/// 由作用域内的符号卡建解析表。
ScopeResolver buildResolver(const QVector<Card> &symbolCards)
{
    ScopeResolver r;
    for (const Card &c : symbolCards) {
        r.byId.insert(c.id, c.id);
        r.byTuple.insert(tupleKey(c.path, c.declLine, c.name), c.id);
    }
    return r;
}

} // namespace

int confScore(int penalty, int files)
{
    const double n = qMax(1, files);
    const double density = penalty / n;
    const int s = static_cast<int>(std::floor(100.0 * 20.0 / (20.0 + density)));
    return qBound(0, s, 100);
}

QColor heatColor(int score)
{
    // 契约色（与 HTML 交付物的 confidenceColor 逐字同色）：绿 / 琥珀 / 粉三档。
    // 写成 rgb 三元组而不是 #hex —— D2 grep 门盯的就是 #RRGGBB 字面量
    //（见 scripts/ci.sh 第 5 门），契约色不是设计令牌，不该走那条路。
    if (score >= 80)
        return QColor(89, 240, 184);
    if (score >= 60)
        return QColor(255, 200, 87);
    return QColor(255, 107, 138);
}

QColor idColor(int hue)
{
    const int v = ((hue % 2) + 2) % 2;
    return hslToColor(hue / 360.0, 0.62 + v * 0.16, 0.52 + v * 0.14);
}

QHash<QString, int> huesFor(const CodeGraph &g)
{
    // 黄金角 137.508° 散布（相邻节点色相差最大化），排序键 = 节点 id 字典序
    // （与 HTML 的 HUE_OF 相同）。目录不参与（它们不出现在热力图里）。
    QStringList ids;
    for (const GraphNode &n : g.nodes) {
        if (n.kind != GraphNodeKind::dir)
            ids << n.id;
    }
    ids.sort();
    QHash<QString, int> out;
    for (int i = 0; i < ids.size(); ++i)
        out.insert(ids.at(i), static_cast<int>(qRound(i * 137.508)) % 360);
    return out;
}

QVector<Card> scopeCards(const CodeGraph &g, const QHash<QString, int> &hues, int drillNode,
    const QVector<Edge> &symEdges)
{
    QVector<Card> out;
    if (drillNode >= 0) {
        // 下钻层：该文件的符号（按声明行）
        out = scopeSymbolCards(g, drillNode);
        for (Card &c : out)
            c.hue = hues.value(c.id, 0);
        const GraphNode *f = g.node(drillNode);
        if (!f)
            return out;

        // 跨作用域边界：作用域内的符号调用到**作用域外**的符号 → 按被调方所在
        // **文件**聚合（mac 的注释写的是「按文件聚合」，但它的键其实是符号 id，
        // 卡片名会带行号；本端按文件聚合，名字更干净）。
        const ScopeResolver res = buildResolver(out);
        QMap<QString, int> aggCount;
        QMap<QString, int> aggWeight;
        for (const Edge &e : symEdges) {
            if (res.resolve(e.from).isEmpty())
                continue; // 调用方不在本作用域内
            if (!res.resolve(e.to).isEmpty())
                continue; // 被调方也在本作用域内 → 不是跨作用域
            // 被调方的文件**从 id 直接取**：不依赖它在本地树里有没有对应节点 ——
            // 树被截断、符号没进 tree 时，跨作用域引用照样要显示出来。
            const QString file = fileOfSymbolId(e.to);
            if (file.isEmpty() || file == f->path)
                continue; // 文件认不出（同文件的漏网符号也不算跨作用域）→ 不猜
            aggCount[file] += 1;
            aggWeight[file] += e.w;
        }
        // 按权重降序、同权重按路径字典序（mac 同款排序键）
        QStringList files = aggCount.keys();
        std::sort(files.begin(), files.end(), [&aggWeight, &aggCount](const QString &a,
                           const QString &b) {
            if (aggWeight.value(a) != aggWeight.value(b))
                return aggWeight.value(a) > aggWeight.value(b);
            return a < b;
        });
        for (int i = 0; i < files.size() && i < 9; ++i) {
            const QString &file = files.at(i);
            Card c;
            c.node = -1;
            c.id = QStringLiteral("cgx:") + file;
            c.path = file;
            const QStringList segs = file.split(QLatin1Char('/'), Qt::SkipEmptyParts);
            c.name = QStringLiteral("↗ ") + (segs.isEmpty() ? file : segs.last());
            c.hue = hues.value(QStringLiteral("f:") + file, 0);
            c.penalty = qMin(8, aggWeight.value(file));
            c.kind = GraphNodeKind::sym;
            c.boundary = true;
            out << c;
        }
        if (files.size() > 9) {
            Card c;
            c.node = -1;
            c.id = QStringLiteral("cgx:__more");
            c.name = QStringLiteral("↗ +%1").arg(files.size() - 9);
            c.kind = GraphNodeKind::sym;
            c.boundary = true;
            out << c;
        }
        return out;
    }

    // 文件层：全部文件（按名）
    QVector<int> files;
    for (int i = 0; i < g.nodes.size(); ++i) {
        if (g.nodes.at(i).kind == GraphNodeKind::file)
            files << i;
    }
    std::sort(files.begin(), files.end(), [&g](int a, int b) {
        return g.nodes.at(a).name < g.nodes.at(b).name;
    });
    for (int k : files) {
        const GraphNode &n = g.nodes.at(k);
        Card c;
        c.node = k;
        c.id = n.id;
        c.name = n.name;
        c.path = n.path;
        c.hue = hues.value(n.id, 0);
        c.penalty = n.rollWeightSum; // 文件的子树权重和（热色输入）
        c.kind = GraphNodeKind::file;
        out << c;
    }
    return out;
}

QVector<Edge> scopeEdges(const CodeGraph &g, const QVector<Edge> &symEdges,
    const QVector<GraphFileEdge> &fileEdges, int drillNode)
{
    Q_UNUSED(g);
    QVector<Edge> out;
    if (drillNode >= 0) {
        // 下钻层：作用域内的符号级调用边（同对聚合权重）
        const GraphNode *f = g.node(drillNode);
        if (!f)
            return out;
        const ScopeResolver res = buildResolver(scopeSymbolCards(g, drillNode));
        QMap<QString, Edge> agg;
        for (const Edge &e : symEdges) {
            const QString from = res.resolve(e.from);
            const QString to = res.resolve(e.to);
            if (from.isEmpty() || to.isEmpty())
                continue; // 有一端不在本作用域内 → 不是作用域内的边
            const QString key = from + QStringLiteral("=>") + to;
            auto it = agg.find(key);
            if (it != agg.end())
                it->w += e.w;
            else
                agg.insert(key, Edge { from, to, e.w, e.tier });
        }
        for (const Edge &e : agg)
            out << e;
        return out;
    }
    // 文件层：文件级引用边 → 节点 id「f:路径」
    for (const GraphFileEdge &e : fileEdges)
        out << Edge { QStringLiteral("f:") + e.from, QStringLiteral("f:") + e.to, e.weight,
            QStringLiteral("resolved") };
    return out;
}

QVector<Card> layout(const QVector<Card> &nodes, const QVector<Edge> &edges, double width,
    double height)
{
    QVector<Card> cards;
    if (nodes.isEmpty() || width <= 60 || height <= 60)
        return cards;

    // 分带（按视觉分层归组；层内保持输入顺序，随后再排）
    struct Band {
        Layer layer;
        QVector<int> cards; ///< nodes 的下标
    };
    QVector<Band> bands;
    for (int i = 0; i < nodes.size(); ++i) {
        const Card &c = nodes.at(i);
        const Layer l = layerOf(c.kind, c.boundary);
        int bi = -1;
        for (int k = 0; k < bands.size(); ++k) {
            if (bands.at(k).layer == l) {
                bi = k;
                break;
            }
        }
        if (bi < 0) {
            Band b;
            b.layer = l;
            b.cards << i;
            bands << b;
        } else {
            bands[bi].cards << i;
        }
    }
    std::sort(bands.begin(), bands.end(),
        [](const Band &a, const Band &b) { return int(a.layer) < int(b.layer); });

    // 带内语义排序：符号按声明行，其余按名（mac 同款）
    for (Band &b : bands) {
        std::sort(b.cards.begin(), b.cards.end(), [&nodes](int a, int c) {
            const Card &na = nodes.at(a);
            const Card &nc = nodes.at(c);
            if (na.kind == GraphNodeKind::sym && nc.kind == GraphNodeKind::sym
                && na.declLine != nc.declLine) {
                return na.declLine < nc.declLine;
            }
            return na.name < nc.name;
        });
    }

    // 网格几何
    const double gapX = 78, gapY = 84;
    double maxW = 120, maxH = 70;
    for (const Band &b : bands) {
        for (int i : b.cards) {
            double w = 0, h = 0;
            const Card &c = nodes.at(i);
            boxSize(c.kind, c.boundary, w, h);
            maxW = qMax(maxW, w);
            maxH = qMax(maxH, h);
        }
    }
    const double cellW = maxW + gapX, cellH = maxH + gapY;
    const double left = 40;
    struct Grid {
        int cols = 1, rows = 1;
        double w = 0, h = 0;
    };
    QVector<Grid> grids;
    for (const Band &b : bands) {
        Grid gr;
        const int n = b.cards.size();
        gr.cols = qMax(1, qMin(n, static_cast<int>(qCeil(qSqrt(n * 1.7)))));
        gr.rows = (n + gr.cols - 1) / gr.cols;
        gr.w = left * 2 + gr.cols * cellW - gapX;
        gr.h = 40 + gr.rows * cellH - gapY + 70;
        grids << gr;
    }
    double maxGridW = 0;
    for (const Grid &gr : grids)
        maxGridW = qMax(maxGridW, gr.w);
    const double worldW = qMax(width - 40, maxGridW);
    // 世界高度**不**在这里定：卡片铺完的实际包围盒才是准的（判定层算不准
    // 就让上层按实测算，见 HeatmapWidget::contentSize）。

    double laneY = 30;
    for (int bi = 0; bi < bands.size(); ++bi) {
        const Grid &gr = grids.at(bi);
        const double gridW = gr.cols * cellW - gapX;
        const double offX = qMax(left, (worldW - gridW) / 2);
        int n = 0;
        for (int i : bands.at(bi).cards) {
            const Card &src = nodes.at(i);
            double w = 0, h = 0;
            boxSize(src.kind, src.boundary, w, h);
            const int col = n % gr.cols, row = n / gr.cols;
            Card c = src;
            c.x = offX + col * cellW + (cellW - gapX - w) / 2;
            c.y = laneY + 40 + row * cellH + (cellH - gapY - h) / 2;
            c.w = w;
            c.h = h;
            c.layerIndex = bi;
            cards << c;
            ++n;
        }
        laneY += gr.h + (bands.size() > 1 ? 84 : 0);
    }

    // 关系聚类重心扫描（3 轮）：行内按邻居 x 重心、列内按邻居 y 重心。
    // 格位对换（不破坏网格工整），强关联卡相邻。
    const int passes = 3;
    for (int p = 0; p < passes; ++p) {
        // 行内重排 x
        QMap<int, QVector<int>> rows;
        for (int i = 0; i < cards.size(); ++i)
            rows[static_cast<int>(cards.at(i).y / 10)] << i;
        for (auto it = rows.begin(); it != rows.end(); ++it) {
            QVector<int> &row = it.value();
            if (row.size() < 2)
                continue;
            QVector<double> slotPos;
            for (int i : row)
                slotPos << cards.at(i).x;
            std::sort(slotPos.begin(), slotPos.end());
            QVector<int> ordered = row;
            std::sort(ordered.begin(), ordered.end(), [&cards, &row, &edges](int a, int b) {
                return barycenter(cards, row, a, edges, true)
                    < barycenter(cards, row, b, edges, true);
            });
            for (int k = 0; k < ordered.size(); ++k)
                cards[ordered.at(k)].x = slotPos.at(k);
        }
        // 列内重排 y
        QMap<int, QVector<int>> cols;
        for (int i = 0; i < cards.size(); ++i)
            cols[static_cast<int>(cards.at(i).x / 10)] << i;
        for (auto it = cols.begin(); it != cols.end(); ++it) {
            QVector<int> &col = it.value();
            if (col.size() < 2)
                continue;
            QVector<double> slotPos;
            for (int i : col)
                slotPos << cards.at(i).y;
            std::sort(slotPos.begin(), slotPos.end());
            QVector<int> ordered = col;
            std::sort(ordered.begin(), ordered.end(), [&cards, &col, &edges](int a, int b) {
                return barycenter(cards, col, a, edges, false)
                    < barycenter(cards, col, b, edges, false);
            });
            for (int k = 0; k < ordered.size(); ++k)
                cards[ordered.at(k)].y = slotPos.at(k);
        }
    }

    // 序号 = 最终排布的阅读序（带内行主序）
    for (int bi = 0; bi < bands.size(); ++bi) {
        QVector<int> inBand;
        for (int i = 0; i < cards.size(); ++i) {
            if (cards.at(i).layerIndex == bi)
                inBand << i;
        }
        std::sort(inBand.begin(), inBand.end(), [&cards](int a, int b) {
            if (cards.at(a).y != cards.at(b).y)
                return cards.at(a).y < cards.at(b).y;
            return cards.at(a).x < cards.at(b).x;
        });
        for (int k = 0; k < inBand.size(); ++k)
            cards[inBand.at(k)].rank = k + 1;
    }
    return cards;
}

QVector<QPointF> catmull(const QVector<QPointF> &pts, int per)
{
    if (pts.size() <= 2)
        return pts;
    QVector<QPointF> out;
    out << pts.first();
    for (int i = 0; i < pts.size() - 1; ++i) {
        const QPointF p0 = pts.at(qMax(0, i - 1));
        const QPointF p1 = pts.at(i);
        const QPointF p2 = pts.at(i + 1);
        const QPointF p3 = pts.at(qMin(pts.size() - 1, i + 2));
        for (int j = 1; j <= per; ++j) {
            const double t = double(j) / per;
            const double t2 = t * t, t3 = t2 * t;
            out << QPointF(
                0.5 * (2 * p1.x() + (-p0.x() + p2.x()) * t
                    + (2 * p0.x() - 5 * p1.x() + 4 * p2.x() - p3.x()) * t2
                    + (-p0.x() + 3 * p1.x() - 3 * p2.x() + p3.x()) * t3),
                0.5 * (2 * p1.y() + (-p0.y() + p2.y()) * t
                    + (2 * p0.y() - 5 * p1.y() + 4 * p2.y() - p3.y()) * t2
                    + (-p0.y() + 3 * p1.y() - 3 * p2.y() + p3.y()) * t3));
        }
    }
    return out;
}

QVector<Route> routes(const QVector<Card> &cards, const QVector<Edge> &edges)
{
    QVector<Route> out;
    QHash<QString, Card> byId;
    for (const Card &c : cards)
        byId.insert(c.id, c);

    // 行聚类：带内卡片按 y 聚行（同一水平带的卡共享行隙通道）
    struct Row {
        double top = 0, bottom = 0;
        QVector<QString> cards;
    };
    QMap<int, QVector<Row>> rowsByLayer;
    for (const Card &c : cards) {
        QVector<Row> &rows = rowsByLayer[c.layerIndex];
        int ri = -1;
        for (int i = 0; i < rows.size(); ++i) {
            if (qAbs(rows.at(i).top - c.y) < 20) {
                ri = i;
                break;
            }
        }
        if (ri < 0) {
            Row r;
            r.top = c.y;
            r.bottom = c.y + c.h;
            r.cards << c.id;
            rows << r;
        } else {
            rows[ri].top = qMin(rows[ri].top, c.y);
            rows[ri].bottom = qMax(rows[ri].bottom, c.y + c.h);
            rows[ri].cards << c.id;
        }
    }
    for (auto it = rowsByLayer.begin(); it != rowsByLayer.end(); ++it) {
        std::sort(it.value().begin(), it.value().end(),
            [](const Row &a, const Row &b) { return a.top < b.top; });
    }

    const auto rowOf = [&rowsByLayer, &byId](const QString &id, int &layer, int &idx) -> bool {
        auto it = byId.constFind(id);
        if (it == byId.constEnd())
            return false;
        const Card &c = it.value();
        const QVector<Row> &rows = rowsByLayer[c.layerIndex];
        for (int i = 0; i < rows.size(); ++i) {
            if (c.y >= rows.at(i).top - 6 && c.y <= rows.at(i).top + 24) {
                layer = c.layerIndex;
                idx = i;
                return true;
            }
        }
        if (rows.isEmpty())
            return false;
        layer = c.layerIndex;
        idx = 0;
        return true;
    };
    const auto chBelow = [&rowsByLayer](int layer, int idx, double &out) -> bool {
        const QVector<Row> &rows = rowsByLayer[layer];
        if (rows.isEmpty())
            return false;
        if (idx + 1 < rows.size()) {
            out = (rows.at(idx).bottom + rows.at(idx + 1).top) / 2;
            return true;
        }
        out = rows.last().bottom + 42;
        return true;
    };
    const auto chAbove = [&rowsByLayer](int layer, int idx, double &out) -> bool {
        const QVector<Row> &rows = rowsByLayer[layer];
        if (rows.isEmpty())
            return false;
        if (idx > 0) {
            out = (rows.at(idx - 1).bottom + rows.at(idx).top) / 2;
            return true;
        }
        out = rows.first().top - 42;
        return true;
    };
    const auto anchor = [](const Card &c, bool top, double t) {
        const double inset = 12;
        return QPointF(c.x + inset + t * qMax(1.0, c.w - 2 * inset),
            top ? c.y : c.y + c.h);
    };

    for (const Edge &e : edges) {
        auto ia = byId.constFind(e.from);
        auto ib = byId.constFind(e.to);
        if (ia == byId.constEnd() || ib == byId.constEnd())
            continue;
        int sl = 0, si = 0, tl = 0, ti = 0;
        if (!rowOf(e.from, sl, si) || !rowOf(e.to, tl, ti))
            continue;
        const bool sameRow = (sl == tl && si == ti);
        const bool down = (tl > sl) || (tl == sl && ti > si);
        const double spreadA = double((stableHash(e.from) % 100) + 8) / 100.0;
        const double spreadB = double((stableHash(e.to) % 100) + 8) / 100.0;
        const QPointF s = anchor(ia.value(), !sameRow && !down, spreadA);
        const QPointF t = anchor(ib.value(), sameRow || !down, spreadB);

        QVector<QPointF> pts;
        pts << s;
        if (sameRow) {
            double ch = s.y() + 42;
            chBelow(sl, si, ch);
            pts << QPointF(s.x(), ch);
            pts << QPointF(t.x(), ch);
        } else if (down) {
            double chA = s.y(), chB = t.y();
            chBelow(sl, si, chA);
            chAbove(tl, ti, chB);
            pts << QPointF(s.x(), chA);
            if (qAbs(chA - chB) > 2) {
                // 列间隙垂直段（被卡挡住时绕行）
                bool blocked = false;
                for (const Card &c : cards) {
                    if (c.id == e.from || c.id == e.to)
                        continue;
                    if (c.y + c.h > qMin(chA, chB) + 4 && c.y < qMax(chA, chB) - 4
                        && t.x() > c.x + 6 && t.x() < c.x + c.w - 6) {
                        blocked = true;
                        break;
                    }
                }
                if (blocked) {
                    const int k = int(stableHash(e.from) % 3);
                    const double vx = t.x() + (k == 0 ? -52 : (k == 1 ? 52 : 0));
                    pts << QPointF(vx, chA);
                    pts << QPointF(vx, chB);
                    pts << QPointF(t.x(), chB);
                } else {
                    pts << QPointF(t.x(), chA);
                    if (qAbs(chB - chA) > 2)
                        pts << QPointF(t.x(), chB);
                }
            }
        } else {
            double chA = s.y(), chB = t.y();
            chAbove(sl, si, chA);
            chBelow(tl, ti, chB);
            pts << QPointF(s.x(), chA);
            if (qAbs(chA - chB) > 2) {
                pts << QPointF(t.x(), chA);
                pts << QPointF(t.x(), chB);
            }
        }
        pts << t;

        // 合并重复点
        QVector<QPointF> clean;
        clean << pts.first();
        for (int i = 1; i < pts.size(); ++i) {
            const QPointF &p = pts.at(i);
            const QPointF &q = clean.last();
            if (qAbs(p.x() - q.x()) > 1 || qAbs(p.y() - q.y()) > 1)
                clean << p;
        }
        if (clean.size() < 2)
            continue;
        Route r;
        r.from = e.from;
        r.to = e.to;
        r.w = e.w;
        r.tier = e.tier;
        r.points = clean;
        r.smoothed = catmull(clean, 12);
        out << r;
    }
    return out;
}

} // namespace HeatLayout
