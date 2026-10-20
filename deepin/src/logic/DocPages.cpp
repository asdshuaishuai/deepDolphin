#include "DocPages.h"

namespace DocPages {
namespace {

/// 客户端仓库（关于页 / 致谢页 / 帮助页共用的**唯一**出处）。
const char *const kClientRepo = "https://github.com/asdshuaishuai/deepDolphin";
/// 引擎仓库。
const char *const kEngineRepo = "https://github.com/asdshuaishuai/moongit";

// ── 关于页 ────────────────────────────────────────────────────────────────
//
// ⚠ 平台词（Qt 6 / DDE / DTK / deepin）是**本平台的事实**，不是抄来的 ——
//   抄 mac 的就会把本客户端说成 Swift/macOS 的。
//
// ⚠ 四种语言**给全**（mac 的 zhTW / ja 译文是残缺的 —— 比 zhCN 少好几节；
//   本批按 deepin 的中文底本逐篇写全，不抄残缺版）。

const char *const kAboutZhCN = R"MD(## deepDolphin

**moongit 引擎的原生客户端** — AI 驱动的本地项目群管理面板（deepin / UOS 桌面版）。

deepDolphin 是 [moongit](https://github.com/asdshuaishuai/moongit) 引擎的上层 UI 实现。
引擎（仓颉语言，AI 无关）提供事实与动作；客户端提供原生界面与 AI 层。

- **仪表盘** — 项目群脉搏 + 统计卡 + 项目卡片（整卡可点）
- **看板** — 按健康状态分列的项目画板
- **里程碑** — 绑定 git tag 自动判定达成
- **架构图** — 模块分层与依赖治理
- **代码图谱** — 符号树 / 置信度疑点 / 调用关系，左栏可切「列表 / 热力图」
- **补丁体检** — 工作区改动的置信度三层体检（算法 → 人工裁决 → 合并终稿）
- **AI 整合** — 浅 / 深更新 + AI 摘要、一键项目说明、定时简报
- **Git 白名单操作** — 拉取 / 推送 / 提交 / 暂存 / 恢复

### 架构

```
引擎（moongit，仓颉，AI 无关）
    ↑ CLI 子进程
客户端（deepDolphin，Qt 6 + DDE / DTK，AI 层）
    ↑ LLM API
用户选择的 AI Provider
```

### 版本

v0.1.0 — deepin / UOS 桌面版
)MD";

const char *const kAboutEn = R"MD(## deepDolphin

**Native client for the moongit engine** — AI-powered local project group management (deepin / UOS desktop edition).

deepDolphin is the UI layer on top of the [moongit](https://github.com/asdshuaishuai/moongit) engine.
The engine (written in Cangjie, AI-agnostic) provides facts and actions; the client provides the native UI and the AI layer.

- **Dashboard** — project group pulse + stat cards + project cards (the whole card is clickable)
- **Board** — projects laid out by health status
- **Milestones** — auto-complete via git tag binding
- **Architecture graph** — module layering and dependency governance
- **Code graph** — symbol tree / confidence findings / call relations; the left pane switches between "list" and "heatmap"
- **Patch check** — three-layer confidence check of working-tree changes (algorithm → human verdict → merged final draft)
- **AI integration** — shallow / deep update + AI digest, one-click project brief, scheduled briefing
- **Git whitelist ops** — pull / push / commit / stash / restore

### Architecture

```
Engine (moongit, Cangjie, AI-agnostic)
    ↑ CLI subprocess
Client (deepDolphin, Qt 6 + DDE / DTK, AI layer)
    ↑ LLM API
User-configured AI Provider
```

### Version

v0.1.0 — deepin / UOS desktop edition
)MD";

const char *const kAboutZhTW = R"MD(## deepDolphin

**moongit 引擎的原生客戶端** — AI 驅動的本機專案群管理面板（deepin / UOS 桌面版）。

deepDolphin 是 [moongit](https://github.com/asdshuaishuai/moongit) 引擎的上層 UI 實作。
引擎（倉頡語言，AI 無關）提供事實與動作；客戶端提供原生介面與 AI 層。

- **儀表板** — 專案群脈搏 + 統計卡 + 專案卡片（整卡可點）
- **看板** — 依健康狀態分列的專案畫板
- **里程碑** — 綁定 git tag 自動判定達成
- **架構圖** — 模組分層與依賴治理
- **程式碼圖譜** — 符號樹 / 信賴度疑點 / 呼叫關係，左欄可切「清單 / 熱區圖」
- **修補檢查** — 工作區變更的信賴度三層檢查（演算法 → 人工裁決 → 合併終稿）
- **AI 整合** — 淺 / 深更新 + AI 摘要、一鍵專案說明、排程簡報
- **Git 白名單操作** — 拉取 / 推送 / 提交 / 暫存 / 還原

### 架構

```
引擎（moongit，倉頡，AI 無關）
    ↑ CLI 子行程
客戶端（deepDolphin，Qt 6 + DDE / DTK，AI 層）
    ↑ LLM API
使用者選擇的 AI Provider
```

### 版本

v0.1.0 — deepin / UOS 桌面版
)MD";

const char *const kAboutJa = R"MD(## deepDolphin

**moongit エンジンのネイティブクライアント** — AI 駆動のローカルプロジェクト群管理パネル（deepin / UOS デスクトップ版）。

deepDolphin は [moongit](https://github.com/asdshuaishuai/moongit) エンジンの上位 UI 実装です。
エンジン（倉頡言語、AI 非依存）が事実とアクションを提供し、クライアントがネイティブ UI と AI レイヤーを提供します。

- **ダッシュボード** — プロジェクト群の鼓動 + 統計カード + プロジェクトカード（カード全体がクリック可能）
- **ボード** — 健全な状態ごとに並べたプロジェクトボード
- **マイルストーン** — git tag 紐付けによる自動達成判定
- **アーキテクチャ図** — モジュール階層と依存関係のガバナンス
- **コードグラフ** — シンボルツリー / 信頼度の指摘 / 呼び出し関係。左ペインは「リスト / ヒートマップ」を切り替え可能
- **パッチチェック** — ワークツリー変更の信頼度 3 層チェック（アルゴリズム → 人による裁決 → 統合された最終稿）
- **AI 連携** — 浅い / 深い更新 + AI 要約、ワンクリックのプロジェクト説明、定時ブリーフィング
- **Git 許可リスト操作** — 取得 / 送信 / コミット / 退避 / 復元

### アーキテクチャ

```
エンジン（moongit、倉頡、AI 非依存）
    ↑ CLI サブプロセス
クライアント（deepDolphin、Qt 6 + DDE / DTK、AI イヤー）
    ↑ LLM API
ユーザーが選択した AI プロバイダ
```

### バージョン

v0.1.0 — deepin / UOS デスクトップ版
)MD";

// ── 帮助页 ────────────────────────────────────────────────────────────────

const char *const kHelpZhCN = R"MD(## 使用指南

### 快速开始

1. 侧栏 **"+ 添加 / 扫描项目"** 注册你的项目
2. 仪表盘自动加载所有项目的进度数据
3. **点项目卡片的任意位置** 进入详情页（分支进度 / Git 操作 / 里程碑）

### 里程碑

在里程碑页面点 **"+"** 新建里程碑。绑定 git tag 后，tag 出现在仓库中即自动判定达成。

### 图谱三件套

- **架构图** — 详情页「架构图」入口，看模块分层与依赖治理；可生成、可导出
- **代码图谱** — 详情页「代码图谱」入口，看符号树 / 置信度 / 调用关系；左栏可在「列表 / 热力图」间切换
- **补丁体检** — 详情页「补丁体检」入口，对工作区未提交改动做三层体检：
  算法层给分与疑点 → 人工逐项裁决 → 合并出终稿

### AI 功能

1. 面板菜单 **「设置」** → AI 页签，配置 Provider 与 API Key
2. 更新菜单里的 **"+AI 摘要"** 变体
3. 项目页的 **"✦ 项目说明"** 一键生成
4. 仪表盘的 **"项目群说明"** 一键生成全局摘要

### Git 操作

项目详情页的 Git 操作区域支持：

- **拉取 / 推送** — 远端同步
- **暂存 / 恢复** — 工作区暂存
- **提交** — 输入提交信息后一键提交全部改动

### 引擎

deepDolphin 的一切事实与动作都来自 **moongit 引擎**（CLI 子进程）。
引擎缺席时面板会给出安装指引，而不是假装有数据。
)MD";

const char *const kHelpEn = R"MD(## User Guide

### Quick start

1. Use **"+ Add / scan projects"** in the sidebar to register your projects
2. The dashboard loads the progress data of every project automatically
3. **Click anywhere on a project card** to open the detail page (branch progress / Git ops / milestones)

### Milestones

Click **"+"** on the milestones page to create one. After a git tag is bound, the milestone counts as
achieved as soon as that tag appears in the repository.

### The three graph tools

- **Architecture graph** — entry in the detail page: module layering and dependency governance; can be generated and exported
- **Code graph** — entry in the detail page: symbol tree / confidence / call relations; the left pane switches between "list" and "heatmap"
- **Patch check** — entry in the detail page: a three-layer check of uncommitted working-tree changes:
  algorithm layer gives a score and findings → human adjudicates item by item → a final draft is merged

### AI features

1. Panel menu **"Settings"** → AI tab, to configure the provider and the API key
2. The **"+AI digest"** variant in the update menu
3. **"✦ Project brief"** on the project page — one click
4. **"Project group brief"** on the dashboard — one click for a global summary

### Git operations

The Git area of the project detail page supports:

- **Pull / push** — remote sync
- **Stash / restore** — stash the working tree
- **Commit** — enter a message and commit every change at once

### The engine

Every fact and every action in deepDolphin comes from the **moongit engine** (a CLI subprocess).
When the engine is missing, the panel shows install guidance instead of pretending to have data.
)MD";

