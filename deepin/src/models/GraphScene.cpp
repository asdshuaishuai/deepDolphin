#include "GraphScene.h"

namespace {

// 引擎的 numbers 可能是 int 或 double —— 两种都要收（mac 同款：`as? Double ?? Int`）。
double numOf(const QJsonObject &o, const char *key, double dflt = 0.0)
{
    const QJsonValue v = o.value(QLatin1String(key));
    if (v.isDouble())
        return v.toDouble();
    if (v.isString()) {
        bool ok = false;
        const double d = v.toString().toDouble(&ok);
        return ok ? d : dflt;
    }
    return dflt;
}

QString strOf(const QJsonObject &o, const char *key)
{
    return o.value(QLatin1String(key)).toString();
}

} // namespace

GraphShape GraphShape::fromJson(const QJsonObject &o)
{
    GraphShape s;
    s.type = strOf(o, "t");
    s.x = numOf(o, "x");
    s.y = numOf(o, "y");
    s.w = numOf(o, "w");
    s.h = numOf(o, "h");
    s.r = numOf(o, "r");
    s.text = strOf(o, "text");
    s.label = strOf(o, "label");
    s.color = strOf(o, "color");
    s.fill = strOf(o, "fill");
    s.stroke = strOf(o, "stroke");
    s.align = strOf(o, "align");
    s.node = strOf(o, "node");
    s.size = numOf(o, "size");
    s.weight = numOf(o, "weight", 400);
    s.maxw = numOf(o, "maxw");
    s.sw = numOf(o, "sw");
    s.alpha = numOf(o, "alpha", 1.0);
    s.arrow = numOf(o, "arrow");
    s.delay = numOf(o, "delay");
    s.c0 = strOf(o, "c0");
    s.c1 = strOf(o, "c1");
    for (const QJsonValue &v : o.value(QLatin1String("p")).toArray())
        s.points.push_back(v.toDouble());
    for (const QJsonValue &v : o.value(QLatin1String("edge")).toArray())
        s.edge << v.toString();
    return s;
}

GraphHit GraphHit::fromJson(const QJsonObject &o)
{
    GraphHit h;
    h.id = strOf(o, "id");
    h.x = numOf(o, "x");
    h.y = numOf(o, "y");
    h.w = numOf(o, "w");
    h.h = numOf(o, "h");
    h.drill = strOf(o, "drill");
    h.jump = strOf(o, "jump");
    return h;
}

GraphParticle GraphParticle::fromJson(const QJsonObject &o)
{
    GraphParticle p;
    for (const QJsonValue &v : o.value(QLatin1String("p")).toArray())
        p.p.push_back(v.toDouble());
    p.n = static_cast<int>(numOf(o, "n"));
    p.sp = numOf(o, "sp");
    p.color = strOf(o, "color");
    return p;
}

GraphView GraphView::fromJson(const QString &id, const QJsonObject &o)
{
    GraphView v;
    v.id = id;
    v.label = strOf(o, "label");
    v.parent = strOf(o, "parent");
    const QJsonObject nt = o.value(QLatin1String("nodeTheme")).toObject();
    for (auto it = nt.constBegin(); it != nt.constEnd(); ++it)
        v.nodeTheme.insert(it.key(), it.value().toString());
    for (const QJsonValue &s : o.value(QLatin1String("shapes")).toArray()) {
        if (s.isObject())
            v.shapes.push_back(GraphShape::fromJson(s.toObject()));
    }
    for (const QJsonValue &s : o.value(QLatin1String("particles")).toArray()) {
        if (s.isObject())
            v.particles.push_back(GraphParticle::fromJson(s.toObject()));
    }
    for (const QJsonValue &s : o.value(QLatin1String("hits")).toArray()) {
        if (s.isObject())
            v.hits.push_back(GraphHit::fromJson(s.toObject()));
    }
    // edgesDropped 恒发：0 也发。读不到就留 0，但**不把它当「没有丢弃」**
    // —— 用 edgesDroppedPresent 区分「确实 0」与「契约没发这个键」。
    v.edgesDroppedPresent = o.contains(QLatin1String("edgesDropped"));
    v.edgesDropped = static_cast<int>(numOf(o, "edgesDropped"));
    // bounds（内容包围盒）：引擎无条件发；缺了就退化成恒等视口，
    // 但**必须能区分**「空视图」与「契约没给包围盒」→ boundsPresent。
    v.boundsPresent = o.contains(QLatin1String("bounds"));
    const QJsonObject b = o.value(QLatin1String("bounds")).toObject();
    v.bx0 = numOf(b, "x0");
    v.by0 = numOf(b, "y0");
    v.bx1 = numOf(b, "x1");
    v.by1 = numOf(b, "y1");
    return v;
}

