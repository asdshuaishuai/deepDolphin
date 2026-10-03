# deepDolphin — deepin/DTK6 客户端（PLAN 里程碑 1：基础框架）
#
# 依据 /tmp/dd-deepin-port/PLAN.md §3 的 CMake 工程设计：
# · DTK6 + Qt6 纯 Widgets（禁止与 DTK5/Qt5 混用——dtk-development SKILL 关键约束）
# · C++17 + AUTOMOC/AUTORCC
# · ★ 冒烟硬约束：可执行文件必须落在 <源>/build 根目录
#
# 【文件清单纪律】add_executable 不展开通配符（glob 会掩盖漏 add 的文件），
# 逐文件显式列出；纯头文件组件（StatusTypes/EngineSummary/DocsEnvelope/
# JournalEnvelope/GitOpResponse/ScanResult/ProjectEntry/MilestoneWrite/
# ToolsEnvelope/LoadState/Milestone/Liveness/ShortcutMap）无需列出，由 AUTOMOC
# 按 include 扫描。后续阶段（四页/AI/AppModel）落地时必须同步本清单。
cmake_minimum_required(VERSION 3.13)
project(deepDolphin VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 版本号单一来源：project() VERSION → build/Version.h（--version / setApplicationVersion 同源）
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/app/Version.h.in
               ${CMAKE_CURRENT_BINARY_DIR}/app/Version.h @ONLY)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets DBus Network)
# Qt6Svg：图标染色通道（QSvgRenderer）。本构建环境无 libqt6svg6-dev（deepin
# crimson 仓库未打包），缺省降级为 QPainter 占位图标；装上后自动启用。
find_package(Qt6 QUIET COMPONENTS Svg)

