// DocsPages.swift — 关于 / 帮助 / 开源感谢 / 更新日志
// 固定内容写在代码里（跨平台一致），四语言通过 L10n.doc(.about) 等获取。
import SwiftUI

// MARK: - 多语言文档内容

enum DocPages {
    static func content(for kind: DocPageKind, language: AppLanguage) -> String {
        switch (kind, language) {
        case (.about, .zhCN):   return aboutZhCN
        case (.about, .en):     return aboutEn
        case (.about, .zhTW):   return aboutZhTW
        case (.about, .ja):     return aboutJa
        case (.help, .zhCN):    return helpZhCN
        case (.help, .en):      return helpEn
        case (.help, .zhTW):    return helpZhTW
        case (.help, .ja):      return helpJa
        case (.openSource, .zhCN): return openSourceZhCN
        case (.openSource, .en):   return openSourceEn
        case (.openSource, .zhTW): return openSourceZhTW
        case (.openSource, .ja):   return openSourceJa
        case (.changelog, .zhCN):  return changelogZhCN
        case (.changelog, .en):    return changelogEn
        case (.changelog, .zhTW):  return changelogZhTW
        case (.changelog, .ja):    return changelogJa
        }
    }

    // MARK: 关于

    static let aboutZhCN = """
    ## deepDolphin

    **moongit 引擎的原生客户端** — AI 驱动的本地项目群管理面板。

    deepDolphin 是 [moongit](https://github.com/asdshuaishuai/moongit) 引擎的上层 UI 实现。
    引擎（仓颉语言，AI 无关）提供事实与动作；客户端提供原生界面与 AI 层。

    - **看板** — 按健康状态分列的项目画板
    - **里程碑** — 绑定 git tag 自动判定达成
    - **AI 整合** — 浅/深更新 + AI 摘要、一键项目说明、定时简报
    - **Git 白名单操作** — pull/push/commit/stash/unstash/fetch

    ### 架构

    ```
    引擎（moongit, 仓颉, AI 无关）
        ↑ CLI 子进程
    客户端（deepDolphin, Swift, AI 层）
        ↑ LLM API
    用户选择的 AI Provider
    ```

    ### 版本

    v0.1.0 — macOS ARM64 首发版
    """

    static let aboutEn = """
    ## deepDolphin

    **Native client for the moongit engine** — AI-powered local project group management.

    deepDolphin is the UI layer on top of the [moongit](https://github.com/asdshuaishuai/moongit) engine
    (Cangjie language, AI-agnostic). The engine provides facts and actions; the client provides native UI and the AI layer.

    - **Board** — Projects laid out by health status
    - **Milestones** — Auto-complete via git tag binding
    - **AI Integration** — Shallow/deep update + AI digest, one-click project brief, scheduled briefing
    - **Git Whitelist Ops** — pull/push/commit/stash/unstash/fetch

    ### Architecture

    ```
    Engine (moongit, Cangjie, AI-agnostic)
        ↑ CLI subprocess
    Client (deepDolphin, Swift, AI layer)
        ↑ LLM API
    User-configured AI Provider
    ```

    ### Version

    v0.1.0 — macOS ARM64 initial release
    """

    static let aboutZhTW = """
    ## deepDolphin

    **moongit 引擎的原生客戶端** — AI 驅動的本地專案群管理面板。

    deepDolphin 是 [moongit](https://github.com/asdshuaishuai/moongit) 引擎的上層 UI 實現。
    引擎（倉頡語言，AI 無關）提供事實與動作；客戶端提供原生介面與 AI 層。

    ### 版本

    v0.1.0 — macOS ARM64 首發版
    """

    static let aboutJa = """
    ## deepDolphin

    **moongit エンジンのネイティブクライアント** — AI駆動のローカルプロジェクト群管理パネル。

    deepDolphin は [moongit](https://github.com/asdshuaishuai/moongit) エンジンの上位 UI 実装です。
    エンジン（倉頡言語、AI非依存）が事実とアクションを提供し、クライアントがネイティブUIとAIレイヤーを提供します。

    ### バージョン

    v0.1.0 — macOS ARM64 初回リリース
    """

    // MARK: 帮助

