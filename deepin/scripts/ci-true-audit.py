#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批 CJ · 常驻盘点：shell 脚本里「命令替换内部的 `|| true`」站点。

⚠⚠⚨ **为什么这个脚本必须存在在仓里**（批 CJ 的起因）：
  批 CG / 批 CE / 批 CI 的结论都引用了「`scripts/` 下命令替换内带 `|| true`
  的站点 **N** 处」这个数字 ⇒ 那个数字来自**一次性盘点脚本**（还放在 /tmp 里）
  ⇒ **仓内没有任何东西能重算出它** ⇒ 数字不可复核；
  ⇒ 且实测：换一个盘点器（逐行 + 不剥注释）⇒ 给出**另一个数**
  ⇒ 且原盘点器**行号错位**（报 `:301` 实际在 `:334`）+ 有**假阳性**
  ⇒ ⇒ 「一次性盘点的数字」本身没有门守 ⇒ **不许被当成事实**。

⚠⚠⚨ **口径单一真相源**（批 CF 纪律：绝不复刻）：
  剥注释**直接 import 判据层自己的审计器**（`ci-wiring-audit.py`）
  ⇒ 与 `ci-wiring.sh` / 审计器 / 门侧**同一条 perl/sed**；
  ⇒ 并带**抽取自检**（批 CF 教训：「复用实现的方式本身要有自检」）：
     本脚本产出的剥注释结果必须与 **shell 侧 `strip_comments`** 对同一文件
     **逐字节相同** ⇒ 漂移当场红。

用法：
  ci-true-audit.py --list      列出全部站点（落盘可复核）
  ci-true-audit.py             对照登记册（scripts/ci-true-audit.baseline）判红
