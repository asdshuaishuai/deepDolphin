#!/usr/bin/env bash
# check-icon.sh —— 判据：「所有平台用同一套 icon」这句约束真的成立吗？
#
# 这句话一旦没有机器检查，退化得很快：某天有人给 macOS 换图标，
# 直接在 macos/ 里放一个 AppIcon.icns；另一个人给 Linux 塞一张 png。
# 两边都跑得好好的，只是从此「同一套」只剩名字。
#
# 所以这里查的不是「图标好不好看」，而是**结构上有没有分家**，以及 CMP 客户端**有没有真的接上**：
# 任何一条红都意味着：图标被复制走了、公共产物没跟上母版、窗口 / 打包器 / 桌面项里有一处还在用默认图。
# 2026-11-28 起客户端只有 CMP 一份；macos / linux / deepin / windows / harmonyos 五个原生端已冻结，
# 关于它们的检查只报不判红。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CLIENT="$REPO/client"
APP_ID="canopy"

fail=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; fail=$((fail + 1)); }
note() { echo "  · $1（冻结端，不判红）"; }

echo "› 1. 平台与客户端目录不得自带图标（唯一真相源在 assets/icon/）"
# 复制出去是最常见的分家方式。逐个目录查，越界就是红。
stray=$(find "$REPO/macos" "$REPO/linux" "$REPO/windows" "$REPO/harmonyos" "$REPO/deepin" "$CLIENT/src" \
        -maxdepth 6 \
        \( -name '*.icns' -o -name '*.ico' -o -name 'AppIcon*' -o -name 'mark*.png' -o -name "$APP_ID.png" \) \
        -not -path '*/vendor/*' -not -path '*/target/*' -not -path '*/.build/*' -not -path '*/build/*' \
        2>/dev/null)
if [[ -z "$stray" ]]; then
  ok "各平台目录与 client/src 下都没有自己的图标文件"
else
  bad "出现了自有图标（应由 assets/icon/out/ 统一提供，客户端资源在构建时并入）："
  echo "$stray" | sed 's/^/      /'
fi

echo "› 2. 母版：SVG 是真相源，mark.png 是它的同步位图，小尺寸另有母版"
if [[ -f "$HERE/mark.svg" && -f "$HERE/mark-small.svg" ]]; then
  ok "assets/icon/mark.svg、mark-small.svg 存在"
else
  bad "缺母版：mark.svg / mark-small.svg"
fi
if [[ -f "$HERE/mark.png" ]]; then
  bbox=$(python3 - "$HERE/mark.png" <<'PY' 2>/dev/null || echo "PIL-缺"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
print(im.split()[3].getbbox())
PY
)
  if [[ "$bbox" == "(0, 0, 1024, 1024)" ]]; then
    ok "mark.png 1024×1024 满幅"
  else
    bad "mark.png 不是满幅：alpha 包围盒 ${bbox}（期望 (0, 0, 1024, 1024)）"
  fi
else
  bad "缺 assets/icon/mark.png"
fi

echo "› 3. 公共产物齐全、尺寸正确、内容与母版一致"
missing=0
for s in 16 24 32 48 64 128 256 512; do
  p="$HERE/out/linux/hicolor/${s}x${s}/apps/$APP_ID.png"
  [[ -f "$p" ]] || { bad "缺 $p"; missing=1; }
done
[[ $missing -eq 0 ]] && ok "hicolor 八个尺寸齐全"
[[ -f "$HERE/out/AppIcon.ico" ]] && ok "out/AppIcon.ico（Windows）" || bad "缺 out/AppIcon.ico"
# icns 以前只在 macOS 上查（那时只有 iconutil 能生成）；现在任何平台都能写，任何平台都要有
[[ -f "$HERE/out/macos/AppIcon.icns" ]] && ok "out/macos/AppIcon.icns（macOS）" || bad "缺 out/macos/AppIcon.icns"
if python3 "$HERE/make-icons.py" --check > /tmp/canopy-icon-check.out 2>&1; then
  ok "make-icons.py --check：每个产物按档位与母版逐像素一致"
