#!/bin/sh
# 构建 deepDolphin.app —— macOS 客户端（菜单栏常驻 + 主面板窗口），双击即用。
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="deepDolphin"
BUILD_DIR=".build/release"
APP_BUNDLE="$DIR/$APP_NAME.app"

echo "› 编译 Swift 包…"
swift build -c release

echo "› 组装 .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 应用图标 + models.dev 目录快照（AI 设置选择器数据骨干）
#
# ⚠ 图标来自**仓库根的公共资源**，平台目录里不再放第二份。
# 「所有平台用同一套 icon」这句话很容易退化成「每个平台各自拷一份 png，
# 以后慢慢长得不一样」——所以平台只许**引用** `assets/icon/out/` 下的产物，
# 那里的东西由 `assets/icon/make-icons.py` 从唯一母版 `assets/icon/mark.png`
# 生成（几何差异见 assets/icon/README.md）。
#
# 这里**故意不静默跳过**：图标产物缺失说明公共资源没生成或被误删，
# 继续打出一个没图标的 app，比直接失败更难排查。
ICON_ICNS="$DIR/../assets/icon/out/macos/AppIcon.icns"
if [ ! -f "$ICON_ICNS" ]; then
  echo "✗ 找不到公共图标：$ICON_ICNS" >&2
  echo "  先跑：python3 assets/icon/make-icons.py" >&2
  exit 1
fi
cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

if [ -f "$DIR/Resources/models-dev.json" ]; then
  cp "$DIR/Resources/models-dev.json" "$APP_BUNDLE/Contents/Resources/models-dev.json"
