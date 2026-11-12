// main.rs — deepDolphin 跨平台客户端入口（BUI / Blender UI 解耦运行时）。
//
// 【为什么是 BUI】渲染层是 Blender 的 GPU/CPU raster（Win32 / Cocoa / X11 原生宿主），
// 但写法是 HTML + CSS：圆角、渐变、flex/grid、hover 全在样式表里 ——
// 正好用来做「macOS 克制留白 × Windows 11 Mica 层次」的融合设计，
// 同时一套代码三平台（Windows 走 Win32、macOS 走 Cocoa）。
// 许可证：BUI 为 GPL-3.0-or-later（本客户端随之 GPL-3.0-or-later）。
//
// 【字体】HarmonyOS Sans SC 直接编进二进制（add_font）——BUI 没有逐字形
// 回退，必须显式绑定含 CJK 的字面，中文才不会变豆腐块。授权随包
// （assets/fonts/LICENSE.txt）：可随软件嵌入分发，须注明来源。

mod app;
mod design;
mod engine;
mod models;
mod views;

use blenderui::prelude::*;

const FONT_REGULAR: &[u8] = include_bytes!("../assets/fonts/HarmonyOS_Sans_SC_Regular.ttf");
const FONT_MEDIUM: &[u8] = include_bytes!("../assets/fonts/HarmonyOS_Sans_SC_Medium.ttf");

fn main() {
    // 字体注册：常规 + 粗（用 Medium 顶 bold 位，中文 600 观感接近 mac 标题）
    blenderui::add_font("HarmonyOS Sans SC", false, false, FONT_REGULAR);
    blenderui::add_font("HarmonyOS Sans SC", true, false, FONT_MEDIUM);

    // 首屏数据在开窗前预取：BUI 无异步运行时，进窗即数据，避免一进来就冻结
    let mut state = app::AppState::bootstrap();

    // 深链（与旧客户端同形）：--project <名> / --section milestones|dashboard
    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--project" if i + 1 < args.len() => {
                state.select(app::Route::Project(args[i + 1].clone()));
                i += 1;
            }
            "--section" if i + 1 < args.len() => {
                if args[i + 1] == "milestones" {
                    state.select(app::Route::Milestones);
                }
                i += 1;
            }
            _ => {}
        }
        i += 1;
    }

    Application::new().run(move |cx| {
        let bounds = Bounds {
            origin: point(px(120.0), px(90.0)),
            size: size(px(1200.0), px(800.0)),
        };
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions { title: Some("deepDolphin".into()) }),
                is_resizable: Some(true),
                window_min_size: Some(size(px(980.0), px(640.0))),
                gpu: None,
            },
            move |_, cx| cx.new(|_| app::AppRoot { state }),
        )
        .unwrap();
    });
}
