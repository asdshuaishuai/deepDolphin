// ArchCanvasWidget.h — 架构图画布（Qt 侧：QPainter + 批 D1 的 Canvas2D 内核）。
//
// 【职责】
// · 只做「把 scene 画出来」+「把鼠标点翻译成世界坐标」；
// · 画什么、画成什么顺序 —— 那是 `logic/SceneRender` 的事（纯函数层）；
// · 视口换算与命中判定 —— 那是 `logic/ArchViewport` 的事（纯函数层）。
// 三层各司其职，所以这一层很薄，也才可能无头验证。
//
// 【对照 mac】mac 的 `ArchCanvasView`（SwiftUI GraphicsContext 版）职责与此一致：
// 视口 fit / 拖动 / 缩放 / 点选 / 切视图 / 切主题；命中区只用 `hits[].id`
// （契约里的 `drill`/`jump` mac 未接，deepin 同款未接 —— 差距记在
// docs/PARITY-LEDGER.md）。
#pragma once
#include <QElapsedTimer>
#include <QWidget>
#include "../logic/ArchViewport.h"
#include "../models/GraphScene.h"

class QTimer;

class ArchCanvasWidget : public QWidget {
    Q_OBJECT
public:
    explicit ArchCanvasWidget(QWidget *parent = nullptr);

    void setScene(const std::optional<GraphScene> &scene);
    const std::optional<GraphScene> &scene() const { return m_scene; }

    /// 主题：true = 暗色。默认跟随系统（DS::isDarkTheme()）。
    void setDark(bool dark);
    bool dark() const { return m_dark; }

    /// 复位视口（回到自适应包围盒）。
    void refit();

    /// 可切换的视图 id 列表（契约里 arch 恒排第一，其余是 module:*）。
    QStringList viewIds() const;
    /// 当前视图 id（默认 "arch"）。
    QString currentViewId() const { return m_currentView; }
    /// 当前视图标题（工具栏显示用；视图不存在时回落 "arch"）。
    QString currentViewLabel() const;
    /// 切视图。视图不存在 → 拒绝并返回 false（不静默换到别的视图）。
    bool setCurrentView(const QString &id);

    /// 当前选中的节点 id（空 = 未选）。点选同一点是取消选择（mac 同款）。
    QString selectedNode() const { return m_selected; }

signals:
    /// 点中了某个节点（命中区的 id）；空字符串 = 点空了。
    void nodeSelected(const QString &id);

protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void showEvent(QShowEvent *event) override;
    void hideEvent(QHideEvent *event) override;

private:
    const GraphView *currentView() const;
    void ensureAnimTimer();

    std::optional<GraphScene> m_scene;
    QString m_currentView = QStringLiteral("arch");
    QString m_selected;
    ArchViewport::Viewport m_vp;
    bool m_userAdjusted = false; // 用户拖过/缩放过就不再自动 fit
    bool m_dark = false;
    bool m_dragging = false;
    QPointF m_dragOrigin;
    QPointF m_dragOffset;
    QElapsedTimer m_clock;
    QTimer *m_anim = nullptr;
};