const char *const kHelpZhTW = R"MD(## 使用指南

### 快速開始

1. 側欄 **「+ 新增 / 掃描專案」** 註冊你的專案
2. 儀表板自動載入所有專案的進度資料
3. **點專案卡片任意位置** 進入詳細頁（分支進度 / Git 操作 / 里程碑）

### 里程碑

在里程碑頁面點 **"+"** 新增里程碑。綁定 git tag 後，tag 出現在儲存庫中即自動判定達成。

### 圖譜三件套

- **架構圖** — 詳細頁「架構圖」入口，看模組分層與依賴治理；可生成、可匯出
- **程式碼圖譜** — 詳細頁「程式碼圖譜」入口，看符號樹 / 信賴度 / 呼叫關係；左欄可在「清單 / 熱區圖」間切換
- **修補檢查** — 詳細頁「修補檢查」入口，對工作區未提交變更做三層檢查：
  演算法層給分與疑點 → 人工逐項裁決 → 合併出終稿

### AI 功能

1. 面板選單 **「設定」** → AI 分頁，設定 Provider 與 API Key
2. 更新選單裡的 **「+AI 摘要」** 變體
3. 專案頁的 **"✦ 專案說明"** 一鍵生成
4. 儀表板的 **「專案群說明」** 一鍵生成全域摘要

