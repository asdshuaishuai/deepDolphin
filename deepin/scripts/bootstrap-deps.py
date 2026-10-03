#!/usr/bin/env python3
"""deepDolphin deepin 客户端 —— 无 root 开发环境自举。

在无 root、无 apt 的环境（如 linglong 容器）里，从 deepin 官方仓库拉取
Packages 索引，解析「构建目标 + 依赖闭包 - 本机已装」，把缺失的 .deb
解包到用户目录 sysroot（默认 ~/.local/dd-sysroot），供 setup-deps.sh
生成的包装脚本（g++/cmake/pkg-config）使用。不安装、不改系统。

用法：python3 scripts/bootstrap-deps.py [--list REGEX] [--sysroot DIR]
目标闭包：gcc/g++（与原生 libstdc++6 同主版本）、cmake、pkgconf、
qt6-base-dev、libdtk6{core,gui,widget}-dev、libsecret-1-dev、ECM。
"""

import argparse
import lzma
import gzip
import io
import os
import re
import shutil
import subprocess
import sys
import urllib.request

BASE = os.environ.get("DD_REPO", "https://community-packages.deepin.com/beige")
SUITE = os.environ.get("DD_SUITE", "crimson")
COMPONENTS = ["main", "commercial", "community"]
ARCH = "amd64"
HOME = os.path.expanduser("~")
SYSROOT = os.path.join(HOME, ".local", "dd-sysroot")
DEB_CACHE = os.path.join(HOME, ".local", "dd-debs")


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "dd-bootstrap/1.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def load_packages_index() -> dict:
    """解析各组件 binary-amd64/Packages，合并成 {name: [stanza, ...]}。"""
    index: dict = {}
    for comp in COMPONENTS:
        for suffix, opener in (("Packages.xz", lzma.open), ("Packages.gz", gzip.open)):
            url = f"{BASE}/dists/{SUITE}/{comp}/binary-{ARCH}/Packages{'.xz' if suffix.endswith('xz') else '.gz'}"
            try:
                raw = fetch(url)
            except Exception as e:
                print(f"  · {comp} {suffix}: 不可用（{e}）")
                continue
            with opener(io.BytesIO(raw)) as f:
                text = f.read().decode("utf-8", "replace")
            count = 0
            for stanza in text.split("\n\n"):
                fields: dict = {}
                key = None
                for line in stanza.splitlines():
                    if not line.strip():
                        continue
                    if line[0] in " \t" and key:
                        fields[key] += " " + line.strip()
                    elif ":" in line:
                        key, _, val = line.partition(":")
                        fields[key.strip()] = val.strip()
                name = fields.get("Package")
                if name:
                    index.setdefault(name, []).append(fields)
                    count += 1
            print(f"  · {comp}: {count} 条")
            break
    return index


def load_installed() -> dict:
    """本机 dpkg 已装 {name: version}。"""
    installed = {}
    try:
        out = subprocess.run(
            ["dpkg-query", "-W", "-f=${Package}\t${Version}\t${Status}\n"],
            capture_output=True, text=True, check=True).stdout
    except Exception as e:
        print(f"dpkg-query 失败：{e}")
        return installed
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and "install ok installed" in parts[2]:
            installed[parts[0]] = parts[1]
    return installed


def best_candidate(cands: list) -> dict | None:
    """同名单版本去重：优先本机架构，其次版本号最大。"""
    def vkey(f):
        return (f.get("Architecture") == ARCH, [int(x) if x.isdigit() else x
                for x in re.split(r"[.~+-]", f.get("Version", ""))])
    return max(cands, key=vkey) if cands else None


def dep_names(field: str) -> list:
    """Depends/Recommends 字段 → 包名列表（忽略版本约束，备选全收）。"""
    names = []
    for alt in field.split(","):
        for item in alt.split("|"):
            name = item.strip().split(" ")[0].split(":")[0]
            if name and not name.startswith("$"):
                names.append(name)
    return names


