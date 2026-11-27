// DeepinTray.cpp — 平台层：deepin 托盘窗口协议（X11）。
//
// ⚠ 为什么用 **xcb** 而不是 Xlib：Xlib 的 `Bool`/`Status`/`None`/`CursorShape` 是宏，
//   与 Qt 头文件**直接打架**（`qnamespace.h` 编译不过）。xcb 没有这些宏 ⇒ 不用打架。
#include "DeepinTray.h"

#include "../logic/DeepinTray.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QThread>
#include <QVariant>

#include <cstdlib>
#include <cstring>
#include <unistd.h>

#ifdef DD_HAVE_XCB
#include <xcb/xcb.h>
#endif

namespace platform {

#ifndef DD_HAVE_XCB
// ⚠ **没有 xcb 就不做这条协议**（构建时没找到 libxcb）——
//   不是「静默成功」，而是**明确报出原因**（托盘图标会缺席，但不会假装注册成功）。
DeepinTrayStatus probeDeepinTray()
{
    DeepinTrayStatus st;
    st.error = QStringLiteral("构建时没有 xcb（DD_HAVE_XCB 未定义）⇒ deepin 托盘窗口协议不可用");
    return st;
}

DeepinTrayStatus publishDeepinTray(const QImage &, const QString &)
{
    DeepinTrayStatus st;
    st.error = QStringLiteral("构建时没有 xcb（DD_HAVE_XCB 未定义）⇒ deepin 托盘窗口协议不可用");
    return st;
}

bool updateDeepinTrayIcon(const QImage &)
{
    return false;
}

#else

namespace {

/// 图标窗口边长（实测 dock 的托盘图标槽 ~22px）。
constexpr int kIconSize = 22;

/// 进程内唯一的 X11 状态（图标窗口必须**一直活着**，被销毁 dock 就会移除图标）。
struct X11State {
    xcb_connection_t *conn = nullptr;
    xcb_screen_t *screen = nullptr;
    xcb_window_t window = 0;
    xcb_visualid_t visual = 0;
    uint8_t depth = 0;
};

X11State g_x11;

void closeX11()
{
    if (!g_x11.conn) {
        return;
    }
    if (g_x11.window) {
        xcb_destroy_window(g_x11.conn, g_x11.window);
        g_x11.window = 0;
    }
    xcb_disconnect(g_x11.conn);
    g_x11.conn = nullptr;
    g_x11.screen = nullptr;
    g_x11.visual = 0;
    g_x11.depth = 0;
}

/// 连上 X11（已有连接就复用）。
bool ensureX11(QString *error)
{
    if (g_x11.conn) {
        return true;
    }
    int screenNum = 0;
    g_x11.conn = xcb_connect(nullptr, &screenNum);
    if (!g_x11.conn || xcb_connection_has_error(g_x11.conn)) {
        if (error) {
            *error = QStringLiteral("连不上 X11（xcb_connect 失败）");
        }
        closeX11();
        return false;
    }
    xcb_screen_iterator_t it = xcb_setup_roots_iterator(xcb_get_setup(g_x11.conn));
    for (int i = 0; it.rem; xcb_screen_next(&it), ++i) {
        if (i == screenNum) {
            g_x11.screen = it.data;
            break;
        }
    }
    if (!g_x11.screen) {
        if (error) {
            *error = QStringLiteral("拿不到 X11 screen");
        }
        closeX11();
        return false;
    }
    return true;
}

/// 在屏幕的允许深度里找某个 visual（拿它的 depth）。
bool findVisual(xcb_screen_t *screen, xcb_visualid_t wanted, uint8_t *depthOut)
{
    xcb_depth_iterator_t di = xcb_screen_allowed_depths_iterator(screen);
    for (; di.rem; xcb_depth_next(&di)) {
        xcb_visualtype_iterator_t vi = xcb_depth_visuals_iterator(di.data);
        for (; vi.rem; xcb_visualtype_next(&vi)) {
            if (vi.data->visual_id == wanted) {
                if (depthOut) {
                    *depthOut = di.data->depth;
                }
                return true;
            }
        }
    }
    return false;
}

/// 选区持有者（`_NET_SYSTEM_TRAY_S0`）。
///
/// ⚠ 选区**不是窗口属性** ⇒ `xprop` 查不到，只能用 `XGetSelectionOwner`。
///   批 X 正是用错了量具，才得出「没有 XEmbed 宿主」的错结论。
/// 内部化一个原子（要 reply 才拿得到 id —— `xcb_intern_atom` 返回的是 cookie）。
xcb_atom_t internAtom(xcb_connection_t *conn, const char *name)
{
    xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(
        conn, xcb_intern_atom(conn, 0, static_cast<uint16_t>(std::strlen(name)), name), nullptr);
    if (!reply) {
        return 0;
    }
    const xcb_atom_t atom = reply->atom;
    free(reply);
    return atom;
}

xcb_window_t selectionOwner(xcb_connection_t *conn, const char *name)
{
    const xcb_atom_t atom = internAtom(conn, name);
    if (atom == 0) {
        return 0;
    }
    xcb_get_selection_owner_reply_t *reply =
        xcb_get_selection_owner_reply(conn, xcb_get_selection_owner(conn, atom), nullptr);
    if (!reply) {
        return 0;
    }
    const xcb_window_t owner = reply->owner;
    free(reply);
    return owner;
}

/// 读 daemon 广告的 `_NET_SYSTEM_TRAY_VISUAL`（VISUALID，32 位）。
///
/// ⚠ 协议要求图标窗口用**它广告的 visual**（实测 deepin 广告的是 32 位 TrueColor/ARGB，
///   visual id 0x6c）—— dock 的容器也是这个 visual ⇒ 深度一致、图像带 alpha。
xcb_visualid_t advertisedVisual(xcb_connection_t *conn, xcb_window_t owner)
{
    const char *name = "_NET_SYSTEM_TRAY_VISUAL";
    const xcb_atom_t atom = internAtom(conn, name);
    if (atom == 0) {
        return 0;
    }
    xcb_get_property_reply_t *reply = xcb_get_property_reply(
        conn, xcb_get_property(conn, 0, owner, atom, XCB_ATOM_VISUALID, 0, 1), nullptr);
    if (!reply) {
        return 0;
    }
    xcb_visualid_t visual = 0;
    if (reply->format == 32 && reply->value_len >= 1) {
        visual = *static_cast<xcb_visualid_t *>(xcb_get_property_value(reply));
    }
    free(reply);
    return visual;
}

/// 把 QImage 画进 X11 窗口。
///
/// ⚠ 深度决定字节序，**不能想当然**：
///   · 32 位 ARGB visual（deepin 广告的那个）：像素字 = 0xAARRGGBB，小端内存里字节序
///     是 B,G,R,A —— 与 `QImage::Format_ARGB32` 的存储**一致** ⇒ 可直传；
///   · 24 位 TrueColor：X 的像素字是 0x00RRGGBB，小端字节序 B,G,R ——
///     与 `QImage::Format_RGB888`（R,G,B 顺序）**相反** ⇒ 必须逐像素换。
bool paintWindow(xcb_connection_t *conn, xcb_window_t win, uint8_t depth, const QImage &icon)
{
    if (icon.isNull()) {
        return false;
    }
    const QImage src = icon.convertToFormat(QImage::Format_ARGB32);
    const int w = src.width();
    const int h = src.height();

    if (depth == 32) {
        const int bytesPerLine = w * 4; // 32 位 ZPixmap：每像素 4 字节，已天然对齐
        QByteArray buf(bytesPerLine * h, Qt::Uninitialized);
        for (int y = 0; y < h; ++y) {
            std::memcpy(buf.data() + y * bytesPerLine, src.constScanLine(y),
                        static_cast<size_t>(bytesPerLine));
        }
        xcb_put_image(conn, XCB_IMAGE_FORMAT_Z_PIXMAP, win, XCB_NONE, w, h, 0, 0, w, h,
                      bytesPerLine, reinterpret_cast<const uint8_t *>(buf.constData()));
        return true;
    }

    // 24 位：X 期待 B,G,R 顺序 ⇒ 逐像素换
    const int bytesPerLine = w * 4; // ZPixmap 24 位按 4 字节对齐
    QByteArray buf(bytesPerLine * h, Qt::Uninitialized);
    auto *out = reinterpret_cast<uint8_t *>(buf.data());
    for (int y = 0; y < h; ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(src.constScanLine(y));
        for (int x = 0; x < w; ++x) {
            const QRgb v = line[x];
            uint8_t *px = out + y * bytesPerLine + x * 4;
            px[0] = static_cast<uint8_t>(qBlue(v));
            px[1] = static_cast<uint8_t>(qGreen(v));
            px[2] = static_cast<uint8_t>(qRed(v));
            px[3] = 0;
        }
    }
    xcb_put_image(conn, XCB_IMAGE_FORMAT_Z_PIXMAP, win, XCB_NONE, w, h, 0, 0, w, h, bytesPerLine,
                  reinterpret_cast<const uint8_t *>(buf.constData()));
    return true;
}

/// daemon 认不认得这个窗口（`GetName` 返回我们的名字 ⇒ 它确实登记了它）。
bool daemonKnowsWindow(xcb_window_t win, const QString &expectName)
{
    QDBusInterface iface(QStringLiteral("org.deepin.dde.TrayManager1"),
                          QStringLiteral("/org/deepin/dde/TrayManager1"),
                          QStringLiteral("org.deepin.dde.TrayManager1"),
                          QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        return false;
    }
    QDBusReply<QString> reply =
        iface.call(QStringLiteral("GetName"), QVariant::fromValue(static_cast<uint32_t>(win)));
    if (!reply.isValid()) {
        return false;
    }
    return reply.value() == expectName;
}

} // namespace

DeepinTrayStatus probeDeepinTray()
{
    DeepinTrayStatus st;
    QString err;
    if (!ensureX11(&err)) {
        st.error = err;
        return st;
    }
    st.selectionPresent = selectionOwner(g_x11.conn, TraySni::dockSelectionName()) != 0;
    if (!st.selectionPresent) {
        st.error = QStringLiteral("没有 `_NET_SYSTEM_TRAY_S0` 选区持有者（不是 deepin 式托盘？）");
    }
    return st;
}

DeepinTrayStatus publishDeepinTray(const QImage &icon, const QString &windowName)
{
    DeepinTrayStatus st;
    QString err;
    if (!ensureX11(&err)) {
        st.error = err;
        return st;
    }

    const xcb_window_t owner = selectionOwner(g_x11.conn, TraySni::dockSelectionName());
    if (owner == 0) {
        st.error = QStringLiteral("`_NET_SYSTEM_TRAY_S0` 没有持有者 ⇒ 这台机器不是 deepin 式托盘");
        return st;
    }
    st.selectionPresent = true;

    const QString name = windowName.isEmpty() ? QStringLiteral("deepDolphin") : windowName;

    // ⚠ **已经建过就只重画** —— 每次刷新都新建窗口 ⇒ 一堆野窗口 + 反复 dock 请求
    //   （实测：窗口 id 一路涨 0x7000000 → 0x7000002 → …）。
    if (g_x11.window) {
        st.windowId = static_cast<quint32>(g_x11.window);
        if (!paintWindow(g_x11.conn, g_x11.window, g_x11.depth, icon)) {
            st.error = QStringLiteral("重画图标窗口失败");
            return st;
        }
        xcb_flush(g_x11.conn);
        st.published = daemonKnowsWindow(g_x11.window, name);
        if (!st.published) {
            st.error = QStringLiteral("图标窗口还在，但 daemon 不认领它（GetName 认不出）");
        }
        return st;
    }

    // ① 视觉：优先用 daemon 广告的（协议要求；实测是 32 位 TrueColor/ARGB）
    xcb_visualid_t visual = advertisedVisual(g_x11.conn, owner);
    uint8_t depth = 0;
    if (visual == 0 || !findVisual(g_x11.screen, visual, &depth)) {
        visual = g_x11.screen->root_visual;
        depth = g_x11.screen->root_depth;
    }
    g_x11.visual = visual;
    g_x11.depth = depth;

    // ② 窗口
    xcb_window_t win = xcb_generate_id(g_x11.conn);
    xcb_colormap_t cmap = xcb_generate_id(g_x11.conn);
    xcb_void_cookie_t ckMap = xcb_create_colormap(g_x11.conn, XCB_COLORMAP_ALLOC_NONE, cmap,
                                                   g_x11.screen->root, visual);
    // ⚠⚠ **`values[]` 的顺序必须按 mask 位的升序**（实测踩出来的坑）：
    //   `XCB_CW_BORDER_PIXEL`(bit3) → values[0]、`XCB_CW_EVENT_MASK`(bit11) → values[1]、
    //   `XCB_CW_COLORMAP`(bit13) → values[2]。
    //   写反了 ⇒ 边界像素被当成 colormap、colormap 传成 None ⇒
    //   **32 位 ARGB 窗口「建了却不存在」**（GetWindowAttributes 报 BadValue(3)、
    //   窗口不在 root 的子窗口里）⇒ daemon 自然认不出它。
    //   ⚠ 24 位那条当时「能用」纯属侥幸：传错的字段恰好无害。
    uint32_t values[3] = { 0 /*border*/, XCB_EVENT_MASK_STRUCTURE_NOTIFY, cmap /*colormap*/ };
    xcb_void_cookie_t ckWin = xcb_create_window(
        g_x11.conn, depth, win, g_x11.screen->root, 0, 0, kIconSize, kIconSize, 0,
        XCB_WINDOW_CLASS_INPUT_OUTPUT, visual,
        XCB_CW_BORDER_PIXEL | XCB_CW_EVENT_MASK | XCB_CW_COLORMAP, values);
    // ⚠ **X 错误必须查**：colormap/窗口建不出来时 X **不报错给你**，只是窗口不存在
    //   （实测：32 位 ARGB 那条路上窗口压根没出现 ⇒ daemon 自然认不出它）。
    if (xcb_generic_error_t *e = xcb_request_check(g_x11.conn, ckMap)) {
        st.error = QStringLiteral("建 colormap 失败（X error %1，visual 0x%2）")
                       .arg(e->error_code)
                       .arg(visual, 0, 16);
        free(e);
        return st;
    }
    if (xcb_generic_error_t *e = xcb_request_check(g_x11.conn, ckWin)) {
        st.error = QStringLiteral("建图标窗口失败（X error %1，depth %2，visual 0x%3）")
                       .arg(e->error_code)
                       .arg(depth)
                       .arg(visual, 0, 16);
        free(e);
        return st;
    }

    // ③ 窗口属性：WM_NAME（= 托盘里显示的名字，实测 daemon 的 `GetName` 读它）、
    //    WM_CLASS（照 cc-switch / clash-verge 的约定：`tray-icon tray app <名>`）、
    //    _NET_WM_PID（dock 靠它把窗口映射到进程）
    const QByteArray nameUtf8 = name.toUtf8();
    xcb_change_property(g_x11.conn, XCB_PROP_MODE_REPLACE, win, XCB_ATOM_WM_NAME,
                        XCB_ATOM_STRING, 8, static_cast<uint32_t>(nameUtf8.size()),
                        nameUtf8.constData());

    QByteArray classValue;
    classValue.append("tray-icon");
    classValue.append('\0');
    classValue.append("tray-icon tray app ");
    classValue.append(nameUtf8);
    classValue.append('\0');
    xcb_change_property(g_x11.conn, XCB_PROP_MODE_REPLACE, win, XCB_ATOM_WM_CLASS,
                        XCB_ATOM_STRING, 8, static_cast<uint32_t>(classValue.size()),
                        classValue.constData());

    const uint32_t pid = static_cast<uint32_t>(getpid());
    const xcb_atom_t netWmPid = internAtom(g_x11.conn, "_NET_WM_PID");
    xcb_change_property(g_x11.conn, XCB_PROP_MODE_REPLACE, win, netWmPid, XCB_ATOM_CARDINAL, 32,
                        1, &pid);

    // ④ 画图标 + 显示
    // ⚠ **图标要按窗口大小画**：put_image 的尺寸超过窗口 ⇒ BadMatch（X 不会拦你，
    //   只是这一次绘制失败）⇒ 窗口里是**空白**。
    QImage scaled = icon;
    if (scaled.width() != kIconSize || scaled.height() != kIconSize) {
        scaled = icon.scaled(kIconSize, kIconSize, Qt::KeepAspectRatio,
                             Qt::SmoothTransformation);
    }
    paintWindow(g_x11.conn, win, depth, scaled);
    xcb_void_cookie_t ckMapWin = xcb_map_window(g_x11.conn, win);
    xcb_flush(g_x11.conn);
    if (xcb_generic_error_t *e = xcb_request_check(g_x11.conn, ckMapWin)) {
        st.error = QStringLiteral("映射图标窗口失败（X error %1）").arg(e->error_code);
        free(e);
        return st;
    }
    // 确认窗口真的在（拿属性；拿不到 = 窗口没建成）
    xcb_generic_error_t *attrErr = nullptr;
    xcb_get_window_attributes_reply_t *attr = xcb_get_window_attributes_reply(
        g_x11.conn, xcb_get_window_attributes(g_x11.conn, win), &attrErr);
    if (!attr) {
        st.error = QStringLiteral("图标窗口建出来后查不到属性（X error %1）⇒ 没建成；"
                                   "depth=%2 visual=0x%3")
                       .arg(attrErr ? attrErr->error_code : 0)
                       .arg(depth)
                       .arg(visual, 0, 16);
        if (attrErr)
            free(attrErr);
        return st;
    }
    free(attr);
    if (attrErr)
        free(attrErr);

    g_x11.window = win;
    st.windowId = static_cast<quint32>(win);

    // ⑤ 发 dock 请求（★ 字段偏移由判定层给，别在这里写死数字）
    const TraySni::DockRequest req = TraySni::buildDockRequest(static_cast<quint32>(win));
    const xcb_atom_t opcodeAtom = internAtom(g_x11.conn, TraySni::dockOpcodeAtomName());
    if (opcodeAtom == 0) {
        st.error = QStringLiteral("内部化 `_NET_SYSTEM_TRAY_OPCODE` 失败");
        return st;
    }
    xcb_client_message_event_t ev;
    std::memset(&ev, 0, sizeof(ev));
    ev.response_type = XCB_CLIENT_MESSAGE;
    ev.format = 32;
    ev.window = owner;
    ev.type = opcodeAtom;
    ev.data.data32[0] = 0; // 未用（deepin 从 data32[1] 读）
    ev.data.data32[TraySni::dockFieldIndex(TraySni::DockField::Opcode)] = req.opcode;
    ev.data.data32[TraySni::dockFieldIndex(TraySni::DockField::WindowId)] = req.windowId;
    xcb_send_event(g_x11.conn, 0, owner, XCB_EVENT_MASK_NO_EVENT,
                   reinterpret_cast<const char *>(&ev));
    xcb_flush(g_x11.conn);

    // ⑥ 验：daemon 认得我们吗（`GetName` 返回我们的名字 ⇒ 它确实登记了这个窗口）
    for (int i = 0; i < 20; ++i) {
        if (daemonKnowsWindow(win, name)) {
            st.published = true;
            return st;
        }
        QThread::msleep(50);
    }
    st.error = QStringLiteral("已发 REQUEST_DOCK，但 daemon 没认领我们的窗口 0x%1（GetName 认不出）")
                   .arg(static_cast<quint32>(win), 0, 16);
    return st;
}

bool updateDeepinTrayIcon(const QImage &icon)
{
    if (!g_x11.conn || !g_x11.window) {
        return false;
    }
    if (!paintWindow(g_x11.conn, g_x11.window, g_x11.depth, icon)) {
        return false;
    }
    xcb_flush(g_x11.conn);
    return true;
}

} // namespace platform

#endif // DD_HAVE_XCB