### Git 操作

專案詳細頁的 Git 操作區支援：

- **拉取 / 推送** — 遠端同步
- **暫存 / 還原** — 工作區暫存
- **提交** — 輸入提交訊息後一鍵提交全部變更

### 引擎

deepDolphin 的一切事實與動作都來自 **moongit 引擎**（CLI 子行程）。
引擎缺席時面板會給出安裝指引，而不是假裝有資料。
)MD";

const char *const kHelpJa = R"MD(## 使い方ガイド

### クイックスタート

1. サイドバーの **「+ プロジェクトを追加 / スキャン」** でプロジェクトを登録します
2. ダッシュボードが全プロジェクトの進捗データを自動的に読み込みます
3. **プロジェクトカードの任意の場所をクリック** して詳細ページを開きます（ブランチ進捗 / Git 操作 / マイルストーン）

### マイルストーン

マイルストーンページで **「+」** を押すと作成できます。git tag を紐付けると、その tag が
リポジトリに現れた時点で自動的に達成と判定されます。

### グラフ系 3 ツール

- **アーキテクチャ図** — 詳細ページからの入口。モジュール階層と依存関係のガバナンス。生成と書き出しができます
- **コードグラフ** — 詳細ページからの入口。シンボルツリー / 信頼度 / 呼び出し関係。左ペインは「リスト / ヒートマップ」を切り替え可能
- **パッチチェック** — 詳細ページからの入口。未コミットのワークツリー変更を 3 層で検査します:
  アルゴリズム層がスコアと指摘を出し → 人が 1 件ずつ裁決 → 最終稿を統合します