fi
# 中文本地化
mkdir -p "$APP_BUNDLE/Contents/Resources/zh_CN.lproj"
if [ -f "$DIR/Resources/zh_CN.lproj/InfoPlist.strings" ]; then
  cp "$DIR/Resources/zh_CN.lproj/InfoPlist.strings" "$APP_BUNDLE/Contents/Resources/zh_CN.lproj/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleName</key><string>deepDolphin</string>
    <key>CFBundleDisplayName</key><string>deepDolphin</string>
    <key>CFBundleIdentifier</key><string>cn.deepdolphin.app</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <!-- 必须与 Package.swift 的 platforms: [.macOS(.v14)] 一致。
         原来这里写 13.0：app 声称支持 macOS 13，实际却是用 14 的 SDK 编的 ——
         用户在 13 上装得上、点得开，然后崩在一个费解的 dyld 错误上。
         声称的最低版本必须等于真实最低版本。

         ⚠️ 这个 heredoc 是**无引号**的（为了插值 ${APP_NAME}），所以正文里
         不能出现反引号 —— 它们会被当命令替换，实测直接把构建打断。 -->
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# 可选地把引擎二进制打包进 app（独立分发；找不到时 app 会按
# DEEPGIT_BIN → 内嵌副本 → ~/.local/bin → PATH 的顺序自行发现引擎）
#
# ⚠️ 顺序必须是「仓内 release 优先」，原来反过来
# （command -v → ~/.local/bin → 仓内），于是永远选到 ~/.local/bin 那个
# **过期安装版**。后果：打出来的 app 内嵌的是旧引擎，而你在本地跑通了
# 一切检查、看到的输出却来自另一个二进制 —— 本会话已经因为这个栽过
# （契约检查一度报出一堆假失败，症状与「模型写错了」几乎无法分辨）。
# 仓内 release 找不到时才退回已安装版，且**必须打印警告**。
ENGINE_PICKED=""
ENGINE_IS_REPO=0
for CANDIDATE in \
  "${DEEPGIT_BIN:-}" \
  "$DIR/../../moonGit/target/release/bin/main" \
  "$(command -v moongit 2>/dev/null || true)" \
  "$(command -v deepgit 2>/dev/null || true)" \
  "$HOME/.local/bin/moongit" \
  "$HOME/.local/bin/deepgit"; do
  if [ -n "$CANDIDATE" ] && [ -x "$CANDIDATE" ]; then
    case "$CANDIDATE" in
      */moonGit/target/*) ENGINE_IS_REPO=1 ;;
      *) ENGINE_IS_REPO=0 ;;
    esac
    ENGINE_PICKED="$CANDIDATE"
    break
  fi
done

if [ -n "$ENGINE_PICKED" ]; then
  cp "$ENGINE_PICKED" "$APP_BUNDLE/Contents/Resources/moongit"
  if [ "$ENGINE_IS_REPO" = "1" ]; then
    echo "   已内嵌引擎（仓内 release）：$ENGINE_PICKED"
  else
    echo "⚠ 已内嵌引擎（**已安装版，可能过期**）：$ENGINE_PICKED" >&2
    echo "  仓内 moonGit/target/release/bin/main 没找到或不可执行。" >&2
    echo "  打出来的 app 会带着旧引擎，而下面的检查测的是仓内代码 —— 两者不是一回事。" >&2
    echo "  先 cd moonGit && cjpm build 再打包。" >&2
  fi
fi

# 内嵌引擎所需的仓颉运行时（若存在），使 app 可独立运行
CJ_HOME="${CANGJIE_HOME:-$HOME/.local/share/cangjie/current}"
CJ_RUNTIME="$CJ_HOME/runtime/lib/darwin_aarch64_cjnative"
if [ -d "$CJ_RUNTIME" ]; then
  mkdir -p "$APP_BUNDLE/Contents/Frameworks"
  cp "$CJ_RUNTIME/"*.dylib "$APP_BUNDLE/Contents/Frameworks/" 2>/dev/null || true
  # 让内嵌引擎**只**从 app 自己的 Frameworks 目录加载运行时，
  # 这样分发给别人时无需安装仓颉 SDK。
  #
  # ⚠️ 原来只用 `-add_rpath` 追加，于是顺序是错的。实测构建产物的 rpath：
  #     1. @executable_path/../runtime                              （bundle 相对）
  #     2. /Users/kelthas/.local/share/cangjie/current/runtime/...   ← 构建机绝对路径
  #     3. /Users/kelthas/.local/share/cangjie/current/tools/lib    ← 构建机绝对路径
  #     4. @executable_path/../Frameworks                           ← 追加在最后
  #
  # 两个后果：
  #   1. **本地能跑不能证明分发可用**。只要开发机装了 SDK，前两条就命中，
  #      bundle 里的 Frameworks 一次都用不上 —— 「跑起来了」证明的是
  #      「这台机器装了 SDK」，不是「app 自包含」。这正是本项目反复栽的
  #      「用本地成功当成分发可用」。
  #   2. 把 `/Users/kelthas/...` 写进了要分发的二进制，还硬编码 arm64。
  #
  # 修法：**重写** rpath 而不是追加 —— 先逐条删干净，再按 bundle 相对顺序加回。
  # 只改 bundle 里这份拷贝，不动 moonGit/target/release/bin/main（开发时仍需 SDK 路径）。
  EMBEDDED="$APP_BUNDLE/Contents/Resources/moongit"
  if [ -x "$EMBEDDED" ]; then
    # ⚠️ 三条实测踩出来的坑，写在这里免得下一个人再踩一遍：
    #
    # (1) `otool -l` 在 LC_RPATH 之后**不是**紧跟 path 那一行，而是先一行
    #     `cmdsize 56`。所以 `awk '/LC_RPATH/{getline; print $2}'` 取到的是
    #     cmdsize 的数值（实测得到 "40"），不是路径。正确写法是匹配以 path 开头的那行。
    #
    # (2) **install_name_tool 拒绝修改已签名的二进制**。引擎是 cjpm 编出来、
    #     带签名的，直接改会失败；又因为 `set -e` 下裸命令失败会**当场终止构建**，
    #     症状极具迷惑性：构建在「已内嵌引擎」那行之后就没动静了，退出码 1，
    #     后面什么都不打印（实测连栽三次才定位到）。先剥签名再改，bundle 最后统一重签。
    #
    # (3) **`-delete_rpath` 收的是 rpath 的路径字符串，不是序号**。
    #     传序号会得到：
    #         no LC_RPATH load command with path: 1 found ...
    #     而它的退出码仍是 0 ⇒ 光看 `if` 判断不出来，会以为删成功了。
    #     —— 又一个「失败但不报错」的形态，删不掉的东西会让绝对路径留在产物里。
    embedded_rpaths() {
      otool -l "$1" 2>/dev/null | awk '$1 == "path" { print $2 }'
    }
    codesign --remove-signature "$EMBEDDED" 2>/dev/null || true
    while :; do
      FIRST_RPATH="$(embedded_rpaths "$EMBEDDED" | head -1)"
      # ⚠️ 不能写成 `[ -z "$X" ] && break`：`set -e` 下 `a && b` 作为独立语句，
      # 在 a 为假时整体返回非零 ⇒ 脚本当场退出。看起来等价的写法在 set -e 下会要命。
      if [ -z "$FIRST_RPATH" ]; then break; fi
      install_name_tool -delete_rpath "$FIRST_RPATH" "$EMBEDDED" 2>/dev/null || break
    done
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$EMBEDDED" 2>/dev/null \
      || echo "⚠ 写入 @executable_path/../Frameworks 失败" >&2
    install_name_tool -add_rpath "@executable_path/../runtime" "$EMBEDDED" 2>/dev/null \
      || echo "⚠ 写入 @executable_path/../runtime 失败" >&2
    LEFT="$(embedded_rpaths "$EMBEDDED")"
    if printf '%s\n' "$LEFT" | grep -q '^/'; then
      echo "✗ 内嵌引擎的 rpath 里仍有构建机绝对路径，分发出去会失效：" >&2
      printf '%s\n' "$LEFT" | sed 's/^/  /' >&2
      DEFECT=1
    elif [ -z "$LEFT" ]; then
      echo "✗ 内嵌引擎的 rpath 被清空了却没写回来，引擎将无法启动" >&2
      DEFECT=1
    else
      echo "   内嵌引擎 rpath 已重写为 bundle 相对路径："
      printf '%s\n' "$LEFT" | sed 's/^/     /'
    fi

    # ⚠️ 必须**显式**给内嵌引擎补签，否则它会变成未签名的 arm64 二进制。
    #
    # 实测栽在这里：`codesign --force --deep --sign - "$APP_BUNDLE"` **不会**签
    # `Contents/Resources/` 下的文件 —— `--deep` 只把 `Contents/MacOS`、
    # `Frameworks/`、`PlugIns/`、`XPCServices/` 这些位置当嵌套代码，
    # Resources 里的东西在它眼里是「资源」，不是「代码」。
    #
    # 而 install_name_tool 又拒绝对已签名二进制动手（见上面坑 (2)），
    # 于是流程变成：剥签名 → 改 rpath → bundle 签名跳过它 → 交付一份裸的。
    #
    # 后果非常隐蔽：未签名的 arm64 可执行文件在 macOS 上被 AMFI 直接
    # `SIGKILL`（exit 137、stdout/stderr 全 0 字节，连报错都没有）。
    # app 的引擎发现会静默退回到 ~/.local/bin 或 PATH ——
    # 于是「本机能跑」，但打出来的 app 里那份引擎**从来没被执行过一次**。
    # 这跟这次要修的 rpath 缺陷是同一族：拿本机的成功冒充分发的可用。
    if ! EMBED_SIGN_OUT="$(codesign --force --sign - "$EMBEDDED" 2>&1)"; then
      echo "✗ 内嵌引擎补签失败（未签名的 arm64 二进制在 macOS 上会被直接杀掉）：" >&2
      printf '%s\n' "$EMBED_SIGN_OUT" | sed 's/^/  /' >&2
      DEFECT=1
    fi
  fi
  echo "   已内嵌仓颉运行时（$(ls "$APP_BUNDLE/Contents/Frameworks" | wc -l | tr -d ' ') 个 dylib）"
fi

# 广告（ad-hoc）签名：本机运行足够
#
# ⚠️ 原来是 `codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true`
# —— **退出码和错误输出一起被丢掉**。签名失败时构建照样往下走，
# 最后打印「✓ 构建完成」，交付一个自己都不知道签没签上的 app。
# 「构建对自己的成败说谎」和这项目里反复修的那族缺陷是同一族：
# 读不出来/没做成，被报成「做完了」。
#
# 所以：签名失败要**响**（不阻断打包流程，但必须打印原始错误），
# 并且事后真的验一次 —— 签名命令返回 0 也不等于签名自洽。
if ! SIGN_OUT="$(codesign --force --deep --sign - "$APP_BUNDLE" 2>&1)"; then
  echo "✗ 签名失败（不阻断打包，但这个 app 的签名不可信）：" >&2
  printf '%s\n' "$SIGN_OUT" | sed 's/^/  /' >&2
  DEFECT=1
fi
if VERIFY_OUT="$(codesign --verify --deep --strict "$APP_BUNDLE" 2>&1)"; then
  echo "✓ 已 ad-hoc 签名并校验通过"
else
  echo "✗ 签名校验不通过：" >&2
  printf '%s\n' "$VERIFY_OUT" | sed 's/^/  /' >&2
  DEFECT=1
fi

# ⚠️ 上面那条 bundle 级校验**查不出内嵌引擎的问题**，它只看 bundle 自身的
# 代码目录，`Contents/Resources/` 下的东西按定义就不是嵌套代码。
# 实测：引擎完全未签名时，`codesign --verify --deep --strict "$APP_BUNDLE"`
# 依然返回 0 并打印成功，而那个引擎在 macOS 上根本跑不起来。
#
# 所以对内嵌引擎要**单独**验，而且必须**真的执行它** ——
# 「检查通过」和「东西能用」之间隔着 AMFI、dyld、rpath 三道闸，
# 任何只读元数据的检查都跨不过去。只有 fork 一次真进程才算数。
if [ -x "$APP_BUNDLE/Contents/Resources/moongit" ]; then
  EMBED="$APP_BUNDLE/Contents/Resources/moongit"
  if ! codesign --verify --strict "$EMBED" >/dev/null 2>&1; then
    echo "✗ 内嵌引擎未通过签名校验：" >&2
    codesign -dv "$EMBED" 2>&1 | sed 's/^/  /' >&2
    DEFECT=1
  fi
  # 冒烟：在**空环境**下执行一次。
  # `env -i` 是关键 —— 它抹掉 CANGJIE_HOME / PATH / DYLD_*，
  # 于是「能跑」只能来自 bundle 自己的 Frameworks。
  # 一旦 rpath 里还留着构建机绝对路径，这条在开发机上仍会过
  # （因为开发机装了 SDK），所以它验证的是 bundle 自包含，不是「本机能跑」。
  SMOKE_HOME="${TMPDIR:-/tmp}/deepdolphin-build-smoke-$$"
  mkdir -p "$SMOKE_HOME"
  if SMOKE_OUT="$(env -i HOME="$SMOKE_HOME" PATH=/usr/bin:/bin \
        DEEPGIT_HOME="$SMOKE_HOME/home" "$EMBED" --help 2>&1)"; then
    echo "✓ 内嵌引擎脱离 SDK 可执行（空环境冒烟通过）"
  else
    SMOKE_RC=$?
    echo "✗ 内嵌引擎在空环境下跑不起来（exit=${SMOKE_RC}）：" >&2
    # 137=SIGKILL，几乎必然是未签名被 AMFI 杀；139=SIGSEGV，多半是 dylib 没找到
    case "$SMOKE_RC" in
      137) echo "  137=SIGKILL：二进制未签名，macOS 直接杀掉且不输出任何东西" >&2 ;;
      139) echo "  139=SIGSEGV：多半是 Frameworks 里的 dylib 没解析到" >&2 ;;
    esac
    [ -n "$SMOKE_OUT" ] && printf '%s\n' "$SMOKE_OUT" | head -5 | sed 's/^/  /' >&2
    DEFECT=1
  fi
  # 清理沙箱：跟本仓其他脚本同一套约定（mavis-trash 优先，rm -rf 兜底）。
  # ⚠️ 不能用 `rmdir` —— 引擎在里面建了 `home/`，目录非空，rmdir 会失败，
  # 于是每次构建都在 TMPDIR 里留一个孤儿目录（实测跑 3 次就攒了 3 个）。
  if command -v mavis-trash >/dev/null 2>&1; then
    mavis-trash -- "$SMOKE_HOME" >/dev/null 2>&1 || rm -rf "$SMOKE_HOME"
  else
    rm -rf "$SMOKE_HOME"
  fi
fi

# 契约检查：拿引擎的真实输出喂客户端的真实模型。
#
# 为什么放在 build 末尾：它挡的是「引擎改了 JSON 键名而客户端模型没跟上」——
# 那类缺陷编译期发现不了、代码评审也看不出来（两边各自看着都合理），
# 只在真解码时才炸。P0-1 就是 100% 必现的解码失败，靠人工审计没抓住。
#
# 失败不阻断构建：契约不一致有时是预期的（比如引擎先改、客户端后跟），
# 但必须在构建输出里显眼。用 CONTRACT_STRICT=1 让它阻断。
if [ -x "$DIR/scripts/contract-check.sh" ]; then
  echo ""
  echo "── 契约检查 ──────────────────────────────────"
  if "$DIR/scripts/contract-check.sh"; then
    echo "✓ 契约一致"
  else
    if [ "${CONTRACT_STRICT:-0}" = "1" ]; then
      echo "✗ 契约不一致（CONTRACT_STRICT=1，构建中止）" >&2
      exit 1
    fi
    echo "⚠ 契约不一致 —— 构建继续，但客户端可能解码失败。详见上面各项。" >&2
  fi
fi

# 目录检查（models.dev 快照解析层）。
# 与契约检查分开的原因：契约检查管**跨进程契约**，这里管纯客户端内部的两个 P0 ——
#   · P0-1 打包版 AI 永久不可用（自死锁，swift run 根本触发不到那条分支）
#   · P0-2 225 个 provider 的上下文窗口与成本全为 nil（读错快照形状）
# 两者都是「编译过、代码评审看不出、只在打包版发作」。
# 同样受 CONTRACT_STRICT 控制。
if [ -x "$DIR/scripts/catalog-check.sh" ]; then
  echo ""
  echo "── 目录检查 ──────────────────────────────────"
  if "$DIR/scripts/catalog-check.sh"; then
    echo "✓ 目录层一致"
  else
    if [ "${CONTRACT_STRICT:-0}" = "1" ]; then
      echo "✗ 目录层不一致（CONTRACT_STRICT=1，构建中止）" >&2
      exit 1
    fi
    echo "⚠ 目录层不一致 —— 构建继续。打包版 AI 可能不可用。" >&2
  fi
fi

# agent 检查（工具调用轮次上限的收尾判定）。
# 覆盖 P0-4：原来到上限直接抛错，把本轮模型**已经写出来的**答案丢掉 ——
# 用户看到一句「已达上限」，而答案就在手边。判定抽成了 AgentOutcome 纯函数，
# 就是为了能被这个检查直接编译源码来测。
if [ -x "$DIR/scripts/agent-check.sh" ]; then
  echo ""
  echo "── agent 检查 ─────────────────────────────────"
  if "$DIR/scripts/agent-check.sh"; then
    echo "✓ agent 收尾判定正确"
  else
    if [ "${CONTRACT_STRICT:-0}" = "1" ]; then
      echo "✗ agent 收尾判定有误（CONTRACT_STRICT=1，构建中止）" >&2
      exit 1
    fi
    echo "⚠ agent 收尾判定有误 —— 构建继续。" >&2
  fi
fi

# 客户端状态判定检查（开机自启开关回滚 P1-10 / 刷新请求合并 P1-12）。
# 这两个判定原本内联在视图与生命周期代码里，运行时抓不到 ——
# 抽成 ClientDecisions 纯函数后才可以编译源码来测。
if [ -x "$DIR/scripts/client-check.sh" ]; then
  echo ""
  echo "── 客户端检查 ────────────────────────────────"
  if "$DIR/scripts/client-check.sh"; then
    echo "✓ 客户端状态判定正确"
  else
    if [ "${CONTRACT_STRICT:-0}" = "1" ]; then
      echo "✗ 客户端状态判定有误（CONTRACT_STRICT=1，构建中止）" >&2
      exit 1
    fi
    echo "⚠ 客户端状态判定有误 —— 构建继续。" >&2
  fi
fi

# markdown 检查（块级解析）。
# 覆盖两件事：解析正确性（解析器抽到独立文件时最容易丢行内记号剥离与标题层级），
# 以及**不重复解析** —— 原来 blocks 是 computed property，body 每次求值都全量重解析，
# 200KB 的 README 是每帧的主线程工作。
if [ -x "$DIR/scripts/markdown-check.sh" ]; then
  echo ""
  echo "── markdown 检查 ─────────────────────────────"
  if "$DIR/scripts/markdown-check.sh"; then
    echo "✓ markdown 解析正确且不重复解析"
  else
    if [ "${CONTRACT_STRICT:-0}" = "1" ]; then
      echo "✗ markdown 解析有误（CONTRACT_STRICT=1，构建中止）" >&2
      exit 1
    fi
    echo "⚠ markdown 解析有误 —— 构建继续。" >&2
  fi
fi

echo ""
if [ "${DEFECT:-0}" = "1" ]; then
  # 打包流程走完了，但签名这一环没过 —— 结尾不能还说「构建完成」。
  # 宁可显式说「部分完成」，也不要在一件没做成的事上盖个完成章。
  echo "⚠ 打包完成，但**自检未通过**（签名 / rpath / 内嵌引擎冒烟）：$APP_BUNDLE"
  echo "  上面的错误是真的，请先解决再分发 —— 带着它分出去，"
  echo "  用户拿到的是一台「本地能跑、别人机器上打不开」的 app。"
  echo "  注意：app 会静默退回到 ~/.local/bin 或 PATH 上的引擎，"
  echo "  所以本机一切正常并不代表内嵌引擎可用。"
  exit 1
fi
echo "✓ 构建完成：$APP_BUNDLE"
echo "  安装：cp -R \"$APP_BUNDLE\" /Applications/ && open /Applications/$APP_NAME.app"
