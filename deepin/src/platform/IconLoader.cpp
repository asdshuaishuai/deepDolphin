#include "IconLoader.h"
#include <QDir>
#include <QFile>
#include <QHash>
#include <QPainter>
#include <QPixmap>

#ifdef DD_HAVE_QTSVG
#include <QSvgRenderer>
#endif

#ifdef DD_HAVE_QTSVG
// Qt6Svg 可用：qrc 内 dd-*.svg 的 currentColor 占位替换为 tint 后渲染
namespace {
QIcon tintedSvg(const QString &qrcPath, const QColor &tint, const QSize &size)
{
    QFile f(qrcPath);
    if (!f.open(QIODevice::ReadOnly))
        return QIcon();
    const QByteArray placeholder = f.readAll();
    const QColor c = tint.isValid() ? tint : QColor(0x88, 0x88, 0x88);
    QByteArray svg = placeholder;
    svg.replace("currentColor", c.name(QColor::HexRgb).toUtf8());

    QSvgRenderer renderer(svg);
    if (!renderer.isValid())
        return QIcon();
    QPixmap pm(size);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    renderer.render(&p, QRectF(0, 0, size.width(), size.height()));
    return QIcon(pm);
}
} // namespace
#endif

namespace IconLoader {

QStringList fallbacks(const QString &name)
{
    // 形状优先级列表：SF 专名 → deepin 主题常用名
    static const QHash<QString, QStringList> kMap = {
        { QStringLiteral("bolt"), { QStringLiteral("bolt"), QStringLiteral("applications-graphics") } },
        { QStringLiteral("wand"), { QStringLiteral("edit-find"), QStringLiteral("preferences-desktop-effects") } },
        { QStringLiteral("sparkles"), { QStringLiteral("starred"), QStringLiteral("emblem-favorite") } },
        { QStringLiteral("zzz"), { QStringLiteral("weather-clear-night"), QStringLiteral("moon") } },
    };
    return kMap.value(name, { name });
}

QIcon app()
{
    QIcon theme = QIcon::fromTheme(QStringLiteral("deepdolphin"));
    if (!theme.isNull())
        return theme;
    // qrc 兜底（无 Qt6Svg 时 QIcon 也可能借主题 svg 引擎渲染；再不行给程序化占位）
    QIcon fromQrc(QStringLiteral(":/icons/deepdolphin.svg"));
    if (!fromQrc.isNull())
        return fromQrc;
    QPixmap pm(64, 64);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setBrush(QColor(0x1E, 0x6F, 0xEB)); // deepin accent 蓝（占位，仅无任何图标资源时）
    p.setPen(Qt::NoPen);
    p.drawRoundedRect(4, 4, 56, 56, 14, 14);
    p.setBrush(Qt::white);
    p.drawEllipse(22, 20, 20, 20);
    return QIcon(pm);
}

QIcon symbol(const QString &name, const QColor &tint, QSize size)
{
    for (const QString &themeName : fallbacks(name)) {
        QIcon icon = QIcon::fromTheme(themeName);
        if (!icon.isNull())
            return icon;
    }
#ifdef DD_HAVE_QTSVG
    const QString qrcPath = QStringLiteral(":/icons/dd-%1.svg").arg(name);
    if (QFile::exists(qrcPath)) {
        QIcon icon = tintedSvg(qrcPath, tint, size);
        if (!icon.isNull())
            return icon;
    }
#endif
    // 全部落空：tint 色圆点占位（未知状态显形为占位，不假装是某个具体符号）
    QPixmap pm(size);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    p.setBrush(tint.isValid() ? tint : QColor(0x88, 0x88, 0x88));
    p.setPen(Qt::NoPen);
    const int d = qMin(size.width(), size.height()) / 2;
    p.drawEllipse((size.width() - d) / 2, (size.height() - d) / 2, d, d);
    return QIcon(pm);
}

} // namespace IconLoader