"""
import importlib.util
import os
import re
import subprocess
import tempfile
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPTS = HERE

BASELINE = os.path.join(SCRIPTS, 'ci-true-audit.baseline')

# ⚠⚠⚨ **仓库根**（`deepin/` 的上一级）⇒ 登记册的键用它算
#   ⇒ ⚠ 必须是**绝对路径**（本脚本可能被用相对路径调用）
REPO_ROOT = os.path.dirname(ROOT)

# ⚠⚠⚨ 批 DQ · **盘点范围**（**显式目录清单** ⇒ 不靠排除表
#   ⇒ `linux/vendor` 是第三方 ⇒ 天然**不进范围** ⇒ 照批 DB 的口径）
#   ⇒ ⚠ **与恒真探针的 shell 范围对齐**（批 CZ / 批 DB 立的判据层面）
#     ⇒ 「命令替换内带 `|| true` 必须逐条登记」这条承诺
#       **不许只覆盖一半**（实测坐实：mac 侧新增一处 ⇒ 盘点照样绿 ⇒ **全绿假绿**）
#   ⇒ ⚠ 每项带**恒真探针范围基线的口径名** ⇒ 下面**逐范围对账**文件数
#   ⇒ ⇒ 两个盘点**共用同一份范围基线** ⇒ 任何一边把范围改窄 ⇒ 对不上 ⇒ 红
TRUE_SCOPE = (('shell', 'deepin/scripts'), ('macos_shell', 'macos'), ('assets_shell', 'assets'), ('linux_shell', 'linux/scripts'))

# ⚠⚠⚨ **恒真探针的扫描范围基线**（批 BP 立）⇒ 用来**对账**本盘点的范围
SCOPE_BASELINE = os.path.join(SCRIPTS, 'ci-tautology-scope.baseline')

# ⚠⚠⚨ 登记册**条数基线**（批 BC 纪律：清单不许被删）⇒ **恰好**（批 BB 口径）
#   ⇒ 整份登记册被删/被截短 ⇒ 这里就红 ⇒ 门项另有一条盯这一行本身
#   ⇒ ⚠⚠⚨ 批 DQ：范围扩到 mac 侧 + linux 侧 ⇒ 21 → **33**
#     （实测：deepin/scripts 21 + macos 7 + linux/scripts 5 + assets 0）
TRUE_AUDIT_EXPECTED_ROWS = 26


# ══════════════════════════════════════════════════════════════
# 口径：复用判据层自己的审计器（批 CF：绝不复刻剥注释）
# ══════════════════════════════════════════════════════════════
def load_audit():
    """加载 `ci-wiring-audit.py` 为模块（⚠ 文件名带连字符 ⇒ 不能直接 import）。

    ⚠⚠⚨ **必须确认它的 `__main__` 保护** ⇒ 不然 import 会把审计器**跑一遍**
    （审计器会打印报告、可能改状态）⇒ 加载后先断言它没被执行。
    """
    path = os.path.join(SCRIPTS, 'ci-wiring-audit.py')
    spec = importlib.util.spec_from_file_location('ci_wiring_audit', path)
    if spec is None or spec.loader is None:
        sys.exit('✗ 加载审计器失败：%s' % path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)          # ⚠ 该文件有 `if __name__ == "__main__"` 保护
    for fn in ('read_source', 'strip_comments'):
        if not hasattr(mod, fn):
            sys.exit('✗ 审计器里没有 %s() ⇒ 口径无法复用 ⇒ 拒绝继续' % fn)
    return mod


AUDIT = load_audit()


# ══════════════════════════════════════════════════════════════
# 抽取自检（批 CF 教训：复用实现的方式本身要有自检）
# ══════════════════════════════════════════════════════════════
# ⚠⚠⚨ 批 EJ-32 · **自检探针路径必须进程唯一**
#   ⇒ ⇒ 起因（实测复现）：以前三个自检临时文件都是**全局固定**路径
#     （`az-cj-selfcheck-probe.sh` / `az-ds-selfcheck-true.sh` /
#     `az-ds-selfcheck-unv.sh`）⇒ ⇒ **每次跑都重写** ⇒ ⇒ ⇒ **两个并发的进程
#     会互相覆盖** ⇒ ⇒ ⇒ 某一边可能**执行对方**写下的探针/样例
#     ⇒ ⇒ ⇒ 抽出来的 `strip_comments` **不是自己那棵树**的
#     ⇒ ⇒ ⇒ 两侧口径对不上 ⇒ ⇒ ⇒ 报「剥注释口径漂移」⇒ ⇒ ⇒ **假红**
#   ⇒ ⇒ 现在：路径**带 PID** ⇒ ⇒ 进程之间**互不干扰**
#   ⇒ ⇒ ⚠ 同一进程内**复用**同一路径（不每次新建）⇒ ⇒ 不 proliferate
def selfcheck_probe_path(tag):
    """自检探针 / 样例的临时文件路径 —— ⚠⚠⚨ **必须带 PID**（批 EJ-32）。

    ⚠ **带 PID** ⇒ ⇒ 进程之间**互不覆盖** ⇒ ⇒ 并发跑不会互相污染
    ⇒ ⇒ ⇒ 口径不再漂移 ⇒ ⇒ ⇒ 「变异前就红了」那一族**假红**少一个来源。
    """
    return os.path.join(tempfile.gettempdir(),
                        'az-%s-selfcheck-%d.sh' % (tag, os.getpid()))


def shell_strip_comments(path):
    """从 `ci-wiring.sh` **原文抽取** `strip_comments` 并跑一遍
    ⇒ 拿它与审计器的 `strip_comments` 对拍 ⇒ 两边不一致 ⇒ 口径漂移 ⇒ 判红。"""
    wiring = os.path.join(SCRIPTS, 'ci-wiring.sh')
    if not os.access(wiring, os.R_OK):
        sys.exit('✗ ci-wiring.sh 读不了 ⇒ 抽取自检做不了')
    with open(wiring, encoding='utf-8') as fh:
        src = fh.read()
    m = re.search(r'^strip_comments\(\) \{.*?^\}', src, re.S | re.M)
    if not m:
        sys.exit('✗ ci-wiring.sh 里抽不出 strip_comments() ⇒ 抽取自检做不了')
    fn = m.group(0)
    probe = selfcheck_probe_path('cj')
    # ⚠⚠⚨ 批 EJ-31 · **探针必须复刻生产的失败通道**
    #   ⇒ 生产的 `strip_comments` 失败时把文件名写进 `$STRIP_FAIL_FILE`
    #     ⇒ 末尾统一判红 + 指名道姓（批 CG 口径）
    #   ⇒ 探针**没设**这个变量 ⇒ ⇒ 失败分支的 `printf … >> "$STRIP_FAIL_FILE"`
    #     会去写一个**空路径** ⇒ ⇒ 报「cannot create : Directory nonexistent」
    #     ⇒ ⇒ **失败被记成「工具没法写标记」**⇒ ⇒ **诊断指错方向**
    #   ⇒ 现在：探针也落标记 ⇒ 失败时**指名道姓**说是哪个文件剥不了
    # ⚠⚠⚨ **逐行列表**写法（不是一串塞满转义的长行）⇒ ⇒ 门可**逐条整行锚定**
    probe_lines = [
        '#!/bin/sh\n',
        'STRIP_FAIL_FILE="${TMPDIR:-/tmp}/deepdolphin-strip-fail-probe.$$"\n',
        fn,
        '\nstrip_comments "$1"\n',
        '_probe_rc=$?\n',
        'if [ -s "$STRIP_FAIL_FILE" ]; then\n',
        '    printf \'%s\\n\' "✗ 剥注释工具失败（工具坏了 ≠ 没找到）：" >&2\n',
        '    while read -r _probe_f; do printf \'%s\\n\' "$_probe_f" >&2; done < "$STRIP_FAIL_FILE"\n',
        '    rm -f "$STRIP_FAIL_FILE"\n',
        'fi\n',
        'exit $_probe_rc\n',
    ]
    with open(probe, 'w', encoding='utf-8') as fh:
        fh.write(''.join(probe_lines))
    out = subprocess.run(['sh', probe, path], capture_output=True, text=True)
    # ⚠⚠⚨ 批 EJ-32 · **用完即删**（路径带 PID ⇒ 每进程一个 ⇒ 不删就堆）
    try:
        os.unlink(probe)
    except OSError:
        pass
    if out.returncode != 0:
        sys.exit('✗ 抽取出来的 strip_comments 跑不了（rc=%d）⇒ %s'
                 % (out.returncode, out.stderr.strip()[:200]))
    return out.stdout


def selftest_strip_parity(paths):
    """两侧剥注释结果必须**逐字节相同** ⇒ 否则口径漂移 ⇒ 判红。"""
    bad = []
    for p in paths:
        try:
            a = AUDIT.strip_comments(p)
        except Exception as e:                       # noqa: BLE001
            bad.append('%s：审计器侧 %s' % (p, e))
            continue
        b = shell_strip_comments(p)
        if a != b:
            bad.append('%s：两侧剥注释结果不同（审计器 %d 字节 / shell %d 字节）'
                       % (p, len(a), len(b)))
    if bad:
        sys.exit('✗ 抽取自检失败（剥注释口径漂移）：\n  ' + '\n  '.join(bad))
    return True


# ══════════════════════════════════════════════════════════════
# 命令替换跨度扫描（剥注释后 · 跳过引号内的文本）
# ══════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════
# 抽取器自检（批 DS · 批 DF/DN 纪律：自检**真的经过被测的抽取器**）
# ══════════════════════════════════════════════════════════════
def selftest_extractors():
    """两个抽取器（`find_subst_spans` / `scan_file`）的自检。

    ⚠⚠⚨ **批 DF 纪律**：自检必须**真的经过被测的抽取器** ⇒ 样例直接喂进去
      ⇒ 抽取器坏了 ⇒ 自检红 ⇒ 盘点**不会**带着坏抽取器绿着出去。

    ⚠⚠⚨ **批 DS 实测坐实的洞**（不是推演）：把 `find_subst_spans` 的
      **反引号分支**摘掉 ⇒ 新增一处**反引号形态**的 `|| true`
      **不再被发现** ⇒ 而盘点 rc=0 + 审计器 rc=0 + 接线门 rc=0
      ⇒ ⚠⚠⚨ **全绿假绿**。
      ⇒ ⚠ 实测当前登记册里**反引号形态站点 = 0** ⇒ 抽坏那个分支
        **不会**让登记册对不上 ⇒ 才有「静默」的可能。

    ⚠ **每档两条样例**（批 DN 纪律）：「该抽到 N 条」+「不该抽到 0 条」
      ⇒ 只测一边 ⇒ 判反了也能过（⚠ 批 BF 纪律）。
    """
    bad = []
    # ── 档 ① `find_subst_spans`（命令替换跨度扫描）────────────────
    for _label, _text, _want in (
            ('样例 A（$() 形态）', 'x=$(cmd || true)\n', 1),
            ('样例 B（反引号形态 · 批 DS 的洞就在这里）',
             'x=`cmd || true`\n', 1),
            ('样例 C（单引号内不做替换 ⇒ 不是站点）',
             "echo '$(not a subst)'\n", 0)):
        _got = len(find_subst_spans(_text))
        if _got != _want:
            bad.append('find_subst_spans %s：期望抽到 %d 个跨度，实得 %d'
                       % (_label, _want, _got))
    # ⚠ 不只数条数 ⇒ 还要断言跨度**内容**对（否则「抽到 1 个但抽错了」也过）
    _sp = find_subst_spans('x=$(cmd || true)\n')
    if _sp and '|| true' not in _sp[0][2]:
        bad.append('find_subst_spans 样例 A：期望跨度内容含 `|| true`，实得 %r'
                   % _sp[0][2][:40])
    # ── 档 ② `scan_file`（单文件扫描 · 站点 + 分类 + 段）──────────
    _p = selfcheck_probe_path('ds-true')
    try:
        with open(_p, 'w', encoding='utf-8') as _fh:
            _fh.write('x=$(cmd || true)\n')
        _sites = scan_file(_p)
        if len(_sites) != 1:
            bad.append('scan_file 样例 A：期望抽到 1 处站点，实得 %d' % len(_sites))
        elif _sites[0]['kind'] != 'other':
            bad.append('scan_file 样例 A：期望分类 other，实得 %r'
                       % _sites[0]['kind'])
        with open(_p, 'w', encoding='utf-8') as _fh:
            _fh.write('echo hi\n')
        _sites0 = scan_file(_p)
        if len(_sites0) != 0:
            bad.append('scan_file 样例 B：期望抽到 0 处站点，实得 %d'
                       % len(_sites0))
    finally:
        if os.path.exists(_p):
            os.unlink(_p)
    return bad

def find_subst_spans(text):
    """找出所有 `$( ... )` 与反引号 `...` 的跨度（返回**绝对下标**对）。

    ⚠⚠⚨ **shell 词法：单引号 vs 双引号不一样**（实测踩出来的坑）：
      · `echo '$(foo || true)'` ⇒ **单引号内**不做替换 ⇒ `$(` 是字面量 ⇒ **不是站点**；
      · `n="$(cmd || true)"`      ⇒ **双引号内照样做替换** ⇒ `$(` **是**站点；
      ⇒ ⚠⚠⚨ 之前这版把**双引号也当成跳过** ⇒ 结果只认出 2 处（漏了绝大多数）
        ⇒ ⚠ **教训：词法规则不许凭印象写，必须实测**（批 CG 纪律）。

    ⚠⚠⚨ **必须处理嵌套括号**：`$(echo $(date))` 的外层跨度到**配对**的 `)`。
    ⚠⚠⚨ **必须处理跨度内部的引号上下文**（`$(echo "a'b")` 里那个 `'`
      不结束外层的双引号 ⇒ 各自独立计数）。
    """
    spans = []
    n = len(text)

    def scan_one(i):
        """从 text[i] 处的 `$(` 或 `  开始，取**一个**跨度。"""
        if text[i] == '`':
            j = text.find('`', i + 1)
            if j < 0:
                j = n
            return (i, j + 1, text[i + 1:j])
        depth = 0
        j = i + 1
        while j < n:
            c = text[j]
            if c == '\\':
                j += 2
                continue
            if c == "'":
                k = text.find("'", j + 1)
                j = (k + 1) if k >= 0 else n
                continue
            if c == '"':
                k = j + 1
                while k < n:
                    if text[k] == '\\':
                        k += 2
                        continue
                    if text[k] == '"':
                        break
                    k += 1
                j = k + 1
                continue
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        return (i, j + 1, text[i + 2:j])

    def scan(text):
        """状态机扫描（⚠ **不许递归** —— 引号状态翻转 + 递归 = 无限递归）。"""
        out = []
        i = 0
        n = len(text)
        in_dq = False
        while i < n:
            c = text[i]
            if c == '\\':
                i += 2
                continue
            if c == "'" and not in_dq:
                # 单引号内：不做任何替换 ⇒ 整段跳过
                k = text.find("'", i + 1)
                i = (k + 1) if k >= 0 else n
                continue
            if c == '"':
                in_dq = not in_dq
                i += 1
                continue
            if text.startswith('$(', i) or c == '`':
                a, b, inner = scan_one(i)
                out.append((a, b, inner))
                i = b          # ⚠ 跨度内部有自己的引号上下文 ⇒ 不再递归进去
                continue
            i += 1
        return out

    return scan(text)


