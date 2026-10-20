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

/// 引擎缺失时给用户的安装指引（**中性措辞**，不绑定具体界面位置）。
///
/// ⚠ 为什么放判定层：同一句指引会被**多处**用
///   （首屏 SetupGuidePage / 面板状态栏 PanelWindow / AppModel 的 engineProblem）
///   ⇒ 放 app 层就得复制多份 ⇒ 改一处漏两处。
/// ⚠ 为什么**不提「点上面的按钮」**：判定层不知道调用方界面长什么样
///   ⇒ 「上面/下面」在换位置后会说错 ⇒ 方位词由界面自己补。
QString installHint();

/// 「下载并安装引擎」这个动作按钮的标签（首屏与设置页共用一份，避免两处写法不一致）。
QString downloadActionLabel();

/// 同一个动作按钮的**悬停说明**（首屏与设置页共用一份）。
/// ⚠ 之前首屏与设置页**逐字抄了同一句**（两处各写一遍）⇒ 改一处漏一处。
///   凡是**同一个动作**要说的话，都归判定层，界面只取不改。
QString downloadActionTooltip();

/// 下载进行中时按钮上的文字（下载中要看得见，否则用户以为没反应）。
QString downloadBusyLabel();

/// 设置页「引擎」卡的**状态说明**（四态：已找到 / 正在查找 / 正在下载 / 没找到）。
/// ⚠ 为什么不放界面层：这句话说的是**引擎的客观状态**，
///   属于判定层职责；界面层自己写 ⇒ 换个界面就换一套说法。
QString downloadStatusText(bool found, bool pending, bool downloading);

/// 落盘位置：用户目录，**不碰系统目录**（不要 sudo，不要往 /usr/local/bin 写）。
QString installDir();

/// 落盘后的引擎路径（落盘名是 `moongit` —— 引擎发现链认这个名字）。
QString installedBin();

// ── 安装的「旁路构建 + 通过后切换」──
//
// 【为什么要这样】⚠ **实测（2026-10-20）**：原来的安装流程是
//   **先删掉旧引擎 → 再解包新的 → 最后才探活**。
//   ⇒ 装到一个跑不起来的包时，**原来能用的引擎已经被顶替成坏的了**
//   （实测：旧引擎 `version` 输出 `old 0.9.9`，装完变成 `boom`），
//   而且**没有备份、无法回滚** ⇒ 用户从「能用」掉到「有个跑不起来的引擎」。
//   ⚠ 这个坑在 v0.2.0 那个坏包上是**真实发生过**的（`runtime/lib/` 是空的）。
//
// 【正确形状】**先在旁路目录里装好、探活通过，再切换**：
//   解包 → stagingDir → 探活 stagingDir 里的引擎 → 通过才切换到 installDir。
//   ⇒ 失败路径**完全不碰**目标目录 ⇒ 旧引擎原封不动。
QString stagingDir(const QString &installDir);

/// 切换时的备份目录（旧的挪到这里，切换成功才删；失败时用来回滚）。
QString backupDir(const QString &installDir);

/// 目标目录里**已经有一份引擎**吗（= 这次是「升级」而不是「首装」）。
/// ⚠ 判据是「那个文件存在**且可执行**」—— 只有半个文件不算「有引擎」。
bool hasInstalledEngine(const QString &installDir);

/// 目标目录里那份引擎的**指纹**（mtime + 大小）。
///
/// ⚠ 用途：让「失败后原引擎还在吗」从**承诺**变成**实测**——
///   安装开始时记一份，失败时复查一遍；**一致**才算「原封未动」。
///   ⚠ 单看「文件还在」不够：负控照出过「文件还在、但内容已被顶替成坏的」
///     （`old 0.9.9` → `boom`）⇒ 存在性证明不了「没被动过」。
/// ⚠ 目标目录里没有可执行引擎时返回**空串**（= 本来就没有）。
QString engineFingerprint(const QString &installDir);

/// 从探活输出里解析引擎版本。
///
/// 引擎输出形如 `moonGit Engine 0.2.1 (Cangjie 1.0.5 LTS)`。
/// ⚠ **优先取 "Engine" 之后**的版本（否则会把 SDK 版本 `1.0.5` 当成引擎版本）；
///   找不到 "Engine" 才退回全文第一个 `x.y` 形态的数字串。
/// ⚠ 解析不出来返回**空串**（不猜）—— 空 = 版本未知，不能拿来比大小。
QString parseEngineVersion(const QString &text);

/// 版本号比较（a<b 返回负数，a==b 返回 0，a>b 返回正数）。
/// ⚠ 按**数字段**逐段比（`0.2.10 > 0.2.9`，不是字符串比）；
///   缺失的段当 0（`0.2` == `0.2.0`）；前导 `v` 与后缀 `-beta` 不参与比较。
/// ⚠ **空串视为「最旧」**（未知版本没有大小可言）⇒ 调用方若不想把「未知」
///   当成「旧」，必须**先**处理未知（`isDowngrade()` 就是这么做的）。
int compareVersions(const QString &a, const QString &b);

/// candidate 比 installed **旧**吗（= 这次下载是「降级」）？
/// ⚠ **任一方版本未知 ⇒ 不判降级**（缺证据不拒绝用户的合法升级）。
bool isDowngrade(const QString &installed, const QString &candidate);

/// 安装失败时**原引擎还在不在**（用户最关心的一句：我的引擎还好吗）。
///
/// ⚠ 两个参数是**两件事**，别混：
///   `hadExisting` = 安装前目标目录里**本来就有**引擎吗；
///   `preserved`   = 实测下来**原封未动**吗（指纹比对的结果）。
///   ⚠ 存在 ≠ 没被动过（负控照出「还在但被顶替」）⇒ 两者都要说清楚。
QString preserveNote(bool hadExisting, bool preserved);

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
    versionDowngrade,   ///< 新版本比已装的旧 ⇒ 拒绝降级（已装的不动）
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