    static let helpZhCN = """
    ## 使用指南

    ### 快速开始

    1. 点击侧栏 **"+ 添加 / 扫描项目"** 注册你的项目
    2. 仪表盘自动加载所有项目的进度数据
    3. 点击项目卡片进入详情页查看分支进度、Git 操作、文档

    ### 里程碑

    在里程碑页面点击 **"+"** 新建里程碑。绑定 git tag 后，tag 出现在仓库中即自动判定达成。

    ### AI 功能

    1. 按 **⌘,** 打开设置，配置 AI Provider 和 API Key
    2. 使用更新菜单中的 **"+AI 摘要"** 变体
    3. 使用项目页的 **"✦ 项目说明"** 一键生成
    4. 仪表盘的 **"项目群说明"** 一键生成全局摘要

    ### Git 操作

    项目详情页的 Git 操作区域支持：
    - **拉取 / 推送 / 抓取** — 远端同步
    - **暂存 / 恢复** — 工作区暂存
    - **提交** — 输入提交信息后一键提交全部改动

    ### 引擎权限

    如果项目在外置卷（/Volumes/data 等）上，需要授予 **完全磁盘访问权限**：
    系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 添加 deepDolphin
    """

    static let helpEn = """
    ## User Guide

    ### Quick Start

    1. Click **"+ Add / Scan Projects"** in the sidebar to register your projects
    2. The dashboard auto-loads progress data for all projects
    3. Click a project card to view branch progress, Git operations, and docs

    ### Milestones

    Click **"+"** on the Milestones page to create one. Bind a git tag — it auto-completes when the tag appears.

    ### AI Features

    1. Press **⌘,** to open Settings, configure your AI Provider and API Key
    2. Use **"+AI Digest"** from the update menu
    3. Use **"✦ Project Brief"** on the project page
    4. Use **"Group Brief"** on the dashboard for a global summary

    ### Git Operations

    The Git Operations area on the project detail page supports:
    - **Pull / Push / Fetch** — remote sync
    - **Stash / Unstash** — workspace stashing
    - **Commit** — one-click commit of all changes with a message

    ### Engine Permissions

    If your projects are on an external volume (/Volumes/data etc.), you need to grant **Full Disk Access**:
    System Settings → Privacy & Security → Full Disk Access → Add deepDolphin
    """

    static let helpZhTW = """
    ## 使用指南

    1. 點擊側欄 **"+ 添加 / 掃描專案"** 註冊專案
    2. 儀表板自動載入進度數據
    3. 點擊專案卡片查看詳情

    ### AI 功能

    按 **⌘,** 開啟設定，配置 AI Provider 和 API Key。
    """

    static let helpJa = """
    ## ユーザーガイド

    1. サイドバーの **"+ プロジェクト追加 / スキャン"** でプロジェクトを登録
    2. ダッシュボードに自動的に進捗データが読み込まれます
    3. プロジェクトカードをクリックして詳細を表示

    ### AI 機能

    **⌘,** で設定を開き、AI プロバイダーと API キーを設定してください。
    """

    // MARK: 开源感谢

    static let openSourceZhCN = """
    ## 开源感谢

    这里只感谢**非基础设施层级**的第三方项目——系统框架（SwiftUI / AppKit 等）
    是平台自带的能力，不在致谢之列。

    ### 引擎

    - **[moongit](https://github.com/asdshuaishuai/moongit)** — 仓颉语言项目群进度引擎（本产品的核心）

    ### 模型目录

    - **[models.dev](https://models.dev)** — AI 模型元数据目录（provider/model/成本/能力），AI 设置页的数据来源

    ### 外部工具

    - **git** — 版本控制（引擎的核心依赖）
    - **curl** — HTTP 请求（引擎的 AI 调用依赖）
    """

    static let openSourceEn = """
    ## Open Source Acknowledgments

    Only non-infrastructure third-party projects are listed here — system
    frameworks (SwiftUI / AppKit, etc.) are platform built-ins and get no credit.

    - **[moongit](https://github.com/asdshuaishuai/moongit)** — Cangjie project group progress engine
    - **[models.dev](https://models.dev)** — AI model metadata catalog
    - **[git](https://git-scm.com)** — Version control (core engine dependency)
    - **[curl](https://curl.se)** — HTTP requests (engine AI calls)
    """

