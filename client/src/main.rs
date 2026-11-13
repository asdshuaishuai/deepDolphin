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
    screenshot: Option<String>,
    size: Option<(f32, f32)>,
    project_tab: Option<ProjectTab>,
    notes: Vec<String>,
}

/// macOS：把应用外观强制为深色（DarkAqua）。
///
/// BUI 的 Cocoa 宿主用标准 NSWindow 标题栏，其配色跟随**应用外观**；
/// 系统处于浅色模式时标题栏是浅灰，与深海主体完全不搭（实测截图）。
/// BUI 0.5 没有外观 API，这里用 objc2 直接设 `NSApp.appearance`
/// （标题栏 / 红绿灯 / 系统菜单一起变深）。仅 macOS 目标编译。
#[cfg(target_os = "macos")]
fn force_dark_appearance() {
    use objc2_app_kit::{NSAppearance, NSAppearanceNameDarkAqua, NSApplication};
    use objc2_foundation::MainThreadMarker;
    let Some(mtm) = MainThreadMarker::new() else {
        return; // 非主线程拿不到 NSApplication
    };
    let app = NSApplication::sharedApplication(mtm);
    // NSAppearanceNameDarkAqua 是 extern static，读取需要 unsafe
    let name = unsafe { NSAppearanceNameDarkAqua };
    if let Some(appearance) = NSAppearance::appearanceNamed(name) {
        app.setAppearance(Some(&appearance));
    }
}

#[cfg(not(target_os = "macos"))]
fn force_dark_appearance() {}

/// 离屏截图：24bpp BMP（Read 工具不认 BMP，macOS 上再由 sips 转 PNG）。
fn write_bmp(path: &str, w: usize, h: usize, px: &[u32]) -> bool {
    use std::io::Write;
    let row = (w * 3 + 3) & !3;
    let size = 54 + row * h;
    let mut out: Vec<u8> = Vec::with_capacity(size);
    out.extend_from_slice(b"BM");
    out.extend_from_slice(&(size as u32).to_le_bytes());
    out.extend_from_slice(&[0u8; 4]);
    out.extend_from_slice(&54u32.to_le_bytes());
    out.extend_from_slice(&40u32.to_le_bytes());
    out.extend_from_slice(&(w as i32).to_le_bytes());
    out.extend_from_slice(&(h as i32).to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&24u16.to_le_bytes());
    out.extend_from_slice(&[0u8; 24]);
    for y in (0..h).rev() {
        let row_start = out.len();
        for x in 0..w {
            let c = px[y * w + x];
            // BUI 的 draw 像素是 0x00RRGGBB；BMP 24bpp 行内顺序是 B,G,R。
            // （先前"行内 byte0→R"的判断是被少补两字节的行错位误导的，
            //   行填充修好后标准顺序即可，实测背景 0x0E1726 → (14,23,38)。）
            out.push((c & 0xFF) as u8);
            out.push(((c >> 8) & 0xFF) as u8);
            out.push(((c >> 16) & 0xFF) as u8);
        }
        // ⚠️ 行填充按**本行**字节数补到 4 的倍数：按文件总长判断时，
        // 54 字节头恰好占掉 2 mod 4，1190 宽（3570B/行）每行少补 2 字节，
        // 整图逐行错位 → 颜色通道旋转（实测品红偏色）。
        while out.len() - row_start < row {
            out.push(0);
        }
    }
    std::fs::File::create(path)
        .and_then(|mut f| f.write_all(&out))
        .is_ok()
}

