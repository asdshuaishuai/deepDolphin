// CountLabel.h — 计数徽标：nullopt → 不显示（读不出来 ≠ 0），0 才显示 0。
// 无 Q_OBJECT：纯呈现。
#pragma once
#include <QLabel>
#include <optional>

class CountLabel : public QLabel {
public:
    explicit CountLabel(QWidget *parent = nullptr)
        : QLabel(parent)
    {
        setVisible(false);
    }

    void setCount(std::optional<int> n)
    {
        if (!n.has_value()) {
            setVisible(false); // 读不出来 ≠ 0
            setText(QString());
            return;
        }
        setVisible(*n > 0); // 0 不显示（侧栏语义：●N 徽标只在 >0 时出现）
        if (*n > 0)
            setText(QStringLiteral("●%1").arg(*n));
    }
};