    static let openSourceZhTW = """
    ## 開源感謝

    這裡只感謝**非基礎設施層級**的第三方專案——系統框架屬平台內建能力，不在致謝之列。

    - **[moongit](https://github.com/asdshuaishuai/moongit)** — 倉頡專案群進度引擎（本產品的核心）
    - **[models.dev](https://models.dev)** — AI 模型元資料目錄（provider/model/成本/能力）
    - **[git](https://git-scm.com)** — 版本控制（引擎的核心依賴）
    - **[curl](https://curl.se)** — HTTP 請求（引擎的 AI 呼叫依賴）
    """

    static let openSourceJa = """
    ## オープンソース謝辞

    ここでは**インフラ層以外**のサードパーティプロジェクトのみを紹介します——
    システムフレームワーク（SwiftUI / AppKit など）はプラットフォーム標準搭載のため含めません。

    - **[moongit](https://github.com/asdshuaishuai/moongit)** — 倉頡製プロジェクト群進捗エンジン（本製品の中核）
    - **[models.dev](https://models.dev)** — AIモデルメタデータカタログ（provider/モデル/コスト/能力）
    - **[git](https://git-scm.com)** — バージョン管理（エンジンの中核依存）
    - **[curl](https://curl.se)** — HTTP リクエスト（エンジンの AI 呼び出し依存）
    """

    // MARK: 更新日志

    static let changelogZhCN = """
    ## v0.1.0

    ### 新功能

    - **仪表盘** — 项目群脉搏 hero + 统计卡 + 看板 + 语言分布 + 里程碑 + 活跃项目
    - **看板** — 按健康状态分列（活跃/待处理/停滞/其他）
    - **项目详情** — 工程脉搏 / 提交构成 / 分支进度 / Git 操作 / 进度日志 / 文档平铺
    - **里程碑管理** — CRUD + tag 自动达成 + 行内按钮
    - **AI 整合更新流** — 浅/深更新 + AI 摘要 / 一键项目说明 / 一键项目群说明 / 定时简报
    - **AI 设置** — models.dev 目录驱动 provider 选择器 / 钥匙串存 key / 测试连接
    - **添加/扫描项目** — 单个添加 + 批量扫描目录
    - **菜单栏速览** — 项目状态一目了然 + 快捷更新
    - **多语言** — 简体中文 / English / 繁體中文 / 日本語

    ### 引擎

    - moonGit v0.1.0 — 仓颉语言，零第三方依赖
    - 493 项测试全绿
    - macOS ARM64 首个正式 Release
    """

    static let changelogEn = """
    ## v0.1.0

    ### New Features

    - **Dashboard** — Group pulse hero + stats cards + kanban + language distribution + milestones + active projects
    - **Board** — Projects laid out by health status (Active / Needs Attention / Stale / Other)
    - **Project Detail** — Engineering pulse / commit composition / branch progress / Git operations / progress log / docs
    - **Milestone Management** — CRUD + tag auto-complete + inline buttons
    - **AI-Integrated Update Flow** — Shallow/deep update + AI digest / one-click project brief / group brief / scheduled briefing
    - **AI Settings** — models.dev catalog-driven provider picker / Keychain key storage / test connection
    - **Add/Scan Projects** — Single project + batch directory scan
    - **Menu Bar** — Project status at a glance + quick actions
    - **Localization** — Simplified Chinese / English / Traditional Chinese / Japanese

    ### Engine

    - moonGit v0.1.0 — Cangjie language, zero third-party dependencies
    - 493 tests all green
    - macOS ARM64 initial release
    """

    static let changelogZhTW = """
    ## v0.1.0

    - 儀表板 / 看板 / 里程碑管理 / AI 整合更新流 / Git 白名單操作 / 多語言
    - 引擎 moonGit v0.1.0
    """

    static let changelogJa = """
    ## v0.1.0

    - ダッシュボード / ボード / マイルストーン管理 / AI統合更新フロー / Gitホワイトリスト操作 / 多言語
    - エンジン moonGit v0.1.0
    """
}