### AI 機能

1. パネルメニュー **「設定」** → AI タブで、プロバイダと API キーを設定します
2. 更新メニューの **「+AI 要約」** バリアント
3. プロジェクトページの **「✦ プロジェクト説明」** — ワンクリック
4. ダッシュボードの **「プロジェクト群説明」** — ワンクリックで全体要約

### Git 操作

プロジェクト詳細ページの Git 操作エリアは次に対応しています:

- **取得 / 送信** — リモート同期
- **退避 / 復元** — ワークツリーの退避
- **コミット** — メッセージを入力して変更をまとめてコミット

### エンジン

deepDolphin の事実とアクションはすべて **moongit エンジン**（CLI サブプロセス）から来ます。
エンジンが無い場合、パネルはデータがあるふりをせず、インストール手順を示します。
)MD";

// ── 开源感谢页 ────────────────────────────────────────────────────────────
//
// 只感谢**非基础设施层级**的第三方项目 —— 系统框架（Qt 6 / DDE / DTK）
// 是平台自带的能力，不在致谢之列（与 mac 同款口径）。

const char *const kOpenSourceZhCN = R"MD(## 开源感谢

这里只感谢**非基础设施层级**的第三方项目 —— 系统框架（Qt 6 / DDE / DTK 等）
是平台自带的能力，不在致谢之列。

### 引擎

