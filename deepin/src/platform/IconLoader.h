// IconLoader.h — 图标双通道加载（PLAN §2.7）。
//
// · 优先主题图标（QIcon::fromTheme：view-refresh-symbolic、utilities-terminal、folder…）
// · SF 专有形状用 qrc 内 dd-*.svg，`currentColor` 占位符渲染前替换成 tint 色
//   （QSvgRenderer，Qt6Svg；编译期探测：本构建环境无 libqt6svg6-dev → 降级为
//   QPainter 画的占位图标，见 deepin/README.md「Qt6Svg」一节）
//
// 禁止取模/内联第二套色板：染色一律走本文件的 tint 通道。
#pragma once
#include <QColor>
#include <QIcon>
#include <QSize>
#include <QString>

namespace IconLoader {

// 应用图标：主题 deepdolphin → qrc 内置 svg → 程序化占位（保证托盘永不空图标）
QIcon app();

// 符号图标：主题优先；qrc dd-*.svg 染色兜底；都没有 → tint 色圆点占位
QIcon symbol(const QString &name, const QColor &tint, QSize size = QSize(16, 16));

// 主题图标候选名（fallbacks 纪律：形状优先级列表，逐个 fromTheme 试）
QStringList fallbacks(const QString &name);

} // namespace IconLoader