find_package(Dtk6Core REQUIRED)
find_package(Dtk6Gui REQUIRED)
find_package(Dtk6Widget REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(SECRET REQUIRED IMPORTED_TARGET libsecret-1)

# ★ 冒烟硬路径：产物固定在源码树 build 根（即使配到别处也不破）
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/build")

add_executable(deepDolphin
    # ── 入口 ──
    src/main.cpp
    # ── app/：进程级编排 ──
    src/app/AppModel.cpp
    src/app/EngineCli.cpp
    src/app/EngineLocator.cpp
    src/app/Notifier.cpp
    src/app/ProcessRegistry.cpp
    src/app/SelfCheck.cpp
    src/app/Settings.cpp
    # ── models/：JSON 契约层（键名逐字对齐 CONTRACT）──
    src/models/ContextEnvelope.cpp
    src/models/DashboardData.cpp
    src/models/EngineError.cpp
    src/models/EngineFailure.cpp
    src/models/EngineJson.cpp
    src/models/ProjectStatus.cpp
    src/models/StatusEnvelope.cpp
    src/models/UpdateResult.cpp
    # ── ai/：AI 抽象、后端与 agent 工具循环（PLAN §2.5/§5）──
    src/ai/AIChannel.cpp
    src/ai/AIConfig.cpp
    src/ai/AIEngine.cpp
    src/ai/AIEngineFactory.cpp
    src/ai/AgentConversation.cpp
    src/ai/AgentCore.cpp
    src/ai/AgentOutcome.cpp
    src/ai/AgentPrompts.cpp
    src/ai/AiDigests.cpp
    src/ai/AnthropicEngine.cpp
    src/ai/MockEngine.cpp
    src/ai/ModelsDevCatalog.cpp
    src/ai/OpenAiCompatEngine.cpp
    src/ai/SecretStore.cpp
    src/ai/SystemAiEngine.cpp
    src/ai/ToolArgs.cpp
    # ── logic/：纯函数判定层（零 GUI 依赖）──
    src/logic/CommitTypeComposition.cpp
    src/logic/DashboardScope.cpp
    src/logic/DashFilter.cpp
    src/logic/Derived.cpp
    src/logic/LanguageCoverage.cpp
    src/logic/PathInput.cpp
    src/logic/Route.cpp
    src/logic/Router.cpp
    src/logic/Scope.cpp
    src/logic/UpdateOutcome.cpp
    # ── platform/ ──
    src/platform/AppService.cpp
    src/platform/AutostartManager.cpp
    src/platform/IconLoader.cpp
    src/platform/SysOpen.cpp
    # ── tray/ ──
    src/tray/TrayController.cpp
    src/tray/TrayPopupWindow.cpp
    # ── ui/：主窗口与四页 ──
    src/ui/DesignTokens.cpp
    src/ui/DualTrackButtons.cpp
    src/ui/PanelWindow.cpp
    src/ui/SidebarNav.cpp
    src/ui/WorkBar.cpp
    src/ui/common/MarkdownView.cpp
    src/ui/common/ConfirmDialog.cpp
    src/ui/pages/BoardPage.cpp
    src/ui/pages/DashboardFilterBar.cpp
    src/ui/pages/DashboardPage.cpp
    src/ui/pages/MilestoneRowWidget.cpp
    src/ui/pages/MilestonesPage.cpp
    src/ui/pages/ProjectDetailPage.cpp
    src/ui/pages/ProjectProgressCard.cpp
    src/ui/pages/SetupGuidePage.cpp
    # ── ui/dialogs/ ──
    src/ui/dialogs/AddMilestoneDialog.cpp
    src/ui/dialogs/AgentDialog.cpp
    src/ui/dialogs/AiResultDialog.cpp
    src/ui/dialogs/AiSettingsDialog.cpp
    src/ui/dialogs/ScanDialog.cpp
    src/ui/dialogs/panes/AutomationPane.cpp
    src/ui/dialogs/panes/GeneralPane.cpp
    src/ui/dialogs/panes/AiSettingsPane.cpp
    resources/resources.qrc)

target_include_directories(deepDolphin PRIVATE src ${CMAKE_CURRENT_BINARY_DIR})
target_compile_options(deepDolphin PRIVATE -Wall -Wextra)

if(Qt6Svg_FOUND)
    target_link_libraries(deepDolphin PRIVATE Qt6::Svg)
    target_compile_definitions(deepDolphin PRIVATE DD_HAVE_QTSVG)
else()
    message(STATUS "Qt6Svg 未找到（无 libqt6svg6-dev）：图标染色走 QPainter 占位通道")
endif()

target_link_libraries(deepDolphin PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::DBus Qt6::Network
    Dtk6::Core Dtk6::Gui Dtk6::Widget
    PkgConfig::SECRET)

# tests/：QtTest 单测随 PLAN 里程碑 2（口径层锁死）加入，届时在此
# enable_testing() + add_subdirectory(tests)；当前以二进制内置 --selfcheck
# 承担模型层冒烟判据。

# ---- 安装规则 ----
include(GNUInstallDirs)
install(TARGETS deepDolphin RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/cn.deepdolphin.app.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# DBus 激活（DBusActivatable=true）：面板没起来时会话总线按本文件拉起
install(FILES data/cn.deepdolphin.app.service
        DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
# 应用元信息（软件中心/「关于」）：appstream metainfo
install(FILES data/metainfo/cn.deepdolphin.app.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
install(FILES data/icons/deepdolphin.svg
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
# 图标集（M2-6）：hicolor 8 档位图 + symbolic 矢量层。symbolic 落到
# hicolor/symbolic/apps（本机实证：/usr/share/icons/hicolor/index.theme 声明
# [symbolic/apps] 档，Size=16/MinSize=8/MaxSize=512），装后
# fromTheme("deepdolphin-symbolic"/"dd-*") 直接命中；免安装走 resources.qrc。
install(DIRECTORY data/icons/hicolor
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons)
install(DIRECTORY data/icons/symbolic
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor)
# 注意：desktop 的 Icon=deepdolphin 与这里的安装名一致（图标查找排查见 SKILL gotchas §3）