- **[moongit](https://github.com/asdshuaishuai/moongit)** — 仓颉语言项目群进度引擎（本产品的核心）

### 模型目录

- **[models.dev](https://models.dev)** — AI 模型元数据目录（provider / model / 成本 / 能力），AI 设置页的数据来源

### 外部工具

- **git** — 版本控制（引擎的核心依赖）
- **curl** — HTTP 请求（引擎的 AI 调用依赖）
)MD";

const char *const kOpenSourceEn = R"MD(## Open Source Thanks

Only third-party projects **above the infrastructure layer** are listed here — system
frameworks (Qt 6 / DDE / DTK, …) ship with the platform and are therefore not credited.

### The engine

- **[moongit](https://github.com/asdshuaishuai/moongit)** — the Cangjie project group progress engine (the core of this product)

### Model catalog

- **[models.dev](https://models.dev)** — AI model metadata catalog (provider / model / cost / capabilities), the data source of the AI settings page

### External tools

- **git** — version control (a core dependency of the engine)
- **curl** — HTTP requests (the engine's AI calls depend on it)
)MD";

const char *const kOpenSourceZhTW = R"MD(## 開源感謝

這裡只感謝**非基礎設施層級**的第三方專案 —— 系統框架（Qt 6 / DDE / DTK 等）
是平台自帶的能力，不在致謝之列。

### 引擎

- **[moongit](https://github.com/asdshuaishuai/moongit)** — 倉頡語言專案群進度引擎（本產品的核心）

### 模型目錄

- **[models.dev](https://models.dev)** — AI 模型中繼資料目錄（provider / model / 成本 / 能力），AI 設定頁的資料來源

### 外部工具

- **git** — 版本控制（引擎的核心相依）
- **curl** — HTTP 請求（引擎的 AI 呼叫相依）
)MD";

const char *const kOpenSourceJa = R"MD(## オープンソースへの感謝

ここでは**インフラ層より上**のサードパーティ製プロジェクトのみを挙げています。
システムフレームワーク（Qt 6 / DDE / DTK など）はプラットフォーム標準の機能であり、
感謝の対象には含めていません。

### エンジン

- **[moongit](https://github.com/asdshuaishuai/moongit)** — 倉頡言語のプロジェクト群進捗エンジン（本製品のコア）

### モデルカタログ

- **[models.dev](https://models.dev)** — AI モデルのメタデータカタログ（provider / model / コスト / 機能）。AI 設定ページのデータソースです

### 外部ツール

- **git** — バージョン管理（エンジンの中心的な依存）
- **curl** — HTTP リクエスト（エンジンの AI 呼び出しが依存）
)MD";

// ── 更新日志页 ────────────────────────────────────────────────────────────

const char *const kChangelogZhCN = R"MD(## v0.1.0

### 新功能

- **仪表盘** — 项目群脉搏 + 统计卡 + 看板 + 语言分布 + 里程碑 + 活跃项目（项目卡片整卡可点）
- **看板** — 按健康状态分列（活跃 / 待处理 / 停滞 / 其他）
- **项目详情** — 工程脉搏 / 提交构成 / 分支进度 / Git 操作 / 进度日志 / 文档平铺
- **里程碑管理** — CRUD + tag 自动达成 + 行内按钮
- **架构图** — 引擎 `graph arch` 的场景契约 + 自绘画布，支持生成与导出
- **代码图谱** — 符号树 + 置信度疑点 + 调用关系；左栏可切符号索引热力图
- **补丁体检** — 工作区改动的置信度三层体检（算法 → 人工裁决 → 合并终稿）
- **AI 整合更新流** — 浅 / 深更新 + AI 摘要 + 一键项目说明 + 一键项目群说明 + 定时简报
- **AI 设置** — models.dev 目录驱动 Provider 选择器 / 密钥存储 / 测试连接
- **添加 / 扫描项目** — 单个添加 + 批量扫描目录
- **托盘速览** — 项目状态一目了然 + 快捷更新

### 引擎

- moongit v0.1.0 — 仓颉语言，零第三方依赖
- deepin / UOS 桌面版首发
)MD";

const char *const kChangelogEn = R"MD(## v0.1.0

### Features

- **Dashboard** — project group pulse + stat cards + board + language distribution + milestones + active projects (the whole project card is clickable)
- **Board** — laid out by health status (active / pending / stale / other)
- **Project detail** — engineering pulse / commit composition / branch progress / Git ops / progress log / document tiles
- **Milestone management** — CRUD + automatic tag-based completion + inline actions
- **Architecture graph** — the engine's `graph arch` scene contract + a self-drawn canvas; generation and export supported
- **Code graph** — symbol tree + confidence findings + call relations; the left pane switches to the symbol index heatmap
- **Patch check** — three-layer confidence check of working-tree changes (algorithm → human verdict → merged final draft)
- **AI update flow** — shallow / deep update + AI digest + one-click project brief + one-click project group brief + scheduled briefing
- **AI settings** — models.dev-catalog-driven provider picker / key storage / connection test
- **Add / scan projects** — add one, or scan a directory in bulk
- **Tray overview** — project status at a glance + quick update

### The engine

- moongit v0.1.0 — Cangjie, zero third-party dependencies
- first release of the deepin / UOS desktop edition
)MD";

const char *const kChangelogZhTW = R"MD(## v0.1.0

### 新功能

- **儀表板** — 專案群脈搏 + 統計卡 + 看板 + 語言分布 + 里程碑 + 活躍專案（專案卡片整卡可點）
- **看板** — 依健康狀態分列（活躍 / 待處理 / 停滯 / 其他）
- **專案詳細** — 工程脈搏 / 提交構成 / 分支進度 / Git 操作 / 進度日誌 / 文件平鋪
- **里程碑管理** — CRUD + tag 自動達成 + 行內按鈕
- **架構圖** — 引擎 `graph arch` 的場景契約 + 自繪畫布，支援生成與匯出
- **程式碼圖譜** — 符號樹 + 信賴度疑點 + 呼叫關係；左欄可切符號索引熱區圖
- **修補檢查** — 工作區變更的信賴度三層檢查（演算法 → 人工裁決 → 合併終稿）
- **AI 整合更新流** — 淺 / 深更新 + AI 摘要 + 一鍵專案說明 + 一鍵專案群說明 + 排程簡報
- **AI 設定** — models.dev 目錄驅動 Provider 選擇器 / 金鑰儲存 / 測試連線
- **新增 / 掃描專案** — 單一新增 + 批次掃描目錄
- **系統匣概覽** — 專案狀態一目了然 + 快速更新

### 引擎

- moongit v0.1.0 — 倉頡語言，零第三方相依
- deepin / UOS 桌面版首發
)MD";

const char *const kChangelogJa = R"MD(## v0.1.0

### 新機能

- **ダッシュボード** — プロジェクト群の鼓動 + 統計カード + ボード + 言語分布 + マイルストーン + アクティブなプロジェクト（プロジェクトカード全体がクリック可能）
- **ボード** — 健全な状態ごとに配置（アクティブ / 保留中 / 停滞 / その他）
- **プロジェクト詳細** — エンジニアリングの鼓動 / コミット構成 / ブランチ進捗 / Git 操作 / 進捗ログ / ドキュメントのタイル表示
- **マイルストーン管理** — CRUD + tag による自動達成 + インライン操作
- **アーキテクチャ図** — エンジンの `graph arch` シーン契約 + 自前描画キャンバス。生成と書き出しに対応
- **コードグラフ** — シンボルツリー + 信頼度の指摘 + 呼び出し関係。左ペインでシンボルインデックスのヒートマップに切り替え可能
- **パッチチェック** — ワークツリー変更の信頼度 3 層チェック（アルゴリズム → 人による裁決 → 統合された最終稿）
- **AI 連携の更新フロー** — 浅い / 深い更新 + AI 要約 + ワンクリックのプロジェクト説明 + ワンクリックのプロジェクト群説明 + 定時ブリーフィング
- **AI 設定** — models.dev カタログ駆動の Provider ピッカー / 鍵の保存 / 接続テスト
- **プロジェクトの追加 / スキャン** — 単一追加とディレクトリのバッチスキャン
- **トレイ概観** — プロジェクトの状態をひと目で確認 + クイック更新

### エンジン

- moongit v0.1.0 — 倉頡言語、サードパーティ依存なし
- deepin / UOS デスクトップ版の最初のリリース
)MD";

} // namespace

