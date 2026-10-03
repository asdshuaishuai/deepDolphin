// DesignTokens.h — 设计 tokens（mac DesignTokens.swift/DesignSystem.swift → DTK 映射）。
//
// 【映射纪律（PLAN §8 T1/T2）】
// · 表面/文字色**接 DTK 调色板**（DGuiApplicationHelper 亮暗自适应）——不搬 mac 的
//   tailwind 表面色（bgDark/cardDark…），它们是 SwiftUI 观感，DTK 有自己的原生体系；
// · **语义色保留 mac 取值**：双轨绿/紫、AI 青、accent 蓝、状态绿黄橙红紫——它们承载
//   跨页一致的状态语义，不是皮肤（SPEC §5「取值逐值对齐」仅在语义色范围内执行）；
// · 间距 6 档刻度 + 圆角档（chip=3/control=6/pill=8/card=10，window/frame 接 DTK metric）
//   + 高度档（bar=6/barMini=4/dot=8/dotLg=10）；
// · 字体层级映射为 px 常量（一处可调），禁止散落 .setPointSize。
#pragma once
#include <QColor>
#include <QFont>
#include <QPalette>
#include <QString>

class QWidget;
class QLabel;

namespace DS {

// ── 间距刻度（DSSpacing）──
namespace Spacing {
constexpr int xs = 4;
constexpr int sm = 8;
constexpr int md = 12;
constexpr int lg = 16;
constexpr int xl = 20;
constexpr int xxl = 24;
} // namespace Spacing

// ── 高度/尺寸档（M3-5：条与点各一档，消灭"同类控件几种尺寸"）──
namespace Height {
constexpr int bar = 6;     // 进度条/分段条统一高度（DProgressBar/SegmentedBar）
constexpr int barMini = 4; // 迷你进度条（托盘行内 44×barMini）
constexpr int dot = 8;     // 状态圆点统一尺寸（页面/卡片/侧栏行）
constexpr int dotLg = 10;  // 大号圆点（侧栏状态条/托盘行等汇总态指示）
} // namespace Height

// ── 圆角（DSRadius；chip/control/card 三档 + pill，window/frame 接 DTK 运行期 metric）──
namespace Radius {
constexpr int chip = 3;    // 迷你条 / 分段条 / Chip
constexpr int control = 6; // 控件 / 小卡
constexpr int card = 10;   // 卡片
constexpr int pill = 8;    // 胶囊/徽章（●N 待记录徽章等）

// 接 DTK 样式像素档：真机随 DDE 圆角设置走；取不到（非 DTK 样式/异常值）
// 退回上面的既有档位，绝不退 0（退 0 = 自绘窗口直角塌方）。
int window(); // DStyle::PM_TopLevelWindowRadius —— 自绘顶层（托盘弹窗）圆角
int frame();  // DStyle::PM_FrameRadius —— 控件框圆角（M3b 组件化时按钮/分段条接入）
} // namespace Radius

// ── 语义色（状态语义保留 mac 取值；accent 接 DTK 主题强调色）──
enum class SemColor {
    accent,     // DTK 主题强调色（LightLively，亮暗自适应）· 强调
    shallow,    // 绿 #10B981 · 浅更新轨 / 活跃
    deep,       // 紫 #8B5CF6 · 深更新轨 / 已合并
    ai,         // 青 #06B6D4 · AI（provider 徽章）
    orange,     // 橙 #F59E0B · needsAction / 量级中档
    red,        // 红 #DC2626 · 错误 / 量级高档
    yellow,     // 黄 #E8B01C · idle / 量级低档
    gray,       // 灰 #9CA3AF · unknown
};

QColor semColor(SemColor c);

// 当前主题是否暗色（DGuiApplicationHelper::themeType）。
bool isDarkTheme();

// ── 表面三级（接 DTK 调色板，亮暗自适应）──
// card = 卡片表面；surfaceAlt = 背景/工作条；border = 描边。
QColor surfaceCard();
QColor surfaceAlt();
QColor surfaceBorder();

// 文字三级：primary 跟调色板 text；secondary 跟调色板 mid（或 text 65% 不透明度）。
QColor textPrimary();
QColor textSecondary();

// ── 字体层级（px 常量，一处可调）──
enum class FontT { metric, cardTitle, sectionTitle, body, label, badge };
QFont font(FontT t);

// Markdown 标题字号（h1/h2/h3 = 22/18/15，其余 14）——改由 DFontManager 档位派生：
// MD_H1=T3(22)、MD_H2=T4(18)、MD_H3=T5(14)，与正文字号档位同一根系。
enum { MD_H1 = 22, MD_H2 = 18, MD_H3 = 14, MD_BODY = 11 };

// ── 动效（全项目唯一动效是 agent 新消息自动滚动，0.20s easeInOut）──
constexpr int MotionStandardMs = 200;

// 按钮几何一档（M3-5）：文本按钮 padding 只此一档「4px 16px」（xs × lg）——
// 原 4 种（3px 12px / 4px 14px / 4px 16px 各写各的）从这里取值，QSS 自包含拼入。
QString buttonPaddingQss();

// ── 调色板自洽判定与兜底（M3-1/M3-4）──
// 真实 DDE（DTK 配置 + 样式插件在位）：applicationPalette() 与当前主题一致 → DTK 自己管
// 应用调色板，客户端**不要** setPalette（DTK 会警告"Don't use it on DTK application"）。
// offscreen / 无 DTK 配置的环境：applicationPalette() 只有一套浅色值（2026-10-03 探针实证：
// setPaletteType(DarkType) 之后 applicationPalette(DarkType) 仍返回 Window=#F8F8F8），
// 直接用它 = 暗色主题下白底黑字的缝合体 → 必须走 applicationPaletteFallback()。
bool paletteIsThemeConsistent();
QPalette applicationPaletteFallback();

// ── 主题/字号变化的树内传播（M3-4）──
// 约定：凡"构建时用 DS:: 取值设过样式/字号"的控件，都要用下面两个 tag 登记一次；
// repolish() 就能在用户切主题/字号时按新 token 重算，而不是停在旧快照。
// 新代码一律走 tag；老代码（28 处 color: %1 复制）由 M3b 的 SecondaryLabel 收编。
void tagSecondaryStyle(QLabel *label); // 次级文字色（最常用）
void tagFont(QWidget *w, FontT t);     // 字号档位
void repolish(QWidget *root);          // 全树按当前 token 重算 + ensurePolishededed

} // namespace DS
