// main.cpp — deepDolphin 应用入口（PLAN §2.7）。
//
// 应用 id cn.deepdolphin.app（对齐 mac bundle id）；单实例 + 二实例深链转发
//（信号在 DGuiApplicationHelper，dtkgui——DApplication 上没有带参的 newProcessInstance）；
// 窗口标题唯一出处「deepDolphin 面板」；退出时收 timer 与引擎子进程。
#include "ai/AIConfig.h"
#include "ai/AgentCore.h"
#include "ai/ModelsDevCatalog.h"
#include "ai/SecretStore.h"
#include "app/AppModel.h"
#include "app/EngineCli.h"
#include "app/EngineInstaller.h"
#include "app/EngineLocator.h"
#include "app/Notifier.h"
#include "app/SelfCheck.h"
#include "app/Settings.h"
#include "app/Version.h"
#include "platform/AppService.h"
#include "platform/Backend.h"
#include "platform/CrashHandler.h"
#include "platform/IconResolver.h"
#include "platform/DeepinTray.h"
#include "logic/AgentToolPlan.h"
#include "logic/ArchReceipt.h"
#include "logic/Backend.h"
#include "logic/CodeGraphBuild.h"
#include "logic/EngineConfig.h"
#include "logic/EngineDoctor.h"
#include "logic/EngineDownload.h"
#include "logic/IconNames.h"
#include "logic/IndexStatus.h"
#include "logic/PanelGeometry.h"
#include "logic/SyntaxHighlight.h"
#include "logic/Liveness.h"
#include "logic/Route.h"
#include "platform/DdePanel.h"
#include "tray/TrayController.h"
#include "tray/TrayGeometry.h"
#include "ui/ColorSampleSheet.h"
#include "ui/DesignTokens.h"
#include "ui/PanelWindow.h"
#include "ui/dialogs/DocsDialog.h"
#include "ui/dialogs/DocsDialogProbe.h"
#include <DApplication>
#include <DGuiApplicationHelper>
#include <DLog>
#include <QComboBox>
#include <QCoreApplication>
#include <QStandardPaths>
#include <unistd.h>
#include <QElapsedTimer>
#include <QFile>
#include <QEventLoop>
#include <QProcess>
#include <QScreen>
#include <QSystemTrayIcon>
#include <QThread>
#include <QTimer>

DWIDGET_USE_NAMESPACE
DCORE_USE_NAMESPACE

// ── 无头 agent 自测（mac DeepGitApp --agent-selftest 对位，PLAN §8 T9）──
// mock 渠道（QSettings 明文 ai.apiKey）即可全链路验证工具循环，不需要真 provider；
// 引擎缺席时工具报 notFound 原文——循环本身（工具调用→执行→回喂→收尾）仍被走通。
// stdout：[selftest] FINAL: <前 200 字> / [selftest] ERROR: <原因>；最后 [selftest-done]。
// 退出码：0 = FINAL；1 = ERROR（headless 测试必须响亮失败）。
// 测试/快照可 DEEPDOLPHIN_THEME=light|dark 强制主题：DTK 在 offscreen 探不到系统
// 配置，不强制就拍不到确定的亮/暗观感；正常桌面会话不设它，跟随系统主题。
// 主路径与 --snapshot 共用（否则两条路径的"暗色"口径会漂）。
static void applyThemeOverride()
{
    const QString themeEnv = qEnvironmentVariable("DEEPDOLPHIN_THEME");
    if (themeEnv.compare(QLatin1String("light"), Qt::CaseInsensitive) == 0)
        DGuiApplicationHelper::instance()->setPaletteType(DGuiApplicationHelper::LightType);
    else if (themeEnv.compare(QLatin1String("dark"), Qt::CaseInsensitive) == 0)
        DGuiApplicationHelper::instance()->setPaletteType(DGuiApplicationHelper::DarkType);
}

// ── 无头 agent 工具面探针（批 AB）：**模型实际能看到什么** ──
// 用法：deepDolphin --agent-tool-surface（配合 QT_QPA_PLATFORM=offscreen 亦可用）。
// 逐行打印（每行一个字段，key=value）：
//   engine=<引擎版本>       model=<模型可见的工具名，逗号分隔>
//   validated=<必填校验表里的工具名>   prompt=<系统提示词里的清单原文>
// ⚠ 只报告不断言（断言归 scripts/probe-agent-tool-surface.sh）。
//
// 【为什么要有】工具面**收敛**（引擎标了「旧名别名，将移除」的那些不再推荐给模型）
//   是一条**行为**：源码里写了过滤 ≠ 模型真的看不到那些工具。
//   ⇒ 这个探针走真实引擎的 `tools --json` + 客户端真实的过滤口径，把三份名单
//     （模型可见 / 校验表 / 提示词）都打出来给人看、给脚本核。
static int headlessAgentToolSurface(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("deepin"));
    QCoreApplication::setApplicationName(QStringLiteral("deepDolphin"));

    const EngineLocator::Result engine = EngineLocator::locate();
    if (!engine.found) {
        fprintf(stderr, "✗ 引擎未找到（工具面探针需要真引擎）\n");
        fflush(stderr);
        return 1;
    }
    AgentCore core(engine.bin);
    QVector<ToolDef> defs;
    QMap<QString, QString> paramsByTool;
    QString toolsText;
    QString err;
    if (!core.loadToolManifest(&defs, &paramsByTool, &toolsText, &err, nullptr)) {
        fprintf(stderr, "✗ 取工具清单失败：%s\n", qPrintable(err));
        fflush(stderr);
        return 1;
    }
    QStringList modelNames;
    for (const ToolDef &d : defs)
        modelNames << d.name;
    QStringList validated;
    for (auto it = paramsByTool.constBegin(); it != paramsByTool.constEnd(); ++it)
        validated << it.key();
    // 引擎**原始**清单里带 deprecated 标记的工具有哪些 ——
    // ⚠ 必须看原始清单：客户端给模型的清单**已经收敛**（别名被剔掉了），
    //   在那里找标记永远找不到 ⇒ 探针会误判「引擎太老」而 SKIP。
    // ⚠ **解析 JSON 取名字**，不用「数 `"deprecated": true` 出现次数」——
    //   计数只给个数、不给**是哪些**，断言脚本就得把别名名单硬编码在脚本里
    //   ⇒ 引擎增减别名时那道门就跟不上真相（漏检），或名单过期时假红。
    //   名字必须**来自引擎**，脚本才知道该断言谁。
    QStringList engineDeprecatedNames;
    {
        QProcess eng;
        eng.setProgram(engine.bin);
        eng.setArguments({ QStringLiteral("tools"), QStringLiteral("--json") });
        eng.start();
        if (eng.waitForFinished(30000)) {
            const QJsonDocument doc = QJsonDocument::fromJson(eng.readAllStandardOutput());
            const QJsonArray arr = doc.object().value(QStringLiteral("tools")).toArray();
            for (const QJsonValue &v : arr) {
                const QJsonObject o = v.toObject();
                if (o.value(QStringLiteral("deprecated")).toBool(false))
                    engineDeprecatedNames << o.value(QStringLiteral("name")).toString();
            }
        }
    }
    fprintf(stdout, "engine_deprecated=%d\n", int(engineDeprecatedNames.size()));
    fprintf(stdout, "engine_deprecated_names=%s\n",
        qPrintable(engineDeprecatedNames.join(QLatin1Char(','))));
    fprintf(stdout, "model=%s\n", qPrintable(modelNames.join(QLatin1Char(','))));
    fprintf(stdout, "validated=%s\n", qPrintable(validated.join(QLatin1Char(','))));
    fprintf(stdout, "prompt=%s\n", qPrintable(toolsText));
    fflush(stdout);
    return 0;
}