QString kindKey(Kind k)
{
    switch (k) {
    case Kind::about:
        return QStringLiteral("about");
    case Kind::help:
        return QStringLiteral("help");
    case Kind::openSource:
        return QStringLiteral("openSource");
    case Kind::changelog:
        return QStringLiteral("changelog");
    }
    return QString();
}

QVector<Kind> kinds()
{
    return { Kind::about, Kind::help, Kind::openSource, Kind::changelog };
}

QVector<Language> languages()
{
    // ⚠ 顺序即展示顺序（与 mac 的 AppLanguage 同一口径）。
    return { Language::zhCN, Language::en, Language::zhTW, Language::ja };
}

QString languageKey(Language lang)
{
    switch (lang) {
    case Language::zhCN:
        return QStringLiteral("zh-CN");
    case Language::en:
        return QStringLiteral("en");
    case Language::zhTW:
        return QStringLiteral("zh-TW");
    case Language::ja:
        return QStringLiteral("ja");
    }
    return QString();
}

std::optional<Language> languageFromKey(const QString &key)
{
    // ⚠ **认不出 ⇒ nullopt**（不猜、不回落成 zhCN）：
    //   回落会让「拼错的值」静默变成「简体中文」，用户改了设置却看不到变化。
    for (Language l : languages()) {
        if (languageKey(l) == key)
            return l;
    }
    return std::nullopt;
}

