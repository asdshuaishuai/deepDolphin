// main.rs — deepDolphin 跨平台客户端入口（BUI / Blender UI 解耦运行时）。
//
// 【为什么是 BUI】渲染层是 Blender 的 GPU/CPU raster（Win32 / Cocoa / X11 原生宿主），
// 但写法是 HTML + CSS：圆角、渐变、flex/grid、hover 全在样式表里 ——
// 正好用来做「macOS 克制留白 × Windows 11 Fluent/Mica 层次」的融合设计，
// 同时一套代码三平台（Windows 走 Win32、macOS 走 Cocoa）。
// 许可证：BUI 为 GPL-3.0-or-later（本客户端随之 GPL-3.0-or-later）。
//
// 【字体】HarmonyOS Sans SC 直接编进二进制（add_font）——BUI 没有逐字形
// 回退，必须显式绑定含 CJK 的字面，中文才不会变豆腐块。授权随包
// （assets/fonts/LICENSE.txt）：可随软件嵌入分发，须注明来源。
//
// 【启动顺序】parse_args → Engine（--engine 优先）→ AppState::bootstrap
// （开窗前同步预取 status/dashboard/milestones/registry）→ 路由应用 → 开窗。
// 首屏即数据；代价是引擎慢时开窗变慢（v0 已接受的取舍，见 README）。

mod app;
mod design;
mod engine;
mod models;
mod views;

use app::{AppState, Lang, ProjectTab, Route, SettingsTab};
use blenderui::prelude::*;
use engine::Engine;

const FONT_REGULAR: &[u8] = include_bytes!("../assets/fonts/HarmonyOS_Sans_SC_Regular.ttf");
const FONT_MEDIUM: &[u8] = include_bytes!("../assets/fonts/HarmonyOS_Sans_SC_Medium.ttf");

/// 命令行解析结果。**未知参数只记说明，不静默吞掉**。
#[derive(Default)]
struct StartupArgs {
    engine: Option<String>,
    lang: Option<Lang>,
    project: Option<String>,
    section: Option<String>,
    open_settings: bool,
    self_check: bool,
    project_tab: Option<ProjectTab>,
    notes: Vec<String>,
}