fn main() {
    // 字体注册：常规 + 粗（用 Medium 顶 bold 位，中文 600 观感接近 mac 标题）
    blenderui::add_font("HarmonyOS Sans SC", false, false, FONT_REGULAR);
    blenderui::add_font("HarmonyOS Sans SC", true, false, FONT_MEDIUM);

    // 原生标题栏跟随深色外观（见 force_dark_appearance 注释）
    force_dark_appearance();
    // Blender 控件主题：输入框等原生控件用深色主题（默认浅色主题在深海底上
    // 是刺眼的白色长条——实测截图里搜索框就是它）。
    blenderui::set_theme("dark");

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
            "--screenshot" => match argv.next() {
                Some(v) => args.screenshot = Some(v),
                None => args.notes.push("--screenshot 缺少路径".to_string()),
            },
            "--size" => match argv.next() {
                Some(v) => {
                    let mut it = v.split('x');
                    let w = it.next().and_then(|x| x.parse::<f32>().ok());
                    let h = it.next().and_then(|x| x.parse::<f32>().ok());
                    match (w, h) {
                        (Some(w), Some(h)) if w >= 900.0 && h >= 600.0 => args.size = Some((w, h)),
                        _ => args.notes.push(format!("--size 需要 WxH（≥900x600）：{v}")),
                    }
                }
                None => args.notes.push("--size 缺少值（WxH）".to_string()),
            },
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
                     --lang <zh|en|tw|ja> 引擎事实语言（zh/en；界面目前只有中文）
                     --size <WxH>          窗口尺寸（默认 1280x860，最小 900x600）
                     --self-check          无头自检：数据/布局/离屏光栅颜色数
                     --screenshot <路径>   配 --self-check 离屏截图（写 BMP，macOS 转 PNG）"
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
        println!("theme: {}", blenderui::theme_name());
        println!("engine: {}", state.engine_short());
        println!("projects: {}", state.projects().len());
        println!("status_ready: {}", state.status.is_some());
        println!("milestones_ready: {}", state.milestones.is_some());
        println!("startup_error: {:?}", state.startup_error.as_ref().map(|e| e.user_message()));
        println!("feedback: {:?}", state.feedback.as_ref().map(|f| f.text.clone()));
        let screenshot_path = args.screenshot.clone();
        let win_size = args.size.unwrap_or((1280.0, 860.0));
        Application::headless().run(move |cx| {
            let win = cx
                .open_window(
                    WindowOptions {
                        window_bounds: Some(WindowBounds::Windowed(Bounds {
                            origin: point(px(0.0), px(0.0)),
                            size: {
                                let (w, h) = win_size;
                                size(px(w), px(h))
                            },
                        })),
                        ..Default::default()
                    },
                    move |_, cx| cx.new(|_| app::AppRoot { state }),
                )
                .unwrap();
            println!("app-root bounds: {:?}", cx.element_bounds(win.id, "app-root"));
            println!("sidebar bounds: {:?}", cx.element_bounds(win.id, "sidebar"));
            // 输入框像素采样：白底 input 是已知问题（BUI 浏览器风控件），
            // 采样它的中心区域判断是否已换到 Blender 深色控件。
            if let Some(b) = cx.element_bounds(win.id, "sidebar-search") {
                let cx0 = (b.origin.x + b.size.width / 2.0) as usize;
                let cy0 = (b.origin.y + b.size.height / 2.0) as usize;
                println!("search-field at ({}, {})", cx0, cy0);
            }
            let (wd, ht, px_data) = cx.draw(win.id);

            // 离屏截图（--screenshot）：光栅化结果写 BMP，macOS 上用 sips 转 PNG。
            if let Some(path) = &screenshot_path {
                if write_bmp(path, wd, ht, &px_data) {
                    println!("screenshot: {path}");
                    #[cfg(target_os = "macos")]
                    {
                        let png = format!("{}.png", path.trim_end_matches(".bmp"));
                        let _ = std::process::Command::new("sips")
                            .args(["-s", "format", "png", path, "--out", &png])
                            .output();
                        println!("screenshot png: {png}");
                    }
                } else {
                    println!("screenshot: write failed");
                }
            }
            // 搜索框区域平均色（白底 input 会把它拉到很高；深色控件应 < 90）
            if let Some(b) = cx.element_bounds(win.id, "sidebar-search") {
                let (x0, y0) = (b.origin.x as usize, b.origin.y as usize);
                let (x1, y1) = (
                    (b.origin.x + b.size.width) as usize,
                    (b.origin.y + b.size.height) as usize,
                );
                let mut sum = 0u64;
                let mut n = 0u64;
                for y in y0..y1.min(ht) {
                    for x in x0..x1.min(wd) {
                        let c = px_data[y * wd + x];
                        let lum = ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF);
                        sum += lum as u64;
                        n += 1;
                    }
                }
                if n > 0 {
                    println!("search-field avg luminance: {}", sum / n);
                }
            }
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

    let win_size_main = args.size;
    Application::new().run(move |cx| {
        let (win_w, win_h) = win_size_main.unwrap_or((1280.0, 860.0));
        let bounds = Bounds {
            origin: point(px(120.0), px(90.0)),
            size: size(px(win_w), px(win_h)),
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
        // 标题栏与主体同色：DarkAqua 只把标题栏变深灰，和深海主体仍有色差。
        // 透明标题栏 + 窗口底色 = 主体底色，红绿灯直接坐在深海面上。
        #[cfg(target_os = "macos")]
        {
            use objc2_app_kit::{NSApplication, NSColor};
            use objc2_foundation::MainThreadMarker;
            if let Some(mtm) = MainThreadMarker::new() {
                let app = NSApplication::sharedApplication(mtm);
                let bg = unsafe {
                    NSColor::colorWithSRGBRed_green_blue_alpha(10.0 / 255.0, 15.0 / 255.0, 26.0 / 255.0, 1.0)
                };
                for w in app.windows().iter() {
                    w.setTitlebarAppearsTransparent(true);
                    w.setBackgroundColor(Some(&bg));
                }
            }
        }
    });
}