static int headlessAgentSelftest(int argc, char *argv[], const QString &question)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("deepin"));
    QCoreApplication::setApplicationName(QStringLiteral("deepDolphin"));
    Settings::instance(); // QSettings 就绪（ai.* 键）

    const EngineLocator::Result engine = EngineLocator::locate();
    if (!engine.found)
        fprintf(stderr, "[selftest] WARN: 引擎未找到，工具执行将报「引擎未找到」原文\n");

    AgentCore core(engine.found ? engine.bin : QString());
    AIConfig cfg = AIConfig::load();
    // 无头自测**恒走 mock 渠道**（M0-7）：否则用户配了真 provider 时"自测"会真打 HTTP、
    // 真消耗额度、还把凭据塞进 CI 输出。mock 通道走脚本状态机（MockEngine），足以验证
    // 工具调用→执行→回喂→收尾的整条循环。明文回退键（ai.apiKey）是 mock 的唯一输入。
    cfg.providerID = QStringLiteral("mock");
    cfg.apiKey = Settings::instance().aiApiKeyPlaintext();
    // Base URL 只当脚本载体：无片段 = 状态机自动编排（先回一个无必填参数的工具调用，
    // 收到结果回最终文本）。显式给 #final 会让循环少走一轮，所以这里保持自动编排。
    if (cfg.baseURL.isEmpty())
        cfg.baseURL = QStringLiteral("mock://headless-selftest#");

    QString err;
    AgentCore::Target target; // .group（与 mac 一致）
    const QList<ChatMessage> convo = core.run(question, {}, target, cfg, 4,
        [](const QString &ev) { fprintf(stderr, "[selftest] … %s\n", qPrintable(ev)); }, &err);
    if (!err.isEmpty()) {
        fprintf(stdout, "[selftest] ERROR: %s\n", qPrintable(err));
        fprintf(stdout, "[selftest-done]\n");
        fflush(stdout);
        Settings::instance().sync();
        return 1;
    }
    QString finalText;
    for (int i = convo.size() - 1; i >= 0; --i) {
        if (convo.at(i).role == ChatMessage::Role::assistant) {
            finalText = convo.at(i).text;
            break;
        }
    }
    fprintf(stdout, "[selftest] FINAL: %s\n", qPrintable(finalText.left(200)));
    fprintf(stdout, "[selftest-done]\n");
    fflush(stdout);
    Settings::instance().sync();
    return 0;
}

// ── 无头快照（mac scripts/render-harness 对位：离屏渲染整窗 PNG，布局可自动验证）──
// 用法：deepDolphin --snapshot <out.png> [--section dashboard|board|milestones|setupguide] [--project <名>]
// 配合 QT_QPA_PLATFORM=offscreen 使用；等数据首轮落地后抓整窗、写文件即退。
// 退出码：0 = 已写文件；1 = 抓取/写盘失败（headless 测试必须响亮失败）。
static int headlessSnapshot(int argc, char *argv[], const LaunchRoute &route, const QString &outPath)
{
    DApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("deepDolphin"));
    app.setOrganizationName(QStringLiteral("deepin"));
    app.setApplicationDisplayName(QStringLiteral("deepDolphin 面板"));
    app.loadTranslator();
    applyThemeOverride(); // 快照与主窗口同一套主题口径
    // 快照路径同样要装兜底调色板（否则暗色拍出来还是白底）
    if (!DS::paletteIsThemeConsistent())
        app.setPalette(DS::applicationPaletteFallback());

    // ⚠ **setupguide 段 = 引擎缺失首屏**（批 AH）：
    //   那个界面在正常启动时**根本不出现**（引擎在 ⇒ 落仪表盘），
    //   ⇒ 以前 docs/snapshots/*-setupguide.png 是**死基线**（拍不出、没人比）。
    //   死基线比没基线更隐蔽：它让人以为「首屏有视觉保障」。
    const bool setupGuide = route.section == QLatin1String("setupguide");

    EngineLocator::Result engine;
    if (setupGuide) {
        // ⚠ **不调 locate()**：它的结果**依赖本机环境**（装没装引擎、DEEPGIT_BIN 指向）
        //   ⇒ 基线不可逐字节重现。这里显式构造**通用缺失态**
        //   （与 EngineLocator::locate() 失败时同款：一条「没找到」+ 一条安装指引）。
        engine.found = false;
        engine.pending = false;
        engine.problems << QStringLiteral(
            "在 DEEPGIT_BIN、开发构建目录、~/.local/bin、/usr/local/bin 与 PATH 上"
            "都没有找到可用的 moongit/deepgit。");
        engine.problems << EngineLocator::installHint();
    } else {
        engine = EngineLocator::locate();
        if (!engine.found)
            qWarning() << "引擎未找到:" << engine.problems.join(QStringLiteral("; "));
    }

    EngineCli cli;
    if (engine.found)
        cli.setEngineBin(engine.bin);
    AppModel model(engine, &cli);
    PanelWindow panel(route, engine, &model);
    // ⚠ 快照**走夹具**（批 T），不走真引擎 —— 真引擎取数会让基线取决于
    //   「本机注册了什么项目」，**不可重现**（此前 4 页快照拍的是空态，
    //   对状态色/布局全是空门：改界面它不红）。夹具走**同一段解析路径**。
    //   夹具是同步喂的 ⇒ 放在 show() 之后，让 UI 一定收到信号再拍。
    panel.show();
    // ⚠ setupguide 段**不喂夹具**：要拍的正是「没有引擎、没有项目」的样子
    //   ⇒ 喂了夹具就变成「有项目但引擎缺失」，那不是用户会看到的画面。
    if (!setupGuide)
        model.useSnapshotFixture();
    int rc = 1;
    // 等 UI 稳定再抓（M0-7）：以前写死 2500ms，引擎慢时拍到 loading 态且退出码仍 0。
    // 现在轮询"数据到位 / 状态已定（引擎未找到 → setup guide 就是终态）"，上限 15s，
    // 超时按失败退出（拍空的图比响亮失败更糟——CI 会把错图固化成基线）。
    QElapsedTimer settle;
    settle.start();
    bool cycleDone = false; // 一轮 refreshAll 收尾（成功/空/失败都算——UI 已到稳定画面）
    QObject::connect(&model, &AppModel::refreshCycleFinished, &panel,
        [&cycleDone] { cycleDone = true; });
    // 轮询循环：每 100ms 查一次"该拍了吗"，拍到/超时即停
    auto *poll = new QTimer(&panel);
    poll->setInterval(100);
    QObject::connect(poll, &QTimer::timeout, &panel,
        [&panel, &model, outPath, &rc, poll, settle, &cycleDone, setupGuide] {
        // 「该拍了」= 数据落地 / 一轮刷新已收尾（含空数据与失败）/ 引擎未找到
        //      （setup guide 即终态）/ 探活仍在飞（pending 也是稳定画面：忙态页）。
        // ⚠ setupguide 段没有数据可等 ⇒ 改成**等一小会儿让布局落定**（300ms），
        //   免得拍到还没排好版的半成品。
        const bool settled = setupGuide
            ? settle.elapsed() >= 300
            : (model.hasLoadedProjectsOnce() || model.lastRefreshedMs() > 0
                || cycleDone || !model.engineFound() || model.enginePending());
        if (!settled && settle.elapsed() < 15000)
            return;
        poll->stop();
        poll->deleteLater();
        if (!settled) {
            fprintf(stdout, "[snapshot] 超时：15s 内数据未落地（引擎慢/未响应）\n");
            fflush(stdout);
            QCoreApplication::quit();
            return;
        }
        const QPixmap shot = panel.grab();
        rc = (shot.isNull() || !shot.save(outPath)) ? 1 : 0;
        // ⚠ **拍到空态 = 响亮失败**（批 T）：夹具没生效 / 夹具被改坏 ⇒ 画面是空的
        //   ⇒ 提交进去的基线又变成「空门」（改界面它不红，说「视觉已评审」是假的）。
        //   宁可构建失败，也不能把空图固化成基线。
        // ⚠ setupguide 段**必然没有项目**（没引擎没夹具）⇒ 这道检查对它不适用，
        //   改用「拍到的**确实是首屏**」来防空门（否则文件名叫 setupguide、
        //   图里其实是仪表盘也能过门）。
        if (rc == 0 && setupGuide) {
            if (!panel.showingSetupGuide()) {
                fprintf(stderr, "[snapshot] setupguide 段却没停在首屏 —— 拍到的不是引擎缺失首屏\n");
                QFile::remove(outPath);
                rc = 1;
            }
        } else if (rc == 0 && model.projects().empty()) {
            fprintf(stderr, "[snapshot] 夹具没有项目 —— 拍出来是空态，基线会变成空门\n");
            QFile::remove(outPath); // 别把那张空图留在盘上（会被当成基线改动）
            rc = 1;
        }
        if (rc == 0)
            fprintf(stdout, "[snapshot] 已写入 %s（%dx%d）\n", qPrintable(outPath),
                shot.width(), shot.height());
        else
            fprintf(stdout, "[snapshot] 写入失败：%s\n", qPrintable(outPath));
        fflush(stdout);
        QCoreApplication::quit();
    });
    poll->start();
    app.exec();
    return rc;
}

