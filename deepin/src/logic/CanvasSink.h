// CanvasSink.h — Canvas2D 子集的**端口**（渲染契约的接缝）。
//
// 【为什么有这一层】
// 引擎的图谱渲染器只依赖标准 Canvas2D 子集；平台只要提供一个「Canvas2D 兼容 context」
// 就能驱动整张图（章程 §3.5 平台 Canvas 分派）。
// 抽出端口有三个好处：
//   ① 判定层（logic/）可挂**记录式接收端**逐条断言调用序列 —— 无需图形环境；
//   ② 平台实现（platform/Canvas2D）只管把调用翻译成 QPainter，不掺业务；
//   ③ 将来换栈（仓颉 Canvas / CoreGraphics）时，判定层与契约层零改动。
//
// 【红线】
// · 方法集与签名**必须**与契约清单一一对应（26 个标准 Canvas2D 方法，见
//   platform/Canvas2D.h 头注释）：少一个 → 引擎渲染器跑不完；多一个私有 API → 契约被污染。
// · 语义是浏览器 Canvas2D 的语义，不是「差不多就行」：
//   角度弧度制、fillText 的 y 是基线、textAlign 改 x 锚点、globalAlpha 是透明度。
// · fillStyle / strokeStyle 在浏览器里既能是颜色也能是渐变对象 —— 用 CanvasPaint
//   一个类型表达两种，免得为渐变单开一个非标准方法（那会污染契约清单）。
#pragma once
#include <QColor>
#include <QLinearGradient>
#include <QString>
#include <QVector>

/// 一次「涂装」的来源：纯色或渐变（二选一）。
struct CanvasPaint {
    QColor color;
    QLinearGradient *gradient = nullptr; // 非空 → 用渐变

    CanvasPaint() = default;
    explicit CanvasPaint(const QColor &c) : color(c) {}
    CanvasPaint(QLinearGradient *g) : gradient(g) {}
    bool isGradient() const { return gradient != nullptr; }
};

class CanvasSink {
public:
    virtual ~CanvasSink() = default;

    virtual void setTransform(double a, double b, double c, double d, double e, double f) = 0;
    virtual void fillRect(double x, double y, double w, double h) = 0;
    virtual void strokeRect(double x, double y, double w, double h) = 0;
    virtual void rect(double x, double y, double w, double h) = 0;

    virtual void beginPath() = 0;
    virtual void moveTo(double x, double y) = 0;
    virtual void lineTo(double x, double y) = 0;
    virtual void arcTo(double x1, double y1, double x2, double y2, double r) = 0;
    virtual void closePath() = 0;
    virtual void arc(double x, double y, double r, double a0, double a1, bool ccw) = 0;
    virtual void bezierCurveTo(double c1x, double c1y, double c2x, double c2y, double x, double y) = 0;
    virtual void fill() = 0;
    virtual void stroke() = 0;

    virtual void fillText(const QString &text, double x, double y) = 0;

    virtual QLinearGradient *createLinearGradient(double x0, double y0, double x1, double y1) = 0;
    virtual void addColorStop(double offset, const QColor &c) = 0;

    virtual void setLineDash(const QVector<double> &dashes) = 0;
    virtual void setLineDashOffset(double offset) = 0;
    virtual void setShadowBlur(double v) = 0;
    virtual void setShadowColor(const QColor &c) = 0;
    virtual void setGlobalAlpha(double v) = 0;
    virtual void setLineWidth(double v) = 0;
    virtual void setStrokeStyle(const CanvasPaint &p) = 0;
    virtual void setFillStyle(const CanvasPaint &p) = 0;
    virtual void setFont(const QString &f) = 0;
    virtual void setTextAlign(const QString &a) = 0;
};

/// 记录式接收端：把每次调用记成一条可断言的文本。
/// 用途：判定层可在**无图形环境**下逐条断言「画了什么、按什么顺序」——
/// 像素断言只能证明「有东西」，指令序列断言才能证明「画的是契约要的那一张」。
class RecordingSink : public CanvasSink {
public:
    QStringList ops;      // 形如 "fillRect(0,0,100,50)" / "fill()" / "setFillStyle(色值)"
    QStringList texts;    // 画过的文字
    int fillRectCount = 0;
    int arcToCount = 0;
    int bezierCount = 0;
    int strokeCount = 0;
    int fillCount = 0;
    int gradientCount = 0;
    int dashCount = 0;
    QString lastFont;
    QString lastAlign;
    QColor lastFill;
    QColor lastStroke;
    double lastLineWidth = 0;