GraphThemeTokens GraphThemeTokens::fromJson(const QJsonObject &o)
{
    GraphThemeTokens t;
    for (auto it = o.constBegin(); it != o.constEnd(); ++it) {
        const QString k = it.key();
        if (k == QLatin1String("cols") || k == QLatin1String("fills") || k == QLatin1String("langs"))
            continue;
        if (it.value().isString())
            t.simple.insert(k, it.value().toString());
    }
    for (const QJsonValue &v : o.value(QLatin1String("cols")).toArray())
        t.cols << v.toString();
    for (const QJsonValue &v : o.value(QLatin1String("fills")).toArray())
        t.fills << v.toString();
    const QJsonObject l = o.value(QLatin1String("langs")).toObject();
    for (auto it = l.constBegin(); it != l.constEnd(); ++it)
        t.langs.insert(it.key(), it.value().toString());
    return t;
}

GraphWarnings GraphWarnings::fromJson(const QJsonObject &o)
{
    GraphWarnings w;
    w.violations = static_cast<int>(numOf(o, "violations"));
    w.cycleEdges = static_cast<int>(numOf(o, "cycleEdges"));
    for (const QJsonValue &v : o.value(QLatin1String("violationPairs")).toArray())
        w.violationPairs << v.toString();
    for (const QJsonValue &v : o.value(QLatin1String("cycleModules")).toArray())
        w.cycleModules << v.toString();
    return w;
}

GraphChip GraphChip::fromJson(const QJsonObject &o)
{
    GraphChip c;
    c.layer = static_cast<int>(numOf(o, "layer"));
    c.count = static_cast<int>(numOf(o, "count"));
    c.label = strOf(o, "label");
    return c;
}

std::optional<GraphScene> GraphScene::fromJson(const QJsonObject &o)
{
    // 契约版本不认识 → 明说不兼容，不静默兼容（mac 同款）。
    if (!o.value(QLatin1String("v")).isDouble())
        return std::nullopt;
    if (o.value(QLatin1String("v")).toInt() != 1)
        return std::nullopt;
    // 必发键：themes / views。缺任一 = 契约过旧。
    if (!o.contains(QLatin1String("themes")) || !o.contains(QLatin1String("views")))
        return std::nullopt;

    GraphScene s;
    s.v = 1;
    s.gen = strOf(o, "gen");

    const QJsonObject meta = o.value(QLatin1String("meta")).toObject();
    s.title = strOf(meta, "title");
    s.sub = strOf(meta, "sub");
    s.stats = strOf(meta, "stats");
    s.hint = strOf(meta, "hint");
    s.root = strOf(meta, "root");
    s.search = strOf(meta, "search");
    s.fit = strOf(meta, "fit");
    s.themeBtn = strOf(meta, "themeBtn");
    s.truncated = meta.value(QLatin1String("truncated")).toBool(false);
    // warnings / chips 恒发（空也发）：缺键时值全是 0/空，与「确实没有」
    // 不可区分 —— 用 present 标志把两种情况分开，交给调用方披露。
    s.warningsPresent = meta.contains(QLatin1String("warnings"));
    s.warnings = GraphWarnings::fromJson(meta.value(QLatin1String("warnings")).toObject());
    s.chipsPresent = meta.contains(QLatin1String("chips"));
    for (const QJsonValue &v : meta.value(QLatin1String("chips")).toArray()) {
        if (v.isObject())
            s.chips.push_back(GraphChip::fromJson(v.toObject()));
    }
    s.panelMeta = meta.value(QLatin1String("panel")).toObject();

    const QJsonObject themes = o.value(QLatin1String("themes")).toObject();
    s.dark = GraphThemeTokens::fromJson(themes.value(QLatin1String("dark")).toObject());
    s.light = GraphThemeTokens::fromJson(themes.value(QLatin1String("light")).toObject());

    const QJsonObject views = o.value(QLatin1String("views")).toObject();
    for (auto it = views.constBegin(); it != views.constEnd(); ++it) {
        if (it.value().isObject()) {
            s.views.push_back(GraphView::fromJson(it.key(), it.value().toObject()));
            if (!s.views.last().boundsPresent)
                ++s.viewsMissingBounds;
        }
    }
    // arch 恒排第一；其余按引擎导出顺序（字典序，module:xxx）——mac 同款。
    // ⚠ 比较器必须是**严格弱序**（std::sort 的前提）：arch 优先靠
    //   「谁是不是 arch」判定，两者都是 arch 时不比较（不能 return true）。
    //   原写法 comp(arch, arch)==true 违反自反性，是未定义行为。
    std::sort(s.views.begin(), s.views.end(), [](const GraphView &a, const GraphView &b) {
        const bool aArch = (a.id == QLatin1String("arch"));
        const bool bArch = (b.id == QLatin1String("arch"));
        if (aArch != bArch)
            return aArch; // arch 排第一
        return a.id < b.id;
    });

    const QJsonObject panels = o.value(QLatin1String("panels")).toObject();
    for (auto it = panels.constBegin(); it != panels.constEnd(); ++it) {
        if (it.value().isObject())
            s.panels.insert(it.key(), it.value().toObject());
    }
    return s;
}

const GraphView *GraphScene::view(const QString &id) const
{
    for (const GraphView &v : views) {
        if (v.id == id)
            return &v;
    }
    return nullptr;
}