// ── 无头状态色样张（批 R）──
// 用法：deepDolphin --color-sample <out.png>（配合 QT_QPA_PLATFORM=offscreen）
// 画一张状态语义色色卡：把**每一档**都画出来。
//
// 【为什么必须单独做这个】4 页面板快照拍的是**空态**（本机引擎注册项目数 0，
// 快照里只有「仪表盘还没有数据」）—— 状态点一个都没画进去。
// ⇒ 面板快照对状态色是**空门**：改色它不红，说「视觉已评审」是假的。
// 这张色卡把每档都画出来，纳入截图矩阵 —— 改色 ⇒ 色卡 diff 红。
// 退出码：0 = 已写文件；1 = 抓取/写盘失败（响亮失败，别把错图固化成基线）。
static int headlessColorSample(int argc, char *argv[], const QString &outPath)
{
    DApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("deepDolphin"));
    app.setOrganizationName(QStringLiteral("deepin"));
    applyThemeOverride(); // 与面板快照同一套主题口径（DEEPDOLPHIN_THEME）
    if (!DS::paletteIsThemeConsistent())
        app.setPalette(DS::applicationPaletteFallback());

    ColorSampleSheet sheet;
    sheet.show();
    const QPixmap shot = sheet.grab();
    int rc = 1;
    if (!shot.isNull() && shot.save(outPath)) {
        rc = 0;
        fprintf(stdout, "[color-sample] 已写入 %s（%dx%d）\n", qPrintable(outPath),
            shot.width(), shot.height());
    } else {
        fprintf(stderr, "[color-sample] 写入失败：%s\n", qPrintable(outPath));
    }
    fflush(stdout);
    return rc;
}

