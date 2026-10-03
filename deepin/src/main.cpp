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
#include "app/EngineLocator.h"
#include "app/Notifier.h"
#include "app/SelfCheck.h"
#include "app/Settings.h"
#include "app/Version.h"
#include "platform/AppService.h"
#include "logic/Liveness.h"
#include "logic/Route.h"
#include "tray/TrayController.h"
#include "ui/DesignTokens.h"
#include "ui/PanelWindow.h"
#include <DApplication>
#include <DGuiApplicationHelper>
#include <DLog>
#include <QCoreApplication>
#include <unistd.h>
#include <QElapsedTimer>
#include <QEventLoop>
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
// 用法：deepDolphin --snapshot <out.png> [--section dashboard|board|milestones] [--project <名>]
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

    const EngineLocator::Result engine = EngineLocator::locate();
    if (!engine.found)
        qWarning() << "引擎未找到:" << engine.problems.join(QStringLiteral("; "));

    EngineCli cli;
    if (engine.found)
        cli.setEngineBin(engine.bin);
    AppModel model(engine, &cli);
    PanelWindow panel(route, engine, &model);
    model.start(); // 快照要真实数据：首轮 CLI --json 落地后再抓

    panel.show();
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
        [&panel, &model, outPath, &rc, poll, settle, &cycleDone] {
        // 「该拍了」= 数据落地 / 一轮刷新已收尾（含空数据与失败）/ 引擎未找到
        //      （setup guide 即终态）/ 探活仍在飞（pending 也是稳定画面：忙态页）。
        const bool settled = model.hasLoadedProjectsOnce() || model.lastRefreshedMs() > 0
            || cycleDone || !model.engineFound() || model.enginePending();
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
        fflush(stdout);
    } // app/tray 在此正常析构：真机上托盘图标被正确摘除，不留残影

    // 不能走常规 return→exit()：探针启动后 ~1s 即返回 main，进程退出时的**静态析构**
    // 会在 DTK/DBus 全局单例收尾上无限等 futex（本容器实测 5/8 次挂死；GUI 常规退出
    // 事件循环跑得久、异步初始化早已落地，不复现）。探针只读不写、输出已 flush、
    // 无需收口的资源（不碰引擎子进程/Settings），::_exit 跳过静态析构是此处唯一的
    // 确定性退出方式。代价：Qt/DTK 全局单例不走析构——对一次性只读探针无影响。
    ::_exit(rc);
}

int main(int argc, char *argv[])
{
    // ── 无头分支：--selfcheck / --version / --platform-probe / --agent-selftest
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
    if (rawArgs.contains(QStringLiteral("--platform-probe"))) {
        // 必须留在无头分支：否则未知 flag 落进 GUI 主路径单实例常驻，ci.sh 步骤 4 挂死
        //（M1a 期实测）。M1-9 起返回探针事实，不再快速失败。
        return headlessPlatformProbe(argc, argv);
    }
    const LaunchRoute preRoute = Route::parseArgs(rawArgs);
    if (preRoute.agentSelftest)
        return headlessAgentSelftest(argc, argv, preRoute.selftestQuestion);
    const int snapIdx = rawArgs.indexOf(QStringLiteral("--snapshot"));
    if (snapIdx >= 0) {
        // 缺参必须响亮失败：以前会带着一个无意义参数把 GUI 拉起来（headless 测试藏在成功里）
        if (snapIdx + 1 >= rawArgs.size()) {
            fprintf(stderr, "用法：deepDolphin --snapshot <out.png> "
                            "[--section dashboard|board|milestones] [--project <名>]\n");
            return 2;
        }
        return headlessSnapshot(argc, argv, preRoute, rawArgs.at(snapIdx + 1));
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