fn main() {
    // 字体注册：常规 + 粗（用 Medium 顶 bold 位，中文 600 观感接近 mac 标题）
    blenderui::add_font("HarmonyOS Sans SC", false, false, FONT_REGULAR);
    blenderui::add_font("HarmonyOS Sans SC", true, false, FONT_MEDIUM);

    let mut args = StartupArgs::default();
    let mut argv = std::env::args().skip(1);
    while let Some(arg) = argv.next() {
        match arg.as_str() {
            "--project" => match argv.next() {
                Some(v) => args.project = Some(v),
                None => args.notes.push("--project 缺少项目名".to_string()),
            },
            "--section" => match argv.next() {
                Some(v) => args.section = Some(v),
                None => args.notes.push("--section 缺少值".to_string()),
            },
            "--open-settings" => args.open_settings = true,
            "--self-check" => args.self_check = true,
            "--lang" => match argv.next() {
                Some(v) => match Lang::parse(&v) {
                    Some(l) => args.lang = Some(l),
                    None => args.notes.push(format!(
                        "--lang {v} 不认识（支持 zh / en / tw / ja）；已用默认语言"
                    )),
                },
                None => args.notes.push("--lang 缺少值".to_string()),
            },
            "--engine" => match argv.next() {
                Some(v) => args.engine = Some(v),
                None => args.notes.push("--engine 缺少路径".to_string()),
            },
            // 自检入口：交互层已有后台 Job（UiSender）+ 取消，但没有可断言的 gate。
            "--selftest-ui-sender" => {
                eprintln!(
                    "SELFTEST 未实现：置信度/补丁已走后台 Job + 取消，但本自检没有\
                     可断言的 UiSender gate，不能以成功退出。"
                );
                std::process::exit(2);
            }
            "--agent-selftest" => {
                eprintln!(
                    "AGENT_SELFTEST 未实现：AI provider / agent 循环属于 P3，尚未落地。"
                );
                std::process::exit(2);
            }
            "--help" | "-h" => {
                println!(
                    "deepDolphin\n\
                     \n\
                     --project <名>        打开项目工作区\n\
                     --section <页>        dashboard|board|milestones|confidence|patch|scan|settings|agent\n\
                     --open-settings      直接打开设置\n\
                     --engine <路径>       指定 moongit 可执行文件\n\
                     --lang <zh|en|tw|ja> 引擎事实语言（zh/en；界面目前只有中文）"
                );
                return;
            }
            other => args.notes.push(format!("未识别的参数：{other}")),
        }
    }

    // section 若本身是项目 tab，就落到 project_tab 而不是全局路由。
    // `--project X --section milestones` 是项目页的「里程碑」标签（旧客户端深链同义）。
    let mut section_route: Option<Route> = None;
    if let Some(section) = &args.section {
        let has_project = args.project.is_some();
        let tab = match section.as_str() {
            "overview" => Some(ProjectTab::Overview),
            "branches" => Some(ProjectTab::Branches),
            "journal" => Some(ProjectTab::Journal),
            "docs" => Some(ProjectTab::Docs),
            "milestones" if has_project => Some(ProjectTab::Milestones),
            "graph" => Some(ProjectTab::Graph),
            _ => None,
        };
        if let Some(tab) = tab {
            if has_project {
                args.project_tab = Some(tab);
            } else {
                args.notes.push(format!(
                    "--section {section} 是项目页标签，需要同时给 --project <名>"
                ));
            }
        } else {
            match section.as_str() {
                "dashboard" => section_route = Some(Route::Dashboard),
                "board" => section_route = Some(Route::Board),
                "milestones" => section_route = Some(Route::Milestones),
                "confidence" => section_route = Some(Route::Confidence),
                "patch" => section_route = Some(Route::Patch),
                "scan" => section_route = Some(Route::Scan),
                "settings" => section_route = Some(Route::Settings(SettingsTab::General)),
                "agent" => section_route = Some(Route::Agent),
                other => args
                    .notes
                    .push(format!("--section {other} 不认识；已停在默认页")),
            }
        }
    }

    let engine = match &args.engine {
        Some(bin) if !bin.trim().is_empty() => Engine::with_bin(bin.trim()),
        _ => Engine::new(),
    };

    // 首屏数据在开窗前预取：BUI 无异步运行时，进窗即数据，避免一进来就冻结
    let mut state = AppState::bootstrap_with(engine);

    if let Some(lang) = args.lang {
        // 启动时只记住「引擎事实语言」的选择；不写引擎 config（避免每次启动都改用户配置）。
        // 界面文案目前只有中文：这里不承诺界面切换。
        if lang.engine_code().is_none() {
            args.notes.push(format!(
                "「{}」没有引擎事实语言（引擎只支持 zh / en）；已忽略该选择",
                lang.label()
            ));
        } else {
            state.lang = lang.engine_option();
        }
    }

    let route = if let Some(p) = args.project {
        Route::Project(p)
    } else if args.open_settings {
        Route::Settings(SettingsTab::General)
    } else if let Some(r) = section_route {
        r
    } else {
        Route::Dashboard
    };
    state.select(route);
    if let Some(tab) = args.project_tab {
        state.set_project_tab(tab);
    }
    if !args.notes.is_empty() {
        state.route_note = Some(args.notes.join("；"));
    }

    // 无头自检：不依赖鼠标/肉眼，回答三个问题——数据到位了吗、布局有边界吗、
    // 离屏光栅有没有画出多种颜色。CI 与截图前的快速体检都走这条。
    if args.self_check {
        println!("engine: {}", state.engine_short());
        println!("projects: {}", state.projects().len());
        println!("status_ready: {}", state.status.is_some());
        println!("milestones_ready: {}", state.milestones.is_some());
        println!("startup_error: {:?}", state.startup_error.as_ref().map(|e| e.user_message()));
        println!("feedback: {:?}", state.feedback.as_ref().map(|f| f.text.clone()));
        Application::headless().run(move |cx| {
            let win = cx
                .open_window(
                    WindowOptions {
                        window_bounds: Some(WindowBounds::Windowed(Bounds {
                            origin: point(px(0.0), px(0.0)),
                            size: size(px(1280.0), px(860.0)),
                        })),
                        ..Default::default()
                    },
                    move |_, cx| cx.new(|_| app::AppRoot { state }),
                )
                .unwrap();
            println!("app-root bounds: {:?}", cx.element_bounds(win.id, "app-root"));
            println!("sidebar bounds: {:?}", cx.element_bounds(win.id, "sidebar"));
            let (wd, ht, px_data) = cx.draw(win.id);
            let mut counts: std::collections::HashMap<u32, usize> = std::collections::HashMap::new();
            for p in &px_data {
                *counts.entry(*p).or_insert(0) += 1;
            }
            let mut top: Vec<(u32, usize)> = counts.into_iter().collect();
            top.sort_by(|a, b| b.1.cmp(&a.1));
            println!("draw: {}x{} unique_colors={}", wd, ht, top.len());
            for (c, n) in top.iter().take(5) {
                println!("  color {:#08X}: {}", c, n);
            }
        });
        return;
    }

    Application::new().run(move |cx| {
        let bounds = Bounds {
            origin: point(px(120.0), px(90.0)),
            size: size(px(1280.0), px(860.0)),
        };
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some("deepDolphin".into()),
                }),
                is_resizable: Some(true),
                // 12 列磁贴 + 260px 侧栏在 1040 以下会挤坏卡片
                window_min_size: Some(size(px(1040.0), px(700.0))),
                gpu: None,
            },
            move |_, cx| {
                cx.new(|_| app::AppRoot { state })
            },
        )
        .unwrap();
    });
}
