// HeatmapWidget.h — 代码图谱的「符号索引热力图」画布（Qt QPainter + 批 D1 的 Canvas2D 内核）。
//
// 【它是什么】
// mac `CodeGraphHeatmap.swift` 的 Canvas 版对位：铺排与走线在 `logic/HeatLayout`
// （纯函数），本控件只负责**画**与**接**（点选、下钻、动画时钟）。
//
// 【两层的分工】
//   logic/HeatLayout  → 卡片在哪、走线怎么走、颜色怎么算（可无头判）
//   HeatmapWidget     → 画出来 + 收点击（依赖图形栈）
//
// 【动画时钟】30fps 重绘，但**布局与走线不每帧重跑**（按「层级 + 画布尺寸 + 边数」缓存），
// 且窗口不可见时停表（mac 的电量纪律）。
#pragma once
#include <QElapsedTimer>
#include <QTimer>
#include <QWidget>
#include "../logic/CodeGraphBuild.h"
#include "../logic/HeatLayout.h"
#include "../models/CodeGraph.h"

class HeatmapWidget : public QWidget {
    Q_OBJECT
public:
    explicit HeatmapWidget(QWidget *parent = nullptr);

    /// 数据源（三源合成的结果）。指针由上层持有，失效时调用方会重设。
    void setData(const CodeGraphBuild::Result *result);
    /// 下钻到的文件（arena 索引；-1 = 文件层）。
    void setDrill(int nodeIdx);
    int drill() const { return m_drill; }
    /// 选中的节点 id（高亮 + 右栏详情联动）。
    void setSelected(const QString &id);
    QString selected() const { return m_selected; }

signals:
    /// 点中了符号（→ 右栏详情面板）。
    void nodeSelected(int nodeIdx);
    /// 下钻层变化（文件层 ↔ 符号层）。
    void drillChanged(int nodeIdx);

protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void showEvent(QShowEvent *event) override;
    void hideEvent(QHideEvent *event) override;
    QSize sizeHint() const override;
    QSize minimumSizeHint() const override;

private:
    void rebuild();
    void paintCards(QPainter &p);
    void paintRoutes(QPainter &p, double now);
    const HeatLayout::Card *cardAt(double x, double y) const;

    const CodeGraphBuild::Result *m_result = nullptr;
    int m_drill = -1;
    QString m_selected;

    QVector<HeatLayout::Card> m_cards;
    QVector<HeatLayout::Route> m_routes;
    QHash<QString, int> m_hues;
    QString m_cacheKey;
    bool m_cacheValid = false;
    double m_contentHeight = 240; ///< 卡片铺完的实际高度（滚动范围）

    QElapsedTimer m_clock;
    QTimer *m_anim = nullptr;
};