QString languageLabel(Language lang)
{
    switch (lang) {
    case Language::zhCN:
        return QStringLiteral("简体中文");
    case Language::en:
        return QStringLiteral("English");
    case Language::zhTW:
        return QStringLiteral("繁體中文");
    case Language::ja:
        return QStringLiteral("日本語");
    }
    return QString();
}

LanguageResolution resolveLanguage(const QString &key, Language fallback)
{
    // ⚠ 「空串」与「认不出」是**两回事**，这里分开：
    //   · 空串 = 还没选过 ⇒ 用默认语言，recovered 保持 false（不是出错，不提示）；
    //   · 非空但认不出 = 存的值坏了 ⇒ 回落 + recovered = true（让 UI 说一句）。
    LanguageResolution r;
    if (key.isEmpty()) {
        r.language = fallback;
        r.recovered = false;
        return r;
    }
    if (const std::optional<Language> l = languageFromKey(key)) {
        r.language = *l;
        r.recovered = false;
        return r;
    }
    r.language = fallback;
    r.recovered = true;
    return r;
}

QString kindTitle(Kind k, Language lang)
{
    switch (k) {
    case Kind::about:
        switch (lang) {
        case Language::zhCN: return QStringLiteral("关于");
        case Language::en: return QStringLiteral("About");
        case Language::zhTW: return QStringLiteral("關於");
        case Language::ja: return QStringLiteral("このアプリについて");
        }
        break;
    case Kind::help:
        switch (lang) {
        case Language::zhCN: return QStringLiteral("帮助");
        case Language::en: return QStringLiteral("Help");
        case Language::zhTW: return QStringLiteral("說明");
        case Language::ja: return QStringLiteral("ヘルプ");
        }
        break;
    case Kind::openSource:
        switch (lang) {
        case Language::zhCN: return QStringLiteral("开源感谢");
        case Language::en: return QStringLiteral("Open Source Thanks");
        case Language::zhTW: return QStringLiteral("開源感謝");
        case Language::ja: return QStringLiteral("オープンソースへの感謝");
        }
        break;
    case Kind::changelog:
        switch (lang) {
        case Language::zhCN: return QStringLiteral("更新日志");
        case Language::en: return QStringLiteral("Changelog");
        case Language::zhTW: return QStringLiteral("更新日誌");
        case Language::ja: return QStringLiteral("変更履歴");
        }
        break;
    }
    return QString();
}

QString content(Kind k, Language lang)
{
    switch (k) {
    case Kind::about:
        switch (lang) {
        case Language::zhCN: return QString::fromUtf8(kAboutZhCN);
        case Language::en: return QString::fromUtf8(kAboutEn);
        case Language::zhTW: return QString::fromUtf8(kAboutZhTW);
        case Language::ja: return QString::fromUtf8(kAboutJa);
        }
        break;
    case Kind::help:
        switch (lang) {
        case Language::zhCN: return QString::fromUtf8(kHelpZhCN);
        case Language::en: return QString::fromUtf8(kHelpEn);
        case Language::zhTW: return QString::fromUtf8(kHelpZhTW);
        case Language::ja: return QString::fromUtf8(kHelpJa);
        }
        break;
    case Kind::openSource:
        switch (lang) {
        case Language::zhCN: return QString::fromUtf8(kOpenSourceZhCN);
        case Language::en: return QString::fromUtf8(kOpenSourceEn);
        case Language::zhTW: return QString::fromUtf8(kOpenSourceZhTW);
        case Language::ja: return QString::fromUtf8(kOpenSourceJa);
        }
        break;
    case Kind::changelog:
        switch (lang) {
        case Language::zhCN: return QString::fromUtf8(kChangelogZhCN);
        case Language::en: return QString::fromUtf8(kChangelogEn);
        case Language::zhTW: return QString::fromUtf8(kChangelogZhTW);
        case Language::ja: return QString::fromUtf8(kChangelogJa);
        }
        break;
    }
    return QString(); // 认不出的类目 → 空串（见头文件的纪律说明）
}

