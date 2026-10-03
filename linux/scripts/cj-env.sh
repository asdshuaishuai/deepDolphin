#!/usr/bin/env bash
# cj-env.sh —— 仓颉运行时环境（被 run.sh / dev-launch.sh 共同 source）。
#
# 抽出来是因为这段逻辑**曾经抄成两份**，而两份都写错了同一个地方：
# 原来按 `uname -m` 选目录，Linux 上 `uname -m` 是 x86_64，落进
# `grep -m1 "^darwin_"` 的兜底分支 → 匹配不到 → CJO 变空串 →
# 库路径指到 `runtime/lib/` 空目录 → 启动报
# `error while loading shared libraries: libcangjie-runtime.so`。
# 症状像「仓颉没装好」，重装 SDK 永远修不好。
#
# 目录名的实际形状是 `<os>_<arch>_cjnative`（本机 darwin_aarch64_cjnative），
# 所以**先按操作系统定前缀，再按磁盘上真实存在的目录挑** ——
# 架构那一段不硬编，因为仓颉各版本写过 arm64/aarch64、x86_64/amd64 两种。
#
# 本文件不设 `set -e` / `set -u`，由调用方决定；出错时用 `dd_die` 退出。

# 退出并给出可操作的提示，别让脚本带着空路径继续跑。
dd_die() {
  echo "$1" >&2
  exit 1
}

# 必须在 source envsetup.sh **之前**调用：
# 仓颉的 envsetup.sh 会直接读 DYLD_LIBRARY_PATH / LD_LIBRARY_PATH，
# 调用方若开了 `set -u`，未定义即触发 unbound variable 并静默退出整个脚本。
dd_cj_pre_source() {
  export DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
}

# envsetup.sh 之后调用：算出 CJO 并摆好库路径。
dd_cj_setup_runtime() {
  local os_prefix
  case "$(uname -s)" in
    Darwin) os_prefix="darwin" ;;
    Linux)  os_prefix="linux" ;;
    *)      os_prefix="" ;;
  esac
  [ -n "$os_prefix" ] || dd_die "认不出当前操作系统（uname -s = $(uname -s)），只处理 macOS 与 Linux。"

  local cjo
  cjo="$(ls "$CANGJIE_HOME/runtime/lib" 2>/dev/null | grep -m1 "^${os_prefix}_" || true)"
  [ -n "$cjo" ] || dd_die "找不到仓颉运行时：$CANGJIE_HOME/runtime/lib 下没有 ${os_prefix}_* 目录
  列一下看看：ls \"$CANGJIE_HOME/runtime/lib\"
  若目录是空的，说明 SDK 没装全，重装 1.0.5 LTS。"

  export CJO="$cjo"
  export DYLD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/$CJO:$CANGJIE_HOME/tools/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/$CJO:$CANGJIE_HOME/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}