// ── 无头平台探针（M1-9，PLAN §4.3：真机回归可断言的平台事实）──
// 用法：deepDolphin --platform-probe（配合 QT_QPA_PLATFORM=offscreen 亦可用）。
// 逐行 key=value 打印，供 ci.sh / 真机回归脚本 grep 断言；**只报告不断言**——
// offscreen 下托盘 geometry 无效属预期，探针本身恒 exit 0（断言归 CI 门）。
// stdout：
//   backend=<QGuiApplication::platformName()>   真机 x11/wayland；离屏 offscreen
//   trayGeometryValid=<0|1>                     真机托盘在位应为 1；offscreen 0 属预期
//   paletteType=<unknown|light|dark>            DGuiApplicationHelper 运行期判定
//   fontSize{Metric|SectionTitle|CardTitle|Body|Badge}Px=<px>
//                                               DS::font 档位实际像素（T4..T8，
//                                               DesignTokens.cpp:182 同一根系）——真机
//                                               改控制中心字号档位后重跑，这些值应整体变大
static int headlessPlatformProbe(int argc, char *argv[])
{
    int rc = 0;
    {
        // DApplication 而非 QGuiApplication：paletteType 与字号档位都要 DTK 配置就位才是
        // 平台事实（与 --snapshot 同一套构造口径）。探针只读不写——不 applyThemeOverride、
        // 不 setPalette 兜底，否则报告的就是我们伪造的状态，不是平台现状。
        DApplication app(argc, argv);
        app.setApplicationName(QStringLiteral("deepDolphin"));
        app.setOrganizationName(QStringLiteral("deepin"));

        fprintf(stdout, "backend=%s\n", qPrintable(QGuiApplication::platformName()));

        // 后端分档（批 V · M1-7）：平台名 → X11 / Wayland / Other。
        // ⚠ 只报告不断言（离屏是 offscreen ⇒ other）：断言归 CI 门与 SelfCheck。
        //   报出来的意义：真机回归时能一眼看出「这台机器跑的是哪套后端」，
        //   激活动作与托盘弹窗定位的差异都挂在这个分档上。
        fprintf(stdout, "backendKind=%s\n", qPrintable(Backend::kindName(platform::current())));

        // 任务栏几何（批 V · M1-7）：屏幕被面板/任务栏占掉的四边边距。
        // ⚠ 现在是**只读事实**（X11/DDE 下 availableGeometry 已扣掉面板）；
        //   Wayland 下 QPA 未必扣 ⇒ 这行是 M1-8 接 `org.deepin.dde.Panel` 的输入口。
        {
            QScreen *prim = QGuiApplication::primaryScreen();
            const QPoint anchor = prim ? prim->geometry().center() : QPoint(0, 0);
            const Backend::Insets ins = platform::taskbarInsetsAt(anchor);
            fprintf(stdout, "taskbarInsets=%d,%d,%d,%d\n", ins.left, ins.top, ins.right,
                ins.bottom);
        }

        // SNI 托盘（批 X · M1-3）：这台机器的托盘认 SNI 吗？我们的项登记上了吗？
        // ⚠ DDE 上 `QSystemTrayIcon` **一个像素都不显示**（实测：全屏差分 0 像素；
        //   ⚠ 批 Y 更正：`_NET_SYSTEM_TRAY_S0` 选区**是存在的**（`xprop` 查属性查错了），
        //   但它托管的是**应用自绘的 X11 窗口**、不画 SNI 图标）⇒ 托盘能不能出现，
        //   全看 SNI 这条路通不通。
        {
            const platform::TraySniStatus sni = platform::probeTraySni();
            fprintf(stdout, "sniWatcher=%d\n", sni.watcherPresent ? 1 : 0);
            fprintf(stdout, "sniHost=%d\n", int(sni.host));
            fprintf(stdout, "sniHostItems=%d\n", int(sni.hostItems.size()));
            if (!sni.error.isEmpty())
                fprintf(stdout, "sniError=%s\n", qPrintable(sni.error));
        }

        // deepin 托盘**窗口协议**（批 Y · M1-3）：`_NET_SYSTEM_TRAY_S0` 选区在不在、
        // 我们自绘的图标窗口有没有被 daemon 认领（认领了 ⇒ 它进了 `TrayIcons`）。
        {
            const platform::DeepinTrayStatus dt = platform::probeDeepinTray();
            fprintf(stdout, "deepinTraySelection=%d\n", dt.selectionPresent ? 1 : 0);
            if (!dt.error.isEmpty())
                fprintf(stdout, "deepinTrayError=%s\n", qPrintable(dt.error));
        }

        // DDE 面板真几何（批 W · M1-8）：面板**自己**报的几何（D-Bus），
        // 以及由此算出的可用区与**托盘弹窗落点**。
        // ⚠ 探针是「一次性、无交互」的无头工具 ⇒ 这里**同步读**是安全的
        //   （交互路径走 platform::DdePanel::refreshAsync()，不卡 GUI 线程）。
        {
            const PanelGeometry::Panel panel = platform::DdePanel::readNow();
            fprintf(stdout, "panelService=%d\n", platform::DdePanel::servicePresent() ? 1 : 0);
            fprintf(stdout, "panelValid=%d\n", panel.valid ? 1 : 0);
            if (panel.valid) {
                fprintf(stdout, "panelRect=%d,%d,%d,%d\n", panel.rect.x(), panel.rect.y(),
                    panel.rect.width(), panel.rect.height());
                fprintf(stdout, "panelEdge=%s\n", qPrintable(PanelGeometry::edgeName(panel.edge)));
            }
            const QRect screen = platform::screenGeometryAt(QPoint(0, 0));
            fprintf(stdout, "screenRect=%d,%d,%d,%d\n", screen.x(), screen.y(), screen.width(),
                screen.height());
            const QRect avail = PanelGeometry::effectiveAvailable(
                platform::availableGeometryAt(QPoint(0, 0)), screen, panel);
            fprintf(stdout, "usableRect=%d,%d,%d,%d\n", avail.x(), avail.y(), avail.width(),
                avail.height());
            // 托盘弹窗落点：**托盘几何不可用**（DDE 常态：`QSystemTrayIcon` 在 DDE 上
            // **没有宿主** —— DDE 托盘画的是应用自绘的 X11 窗口，批 Y 查明 ⇒ 拿不到坐标）
            // ⇒ 走面板/兜底落点。尺寸用 380×300 代替真实高度（探针里没有真实弹窗）。
            const QRect target = Backend::placePopup(QRect(), QSize(380, 300), avail,
                TrayGeometry::popupGeometry(), panel)
                                    .rect;
            fprintf(stdout, "trayPopupTarget=%d,%d,%d,%d\n", target.x(), target.y(),
                target.width(), target.height());
        }

        // 托盘 geometry：先置可见才有平台集成可言；真机托盘嵌入是异步的（毫秒级），
        // 自旋泵事件等它变有效（上限 500ms）；offscreen 无系统托盘，等满 500ms 后
        // 如实报 0——只报告不断言（PLAN §4 注意事项 7：offscreen 托盘判定一律无效）。
        QSystemTrayIcon tray;
        tray.setVisible(true);
        QElapsedTimer spin;
        spin.start();
        while (!tray.geometry().isValid() && spin.elapsed() < 500)
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        fprintf(stdout, "trayGeometryValid=%d\n", tray.geometry().isValid() ? 1 : 0);

        const auto palette = DGuiApplicationHelper::instance()->paletteType();
        const char *paletteName = palette == DGuiApplicationHelper::LightType ? "light"
            : palette == DGuiApplicationHelper::DarkType ? "dark"
                                                         : "unknown";
        fprintf(stdout, "paletteType=%s\n", paletteName);

        // 字号档位：走 DS::font()（应用实际消费的同一出处，DesignTokens.cpp 档位映射），
        // 不在此处复述 T 档映射；真机改控制中心字号档位后重跑，这些值应整体变大。
        fprintf(stdout, "fontSizeMetricPx=%d\n", DS::font(DS::FontT::metric).pixelSize());
        fprintf(stdout, "fontSizeSectionTitlePx=%d\n", DS::font(DS::FontT::sectionTitle).pixelSize());
        fprintf(stdout, "fontSizeCardTitlePx=%d\n", DS::font(DS::FontT::cardTitle).pixelSize());
        fprintf(stdout, "fontSizeBodyPx=%d\n", DS::font(DS::FontT::body).pixelSize());
        fprintf(stdout, "fontSizeBadgePx=%d\n", DS::font(DS::FontT::badge).pixelSize());

        // 图标解析（批 U · M1-2）：每个逻辑图标名报**解析来源**
        // （dci / theme / qrc / missing）—— 主题缺名是**环境事实**，
        // 只有报出来才知道「界面上那个图标为什么是空的」。
        // ⚠ 这里只**报告**不断言（PLAN §4 注意事项 7 同款：offscreen 下图标主题可能不在位）。
        {
            // 图标主题名：空 = 这台机器**没有**图标主题（offscreen 就是这样）
            // ⇒ 那时「解析不到」不是图标名错了，不该逐个告警、也不该画占位圆点
            //   （圆点会把基线污染成「到处都是圆点」，反而看不出真问题）。
            fprintf(stdout, "iconTheme=%s\n", qPrintable(QIcon::themeName()));
            const QList<IconNames::Id> ids = IconNames::all();
            int missing = 0;
            for (const IconNames::Id id : ids) {
                const QString source = platform::resolveSource(id);
                if (source == QStringLiteral("missing"))
                    ++missing;
                fprintf(stdout, "icon.%s=%s\n", qPrintable(IconNames::name(id)), qPrintable(source));
            }
            fprintf(stdout, "iconCount=%d\n", ids.size());
            fprintf(stdout, "iconMissing=%d\n", missing);
        }
        fflush(stdout);
    } // app/tray 在此正常析构：真机上托盘图标被正确摘除，不留残影

    // 不能走常规 return→exit()：探针启动后 ~1s 即返回 main，进程退出时的**静态析构**
    // 会在 DTK/DBus 全局单例收尾上无限等 futex（本容器实测 5/8 次挂死；GUI 常规退出
    // 事件循环跑得久、异步初始化早已落地，不复现）。探针只读不写、输出已 flush、
    // 无需收口的资源（不碰引擎子进程/Settings），::_exit 跳过静态析构是此处唯一的
    // 确定性退出方式。代价：Qt/DTK 全局单例不走析构——对一次性只读探针无影响。
    ::_exit(rc);
}