QString windowTitle(Language lang)
{
    switch (lang) {
    case Language::zhCN: return QStringLiteral("deepDolphin 文档");
    case Language::en: return QStringLiteral("deepDolphin Documentation");
    case Language::zhTW: return QStringLiteral("deepDolphin 文件");
    case Language::ja: return QStringLiteral("deepDolphin ドキュメント");
    }
    return QString();
}

QString closeLabel(Language lang)
{
    switch (lang) {
    case Language::zhCN: return QStringLiteral("关闭");
    case Language::en: return QStringLiteral("Close");
    case Language::zhTW: return QStringLiteral("關閉");
    case Language::ja: return QStringLiteral("閉じる");
    }
    return QString();
}

QString repoLabel(Language lang)
{
    switch (lang) {
    case Language::zhCN: return QStringLiteral("查看客户端仓库");
    case Language::en: return QStringLiteral("View client repository");
    case Language::zhTW: return QStringLiteral("查看客戶端倉庫");
    case Language::ja: return QStringLiteral("クライアントリポジトリを見る");
    }
    return QString();
}

QString engineRepoHint(Language lang, const QString &engineRepoUrl)
{
    switch (lang) {
    case Language::zhCN:
        return QStringLiteral("内容与 moongit 引擎仓库：%1").arg(engineRepoUrl);
    case Language::en:
        return QStringLiteral("Content follows the moongit engine repository: %1")
            .arg(engineRepoUrl);
    case Language::zhTW:
        return QStringLiteral("內容與 moongit 引擎倉庫：%1").arg(engineRepoUrl);
    case Language::ja:
        return QStringLiteral("内容は moongit エンジンのリポジトリに対応：%1").arg(engineRepoUrl);
    }
    return QString();
}

QString unavailableText(Kind k, Language lang)
{
    const QString id = kindKey(k);
    switch (lang) {
    case Language::zhCN:
        return QStringLiteral("这一篇文档读不到（类目 %1 没有对应内容）。").arg(id);
    case Language::en:
        return QStringLiteral("This document cannot be loaded (kind \"%1\" has no content).").arg(id);
    case Language::zhTW:
        return QStringLiteral("這一篇文件讀不到（類目 %1 沒有對應內容）。").arg(id);
    case Language::ja:
        return QStringLiteral("このドキュメントは読み込めません（種類「%1」に対応本文がありません）。").arg(id);
    }
    return QString();
}

QString recoveredNotice(const QString &badKey, Language lang)
{
    switch (lang) {
    case Language::zhCN:
        return QStringLiteral("语言设置「%1」无法识别，已回落到简体中文。").arg(badKey);
    case Language::en:
        return QStringLiteral("The language setting \"%1\" is not recognized; fell back to Simplified Chinese.")
            .arg(badKey);
    case Language::zhTW:
        return QStringLiteral("語言設定「%1」無法辨識，已回退到簡體中文。").arg(badKey);
    case Language::ja:
        return QStringLiteral("言語設定「%1」を認識できないため、簡体字中国語にフォールバックしました。")
            .arg(badKey);
    }
    return QString();
}

QString engineRepo()
{
    return QString::fromUtf8(kEngineRepo);
}

QString clientRepo()
{
    return QString::fromUtf8(kClientRepo);
}

} // namespace DocPages