else
  bad "make-icons.py --check 不过（改了母版没重导？）"
  sed 's/^/      /' /tmp/canopy-icon-check.out | tail -12
fi

echo "› 4. CMP 客户端：窗口图标接上了（不传就是 Compose 自带的 Kotlin 图标）"
MAIN="$CLIENT/src/jvmMain/kotlin/canopy/Main.kt"
if grep -q 'icon = painterResource("icon/canopy.png")' "$MAIN"; then
  ok "Window(…) 传了 icon = painterResource(\"icon/canopy.png\")"
else
  bad "Main.kt 的 Window(…) 没传 icon —— 窗口 / 任务栏显示的是 Kotlin 默认图标"
fi

echo "› 5. CMP 客户端：图标资源与包图标都取自 assets/icon/out/，资源目录里不留第二份"
GRADLE="$CLIENT/build.gradle.kts"
for needle in \
  'from(appIconRoot.resolve("png/256.png"))' \
  'iconFile.set(appIconRoot.resolve("png/512.png"))' \
  'iconFile.set(appIconRoot.resolve("AppIcon.ico"))' \
  'iconFile.set(appIconRoot.resolve("macos/AppIcon.icns"))' \
  'val appIconRoot = projectDir.parentFile.resolve("assets/icon/out")'; do
  if grep -qF "$needle" "$GRADLE"; then ok "build.gradle.kts：$needle"; else bad "build.gradle.kts 缺：$needle"; fi
done
copies=$(find "$CLIENT/src/jvmMain/resources" -type f \
         \( -name "$APP_ID.png" -o -name '*.ico' -o -name '*.icns' \) 2>/dev/null)
if [[ -z "$copies" ]]; then
  ok "client/src/jvmMain/resources 里没有图标拷贝"
else
  bad "资源目录里放了图标拷贝（第二份迟早和母版分家）："
  echo "$copies" | sed 's/^/      /'
fi

echo "› 6. 桌面项指向打包器拷出来的那份图标"
if grep -q '^Icon=\$APP_DIR/lib/canopy.png$' "$CLIENT/scripts/install-user.sh"; then
  ok "install-user.sh 的桌面项 Icon= \$APP_DIR/lib/canopy.png（jpackage 按 linux.iconFile 拷到这里）"
else
  bad "install-user.sh 的桌面项 Icon= 不是 \$APP_DIR/lib/canopy.png"
fi

echo "› 7. 平台图标生成器不手绘，全部来自同一母版"
if grep -qE 'ImageDraw|draw\.|ellipse\(|polygon\(' "$HERE/make-icons.py" 2>/dev/null; then
  bad "make-icons.py 里有绘制调用 —— 平台产物可能已与母版分家"
else
  ok "make-icons.py 只做缩放与打包，不重新绘制"
fi

echo "› 8. 冻结的原生端（只报不判红）"
if grep -q 'assets/icon/out/macos/AppIcon.icns' "$REPO/macos/build.sh" 2>/dev/null; then
  note "macos/build.sh 引用公共 out/macos/AppIcon.icns"
fi
dt="$HERE/out/linux/$APP_ID.desktop"
if [[ -f "$dt" ]] && grep -qx "Icon=$APP_ID" "$dt"; then
  note "out/linux/$APP_ID.desktop 的 Icon= 与 hicolor 图标名一致（$APP_ID）"
fi
if grep -q 'identifier: Some("canopy")' "$REPO/linux/src/main.cj" 2>/dev/null; then
  note "linux/src/main.cj 的 AppMetadata.identifier = canopy"
else
  note "linux/src/main.cj 的 AppMetadata.identifier 不是 canopy（冻结端保留旧名 deepdolphin）"
fi

if [[ $fail -eq 0 ]]; then
  echo
  echo "✓ 图标一致性全绿：窗口、打包器、桌面项用的是同一套，且与母版一致"
  exit 0
fi
echo
echo "✗ $fail 处不一致"
exit 1
