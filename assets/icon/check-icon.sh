#!/usr/bin/env bash
# check-icon.sh —— 判据：「所有平台用同一套 icon」这句约束真的成立吗？
#
# 这句话一旦没有机器检查，退化得很快：某天有人给 macOS 换图标，
# 直接在 macos/ 里放一个 AppIcon.icns；另一个人给 Linux 塞一张 png。
# 两边都跑得好好的，只是从此「同一套」只剩名字。
#
# 所以这里查的不是「图标好不好看」，而是**结构上有没有分家**。
# 任何一条红都意味着：要么图标被复制走了，要么公共产物没生成，
# 要么三处同名（.desktop 名 / hicolor 图标名 / SDL app_id）断链了。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
APP_ID="deepdolphin"

fail=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; fail=$((fail + 1)); }

echo "› 1. 平台目录不得自带图标（唯一真相源在 assets/icon/）"
# 复制出去是最常见的分家方式。逐个平台查，越界就是红。
stray=$(find "$REPO/macos" "$REPO/linux" "$REPO/windows" "$REPO/harmonyos" \
        -maxdepth 2 \
        \( -name '*.icns' -o -name '*.ico' -o -name 'AppIcon*' -o -name '*icon*.png' \) \
        -not -path '*/vendor/*' -not -path '*/target/*' -not -path '*/.build/*' \
        2>/dev/null)
if [[ -z "$stray" ]]; then
  ok "三个平台目录下都没有自己的图标文件"
else
  bad "平台目录里出现了自有图标（应由 assets/icon/out/ 统一提供）："
  echo "$stray" | sed 's/^/      /'
fi

echo "› 2. 母版存在且满幅（无透明边距）"
if [[ -f "$HERE/mark.png" ]]; then
  ok "assets/icon/mark.png 存在"
  # 满幅 = alpha 包围盒顶到四条边。原来的 macOS 图标四边各留 83px 透明边距，
  # 直接丢给 Linux 启动器后图标小一圈（内容只占 84%）。
  bbox=$(python3 - "$HERE/mark.png" <<'PY' 2>/dev/null || echo "PIL-缺"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
print(im.split()[3].getbbox())
PY
)
  if [[ "$bbox" == "(0, 0, 1024, 1024)" ]]; then
    ok "母版 1024×1024 满幅"
  else
    bad "母版不是满幅：alpha 包围盒 ${bbox}（期望 (0, 0, 1024, 1024)）"
  fi
else
  bad "缺母版 assets/icon/mark.png"
fi

echo "› 3. 公共产物齐全且尺寸正确"
missing=0
for s in 16 32 48 64 128 256 512; do
  p="$HERE/out/linux/hicolor/${s}x${s}/apps/$APP_ID.png"
  [[ -f "$p" ]] || { bad "缺 $p"; missing=1; }
done
[[ $missing -eq 0 ]] && ok "hicolor 八个尺寸齐全"
[[ -f "$HERE/out/AppIcon.ico" ]] && ok "out/AppIcon.ico（Windows）" || bad "缺 out/AppIcon.ico"
if [[ "$(uname -s)" == "Darwin" ]]; then
  [[ -f "$HERE/out/macos/AppIcon.icns" ]] && ok "out/macos/AppIcon.icns（macOS）" \
    || bad "缺 out/macos/AppIcon.icns"
fi

echo "› 4. macOS 端引用公共 icns，不是自己那份"
if grep -q 'assets/icon/out/macos/AppIcon.icns' "$REPO/macos/build.sh" 2>/dev/null; then
  ok "macos/build.sh 从 assets/icon/out/ 取图标"
else
  bad "macos/build.sh 没有引用公共图标路径"
fi

echo "› 5. Linux 三处同名（.desktop 名 / hicolor 图标名 / SDL app_id）"
# 这三样任何一个对不上，症状都是「窗口起来了但任务栏没图标」，
# 从现象几乎反推不出原因，所以只能靠机器查。
dt="$HERE/out/linux/$APP_ID.desktop"
if [[ -f "$dt" ]]; then
  if grep -qx "Icon=$APP_ID" "$dt"; then
    ok ".desktop 的 Icon= 与图标名一致（${APP_ID}）"
  else
    bad ".desktop 的 Icon= 与图标名不一致"
  fi
else
  bad "缺 out/linux/$APP_ID.desktop"
fi
if grep -q 'identifier: Some("deepdolphin")' "$REPO/linux/src/main.cj" 2>/dev/null; then
  ok "main.cj 的 AppMetadata.identifier = deepdolphin"
else
  bad "main.cj 没有设 AppMetadata.identifier —— 窗口不会向桌面环境报 app_id，任务栏无图标"
fi

echo "› 6. 平台图标生成器不手绘，全部来自同一母版"
if grep -qE 'ImageDraw|draw\.|ellipse\(|polygon\(' "$HERE/make-icons.py" 2>/dev/null; then
  bad "make-icons.py 里有绘制调用 —— 平台产物可能已与母版分家"
else
  ok "make-icons.py 只做缩放与打包，不重新绘制"
fi

if [[ $fail -eq 0 ]]; then
  echo
  echo "✓ 图标一致性全绿：三个平台用的是同一套"
  exit 0
fi
echo
echo "✗ $fail 处不一致"
exit 1
