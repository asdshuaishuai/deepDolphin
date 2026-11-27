// IconResolver.cpp — 图标统一入口（平台层执行，PLAN §9 M1-2）。
//
// 【三级解析】
//   ① DDci（deepin 图标集）→ ② freedesktop 主题 → ③ qrc 染色兜底 → ④ 缺失告警 + 占位。
//   候选名链在判定层 `logic/IconNames`（**唯一出处**），本层只管执行与报缺失。
//
// 【缺失为什么要「告警」而不是「给个空图标」】
//   静默的空图标是最难查的故障：界面少个图标，没人知道是名字错了、主题缺了、
//   还是压根没接。⇒ 解析不到时**说出来**（qWarning + missingIcons() 可见面），
//   同时用 tint 圆点占位 —— 界面上显形为「这里本该有东西」，
//   而不是假装那是一个完整的图标。
#include "IconResolver.h"

#include "../logic/IconNames.h"
#include "../logic/SemColors.h"
#include "DpiPixmap.h"

#include <QDebug>
#include <QFile>
#include <QGuiApplication>
#include <QHash>
#include <QPainter>
#include <QPixmap>
#include <QStringList>

#include <DDciIcon>
#include <DGuiApplicationHelper>

DGUI_USE_NAMESPACE

#ifdef DD_HAVE_QTSVG
#include <QSvgRenderer>
#endif

