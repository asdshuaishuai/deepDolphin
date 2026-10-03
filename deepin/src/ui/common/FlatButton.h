// FlatButton.h — flat 文本按钮（plan §3b 组件化：对位 ProjectDetailPage 原 headerButton
// 助手，把「new QPushButton + setFlat + 各写各的尺寸」的 30+ 处散装表达收成一个类）。
//
// 【视觉契约（全从 DS:: 取，无一处 QSS 颜色）】
// · hover/pressed 底色走 paintEvent 读 DS::textPrimary() 低透明叠加——M3-4 长效方案
//   （Card.h 范式）：颜色实时取值，切主题/强调色零快照问题，QSS 只留几何与状态；
// · 字号 = DS::font(body)（T7，DDE 按钮同档），经 DS::tagFont 登记 dsFont——用户
//   切字号档位时 DS::repolish 重算（M3-4）；
// · 几何 = DS::Spacing 一档：带文字 padding 4×16（与 DS::buttonPaddingQss 同源的
//   xs×lg，M3-5）；纯图标位（headerButton 的 copy/finder/term 等文字为空的工具钮）
//   四周 xs，保持 32px 见方；圆角 DS::Radius::control。
//
// 【继承 QPushButton 而非包装】是 QPushButton 的 is-a：DIconButton/DWarningButton/
// DSuggestButton 的语义位（主操作/警示/图标钮）不归本组件（决策 72），调用点
// connect(&QPushButton::clicked) 与 DDialog::insertButton(QPushButton*) 均零改动。
// 【无 Q_OBJECT】无信号、纯呈现（BusyRow 同款）；有配对 .cpp 且已进 CMake 源列表。
#pragma once
#include "../DesignTokens.h"
#include <QColor>
#include <QMargins>
#include <QPushButton>

class FlatButton : public QPushButton {
public:
    explicit FlatButton(QWidget *parent = nullptr);
    explicit FlatButton(const QString &text, QWidget *parent = nullptr);

    // hover/pressed 底色双态（plan §3c「卡片 hover/按下」的按钮先行版）。
    enum class Tone { Hover, Pressed };

    // 双态叠加色（纯函数，SelfCheck 无头可跑）：base 上叠透明度——hover ≈10%，
    // pressed ≈18%（pressed 更重，按下要有「实感」）。
    static QColor overlayColor(const QColor &base, Tone tone);

    // 带文字按钮的 padding 一档（M3-5：xs×lg = 4×16，与 DS::buttonPaddingQss 同源；
    // 纯图标位的四周 xs 直接在 sizeHint 里取 DS::Spacing）。
    static QMargins padding();

protected:
    void paintEvent(QPaintEvent *event) override;
    QSize sizeHint() const override;
    QSize minimumSizeHint() const override;

private:
    void init(); // flat/光标/hover/字号档位的构造共段
};