def resolve(index: dict, installed: dict, seeds: list, force: set = frozenset()) -> tuple:
    """BFS 闭包。返回 (待解包候选, 因缺包失败的名字列表)。"""
    provides = {}
    for name, cands in index.items():
        for f in cands:
            for p in dep_names(f.get("Provides", "")):
                provides.setdefault(p, set()).add(name)
    todo, seen, missing = list(seeds), set(), []
    picked: dict = {}
    while todo:
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        if name in installed and name not in force:
            continue
        cands = index.get(name) or [index[p] for p in provides.get(name, []) if p in index]
        flat = [c for group in cands for c in (group if isinstance(group, list) else [group])]
        chosen = best_candidate(flat if flat else [])
        if not chosen:
            missing.append(name)
            continue
        chosen_name = chosen["Package"]
        if chosen_name in picked or (chosen_name in installed and chosen_name not in force):
            continue
        picked[chosen_name] = chosen
        todo.extend(dep_names(chosen.get("Depends", "")))
        todo.extend(dep_names(chosen.get("Pre-Depends", "")))
    return picked, missing


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", help="按正则列出索引中的包名（查包名用）")
    ap.add_argument("--sysroot", default=SYSROOT)
    ap.add_argument("--download", action="store_true", help="下载并解包（默认只解析）")
    ap.add_argument("extra", nargs="*", help="追加的种子包名（补运行库等非依赖项）")
    ap.add_argument("--force", default="", help="逗号分隔的包名：即便本机已装也强制解包进 sysroot（解决 sysroot 库比原生库新导致的符号缺失）")
    args = ap.parse_args()

    print(f"索引：{BASE} dists/{SUITE}")
    index = load_packages_index()
    if args.list:
        pat = re.compile(args.list)
        for name in sorted(index):
            if pat.search(name):
                c = best_candidate(index[name])
                print(f"{name} {c.get('Version') if c else ''}")
        return 0

    installed = load_installed()
    force = {n for n in args.force.split(",") if n}

    def resolve_fn(names: list):
        return resolve(index, installed, names, force)

    # 编译器主版本跟索引走（与原生 libstdc++6 同仓库，ABI 一致）
    gxx = sorted({m.group(1) for n in index if (m := re.match(r"^g\+\+-(\d+)$", n))},
                 key=int)
    major = gxx[-1] if gxx else "12"
    seeds = [f"g++-{major}", f"gcc-{major}", f"cpp-{major}",
             f"libgcc-{major}-dev", f"libstdc++-{major}-dev",
             "cmake", "cmake-data", "pkgconf",
             "qt6-base-dev", "qt6-base-dev-tools",
             "libdtk6core-dev", "libdtk6gui-dev", "libdtk6widget-dev",
             "libsecret-1-dev", "extra-cmake-modules", "libqt6svg6"] + args.extra
    picked, missing = resolve_fn(seeds)
    total = sum(int(f.get("Installed-Size", 0)) for f in picked.values())
    print(f"\n编译器主版本：{major}；闭包 {len(picked)} 个包，"
          f"解压约 {total/1024:.0f} MB → {args.sysroot}")
    if missing:
        print("索引中找不到（含可选降级项，若被硬依赖引用则要处理）：")
        for m in sorted(set(missing)):
            print(f"  ? {m}")

    if not args.download:
        print("\n（--download 才会实际下载解包）")
        return 0

    os.makedirs(DEB_CACHE, exist_ok=True)
    os.makedirs(args.sysroot, exist_ok=True)
    fail = []
    for i, (name, f) in enumerate(sorted(picked.items()), 1):
        fn = os.path.join(DEB_CACHE, os.path.basename(f["Filename"]))
        if not os.path.exists(fn):
            try:
                data = fetch(f"{BASE}/{f['Filename']}")
                with open(fn, "wb") as w:
                    w.write(data)
            except Exception as e:
                print(f"[{i}/{len(picked)}] {name} 下载失败：{e}")
                fail.append(name)
                continue
        r = subprocess.run(["dpkg-deb", "-x", fn, args.sysroot])
        if r.returncode != 0:
            fail.append(name)
        if i % 25 == 0:
            print(f"  … {i}/{len(picked)} 已解包")
    print(f"\n完成：{len(picked)-len(fail)}/{len(picked)} 解包到 {args.sysroot}")

    fix_dangling_symlinks(args.sysroot)

    if fail:
        print("失败：" + ", ".join(sorted(set(fail))))
        return 1
    return 0


def fix_dangling_symlinks(sysroot: str) -> None:
    """把 sysroot 内悬空的 .so 软链补实：目标若在容器原生库目录里就拷进来。

    背景：-dev 包的 libX.so → libX.so.N 指向的运行库若本机已装，闭包不含它，
    dpkg -x 后软链悬空，CMake find_library（跟随链接）会判定不存在。
    """
    native_dirs = ["/usr/lib/x86_64-linux-gnu", "/lib/x86_64-linux-gnu", "/usr/lib"]
    native_index = {}
    for d in native_dirs:
        if os.path.isdir(d):
            for n in os.listdir(d):
                native_index.setdefault(n, os.path.join(d, n))
    fixed = 0
    for root, _, files in os.walk(sysroot):
        for name in files:
            path = os.path.join(root, name)
            if not os.path.islink(path) or os.path.exists(path):
                continue
            target = native_index.get(os.path.basename(os.readlink(path)))
            if target and os.path.isfile(target):
                shutil.copy2(target, path, follow_symlinks=True)
                fixed += 1
    print(f"悬空软链接补实：{fixed} 个（来源：容器原生库目录）")


if __name__ == "__main__":
    sys.exit(main())