TRUE_RE = re.compile(r'\|\|\s*true\s*$')


def classify(inner):
    """给站点分类 —— ⚠ 分类**只用于登记与说明**，判定仍靠「登记册逐条相等」。"""
    seg = inner.split('||')[0]
    cmds = [c.strip() for c in seg.split('|')]
    last = cmds[-1] if cmds else ''
    if re.search(r'\bgrep\s+(-[a-zA-Z]*c[a-zA-Z]*\b|-c\b)', last):
        return 'count', last
    if re.match(r'cat\b', last):
        return 'content', last
    if re.match(r'command\s+-v\b', last):
        return 'exists', last
    return 'other', last


def enclosing_func(text, line):
    """站点所在的位置：函数名，或 `(顶层)`。

    ⚠⚠⚨ **必须区分「函数体内」与「顶层」**（实测踩出来的坑）：
      上一版只向上找最近的 `name() {` ⇒ **顶层代码被归到上一个函数**
      （实测 `ci-d2.sh` 的顶层 for 循环被归成 `exempt_field`）
      ⇒ 指纹就分不出「同款的两段代码」⇒ 登记册失去区分力。
    ⇒ 判据：向上找**第一个**「列 0 的 `name() {`」**或**「列 0 的 `}`」
      ⇒ 前者 = 该函数；后者 = 已经出了函数体 ⇒ `(顶层)`。

    ⚠⚠⚨ **函数名用来区分「同一文件里的多个同形态站点」**
    （例如 `ci-wiring.sh` 里 7 处 `grep -c .`）
    ⇒ 没有它 ⇒ 登记册里多行一模一样 ⇒ 挪动位置也不会红。
    """
    lines = text.split('\n')
    for i in range(min(line, len(lines)) - 1, -1, -1):
        l = lines[i]
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{', l)
        if m:
            return m.group(1)
        if re.match(r'^\}', l):
            return '(顶层)'          # ⚠ 已出函数体 ⇒ 后面是顶层代码
    return '(顶层)'


def scan_file(path):
    """返回该文件里的全部站点（行号来自**剥注释后**的文本 ⇒ 行号与原文件一致）。"""
    text = AUDIT.strip_comments(path)
    lines = text.split('\n')
    # 每个字符的起始行号
    line_of = []
    ln = 1
    for l in lines:
        line_of.extend([ln] * (len(l) + 1))
        ln += 1
    out = []
    for a, b, inner in find_subst_spans(text):
        if not TRUE_RE.search(inner.rstrip()):
            continue
        # 行号 = 跨度起始处所在行（`$(` 通常与命令同行）
        start_line = line_of[a] if a < len(line_of) else 0
        kind, last = classify(inner)
        out.append({
            # ⚠⚠⚨ 批 DQ · 键必须是**相对仓库根的路径**（批 CY 教训）：
            #   `deepin/scripts/contract-check.sh` 与 `macos/scripts/contract-check.sh`
            #   **同名** ⇒ 若用裸文件名做键 ⇒ 两边的处数**合并**
            #   ⇒ 「一处新增 + 一处减少 = 净 0」⇒ 登记册照样相等 ⇒ **假绿**
            'file': os.path.relpath(path, REPO_ROOT),
            'line': start_line,
            'func': enclosing_func(text, start_line),
            'kind': kind,
            'last': last[:60],
            'inner': ' '.join(inner.split())[:110],
        })
    return out


def scope_files():
    """按 `TRUE_SCOPE` 列出全部 .sh ⇒ 返回 (文件列表, 各口径的文件数)。

    ⚠⚠⚨ **fail closed**（批 CX / 批 CY 同款纪律）：
      范围目录**不存在** / 一个 .sh 都没有 ⇒ **判红**
      ⇒ 否则范围被悄悄掏空 ⇒ 盘点等于没跑 ⇒ **承诺的覆盖面是空的**。

    ⚠ **递归**：`macos/scripts/render-harness/run.sh` 在**子目录**里
      ⇒ 不递归 ⇒ 那批脚本上的 `|| true` **永远不被查** ⇒ 又一个「没有牙」的角落。
    """
    files = []
    counts = {}
    for key, rel in TRUE_SCOPE:
        base = os.path.join(REPO_ROOT, rel)
        if not os.path.isdir(base):
            sys.exit('✗ 盘点范围里的目录不存在：%s ⇒ 盘点做不了 ⇒ '
                     '**承诺的覆盖面不许被悄悄改窄**' % base)
        n = 0
        for dp, dn, fns in os.walk(base):
            dn[:] = sorted(d for d in dn if d not in ('__pycache__', '.git'))
            for fn in sorted(fns):
                if not fn.endswith('.sh'):
                    continue
                n += 1
                files.append((key, os.path.join(dp, fn)))
        if n == 0:
            sys.exit('✗ 盘点范围 %s 里一个 .sh 都没有 ⇒ 范围被掏空 ⇒ '
                     '盘点等于没跑 ⇒ **承诺的覆盖面不许被悄悄改窄**' % rel)
        counts[key] = n
    return files, counts


def read_scope_baseline():
    """读**恒真探针的扫描范围基线**（批 BP 立）⇒ 返回 {口径: 期望文件数}。

    ⚠ **fail closed**：读不到 / 有坏行 ⇒ 返回 **None** ⇒ 调用方照红
    ⇒ 不许「读不到就当没有基线」（批 BP 同款纪律）。
    """
    if not os.path.isfile(SCOPE_BASELINE):
        return None
    out = {}
    try:
        with open(SCOPE_BASELINE, encoding='utf-8') as fh:
            raw = fh.read()
    except OSError:
        return None
    for line in raw.split('\n'):
        t = line.strip()
        if not t or t.startswith('#'):
            continue
        parts = t.split()
        if len(parts) != 2 or not parts[1].isdigit():
            return None
        out[parts[0]] = int(parts[1])
    return out


def collect(files):
    sites = []
    for _key, path in files:
        sites.extend(scan_file(path))
    return sites


# ══════════════════════════════════════════════════════════════
# 登记册（独立文件 · 批 BH 纪律）
# ══════════════════════════════════════════════════════════════
def fmt(site, seq):
    """站点的一行登记格式（**指纹**部分）。

    ⚠⚠⚨ **不登记行号**（行号漂移 ⇒ 假红 ⇒ 批 BS 纪律：假红比假绿更坏）
    ⇒ 登记**内容指纹**：`文件<TAB>段<TAB>分类<TAB>末命令摘要<TAB>序号`
    ⇒ 内容变了 ⇒ 指纹变了 ⇒ 登记册对不上 ⇒ 红（这正是我们要的）。
    ⇒ **序号**用来区分「同款代码的两份拷贝」（实测 `ci-d2.sh` 的规则1/规则2
    两段完全对称 ⇒ 指纹完全相同 ⇒ 没有序号就分不开）。
    """
    digest = re.sub(r'[^\S|]+', '_', site['last'][:24])
    return '%s\t%s\t%s\t%s\t%d' % (site['file'], site['func'], site['kind'],
                                    digest, seq)


def assign_seq(sites):
    """给同指纹的站点编序号（按出现顺序）⇒ 返回 [(site, seq)]。"""
    seen = {}
    out = []
    for s in sites:
        key = (s['file'], s['func'], s['kind'],
               re.sub(r'[^\S|]+', '_', s['last'][:24]))
        seen[key] = seen.get(key, 0) + 1
        out.append((s, seen[key]))
    return out


def load_baseline():
    """读登记册 ⇒ 返回 [行]。

    ⚠⚠⚨ **每行必须恰好 6 段且第 6 段（理由）非空**（批 BN 纪律：逐条理由）
    ⇒ 不满足 ⇒ **判红**（不许「登记了但没写为什么」）。

    ⚠⚠⚨ **分隔符用 TAB 而不是 `|`**（实测踩出来的坑）：
      理由里要写「`|| true`」⇒ 用 `|` 分隔 ⇒ 理由本身会把行**劈开**
      ⇒ 段数对不上 ⇒ 登记册**永远读不出来**。
      ⇒ ⚠ 批 BN 已有先例（豁免表用 TAB 分隔）⇒ 沿用。
    """
    if not os.path.isfile(BASELINE):
        sys.exit('✗ 登记册不存在：%s' % BASELINE)
    with open(BASELINE, encoding='utf-8') as fh:
        raw = fh.read()
    if '\ufffd' in raw:
        sys.exit('✗ 登记册里有 U+FFFD ⇒ 拒绝落盘/判读')
    rows = []
    for no, l in enumerate(raw.split('\n'), 1):
        # ⚠⚠⚨ **只去换行，不 strip**（⚠ 负控 A5.1 逮到的真洞）：
        #   `strip()` 会把**行尾的空白**一起吃掉 ⇒ 而「理由为空」的表现正是
        #   「第 6 段是空白」⇒ 段数先变成 5 ⇒ **「没有理由」那条判定根本到不了**
        #   ⇒ 那条判定**形同虚设**（门项盯的是它在不在，不是它能不能被触发
        #   ⇒ 批 AX 的形状：门在，牙没有）。
        #   ⇒ 所以这里**只去换行符** ⇒ 空理由仍然是「6 段 + 第 6 段为空」。
        t = l.rstrip('\r\n')
        if not t.strip() or t.strip().startswith('#'):
            continue
        parts = t.split('\t')
        if len(parts) != 6:
            sys.exit('✗ 登记册第 %d 行不是 6 段（`文件<TAB>段<TAB>分类<TAB>摘要<TAB>序号<TAB>理由`）：%s'
                     % (no, t))
        if not parts[5].strip():
            sys.exit('✗ 登记册第 %d 行**没有理由** ⇒ 不许「登记了但没写为什么」：%s'
                     % (no, t))
        rows.append(t)
    return rows


def main():
    args = sys.argv[1:]
    # ⚠⚠⚨ 批 DQ · 先列**范围**（fail closed）⇒ 再跑抽取自检
    files, counts = scope_files()
    shs = [p for _k, p in files]
    # ⚠⚠⚨ 批 DS · **抽取器自检**必须真的跑
    #   ⇒ 抽取器被抽坏 ⇒ 盘点的数字**不可信** ⇒ 必须判红（不许带着坏抽取器绿着出去）
    _ex_bad = selftest_extractors()
    if _ex_bad:
        sys.exit('✗ 抽取器自检失败（抽取器被抽坏 ⇒ 盘点的数字不可信）：\n  '
                 + '\n  '.join(_ex_bad))
    # ⚠ 抽取自检：口径漂移（两侧剥注释结果不同）⇒ 立即判红
    selftest_strip_parity(shs)

    # ⚠⚠⚨ 批 DQ · **范围对账**（与恒真探针**共用**同一份范围基线）
    #   ⇒ 两个盘点的范围**必须一致** ⇒ 任何一边把范围改窄 ⇒ 文件数对不上 ⇒ 红
    scope_expect = read_scope_baseline()
    if scope_expect is None:
        sys.exit('✗ 恒真探针的扫描范围基线读不到或坏了：scripts/%s ⇒ '
                 '本盘点的范围**无处对账** ⇒ 拒绝继续'
                 % os.path.basename(SCOPE_BASELINE))
    for key, _rel in TRUE_SCOPE:
        want = scope_expect.get(key)
        got = counts.get(key, 0)
        if want is None or got != want:
            sys.exit('✗ 盘点范围 %s 的 .sh 文件数 %d ≠ 恒真探针范围基线 %s ⇒ '
                     '两个盘点的**范围不再一致** ⇒ 承诺的覆盖面被悄悄改窄'
                     % (key, got, want))
    # ⚠⚠⚨ **反向对账**（堵「恒真探针扩了范围而本盘点没跟上」）
    #   ⇒ 基线里凡是 **shell 口径**的键（`shell` 或 `*_shell`）都必须在本盘点的范围里
    #   ⇒ 少了 ⇒ 恒真探针新加的那块目录**永远不被查** ⇒ 覆盖面又窄了一块 ⇒ 红
    scope_keys = set(k for k, _rel in TRUE_SCOPE)
    extra_shell = sorted(k for k in scope_expect
                         if (k == 'shell' or k.endswith('_shell'))
                         and k not in scope_keys)
    if extra_shell:
        sys.exit('✗ 恒真探针的范围基线里有 %s 这几个 shell 口径，但本盘点的范围里没有 ⇒ '
                 '恒真探针扩了范围而本盘点没跟上 ⇒ 承诺的覆盖面又窄了一块'
                 % '、'.join(extra_shell))

    sites = collect(files)

    if '--list' in args:
        print('命令替换内带 `|| true` 的站点：%d 处' % len(sites))
        for s, seq in assign_seq(sites):
            print('  · %-26s :%-5s 段=%-22s 分类=%-8s 摘要=%s 序号=%d'
                  % (s['file'], s['line'], s['func'], s['kind'],
                     re.sub(r'[^\S|]+', '_', s['last'][:24]), seq))
        by_kind = {}
        for s in sites:
            by_kind[s['kind']] = by_kind.get(s['kind'], 0) + 1
        for k in sorted(by_kind):
            print('  [%s] %d 处' % (k, by_kind[k]))
        return 0

    # ---- 对照登记册（**双向红**，批 BH 纪律：恰好口径双向红）----
    base = load_baseline()
    # ⚠ 只比**指纹**（前 5 段）⇒ 理由不参与比较（理由只校验非空）
    base_keys = ['\t'.join(t.split('\t')[:5]) for t in base]
    got = [fmt(s, seq) for s, seq in assign_seq(sites)]
    from collections import Counter
    cb, cg = Counter(base_keys), Counter(got)
    # 「登记册有、实测没有」⇒ 登记册腐化
    missing = list((cb - cg).elements())
    # 「实测有、登记册没有」⇒ 新增未登记
    extra = list((cg - cb).elements())
    bad = False
    if missing or extra:
        bad = True
        print('✗ 「命令替换内 `|| true`」的盘点与登记册对不上 ⇒ 判红',
              file=sys.stderr)
        for m in missing:
            print('  ✗ 登记册有、实测没有（**登记册腐化** ⇒ 修好后请删掉登记册那一行）：%s'
                  % m, file=sys.stderr)
        for e in extra:
            print('  ✗ 实测有、登记册没有（**新增未登记** ⇒ 必须登记并写清理由）：%s'
                  % e, file=sys.stderr)
        print('  ⇒ 登记册：%s' % BASELINE, file=sys.stderr)
    # ⚠⚠⚨ **条数必须恰好等于基线**（批 BC + 批 BB 口径）
    #   ⚠⚠⚨ **放在对拍之后**（⚠ 负控 A3.1 逮到的真洞）：
    #   放在**前面** ⇒ 「登记册多一行/少一行」会**先**被条数检查拦下
    #   ⇒ 「**登记册腐化**」那条判定（missing）**永远到不了**
    #   ⇒ ⇒ 那条判定**形同虚设**（门项盯的是它在不在，不是它能不能被触发）。
    #   ⇒ 现在：**两个都报**（先对拍、再条数）⇒ 诊断更全、判定都可达。
    if len(base) != TRUE_AUDIT_EXPECTED_ROWS:
        bad = True
        print('✗ 登记册条数 %d ≠ 基线 %d ⇒ 整份清单被删/被改 ⇒ 判红'
              % (len(base), TRUE_AUDIT_EXPECTED_ROWS), file=sys.stderr)
    # ⚠⚠⚨ **两个判定都报、都可达**（⚠ 负控 A3.1 / A4.1 逮到的真洞）：
    #   若任一处**提前 return** ⇒ 另一处就**永远到不了**
    #   ⇒ 那条判定**形同虚设**（门项盯的是它在不在，不是它能不能被触发）。
    #   ⇒ 现在：**不提前 return** ⇒ 两个原因都报出来（批 AZ：一个退出码
    #     可能对应两种原因 ⇒ 诊断不许只报一个）。
    if bad:
        return 1
    print('✓ 「命令替换内 `|| true`」盘点与登记册逐条相等（%d 处）' % len(got))
    return 0


if __name__ == '__main__':
    sys.exit(main())