namespace {

/// 解析结果（图标 + 来源）。缓存键 = 逻辑名@尺寸。
struct Resolved {
    QIcon icon;
    QString source; ///< dci / theme / qrc / missing
};

QHash<QString, Resolved> &cache()
{
    static QHash<QString, Resolved> gCache;
    return gCache;
}

/// 解析过但没找到的逻辑名（保序去重）—— 缺失告警的可见面。
QStringList &missingList()
{
    static QStringList gMissing;
    return gMissing;
}

#ifdef DD_HAVE_QTSVG
/// qrc 内 dd-*.svg 的 currentColor 占位替换为 tint 后渲染（免安装兜底）。
QIcon tintedSvg(const QString &qrcPath, const QColor &tint, const QSize &size)
{
    QFile f(qrcPath);
    if (!f.open(QIODevice::ReadOnly))
        return QIcon();
    QByteArray svg = f.readAll();
    const QColor c = tint.isValid() ? tint : FixedColors::iconFallback();
    svg.replace("currentColor", c.name(QColor::HexRgb).toUtf8());

    QSvgRenderer renderer(svg);
    if (!renderer.isValid())
        return QIcon();
    QPixmap pm = platform::dpiPixmap(size);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    renderer.render(&p, QRectF(0, 0, size.width(), size.height()));
    return QIcon(pm);
}
#endif

/// ① DDci 优先：deepin 自己的图标集（真机观感最好）。
QIcon fromDci(const QString &name, const QSize &size)
{
    // 无 QGuiApplication 时不碰 DDci（--selfcheck 跑在 app 构造前；DDci 依赖 DTK 全局态）。
    if (!qApp)
        return QIcon();
    const DDciIcon dci = DDciIcon::fromTheme(name);
    if (dci.isNull())
        return QIcon();
    const auto palette = DGuiApplicationHelper::instance()->paletteType();
    const DDciIcon::Theme theme = palette == DGuiApplicationHelper::DarkType ? DDciIcon::Dark
                                                                            : DDciIcon::Light;
    const qreal dpr = qApp->devicePixelRatio();
    QPixmap pm = dci.pixmap(dpr, size.width(), theme, DDciIcon::Normal);
    if (pm.isNull())
        return QIcon();
    pm.setDevicePixelRatio(dpr);
    return QIcon(pm);
}

/// ④ 占位：tint 色圆点（未知显形为占位，不假装是某个具体符号）。
QIcon placeholderDot(const QColor &tint, const QSize &size)
{
    // ⚠ **HiDPI 感知**（批 AP · M3c）：占位圆点也是**自绘**位图 ⇒ 必须按 dpr 放大，
    //   否则缩放到 125%/150%/200% 时这个「占位」本身发虚。
    QPixmap pm = platform::dpiPixmap(size);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setBrush(tint.isValid() ? tint : FixedColors::iconFallback());
    p.setPen(Qt::NoPen);
    const int d = qMin(size.width(), size.height()) / 2;
    p.drawEllipse((size.width() - d) / 2, (size.height() - d) / 2, d, d);
    return QIcon(pm);
}

Resolved resolveUncached(IconNames::Id id, const QSize &size, const QColor &tint)
{
    const QString logical = IconNames::name(id);
    const QStringList candidates = IconNames::fallbacks(id);
    if (candidates.isEmpty()) {
        // 枚举项没登记候选链 —— 判据会红（表与枚举必须严格一一对应），
        // 但执行层也不能静默：这是**我们的问题**，必须说出来。
        qWarning().noquote() << QStringLiteral("[icon] 逻辑图标未登记候选链：%1").arg(logical);
        if (!missingList().contains(logical))
            missingList().append(logical);
        return { QIcon(), QStringLiteral("missing") };
    }

    // ① DDci 优先（逐候选）
    for (const QString &name : candidates) {
        const QIcon icon = fromDci(name, size);
        if (!icon.isNull())
            return { icon, QStringLiteral("dci") };
    }
    // ② freedesktop 主题
    for (const QString &name : candidates) {
        const QIcon icon = QIcon::fromTheme(name);
        if (!icon.isNull())
            return { icon, QStringLiteral("theme") };
    }
#ifdef DD_HAVE_QTSVG
    // ③ qrc 染色兜底（免安装时 dd-* 也能用；需 Qt6Svg，本构建环境无 → 整段编译不进）
    for (const QString &name : candidates) {
        const QString qrcPath = QStringLiteral(":/icons/%1.svg").arg(name);
        if (!QFile::exists(qrcPath))
            continue;
        const QIcon icon = tintedSvg(qrcPath, tint, size);
        if (!icon.isNull())
            return { icon, QStringLiteral("qrc") };
    }
#endif
    // ④ 全落空 —— **分两种情况**（这层区分是本文件的关键）：
    //   (a) 这台机器**根本没有图标主题**（`QIcon::themeName()` 为空，offscreen 就是）：
    //       ⇒ 是**环境事实**，不是图标名错了。此时既不逐个告警（否则日志被刷屏），
    //          也不画占位圆点（否则离屏基线变成「到处都是圆点」，反而看不出真问题）。
    //          返回空图标 = 界面上的图标位空着，与「没有图标资源」的老行为一致。
    //   (b) 环境**有**图标主题，但这几个候选都解析不到：
    //       ⇒ 是**我们的问题**（候选链没覆盖该主题的名字）⇒ 告警 + 占位显形。
    if (QIcon::themeName().isEmpty())
        return { QIcon(), QStringLiteral("none") };
    qWarning().noquote()
        << QStringLiteral("[icon] 图标解析不到：%1（候选：%2）")
               .arg(logical, candidates.join(QStringLiteral(" / ")));
    if (!missingList().contains(logical))
        missingList().append(logical);
    return { placeholderDot(tint, size), QStringLiteral("missing") };
}

} // namespace

namespace platform {

QIcon icon(IconNames::Id id, const QSize &size, const QColor &tint)
{
    const QString key = QStringLiteral("%1@%2x%3")
                            .arg(IconNames::name(id)).arg(size.width()).arg(size.height());
    auto it = cache().constFind(key);
    if (it != cache().constEnd())
        return it->icon;
    const Resolved r = resolveUncached(id, size, tint);
    cache().insert(key, r);
    return r.icon;
}

QString resolveSource(IconNames::Id id, const QSize &size)
{
    const QString key = QStringLiteral("%1@%2x%3")
                            .arg(IconNames::name(id)).arg(size.width()).arg(size.height());
    auto it = cache().constFind(key);
    if (it != cache().constEnd())
        return it->source;
    return resolveUncached(id, size, QColor()).source;
}

QStringList missingIcons()
{
    return missingList();
}

} // namespace platform