// ── 无头文档语言探针（批 AA）：固定文档页的四语言切换**真跑**一遍 ──
// 用法：deepDolphin --docs-lang-probe（配合 QT_QPA_PLATFORM=offscreen 亦可用）。
// 逐语言打印文档窗的**实际**呈现（每行一个字段，key=value）：
//   lang=<语言 key>   title=<窗口标题>   close=<关闭按钮文字>
//   segments=<四个类目分段名，用 | 分隔>   body=<正文前 120 字，换行折成 |>
//   hint=<底部说明>
// ⚠ 只报告不断言（断言归 scripts/ci-docs-lang-probe.sh）。
// ⚠ **必须隔离设置**：探针会切语言 ⇒ 会写 `app.language` ⇒ 走 QSettings 的
//   测试模式（QStandardPaths test mode）⇒ 绝不碰用户的真实设置。
static int headlessDocsLangProbe(int argc, char *argv[])
{
    // ⚠ 必须在 QApplication 构造**之前**开测试模式：QSettings 的落盘位置
    //   在构造时就定下来了。
    QStandardPaths::setTestModeEnabled(true);

    DApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("deepDolphin"));
    app.setOrganizationName(QStringLiteral("deepin"));

    DocsDialog dlg;
    const QString report = docsLangProbeReport(&dlg);
    if (report.isEmpty()) {
        fprintf(stderr, "✗ 文档窗里找不到语言选择器（无从断言）\n");
        fflush(stderr);
        ::_exit(1);
    }
    fprintf(stdout, "%s\n", qPrintable(report));
    fflush(stdout);
    // 同平台探针：走 ::_exit 跳过静态析构（DTK/DBus 全局单例收尾会挂死）。
    ::_exit(0);
}

static int headlessEngineDownload(int argc, char *argv[], const QString &apiUrl, const QString &dest)
{
    // 无头跑一遍「查发布信息 → 下载 → 校验 → 解压 → 落盘 → 探活」全链，
    // 把结论打成 JSON 打到 stdout（契约门拿它断言）。
    // ⚠ 必须留在无头分支：否则未知 flag 落进 GUI 主路径单实例常驻，ci.sh 挂死。
    QCoreApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("deepin"));
    QCoreApplication::setApplicationName(QStringLiteral("deepDolphin"));

    EngineInstaller installer;
    QEventLoop loop;
    bool got = false;
    EngineInstaller::Result last;
    QObject::connect(&installer, &EngineInstaller::progress, &app,
        [](const QString &text) {
            fprintf(stderr, "› %s\n", qPrintable(text));
            fflush(stderr);
        });
    QObject::connect(&installer, &EngineInstaller::finished, &app,
        [&](const EngineInstaller::Result &r) {
            last = r;
            got = true;
            loop.quit();
        });

    installer.start(apiUrl, dest);
    // 兜底超时：网络卡死不能让 CI 永久挂着（引擎链自己也有 30s/步超时）
    QTimer::singleShot(180000, &loop, &QEventLoop::quit);
    loop.exec();

    QJsonObject out;
    out.insert(QStringLiteral("ok"), got && last.ok);
    out.insert(QStringLiteral("stage"), EngineDownload::stageName(last.stage));
    out.insert(QStringLiteral("message"), last.message);
    out.insert(QStringLiteral("bin"), last.bin);
    out.insert(QStringLiteral("tag"), last.tag);
    out.insert(QStringLiteral("verified"), last.verified);
    // ⚠ 这两个字段是本批的核心判据（契约门拿它们断言）：
    //   installedVersion = 实际装上的版本（空 = 未知）
    //   keptPrevious    = 失败时**原有引擎是否被保留**（装坏包不许毁掉已有引擎）
    out.insert(QStringLiteral("installedVersion"), last.installedVersion);
    out.insert(QStringLiteral("keptPrevious"), last.keptPrevious);
    fprintf(stdout, "%s\n",
        qPrintable(QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact))));
    fflush(stdout);
    if (!got) {
        fprintf(stderr, "✗ 引擎下载无头跑超时（没拿到结论）\n");
        return 2;
    }
    return last.ok ? 0 : 1;
}

