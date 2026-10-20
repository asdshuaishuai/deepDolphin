// EngineDownload.h — 引擎获取（GitHub Releases 下载）的**判定层**（纯函数，零 QWidget 头）。
//
// 【为什么判定不接 GUI】—— 其实**接**：这是引擎缺失时用户唯一的出路。
//   判据先行：所有「挑哪个资产 / 校验 / 落哪 / 失败是哪一种」都在这里，
//   网络与解压在 app 层，界面只读结论。
//
// 【为什么必须走 API 而不是固定 URL】⚠ **实测（2026-10-19）**：
//   引擎 release 的资产名带版本号（`moongit-v0.1.0-linux-x64.tar.gz`），
//   而 GitHub 的 `releases/latest/download/<name>` 要求**资产名精确匹配** ——
//   mac 侧用的固定 URL `releases/latest/download/moongit-darwin-arm64.tar.gz`
//   **实测 404**（不带版本号），带版本号的才 200。
//   ⇒ 固定 URL 是脆的（引擎改打包命名就断）；查 API 拿资产列表再挑，才跟得上。
//
// 【失败要说清是哪一种】—— 见 Stage 枚举。绝不「下载失败」四个字打发了事。
#pragma once
#include <QByteArray>
#include <QNetworkReply>
#include <QString>
#include <QStringList>

namespace EngineDownload {

/// 本平台资产后缀（deepin = linux x86_64）。
QString platformSuffix();

/// GitHub Releases「最新版本」API（返回 JSON：tag_name + assets[]）。
QString releaseApiUrl(const QString &repo = QStringLiteral("asdshuaishuai/moongit"));

/// 一个 release 资产。
struct Asset {
    QString name;   ///< 如 moongit-v0.1.0-linux-x64.tar.gz
    QString url;    ///< browser_download_url
    QString digest; ///< "sha256:…"（GitHub 提供；旧 release 可能为空）
    qint64 size = -1;
    bool present = false; ///< 字段真的存在（size=-1 是「没这个键」不是「0 字节」）
};

/// release 解析结果。
struct Release {
    bool parsed = false;  ///< JSON 本身读懂了
    QString tag;          ///< tag_name（如 v0.1.0）
    Asset asset;          ///< 挑中的本平台资产（present=false = 没挑到）
    QStringList available; ///< 该 release 的全部资产名（失败要说清「到底有什么」）
};

/// 从 release JSON 里挑本平台的 tar.gz 资产。
/// 挑不到**不是错误**：asset.present=false + available 列出全部资产名，
/// 由上层报「该版本没有 Linux x64 安装包（现有：…）」。
Release parseRelease(const QByteArray &json);

/// 资产名是否匹配本平台（且是 .tar.gz 包）。
bool assetMatches(const QString &assetName, const QString &suffix);

/// sha256 校验：expected 形如 "sha256:abc…" 或纯 hex；空 = 未提供校验和。
/// ⚠ **空值返回 true** —— 不是「校验通过」，是「无校验和可比」。
///   上层必须据此把「未校验」如实说给用户（不能冒充已校验）。
bool digestMatches(const QString &expected, const QByteArray &data);

/// 落盘位置：用户目录，**不碰系统目录**（不要 sudo，不要往 /usr/local/bin 写）。
QString installDir();

/// 落盘后的引擎路径（落盘名是 `moongit` —— 引擎发现链认这个名字）。
QString installedBin();

/// 引擎 release 包**根部**的可执行文件名（发布包根部的**启动器** `moongit`）。
///
/// ⚠ 发布包**不是**单个裸二进制：根部的 `moongit` 是启动器，真二进制在
///   `bin/moongit-cli`、仓颉运行库在 `runtime/lib/`，启动器按**自身所在目录**
///   去找这两样 ⇒ 三样必须**一起**落盘，否则装下来的引擎跑不起来。
QString packagedBinName();

/// 发布包里要与启动器**一起**落盘的目录（相对包根：`bin` / `runtime`）。
///
/// ⚠ 少落一个 = 装下来的引擎跑不起来（runtime 缺了就是 Library not loaded；
///   bin 缺了启动器 exec 不到真二进制）。
QStringList packagedDirs();

/// 失败分类 —— 「失败要说清是哪一种」。
enum class Stage {
    ok,
    networkUnreachable, ///< 网络不可达（连不上 GitHub）
    releaseUnreadable,  ///< release 载荷读不懂（契约过旧 / 被限流 / 404 HTML）
    noPlatformAsset,    ///< 该 release 没有本平台的资产
    downloadFailed,     ///< 下载中断
    digestMismatch,     ///< 校验和不匹配（资产被换过 / 下载损坏）
    extractFailed,      ///< 解压失败
    probeFailed,        ///< 落盘后探活失败（引擎跑不起来）
};

/// 面向用户的失败说明（detail 放具体上下文，如 URL / 期望与实际校验和）。
QString stageMessage(Stage s, const QString &detail = QString());

/// 失败分类的**机器可读名**（契约门断言用；别拿它当界面文案）。
QString stageName(Stage s);

// ── 网络韧性：瞬时故障要重试，永久故障不要 ──
//
// 【为什么要有】**实测（2026-10-20）**：本机第一次下载引擎 release 直接
//   `{"ok":false,"stage":"downloadFailed","message":"下载中断：Connection closed"}`
//   —— 同时 curl 也卡死 90 秒无数据；**稍后重试**同一个 URL 1.17 秒下完 7.5MB。
//   ⇒ 网络瞬断是**常态**，不是「没网」⇒ 一次失败就放弃，等于把可恢复的故障
//   变成「用户必须手动再点一次」。
//
// ⚠ **重试要有边界**：① 只重试**再试一次可能成**的故障（连接被关 / 超时 /
//   未知网络错 / 服务端 5xx）；② **HTTP 4xx 与校验和不匹配不重试**
//   （重试只会让用户多等）；③ 次数与退避是**有上限的**（不是无限重试）。
// ⚠ 判定用**白名单**而不是黑名单：Qt 将来新增的错误码默认**不**重试（保守）——
//   「漏重试」只是慢一点，「乱重试」是把 404 重试三遍。

/// 这个网络错误**值得重试**吗（瞬时故障类）。
bool isRetryableNetworkError(QNetworkReply::NetworkError err);

/// 最多尝试几次（**含**第一次）。
int maxDownloadAttempts();

/// 第 `failedAttempts` 次失败后，等多久再试（毫秒；指数退避）。
///
/// ⚠ `failedAttempts` 是「**已经失败了几次**」（1 = 第一次失败后要等的时长）。
int retryDelayMs(int failedAttempts);

} // namespace EngineDownload
