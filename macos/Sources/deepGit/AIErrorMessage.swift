// AIErrorMessage.swift — 把网络/通道错误翻译成「能指导下一步」的中文。
//
// 为什么需要它：实测一个配错的 baseURL，用户在中文界面里看到的是
//
//     Could not connect to the server.
//
// 英文、且完全不指导下一步 ——
// 而这恰恰发生在「测试连接」按钮上：用户刚填完 baseURL 想知道对不对，
// 这句话没告诉他**哪一部分**错了（地址？网络？服务没起？）。
//
// 六个调用点全都直接用 `error.localizedDescription`，
// 于是每一条网络错误都在用 Cocoa 的英文原文、且不带任何建议。
//
// 无 SwiftUI / Foundation 网络依赖，判据可被 agent-check 直接编译来测。
import Foundation

/// 带上「试的是哪个地址」的通道错误。
///
/// 为什么不让六个调用点各自去查 baseURL：
/// 那样每个调用点都要多传一个参数、且要记得传 ——
/// 漏一处，那个出口就退回英文原文。
/// 让错误**自己**带着地址，`localizedDescription` 在任何地方都自动是好的。
struct AIChannelError: LocalizedError {
    let underlying: Error
    let attemptedURL: String?

    var errorDescription: String? {
        AIErrorMessage.describe(underlying, attemptedURL: attemptedURL).text
    }
}

/// 一条能指导下一步的错误。
struct AIErrorReport: Equatable {
    /// 一句话说发生了什么。
    let title: String
    /// 下一步该做什么。**不许为空** —— 只说"失败了"的错误等于让用户猜。
    let hint: String

    var text: String { "\(title)。\(hint)" }
}

enum AIErrorMessage {

    /// 把任意错误翻译成可执行的说明。
    ///
    /// `attemptedURL` 只用来显示"试的是哪个地址"，
    /// **必须先脱敏**（只取 host:port）——
    /// 有些服务把 key 放在 URL 的 user 或 query 里，
    /// 而错误信息会被写进 UI、日志甚至通知中心。
    static func describe(_ error: Error, attemptedURL: String? = nil) -> AIErrorReport {
        // 已经是通道错误就递归解包，别把外层的壳显示给用户。
        if let ch = error as? AIChannelError {
            return describe(ch.underlying, attemptedURL: ch.attemptedURL ?? attemptedURL)
        }
        if let u = error as? URLError {
            return describe(URLError.Code(rawValue: u.errorCode), host: hostOf(attemptedURL))
        }
        // 通道自己的错误（HTTP 非 200、JSON 解析失败等）已经带中文说明了，
        // 补一条通用建议即可，不要覆盖原文。
        let raw = error.localizedDescription
        return AIErrorReport(
            title: raw.isEmpty ? "AI 调用失败" : raw,
            hint: "可在 AI 设置里换一个 provider 或模型后重试。"
        )
    }

    /// 只按 URL 错误码翻译（便于测：不必真发请求）。
    static func describe(_ code: URLError.Code, host: String?) -> AIErrorReport {
        let at = host.map { "（\($0)）" } ?? ""
        switch code {
        case .cannotConnectToHost:
            return AIErrorReport(
                title: "连不上 AI 服务\(at)",
                hint: "检查 AI 设置里的 baseURL 是否写对（要含 /v1 之类的路径），"
                    + "以及本机网络是否可用。"
            )
        case .cannotFindHost:
            return AIErrorReport(
                title: "AI 服务域名解析不了\(at)",
                hint: "baseURL 里的域名可能有拼写错误，或本机 DNS 不可用。"
            )
        case .timedOut:
            return AIErrorReport(
                title: "AI 请求超时（120 秒无响应）",
                hint: "可能是模型太大或网络太慢；换一个小一点的模型，或稍后重试。"
            )
        case .notConnectedToInternet:
            return AIErrorReport(
                title: "设备没有网络连接",
                hint: "接上网络后再试。"
            )
        case .networkConnectionLost:
            return AIErrorReport(
                title: "AI 连接中途断开\(at)",
                hint: "网络不稳定；重试一次，或换一个 provider。"
            )
        case .secureConnectionFailed:
            return AIErrorReport(
                title: "HTTPS 连接建立失败\(at)",
                hint: "该地址的证书无法校验；若是你自建的服务，检查证书链是否完整。"
            )
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return AIErrorReport(
                title: "AI 服务的 HTTPS 证书不受信任\(at)",
                hint: "证书可能已过期或自签。若是你自建的服务，需要在系统设置里手动信任。"
            )
        case .userAuthenticationRequired:
            return AIErrorReport(
                title: "AI 服务要求身份验证",
                hint: "检查 AI 设置里的 API Key 是否填写。"
            )
        case .appTransportSecurityRequiresSecureConnection:
            return AIErrorReport(
                title: "该地址不是 HTTPS，系统拒绝明文请求",
                hint: "把 baseURL 改成 https:// 开头。"
            )
        case .badURL:
            return AIErrorReport(
                title: "AI 服务地址格式不合法",
                hint: "baseURL 应当形如 https://api.example.com/v1"
            )
        case .cancelled:
            return AIErrorReport(title: "AI 请求已取消", hint: "可以重新发起。")
        case .dataNotAllowed:
            return AIErrorReport(
                title: "系统不允许这次请求",
                hint: "检查「系统设置 → 网络 → 防火墙」是否拦了该应用。"
            )
        default:
            return AIErrorReport(
                title: "AI 调用失败\(at)",
                hint: "可在 AI 设置里换一个 provider 或模型后重试。"
            )
        }
    }

    /// 从地址里取出 host:port 用于显示。
    ///
    /// **只取 host，不带 userinfo 与 query** ——
    /// 有些服务把 key 放在 URL 的 user 或 query 里，
    /// 而这条文本会进 UI、进日志、进通知中心。
    static func hostOf(_ urlString: String?) -> String? {
        guard let s = urlString, !s.isEmpty else { return nil }
        guard let comps = URLComponents(string: s), let host = comps.host else {
            // 解析不出来就整个丢掉：宁可少说，也不能把可能含 key 的原文打出去。
            return nil
        }
        if let port = comps.port { return "\(host):\(port)" }
        return host
    }
}
