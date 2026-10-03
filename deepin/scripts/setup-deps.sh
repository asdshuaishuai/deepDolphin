#!/bin/sh
# deepDolphin deepin 客户端 —— 用户态工具链包装脚本安装器。
#
# 前提：先跑 scripts/bootstrap-deps.py --download，把 deepin crimson 仓库的
# 工具链与 Qt6/DTK6 开发闭包解包到 ~/.local/dd-sysroot。
# 本脚本在 ~/.local/bin（已在 PATH）生成包装脚本，使 cmake / g++ / gcc /
# c++ / pkg-config / ctest 无 root 可用：
#   · 编译器：指到 sysroot 里的 gcc-13，-B 找 cc1plus，-isystem 挂 sysroot
#     开发头文件（libc 头文件用容器原生 /usr/include，版本一致不冲突）
#   · cmake/ctest：LD_LIBRARY_PATH 指向 sysroot，moc/rcc 等子进程同样受益
#   · pkg-config：PKG_CONFIG_SYSROOT_DIR + LIBDIR 指向 sysroot 的 .pc
# 运行期：构建产物链接时已由 -rpath 指到 sysroot，冒烟用
#   env LD_LIBRARY_PATH=~/.local/dd-sysroot/usr/lib/x86_64-linux-gnu 即可。
set -e
S="$HOME/.local/dd-sysroot"
BIN="$HOME/.local/bin"
GCCM="$S/usr/bin/x86_64-linux-gnu-g++-13"
[ -x "$GCCM" ] || { echo "错误：$GCCM 不存在，先跑 bootstrap-deps.py --download" >&2; exit 1; }
mkdir -p "$BIN"

GXX_LIB="$S/usr/lib/gcc/x86_64-linux-gnu/13"
CXXINC="-isystem $S/usr/include/c++/13 -isystem $S/usr/include/x86_64-linux-gnu/c++/13 -isystem $S/usr/include/c++/13/backward -isystem $S/usr/lib/gcc/x86_64-linux-gnu/13/include -isystem $S/usr/include -isystem $S/usr/include/x86_64-linux-gnu"

for name in g++ gcc c++; do
  cat > "$BIN/$name" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="$S/usr/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$GCCM" -B"$GXX_LIB/" -B"$S/usr/bin/x86_64-linux-gnu-" -L"$S/usr/lib/x86_64-linux-gnu" $CXXINC "\$@"
EOF
  chmod +x "$BIN/$name"
done

for tool in cmake ctest cpack; do
  [ -x "$S/usr/bin/$tool" ] || continue
  cat > "$BIN/$tool" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="$S/usr/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$S/usr/bin/$tool" "\$@"
EOF
  chmod +x "$BIN/$tool"
done

cat > "$BIN/pkg-config" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="$S/usr/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PKG_CONFIG_SYSROOT_DIR="$S"
export PKG_CONFIG_LIBDIR="$S/usr/lib/x86_64-linux-gnu/pkgconfig:$S/usr/lib/pkgconfig:$S/usr/share/pkgconfig"
exec "$S/usr/bin/pkgconf" "\$@"
EOF
chmod +x "$BIN/pkg-config"

echo "已生成包装脚本：g++ gcc c++ cmake ctest cpack pkg-config → $BIN"
echo "自检：$BIN/g++ --version && $BIN/cmake --version && $BIN/pkg-config --modversion libsecret-1"
