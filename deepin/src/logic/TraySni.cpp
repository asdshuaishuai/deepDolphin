#include "TraySni.h"

#include <QStringList>

namespace TraySni {

Host classifyHost(const HostCaps &caps)
{
    // ⚠ **先判「有没有 watcher」**：连服务都不在的时候，什么接口形状都读不出来，
    //   那时候报 Ayatana/Kde 都是把「读不到」误当成「形状不同」⇒ 必须先短路。
    if (!caps.watcherPresent)
        return Host::None;
    // 单参数注册 + 已注册项是属性 + ProtocolVersion 0 ⇒ ayatana 变体（DDE 实证）。
    if (caps.singleArgRegister && caps.itemsAsProperty && caps.protocolVersion == 0)
        return Host::Ayatana;
    return Host::Kde;
}

Registration registrationFor(Host host)
{
    switch (host) {
    case Host::None:
        // 没有 watcher ⇒ 谈不上注册方式；给服务名（最保守：不依赖调用方 unique name）。
        return Registration::ServiceName;
    case Host::Ayatana:
    case Host::Kde:
        break;
    }
    // ⚠ **两种传法 host 都接受**（实测方法调用都返回无错误），差别在「项 id 的形态」：
    //   传服务名 ⇒ 记录 `服务名/StatusNotifierItem`（能一眼认出是自己）；
    //   传对象路径 ⇒ 记录 `调用方unique名/StatusNotifierItem`。
    //   ⇒ 统一用服务名，别两处各写一种。
    return Registration::ServiceName;
}

QString registrationArgument(Registration mode, const ItemSpec &spec)
{
    return mode == Registration::ObjectPath ? spec.objectPath : spec.serviceName;
}

QStringList requiredProperties()
{
    // ⚠ 这三个是**入场券**（缺一个当场被注销，实测），不是可选增强。
    return {QStringLiteral("IconPixmap"),
            QStringLiteral("AttentionIconPixmap"),
            QStringLiteral("OverlayIconPixmap")};
}

QString primaryPixmapProperty()
{
    // ⚠ 就是必填表的**第一个** —— 不另写一份字面量。
    return requiredProperties().value(0);
}

QStringList hostReadProperties()
{
    // 实测 host 注册后主动读的顺序。
    // ⚠ 三个 pixmap **不在这儿再写一遍字面量** —— 直接复用 requiredProperties()：
    //   它们既是「必填表」也是「宿主会读的属性表」的子集，两处各写一份迟早走偏
    //   （改了必填表忘了改读表 ⇒ 宿主读了一个我们没暴露的属性 ⇒ 当场被注销）。
    QStringList props{QStringLiteral("Id"), QStringLiteral("Menu")};
    props += requiredProperties();
    props += QStringList{QStringLiteral("ToolTip"), QStringLiteral("IconName"),
                         QStringLiteral("IconThemePath")};
    return props;
}

QStringList missingRequired(const QStringList &provided)
{
    QStringList missing;
    const QStringList required = requiredProperties();
    for (const QString &name : required) {
        if (!provided.contains(name))
            missing << name;
    }
    return missing;
}

QByteArray encodeArgb32NetworkOrder(const QImage &image)
{
    if (image.isNull())
        return QByteArray();
    // ⚠⚡ **不要直接读 constScanLine 的原始字节** —— 源图的格式可能是
    //   **预乘**的（`QIcon::pixmap().toImage()` 就是 `Format_ARGB32_Premultiplied`），
    //   而预乘图在内存里的字节含义与非预乘**不是一回事** ⇒ 按非预乘去读会读出
    //   一堆错值（实测：整张图编成全 0 的透明图 ⇒ 宿主拿到空图 ⇒ 托盘里不画它）。
    //   ⇒ 统一先转成**非预乘** ARGB32，再用 `pixel()` 取 0xAARRGGBB 数值，
    //   按**网络字节序**逐字节写出（不依赖任何平台的字节序假设）。
    const QImage argb = image.convertToFormat(QImage::Format_ARGB32);
    QByteArray out;
    out.resize(argb.width() * argb.height() * 4);
    char *dst = out.data();
    for (int y = 0; y < argb.height(); ++y) {
        for (int x = 0; x < argb.width(); ++x) {
            const QRgb v = argb.pixel(x, y); // 0xAARRGGBB
            *dst++ = char((v >> 24) & 0xFF);  // A
            *dst++ = char((v >> 16) & 0xFF);  // R
            *dst++ = char((v >> 8) & 0xFF);   // G
            *dst++ = char(v & 0xFF);          // B
        }
    }
    return out;
}

QList<Pixmap> encodePixmap(const QImage &image)
{
    if (image.isNull())
        return {};
    Pixmap pm;
    pm.width = image.width();
    pm.height = image.height();
    pm.bytes = encodeArgb32NetworkOrder(image);
    return {pm};
}

QList<Pixmap> encodePixmaps(const QList<QImage> &images)
{
    QList<Pixmap> out;
    for (const QImage &img : images) {
        if (img.isNull())
            continue;
        out += encodePixmap(img);
    }
    return out;
}

} // namespace TraySni