int main(int argc, char *argv[])
{
    // ⚠ **快照必须逐字节可重现**（批 T）⇒ 快照进程内固定时区为 UTC。
    //   侧栏状态条渲染「空闲 · 上次刷新 HH:mm」，那是 epoch 的**本地时区**渲染：
    //   时区不固定 ⇒ 同一份代码在 UTC 机与 UTC+8 机上拍出两张不同的基线
    //   ⇒ 视觉 diff 门被环境牵着走（与「离屏才同机位」同一个道理）。
    //   只对 --snapshot 生效：正常桌面会话仍用用户本地时区。
    //   ⚠ 必须在**任何 QDateTime 构造之前**设置：Qt 的本地时区是首次使用时缓存的，
    //   之后再改 TZ 不生效。
    for (int i = 1; i < argc; ++i) {
        if (qstrcmp(argv[i], "--snapshot") == 0) {
            qputenv("TZ", "UTC");
            break;
        }
    }

    // 崩溃可观测（M4c）：装在无头分支分派之前——GUI 路径必装；无头路径
    //（--selfcheck/--version/--platform-probe/--agent-selftest/--snapshot）也装：
    // CI 里崩了若只留一行 "Segmentation fault" 无从排障。取舍：崩溃时 stderr
    // 多十几行栈回溯（未开 -rdynamic，主程序帧只有地址），但退出码/信号语义
    // 不变（打完栈恢复默认处置并 re-raise，core 照常），ci.sh 成败判定不受影响。
    CrashHandler::install();

    // ── 无头分支：--selfcheck / --version / --platform-probe / --docs-lang-probe /
    //   --agent-selftest
    //（GUI 应用构造前解析——未知 flag 落进 GUI 主路径会以单实例常驻，无头 CI 挂死）──
    QStringList rawArgs;
    rawArgs.reserve(argc);
    for (int i = 0; i < argc; ++i)
        rawArgs << QString::fromLocal8Bit(argv[i]);
    if (rawArgs.contains(QStringLiteral("--selfcheck"))) {
        QStringList log;
        const int failures = SelfCheck::run(log);
        for (const QString &line : log)
            fprintf(stdout, "%s\n", qPrintable(line));
        fflush(stdout);
        return failures == 0 ? 0 : 1;
    }
    if (rawArgs.contains(QStringLiteral("--version"))) {
        fprintf(stdout, "deepDolphin %s\n", DD_VERSION_STRING);
        return 0;
    }
    if (rawArgs.contains(QStringLiteral("--code-graph-symbol-id"))) {
        // 客户端的符号 id 构造式（与引擎 functions 侧同形）。
        // 契约检查拿它与引擎实际给的 id 逐条比对 —— 构造式一改，关系页签就
        // 永远对不上「调用方/被调方」，而症状极隐蔽（树能画、关系是空的）。
        // 用法：--code-graph-symbol-id <路径> <行号> <名字>
        const int at = rawArgs.indexOf(QStringLiteral("--code-graph-symbol-id"));
        if (at + 3 >= rawArgs.size()) {
            fprintf(stderr, "用法：deepDolphin --code-graph-symbol-id <路径> <行号> <名字>\n");
            return 2;
        }
        const QString id = CodeGraphBuild::symbolId(rawArgs.at(at + 1),
            rawArgs.at(at + 2).toInt(), rawArgs.at(at + 3));
        fprintf(stdout, "%s\n", qPrintable(id));
        fflush(stdout);
        return 0;
    }
    if (rawArgs.contains(QStringLiteral("--agent-tool-names"))) {
        // 客户端能执行的 agent 工具清单（**单一真相源**在 logic/AgentToolPlan）。
        // 契约检查拿它与引擎 `tools --json` 的声明集对位（mac 同款第 12 组，
        // 但这里是运行时真清单，不靠源码解析 —— 解析 switch 会在改写法时静默空转）。
        for (const QString &tool : AgentToolPlan::knownToolNames())
            fprintf(stdout, "%s\n", qPrintable(tool));
        fflush(stdout);
        return 0;
    }
    if (rawArgs.contains(QStringLiteral("--syntax-languages"))) {
        // 客户端语法高亮支持的语言清单（单一真相源在 logic/SyntaxHighlight）。
        // 契约检查拿它与**真引擎**的 detectLang 产物对位：引擎报什么语言，
        // 客户端就得能高亮什么语言 —— 对不上时那些文件的源码是一片纯色，
        // 而「一片纯色」在界面上看不出是缺能力还是代码本来就长这样。
        for (const QString &lang : SyntaxHighlight::languages())
            fprintf(stdout, "%s\n", qPrintable(lang));
        fflush(stdout);
        return 0;
    }
    if (rawArgs.contains(QStringLiteral("--doctor-parse"))) {
        // 客户端对 `doctor --json` 载荷的判定结果（单一真相源在 logic/EngineDoctor）。
        // 契约检查拿**真引擎**的载荷喂它，逐条对「问题数 / 档 / 摘要」——
        // 引擎 doctor 有问题时退出码是 1，但 stdout 仍是合法 JSON，这条口径
        // 只有把真载荷喂进客户端才验得到（自造夹具验的是另一回事）。
        // 用法：deepDolphin --doctor-parse < payload.json
        QFile in;
        in.open(stdin, QIODevice::ReadOnly);
        const QByteArray raw = in.readAll();
        QJsonParseError perr{};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &perr);
        EngineDoctor::Report rep;
        if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
            rep.ok = false;
            rep.error = QStringLiteral("自检载荷不是 JSON 对象");
        } else {
            rep = EngineDoctor::parse(doc.object());
        }
        const char *tone = "ok";
        switch (EngineDoctor::toneOf(rep)) {
        case EngineDoctor::Tone::ok:
            tone = "ok";
            break;
        case EngineDoctor::Tone::problem:
            tone = "problem";
            break;
        case EngineDoctor::Tone::unknown:
            tone = "unknown";
            break;
        case EngineDoctor::Tone::unreadable:
            tone = "unreadable";
            break;
        }
        QJsonObject out;
        out.insert(QStringLiteral("ok"), rep.ok);
        out.insert(QStringLiteral("problems"), rep.problems);
        out.insert(QStringLiteral("tone"), QString::fromLatin1(tone));
        out.insert(QStringLiteral("summary"), EngineDoctor::summary(rep));
        out.insert(QStringLiteral("checks"), rep.checks.size());
        fprintf(stdout, "%s\n",
            qPrintable(QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact))));
        fflush(stdout);
        return rep.ok ? 0 : 1;
    }
    if (rawArgs.contains(QStringLiteral("--receipt-file-path"))) {
        // 从回执型命令的 stdout 里抽出落盘文件的绝对路径（判定层在
        // logic/ArchReceipt）。契约检查拿**真引擎**的回执喂它 —— 「打开导出
        // 文件 / 打开报告」入口全靠这一步，抽不到就永远是坏按钮。
        // 用法：deepDolphin --receipt-file-path .md < receipt.txt
        const int at = rawArgs.indexOf(QStringLiteral("--receipt-file-path"));
        const QString suffix = (at + 1 < rawArgs.size()) ? rawArgs.at(at + 1) : QString();
        if (suffix.isEmpty()) {
            fprintf(stderr, "用法：deepDolphin --receipt-file-path <后缀> < 回执.txt\n");
            return 2;
        }
        QFile in;
        in.open(stdin, QIODevice::ReadOnly);
        const QString text = QString::fromUtf8(in.readAll());
        const QString path = ArchReceipt::filePath(ArchReceipt::plain(text), suffix);
        fprintf(stdout, "%s\n", qPrintable(path));
        fflush(stdout);
        return path.isEmpty() ? 1 : 0;
    }
    if (rawArgs.contains(QStringLiteral("--engine-config-parse"))) {
        // 客户端对 `config list --json` 载荷的判定结果（单一真相源在 logic/EngineConfig）。
        // 契约检查拿**真引擎**的载荷喂它 —— 客户端与引擎各认各的键时，
        // 自造夹具验的是另一回事。
        // 用法：deepDolphin --engine-config-parse < config.json
        QFile in;
        in.open(stdin, QIODevice::ReadOnly);
        const QByteArray raw = in.readAll();
        QJsonParseError perr{};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &perr);
        EngineConfig::Config rep;
        if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
            rep.ok = false;
            rep.error = QStringLiteral("引擎配置载荷不是 JSON 对象");
        } else {
            rep = EngineConfig::parse(doc.object());
        }
        QJsonObject out;
        out.insert(QStringLiteral("ok"), rep.ok);
        out.insert(QStringLiteral("version"), rep.version);
        out.insert(QStringLiteral("language"), rep.language);
        out.insert(QStringLiteral("roots"), rep.roots.size());
        out.insert(QStringLiteral("docs"), rep.docs.size());
        out.insert(QStringLiteral("backupKeep"), rep.backupKeep);
        out.insert(QStringLiteral("maxShallowBranches"), rep.maxShallowBranches);
        out.insert(QStringLiteral("summary"), EngineConfig::summary(rep));
        fprintf(stdout, "%s\n",
            qPrintable(QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact))));
        fflush(stdout);
        return rep.ok ? 0 : 1;
    }
    if (rawArgs.contains(QStringLiteral("--receipt-plain"))) {
        // 回执净化：剥掉 ANSI 颜色码后打印（界面显示回执前走的就是这一步）。
        // 契约检查拿**真引擎**的回执喂它 —— 引擎的 `report` / `config set`
        // 回执带色码（引擎不认 NO_COLOR），裸显示是「[32m✓[0m …」。
        // 用法：deepDolphin --receipt-plain < receipt.txt
        QFile in;
        in.open(stdin, QIODevice::ReadOnly);
        const QString text = QString::fromUtf8(in.readAll());
        const QString plainText = ArchReceipt::plain(text).trimmed();
        fprintf(stdout, "%s\n", qPrintable(plainText));
        fflush(stdout);
        return plainText.isEmpty() ? 1 : 0;
    }
    if (rawArgs.contains(QStringLiteral("--index-status-parse"))) {
        // 客户端对 `index overview --json` 载荷的判定结果（判定层在 logic/IndexStatus）。
        // 契约检查拿**真引擎**的载荷喂它 —— 引擎形状变了、客户端没跟上时，
        // 自造夹具照样全绿。
        // 用法：deepDolphin --index-status-parse < overview.json
        QFile in;
        in.open(stdin, QIODevice::ReadOnly);
        const QByteArray raw = in.readAll();
        QJsonParseError perr{};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &perr);
        IndexStatus::Overview rep;
        if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
            rep.ok = false;
            rep.error = QStringLiteral("索引概览载荷不是 JSON 对象");
        } else {
            rep = IndexStatus::parseOverview(doc.object());
        }
        QJsonObject out;
        out.insert(QStringLiteral("ok"), rep.ok);
        out.insert(QStringLiteral("project"), rep.project);
        out.insert(QStringLiteral("updateCount"), rep.updateCount);
        out.insert(QStringLiteral("nodes"), rep.nodes);
        out.insert(QStringLiteral("edges"), rep.edges);
        out.insert(QStringLiteral("files"), rep.files);
        out.insert(QStringLiteral("selfHealedPresent"), rep.selfHealedPresent);
        out.insert(QStringLiteral("probeFiles"), rep.probeFiles);
        out.insert(QStringLiteral("summary"), IndexStatus::summary(rep));
        fprintf(stdout, "%s\n",
            qPrintable(QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact))));
        fflush(stdout);
        return rep.ok ? 0 : 1;
    }
    if (rawArgs.contains(QStringLiteral("--platform-probe"))) {
        // 必须留在无头分支：否则未知 flag 落进 GUI 主路径单实例常驻，ci.sh 步骤 4 挂死
        //（M1a 期实测）。M1-9 起返回探针事实，不再快速失败。
        return headlessPlatformProbe(argc, argv);
    }
    if (rawArgs.contains(QStringLiteral("--docs-lang-probe"))) {
        // 固定文档页的四语言切换**真跑**一遍（批 AA）：报文档窗的实际呈现。
        // 同样必须留在无头分支（否则会落进 GUI 主路径常驻，CI 挂死）。
        return headlessDocsLangProbe(argc, argv);
    }
    if (rawArgs.contains(QStringLiteral("--agent-tool-surface"))) {
        // 报**模型实际能看到**哪些 agent 工具（批 AB 的工具面收敛探针）。
        return headlessAgentToolSurface(argc, argv);
    }
    if (rawArgs.contains(QStringLiteral("--hook-status-parse"))) {
        // 客户端对引擎 `hook status <项目> --json` 载荷的判定结果
        // （判定层在 logic/EngineHook）。契约检查拿**真引擎**的载荷喂它 ——
        // 引擎改了 installed 的形状（数组 → 对象）时，自造夹具照样全绿。
        // 用法：deepDolphin --hook-status-parse < status.json
        QFile in;
        in.open(stdin, QIODevice::ReadOnly);
        const EngineHook::Status st = EngineHook::parseStatus(in.readAll());
        QJsonObject out;
        out.insert(QStringLiteral("parsed"), st.parsed);
        out.insert(QStringLiteral("project"), st.project);
        out.insert(QStringLiteral("installedPresent"), st.installedPresent);
        out.insert(QStringLiteral("postCommit"), st.postCommit);
        out.insert(QStringLiteral("postMerge"), st.postMerge);
        out.insert(QStringLiteral("count"), EngineHook::installedCount(st));
        out.insert(QStringLiteral("summary"), EngineHook::summary(st));
        fprintf(stdout, "%s\n",
            qPrintable(QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact))));
        fflush(stdout);
        return st.parsed ? 0 : 1;
    }
    if (rawArgs.contains(QStringLiteral("--engine-release-parse"))) {
        // 客户端对 GitHub Releases「latest」载荷的判定结果（判定层在 logic/EngineDownload）。
        // 契约检查拿**真 API** 的载荷喂它 —— 真 release 的资产名/字段形状变了，
        // 自造夹具照样全绿。
        // 用法：deepDolphin --engine-release-parse < release.json
        QFile in;
        in.open(stdin, QIODevice::ReadOnly);
        const EngineDownload::Release rel = EngineDownload::parseRelease(in.readAll());
        QJsonObject out;
        out.insert(QStringLiteral("parsed"), rel.parsed);
        out.insert(QStringLiteral("tag"), rel.tag);
        out.insert(QStringLiteral("hasAsset"), rel.asset.present);
        out.insert(QStringLiteral("assetName"), rel.asset.name);
        out.insert(QStringLiteral("assetUrl"), rel.asset.url);
        out.insert(QStringLiteral("hasDigest"), !rel.asset.digest.trimmed().isEmpty());
        out.insert(QStringLiteral("available"), QJsonArray::fromStringList(rel.available));
        fprintf(stdout, "%s\n",
            qPrintable(QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact))));
        fflush(stdout);
        return rel.parsed ? 0 : 1;
    }
    if (rawArgs.contains(QStringLiteral("--engine-download"))) {
        // 引擎获取链（GitHub Releases 下载安装）的**无头全链**：
        // 查发布信息 → 下载 → 校验和 → 解压 → 落盘 → 探活，结论打成 JSON 打 stdout。
        // ⚠ 必须留在无头分支：否则未知 flag 落进 GUI 主路径单实例常驻，ci.sh 挂死。
        const int at = rawArgs.indexOf(QStringLiteral("--engine-download"));
        if (at + 1 >= rawArgs.size()) {
            fprintf(stderr, "用法：deepDolphin --engine-download <release-api-url> "
                            "[--engine-download-dest <dir>]\n");
            return 2;
        }
        QString dest;
        const int d = rawArgs.indexOf(QStringLiteral("--engine-download-dest"));
        if (d >= 0 && d + 1 < rawArgs.size())
            dest = rawArgs.at(d + 1);
        return headlessEngineDownload(argc, argv, rawArgs.at(at + 1), dest);
    }
    const LaunchRoute preRoute = Route::parseArgs(rawArgs);
    if (preRoute.agentSelftest)
        return headlessAgentSelftest(argc, argv, preRoute.selftestQuestion);
    const int snapIdx = rawArgs.indexOf(QStringLiteral("--snapshot"));
    if (snapIdx >= 0) {
        // 缺参必须响亮失败：以前会带着一个无意义参数把 GUI 拉起来（headless 测试藏在成功里）
        if (snapIdx + 1 >= rawArgs.size()) {
            fprintf(stderr, "用法：deepDolphin --snapshot <out.png> "
                            "[--section dashboard|board|milestones|setupguide] [--project <名>]\n");
            return 2;
        }
        return headlessSnapshot(argc, argv, preRoute, rawArgs.at(snapIdx + 1));
    }
    const int sampleIdx = rawArgs.indexOf(QStringLiteral("--color-sample"));
    if (sampleIdx >= 0) {
        if (sampleIdx + 1 >= rawArgs.size()) {
            fprintf(stderr, "用法：deepDolphin --color-sample <out.png>\n");
            return 2;
        }
        return headlessColorSample(argc, argv, rawArgs.at(sampleIdx + 1));
    }

    DApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("deepDolphin"));
    app.setProductName(QStringLiteral("deepDolphin"));
    app.setApplicationVersion(QStringLiteral(DD_VERSION_STRING));
    app.setOrganizationName(QStringLiteral("deepin"));
    app.setApplicationDisplayName(QStringLiteral("deepDolphin 面板")); // 窗口标题唯一出处
    // 桌面身份（M2-1）：与 data/cn.deepdolphin.app.desktop 的文件名严格一致。
    // 不设 = Wayland 下窗口与 .desktop 关联不上、任务栏不分组、通知"点回应用"失效——
    // 这是 deepin 生态里最便宜也最容易漏的一行。
    app.setDesktopFileName(QStringLiteral("cn.deepdolphin.app"));
    applyThemeOverride();

    // 应用调色板（M3-1）：**真机上 DTK 自己管**——不插手，也别 setPalette（DTK 会警告
    // "Don't use it on DTK application"）。offscreen/无 DTK 配置的环境里样式插件不会来，
    // 不装一套的话原生 QWidget/QListWidget/菜单停在 Qt 默认亮色 = 「白侧栏 + 深内容」
    // 缝合体（README 决策 13 记录过）。兜底整套调色板只由 DS:: 令牌构造，与页面同源。
    if (!DS::paletteIsThemeConsistent())
        app.setPalette(DS::applicationPaletteFallback());
    app.setApplicationDescription(
        QStringLiteral("moonGit 项目群进度客户端 —— 以 moongit/deepgit CLI 为引擎的本地项目管理面板。"));
    app.loadTranslator();
    DLogManager::registerConsoleAppender();
    DLogManager::registerFileAppender();
    DLogManager::registerJournalAppender(); // journald 可检索（真机排障不用去翻日志文件）

    if (!app.setSingleInstance(QStringLiteral("cn.deepdolphin.app"))) {
        // 已有实例在跑：setSingleInstance 已把参数转给首实例，这里直接退出
        return 0;
    }

    EngineLocator::Result engine; // pending：发现链在跑（M0-2）——窗口先亮，引擎后台探
    engine.pending = true;

    EngineCli cli;

    // ── 数据编排（AppModel）+ 启动路由 ──
    AppModel model(engine, &cli);
    const LaunchRoute route = Route::parseArgs(app.arguments());

    PanelWindow panel(route, engine, &model);

    // ── DDE 面板真几何（批 W · M1-8）：托盘弹窗要落在**面板旁边**，
    //    而 DDE 上 `QSystemTrayIcon::geometry()` 恒无效（DDE 托盘画的是**应用自绘的
    //    X11 窗口**，`QSystemTrayIcon` 压根没有宿主；⚠ 批 Y 实测更正，早先写的是
    //    「DDE 的托盘是 SNI」——**说反了**）⇒
    //    拿不到托盘坐标时，弹窗的落点只能靠面板几何推。
    //    读面板是 D-Bus 同步往返 ⇒ 放 worker 线程，结果回 GUI 线程存缓存。
    platform::DdePanel::refreshAsync();

    // ── 托盘（C10）：图标五态 + 速览弹窗 + 右键两项纪律 ──
    TrayController *tray = new TrayController();
    panel.attachTray(tray);
    auto refreshTray = [&model, &panel, tray] {
        if (!tray)
            return;
        const AppModel::TrayState st = model.trayState();
        tray->refreshIcon(st.menuTitle, st.tint);
        tray->refreshFrom(panel.traySnapshot());
    };
    QObject::connect(&model, &AppModel::projectsChanged, &panel, refreshTray);
    QObject::connect(&model, &AppModel::busyChanged, &panel, refreshTray);
    QObject::connect(&model, &AppModel::refreshCycleFinished, &panel, refreshTray);
    QObject::connect(&panel, &PanelWindow::traySnapshotChanged, refreshTray);
    QObject::connect(tray, &TrayController::quitRequested, &app, &QApplication::quit);

    // ── 系统通知：点通知/「打开面板」动作 → 叫醒面板 ──
    QObject::connect(model.notifier(), &Notifier::actionInvoked, &panel,
        [&panel](const QString &action) {
            if (action == QLatin1String("open") || action == QLatin1String("default"))
                panel.bringToFront();
        });

    // ── models.dev 目录：启动后台静默刷新（成功才置 models-dev.refreshed）──
    ModelsDevCatalog::refreshAsync();

    // ── 启动定时器与首轮刷新（300s 轻刷新 / 定时更新 / 首轮 600s）──
    // 引擎发现是异步的（M0-2）：找不到就先不起来 timer（探不到的机器上重试毫无意义），
    // 找到了才 start()——首轮刷新随之落地，SetupGuidePage 让位给仪表盘。
    auto onLocated = [&model, &panel, &cli](const EngineLocator::Result &r) {
        panel.setEngineResult(r);
        if (!r.found) {
            qWarning() << "引擎未找到:" << r.problems.join(QStringLiteral("; "));
            // 安装引导说明条（不阻塞主窗口展示；此刻已在 setup guide 页，此处补一条说明）
            panel.showRouteNotice(r.problems.join(QStringLiteral(" ")));
            return;
        }
        cli.setEngineBin(r.bin);
        model.start();
    };
    EngineLocator::locateAsync(onLocated);

    // ── 会话总线服务（M2-3）：外部（dbus-send/脚本/别的应用）可探活、叫醒、直达项目 ──
    AppService *appService = new AppService(&app);
    QObject::connect(appService, &AppService::activateRequested, &panel,
        [&panel] { panel.bringToFront(); });
    QObject::connect(appService, &AppService::openProjectRequested, &panel,
        [&panel](const QString &name) {
            LaunchRoute r;
            r.project = name;
            panel.applyRoute(r);
        });
    QObject::connect(appService, &AppService::openPathRequested, &panel,
        [&panel](const QString &path) {
            LaunchRoute r;
            r.path = path;
            panel.applyRoute(r);
        });
    QString dbusErr;
    const bool dbusDisabled = qEnvironmentVariableIsSet("DD_NO_DBUS");
    if (dbusDisabled || !appService || !appService->registerOnBus(&dbusErr))
        qWarning() << "DBus 服务未注册：" << dbusErr;
    else
        qInfo() << "DBus 服务已注册：" << AppService::busName() << AppService::objectPath();

    // 二实例(pid,args) 深链转发：信号在 DGuiApplicationHelper（dtkgui）
    QObject::connect(DGuiApplicationHelper::instance(),
        &DGuiApplicationHelper::newProcessInstance, &panel,
        [&panel](qint64 pid, const QStringList &args) {
            Q_UNUSED(pid);
            panel.applyRoute(Route::parseArgs(args));
        });

    // 运行中跟随系统主题/强调色/字号（M3-4）：DTK 调色板 + 全树重polish。
    // 以前只接 newProcessInstance——会话里切亮暗，整树 setStyleSheet 是"构建时拍的
    // 快照"，大面积停在旧色（真机一眼可见）。现在：① 换 app palette（原生控件立即跟随）
    // ② 逐控件重设样式（DS:: 取值在此时重算）；③ 整树 update。
    auto followSystem = [&app, &panel] {
        if (!DS::paletteIsThemeConsistent())
            app.setPalette(DS::applicationPaletteFallback());
        DS::repolish(&panel);
        panel.update();
    };
    auto *helper = DGuiApplicationHelper::instance();
    QObject::connect(helper, &DGuiApplicationHelper::paletteTypeChanged, &app, followSystem);
    QObject::connect(helper, &DGuiApplicationHelper::themeTypeChanged, &app, followSystem);
    QObject::connect(helper, &DGuiApplicationHelper::applicationPaletteChanged, &app, followSystem);
    QObject::connect(helper, &DGuiApplicationHelper::fontChanged, &app, followSystem);

    // 退出收尾：收 timer（引擎子进程由 QProcess 父子关系随进程收口）+ 配置落盘
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &app, [&model] {
        model.stop();
        Settings::instance().sync();
    });

    panel.show();

    // 引擎未找到时的安装引导说明条已由 locateAsync 回调发出（见上）——不再在启动路径同步查引擎。

    return app.exec();
}
