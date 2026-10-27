// GraphWebView.swift — 图谱交付物的应用内渲染容器。
//
// 用户定稿 2026-10-27：架构图/代码图谱**不再原生绘制**——引擎的交互 HTML
// （render arch / render index 产物，零依赖单文件）就是唯一正身，客户端用
// WKWebView 直接渲染该文件。关系连线、下钻、返回上级、搜索、明暗主题全部
// 是 HTML 自带行为，客户端不再维护第二份绘制实现（两份实现必然漂移，
// 本仓库在「同一份形状抄多处」上已反复栽跟头）。
//
// 契约：只装载**本机引擎落盘**的 file:// 产物（传输层纪律：不跨网络），
// allowReadAccess 限定在产物所在目录。
import SwiftUI
import WebKit

struct GraphWebView: NSViewRepresentable {
    /// 要装载的 HTML 产物路径。nil = 还没有产物（上层显示空态/错误）。
    let htmlPath: String?
    /// 变更即强制重载（重新渲染后路径不变也要刷新）。
    var reloadToken: Int = 0

    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView()
        // 产物自带完整背景色；避免装载瞬间的白闪
        v.underPageBackgroundColor = .black
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        guard let p = htmlPath else { return }
        let url = URL(fileURLWithPath: p)
        let c = context.coordinator
        // 同一路径 + token 未变 ⇒ 不重复装载（SwiftUI 反复调 update 是常态）
        guard c.lastPath != p || c.lastToken != reloadToken else { return }
        c.lastPath = p
        c.lastToken = reloadToken
        v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastPath: String?
        var lastToken = 0
    }
}