    void setTransform(double, double, double, double, double, double) override
    {
        ops << QStringLiteral("setTransform");
    }
    void fillRect(double x, double y, double w, double h) override
    {
        ++fillRectCount;
        ops << QStringLiteral("fillRect(%1,%2,%3,%4)").arg(x).arg(y).arg(w).arg(h);
    }
    void strokeRect(double x, double y, double w, double h) override
    {
        ops << QStringLiteral("strokeRect(%1,%2,%3,%4)").arg(x).arg(y).arg(w).arg(h);
    }
    void rect(double x, double y, double w, double h) override
    {
        ops << QStringLiteral("rect(%1,%2,%3,%4)").arg(x).arg(y).arg(w).arg(h);
    }
    void beginPath() override { ops << QStringLiteral("beginPath"); }
    void moveTo(double x, double y) override
    {
        ops << QStringLiteral("moveTo(%1,%2)").arg(x).arg(y);
    }
    void lineTo(double x, double y) override
    {
        ops << QStringLiteral("lineTo(%1,%2)").arg(x).arg(y);
    }
    void arcTo(double, double, double, double, double) override
    {
        ++arcToCount;
        ops << QStringLiteral("arcTo");
    }
    void closePath() override { ops << QStringLiteral("closePath"); }
    void arc(double x, double y, double r, double, double, bool) override
    {
        ops << QStringLiteral("arc(%1,%2,%3)").arg(x).arg(y).arg(r);
    }
    void bezierCurveTo(double, double, double, double, double, double) override
    {
        ++bezierCount;
        ops << QStringLiteral("bezierCurveTo");
    }
    void fill() override
    {
        ++fillCount;
        ops << QStringLiteral("fill");
    }
    void stroke() override
    {
        ++strokeCount;
        ops << QStringLiteral("stroke");
    }
    void fillText(const QString &text, double x, double y) override
    {
        texts << text;
        ops << QStringLiteral("fillText(%1,%2,%3)").arg(x).arg(y).arg(text);
    }
    QLinearGradient *createLinearGradient(double, double, double, double) override
    {
        ++gradientCount;
        ops << QStringLiteral("createLinearGradient");
        return new QLinearGradient(QPointF(0, 0), QPointF(1, 1));
    }
    void addColorStop(double offset, const QColor &c) override
    {
        ops << QStringLiteral("addColorStop(%1,%2)").arg(offset).arg(c.name());
    }
    void setLineDash(const QVector<double> &d) override
    {
        ++dashCount;
        ops << QStringLiteral("setLineDash(%1)").arg(d.size());
    }
    void setLineDashOffset(double o) override
    {
        ops << QStringLiteral("setLineDashOffset(%1)").arg(o);
    }
    void setShadowBlur(double v) override { ops << QStringLiteral("setShadowBlur(%1)").arg(v); }
    void setShadowColor(const QColor &c) override
    {
        ops << QStringLiteral("setShadowColor(%1)").arg(c.name());
    }
    void setGlobalAlpha(double v) override { ops << QStringLiteral("setGlobalAlpha(%1)").arg(v); }
    void setLineWidth(double v) override
    {
        lastLineWidth = v;
        ops << QStringLiteral("setLineWidth(%1)").arg(v);
    }
    void setStrokeStyle(const CanvasPaint &p) override
    {
        lastStroke = p.color;
        ops << QStringLiteral("setStrokeStyle(%1)").arg(p.isGradient() ? QStringLiteral("gradient") : p.color.name());
    }
    void setFillStyle(const CanvasPaint &p) override
    {
        lastFill = p.color;
        ops << QStringLiteral("setFillStyle(%1)").arg(p.isGradient() ? QStringLiteral("gradient") : p.color.name());
    }
    void setFont(const QString &f) override
    {
        lastFont = f;
        ops << QStringLiteral("setFont(%1)").arg(f);
    }
    void setTextAlign(const QString &a) override
    {
        lastAlign = a;
        ops << QStringLiteral("setTextAlign(%1)").arg(a);
    }
};
