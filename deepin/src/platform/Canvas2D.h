// Canvas2D.h — 标准 Canvas2D API 的**可审计子集**的 Qt/QPainter 实现。
//
// 契约：moonGit 仓库 docs/graph-scene-schema.md（渲染契约层）。
// 引擎的图谱渲染器（src/graph/archhtml.cj）只依赖 ctx 上的这些标准方法，
// 多一个私有 API 都没有 —— 因此「把 ctx 注入渲染器」即可驱动整张图，
// 交互逻辑与绘制完全分离。
//
// 【移植验收清单】契约清单共 26 个标准方法，本类**全部实现**（引擎的 arch 渲染器
// 实际用到其中 25 个，`rect` 未用 —— 但清单是上限不是下限，缺一个就跑不完）:
//   setTransform fillRect beginPath moveTo lineTo arcTo closePath
//   fill stroke rect strokeRect arc bezierCurveTo fillText
//   createLinearGradient addColorStop
//   setLineDash lineDashOffset
//   shadowBlur shadowColor globalAlpha
//   lineWidth strokeStyle fillStyle font textAlign
//
// 【红线】
// · 语义对齐浏览器 Canvas2D，**不**发明「Qt 风格」：角度弧度制、fillText 的 y 是基线、
//   textAlign 改的是 x 锚点、globalAlpha 是透明度（不是混合模式）。
// · shadowBlur/shadowColor：QPainter **无原生阴影**，本类用「离屏绘制 + alpha 盒式模糊
//   （三遍≈高斯）+ 着色合成」模拟。这是显式的等价实现，不是近似糊弄 —— 缺这一项，
//   引擎渲染器跑不完（契约原话：少实现一项就跑不完）。
// · 未知 token/坏色值不在本类兜底（那是 GraphToken 的纪律），本类只忠实执行。
#pragma once
#include <QColor>
#include <QFont>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QString>
#include <QVector>
#include <functional>

#include "../logic/CanvasSink.h"

class Canvas2D : public CanvasSink {
public:
    explicit Canvas2D(QPainter *painter);

    // ── 变换 ──
    void setTransform(double a, double b, double c, double d, double e, double f) override;

    // ── 矩形 ──
    void fillRect(double x, double y, double w, double h) override;
    void strokeRect(double x, double y, double w, double h) override;
    void rect(double x, double y, double w, double h) override; // 加一条子路径（不是立刻描边）

    // ── 路径 ──
    void beginPath() override;
    void moveTo(double x, double y) override;
    void lineTo(double x, double y) override;
    void arcTo(double x1, double y1, double x2, double y2, double r) override;
    void closePath() override;
    void arc(double x, double y, double r, double a0, double a1, bool ccw) override;
    void bezierCurveTo(double c1x, double c1y, double c2x, double c2y, double x, double y) override;
    void fill() override;
    void stroke() override;

    // ── 文本 ──
    void fillText(const QString &text, double x, double y) override;

    // ── 渐变 ──
    QLinearGradient *createLinearGradient(double x0, double y0, double x1, double y1) override;
    void addColorStop(double offset, const QColor &c) override;

    // ── 状态 ──
    void setLineDash(const QVector<double> &dashes) override;
    void setLineDashOffset(double offset) override;
    void setShadowBlur(double v) override;
    double shadowBlur() const { return m_shadowBlur; }
    void setShadowColor(const QColor &c) override;
    void setGlobalAlpha(double v) override;
    double globalAlpha() const { return m_globalAlpha; }
    void setLineWidth(double v) override;
    void setStrokeStyle(const CanvasPaint &p) override;
    void setFillStyle(const CanvasPaint &p) override;
    void setFont(const QString &f) override;
    void setTextAlign(const QString &a) override;
    QString textAlign() const { return m_textAlign; }
    QFont font() const { return m_font; }

private:
    // 填充/描边的 paint 源：可以是纯色，也可以是渐变。
    struct Paint {
        bool gradient = false;
        QColor color;
        QLinearGradient *grad = nullptr;
    };

    QPainter *m_painter = nullptr;
    QPainterPath m_path;
    Paint m_fill;
    Paint m_stroke;
    QFont m_font;
    QString m_textAlign = QStringLiteral("left");
    double m_lineWidth = 1.0;
    double m_globalAlpha = 1.0;
    double m_shadowBlur = 0.0;
    QColor m_shadowColor;
    QVector<double> m_dash;
    double m_dashOffset = 0.0;
    QLinearGradient *m_pendingGradient = nullptr; // createLinearGradient → addColorStop 的中转

    QBrush fillBrush() const;
    QPen strokePen() const;

    // 阴影模拟：把一次绘制操作先画到离屏图、模糊、着色，再合成到目标。
    void withShadow(const std::function<void(QPainter &)> &op);
};
