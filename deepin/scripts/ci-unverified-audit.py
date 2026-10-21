#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批 CM · 常驻盘点：判据层脚本里「**未验证 / 跳过**」的提示站点。

⚠⚠⚨ **为什么这个脚本必须存在在仓里**（批 CL 实测坐实的起因）：
  批 CK / 批 CL 的结论都引用了「判据层有 **N 处**『未验证 / 跳过』提示」这个数字
  ⇒ 那个数字来自**一次性盘点脚本**（放在 `/tmp` 里）
  ⇒ **仓内没有任何东西能重算出它** ⇒ 数字不可复核；
  ⇒ 且实测：批 CL 的**修复本身**又新增了 4 处带「未验证」字样的提示消息
  ⇒ 「**修一次，数字就涨**」⇒ 「N 处未验证出口」这个说法**本身就不可靠**
  ⇒ ⇒ 本脚本把这个盘点**搬进仓内**，并让它与**逐组登记册**双向对拍。

⚠⚠⚨ **口径（机器可判 · 写死在这里 · 门项会盯这些定义行）**：
  一个「站点」= **打印行**（`echo` / `printf`）且**含未验证关键词**，
  且**不在排除表**里。
  ⚠ 排除表（**四类 · 全部有实测依据**，见下）：
    ① `成功消息`  —— 行内含 `✓`（例如「✓ 批 CL 段门项全绿（未验证不许被当成通过…）」）
       ⇒ ⚠⚠⚨ **实测的误报**：那是**成功汇总** ⇒ 它不是「未验证出口」
       ⇒ ⚠ 批 CL 的修复**正是**新增了这样一条 ⇒ 若不排除 ⇒ **修一次数字就涨**；
    ② `步骤标题`  —— 行内含 `›`（例如「› 3/15 desktop / metainfo 校验（缺工具显式 SKIP）」）
       ⇒ 它是**步骤打点**，不是出口；
    ③ `辅助提示`  —— 以 `⇒` 开头（缩进后）（例如「⇒ 逐条看上面带「SKIP」的行…」）
       ⇒ 它紧跟在真正的失败上报**后面**，本身**不构成**「未验却继续走」；
    ④ `汇总行`   —— 行内含 `passed,`（例如「──── contract-check: N passed, N failed, N unverified ────」）
       ⇒ 它是**成功汇总**。

⚠⚠⚨ **分类（机器可判）**：计入的站点按前缀分成两类 ——
  · `失败上报`（行内含 `✗`）⇒ 这一处**已经判红**；
  · `跳过提示`（其余）⇒ 这一处**只打印** ⇒ **必须**有计数 / 判红（批 CK / CL 的口径）。

⚠⚠⚨ **登记册按 (文件, 分类) 聚合计数，不按行登记**（**刻意的取舍**）：
  · 若按行登记 ⇒ 身份要含行号或文案 ⇒ ⚠ **改一句文案就漂** ⇒ **假红**
    ⇒ 批 BS 纪律：**假红比假绿更坏**（假红逼人把承诺改弱）；
  · ⇒ 这里按 (文件, 分类) 记**处数** ⇒ **改文案不漂**、**中间插入不漂**，
    **只有数量变了才红** ⇒ 而数量变了**正是**要人看一眼的时候
    （新增一处「未验证」提示 ⇒ 必须显式登记 + 写理由）；
  · ⚠⚠⚨ **代价（如实记）**：**组级理由** ⇒ 「这一组里**某一处**没判红」机器看不出来
    ⇒ ⚠ 这是本批**最弱的一环**（与批 CJ 同款：机器只校验「登记齐全 + 理由非空」，
    **危险方向靠人工**）。

⚠⚠⚨ **口径单一真相源**（批 CF 纪律：绝不复刻）：
  剥注释**直接复用**判据层自己的实现（`ci-true-audit.py` → `ci-wiring-audit.py`）
  ⇒ 并**复用它的抽取自检**（批 CF 教训：「复用实现的方式本身要有自检」）
  ⇒ 本脚本**不自己实现**剥注释。

用法：
  ci-unverified-audit.py --list      列出全部站点（落盘可复核）
  ci-unverified-audit.py             对照登记册（scripts/ci-unverified-audit.baseline）判红
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = HERE

BASELINE = os.path.join(SCRIPTS, "ci-unverified-audit.baseline")

# ⚠⚠⚨ 登记册**条数基线**（批 BC 纪律：清单不许被删）⇒ **恰好**（批 BB 口径）
UNVERIFIED_EXPECTED_ROWS = 15

# ══════════════════════════════════════════════════════════════
# 口径定义（⚠⚠⚨ 门项会**整行锚定**这几行 ⇒ 口径不许被改弱）
# ══════════════════════════════════════════════════════════════
# 未验证关键词（大小写不敏感）
UNVERIFIED_KEYWORDS = r"SKIP|未验证|不算通过|跳过|无法验证|not verified"
# 必须是**打印行**（⚠ shell 的 echo/printf **与** python 的 print 都算
#   ⇒ 否则 python 侧判据脚本的「未验证」提示**完全不在盘点范围内** ⇒ 盲区）
UNVERIFIED_PRINT_RE = r"^\s*(echo|printf|print)\b"
# 排除表（四类 · 每类都有实测依据）
# ⚠⚠⚨ 批 CM 自查：这四行**不许带行尾注释** ⇒ 审计器 `count_hits`
#   **先剥注释再 grep** ⇒ 行尾注释会被剥掉 ⇒ 整行锚定就匹配不上 ⇒ **门恒红**
#   （⚠ 本批实测踩到的：门项正则现抽 ⇒ 自带行尾注释 ⇒ 命中 0 ⇒ 门恒红）。
#   ⇒ 解释一律写在**上一行**（这四行的语义不许被注释遮住 ⇒ 门项锚定整行）。
# 排除表 · 成功消息（⚠ 成功汇总 ⇒ 不是「未验证出口」；⚠ 批 CL 的修复**正是**新增了这样一条 ⇒ 若不排除 ⇒ **修一次数字就涨**）
UNVERIFIED_EXCLUDE_OK = "✓"
# 排除表 · 步骤标题（⚠「› N/15 …」是步骤打点 ⇒ 不是出口）
UNVERIFIED_EXCLUDE_TITLE = "›"
# 排除表 · 辅助提示（⚠ 引号内首个非空白字符是 ⇒ ⇒ 紧跟在失败上报后面的说明行本身**不构成**出口）
UNVERIFIED_EXCLUDE_HINT = "⇒"
# 排除表 · 成功汇总行（⚠「──── N passed, N failed, N unverified ────」是**成功汇总** ⇒ 不是出口）
UNVERIFIED_EXCLUDE_SUMMARY = "passed,"
# ⚠⚠⚨ 辅助提示的判定**必须按「引号内首个非空白字符」**，
#   不能按「整行 stripped 后以 ⇒ 开头」——⚠ **实测踩过**：
#   实际行是 `echo "  ⇒ 逐条看上面带「SKIP」的行…"` ⇒ stripped 后开头是 `echo`
#   ⇒ 「以 ⇒ 开头」永远不成立 ⇒ **排除规则静默失效**（多算了 3 行）。
UNVERIFIED_HINT_RE = r"^\s*(?:echo|printf)\s+\"?\s*⇒"

# ══════════════════════════════════════════════════════════════
# 复用批 CJ 的常驻盘点脚本（剥注释口径 + 抽取自检）⇒ 不复刻
# ══════════════════════════════════════════════════════════════
def load_helper():
    """加载 `ci-true-audit.py` 为模块 ⇒ 复用它的剥注释口径与抽取自检。

    ⚠⚠⚨ **绝不复刻**剥注释（批 CF 纪律）⇒ 只调它的函数。
    ⚠ 该文件有 `if __name__ == "__main__"` 保护 ⇒ import 不会跑它的 main。
    """
    path = os.path.join(SCRIPTS, 'ci-true-audit.py')
    spec = importlib.util.spec_from_file_location('ci_true_audit', path)
    if spec is None or spec.loader is None:
        sys.exit('✗ 加载 ci-true-audit.py 失败：%s' % path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for fn in ('load_audit', 'selftest_strip_parity'):
        if not hasattr(mod, fn):
            sys.exit('✗ ci-true-audit.py 里没有 %s() ⇒ 口径无法复用 ⇒ 拒绝继续' % fn)
    return mod


HELPER = load_helper()
AUDIT = HELPER.AUDIT

# ⚠ 编译一次（⚠ 口径不许被「随手改正则」⇒ 门项盯的是**定义行**）
KW_RE = re.compile(UNVERIFIED_KEYWORDS, re.I)
PRINT_RE = re.compile(UNVERIFIED_PRINT_RE)
HINT_RE = re.compile(UNVERIFIED_HINT_RE)


def classify_line(stripped):
    """返回 (分类, 是否计入)。

    ⚠⚠⚨ **排除表优先于分类** ⇒ 一行含 `✓` 时**不计入**（哪怕它也含 `✗`）。
    """
    if UNVERIFIED_EXCLUDE_OK in stripped:
        return '成功消息', False
    if UNVERIFIED_EXCLUDE_TITLE in stripped:
        return '步骤标题', False
    if HINT_RE.match(stripped):
        return '辅助提示', False
    if UNVERIFIED_EXCLUDE_SUMMARY in stripped:
        return '汇总行', False
    if '✗' in stripped:
        return '失败上报', True
    return '跳过提示', True


def scan_file(path):
    """扫描一个文件 ⇒ 返回 (站点列表, 排除列表)。"""
    text = AUDIT.strip_comments(path)
    sites, excluded = [], []
    for i, ln in enumerate(text.split('\n'), 1):
        if not PRINT_RE.match(ln):
            continue
        if not KW_RE.search(ln):
            continue
        s = ln.strip()
        cat, counted = classify_line(s)
        rec = (cat, s)
        if counted:
            sites.append(rec)
        else:
            excluded.append(rec)
    return sites, excluded


def collect():
    """扫全 `scripts/` ⇒ 返回 (计数表, 站点明细, 排除明细, 文件列表)。"""
    files = sorted(f for f in os.listdir(SCRIPTS)
                   if f.endswith(('.sh', '.py')) and os.path.isfile(os.path.join(SCRIPTS, f)))
    # ⚠⚠⚨ 抽取自检：两侧剥注释必须**逐字节相同**（批 CF / CH 纪律）
    HELPER.selftest_strip_parity([os.path.join(SCRIPTS, f) for f in files])
    counts = {}
    detail = []
    excluded = []
    for fn in files:
        path = os.path.join(SCRIPTS, fn)
        try:
            sites, exc = scan_file(path)
        except Exception as e:                       # noqa: BLE001
            sys.exit('✗ 读不了 %s：%s ⇒ 盘点做不了 ⇒ **未验证不许被当成通过**' % (fn, e))
        for cat, s in sites:
            counts.setdefault(fn, {})
            counts[fn][cat] = counts[fn].get(cat, 0) + 1
            detail.append((fn, cat, s))
        for cat, s in exc:
            excluded.append((fn, cat, s))
    return counts, detail, excluded, files


def fmt_counts(counts):
    out = []
    for fn in sorted(counts):
        for cat in sorted(counts[fn]):
            out.append('%s\t%s\t%d' % (fn, cat, counts[fn][cat]))
    return out


def load_baseline():
    """读登记册 ⇒ 返回 {(文件, 分类): 处数}；**顺带做逐行体检**（批 CJ 教训）。"""
    if not os.path.isfile(BASELINE):
        sys.exit('✗ 登记册不存在：%s ⇒ 盘点无处对照 ⇒ **未验证不许被当成通过**' % BASELINE)
    with open(BASELINE, encoding='utf-8') as fh:
        raw = fh.read()
    rows = []
    bad = []
    for i, line in enumerate(raw.split('\n'), 1):
        if not line.strip() or line.strip().startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) != 4:
            bad.append('第 %d 行不是 4 段（文件|分类|处数|理由）：%r' % (i, line))
            continue
        fn, cat, n, why = parts
        if not n.strip().isdigit() or int(n) <= 0:
            bad.append('第 %d 行的处数不是正整数：%r' % (i, n))
            continue
        if not why.strip():
            bad.append('第 %d 行**没有理由**：%r' % (i, line))
            continue
        rows.append((fn, cat, int(n), why.strip()))
    # ⚠⚠⚨ **两个判定都报、都不提前 return**（批 CJ 教训：
    #   「一条判定『在』≠『那条判定能被触发』」）
    if bad:
        sys.exit('✗ 登记册有 %d 条坏行：\n  ' % len(bad) + '\n  '.join(bad))
    if len(rows) != UNVERIFIED_EXPECTED_ROWS:
        sys.exit('✗ 登记册条数 %d ≠ 基线 %d ⇒ **清单不许被删**（批 BC）'
                 % (len(rows), UNVERIFIED_EXPECTED_ROWS))
    return rows


def main():
    counts, detail, excluded, files = collect()

    # ⚠ `--list` **不读登记册** ⇒ 否则「登记册还没建」时连清单都列不出来
    if '--list' in sys.argv:
        print('站点：%d 处（计入）｜排除：%d 处（成功消息/步骤标题/辅助提示/汇总行）'
              % (len(detail), len(excluded)))
        print('按 (文件, 分类) 聚合：')
        for fn in sorted(counts):
            for cat in sorted(counts[fn]):
                print('  %s\t%s\t%d' % (fn, cat, counts[fn][cat]))
        print('\n── 计入的站点明细 ──')
        for fn, cat, s in detail:
            print('  %-26s %-10s %s' % (fn, cat, s[:90]))
        print('\n── 被排除的站点明细（排除表也留痕）──')
        for fn, cat, s in excluded:
            print('  %-26s %-10s %s' % (fn, cat, s[:90]))
        return 0

    rows = load_baseline()
    base = {(fn, cat): (n, why) for fn, cat, n, why in rows}
    got = {}
    for row in fmt_counts(counts):
        parts = row.split('\t')
        got[(parts[0], parts[1])] = int(parts[2])

    missing = sorted(set(got) - set(base))       # 实测有、登记册没有
    dead = sorted(set(base) - set(got))          # 登记册有、实测没有
    drifted = sorted(k for k in set(got) & set(base) if got[k] != base[k][0])

    # ⚠⚠⚨ 批 CM 自查：这里**原来还有一整段重复的 `--list` 分支**（复制粘贴留下的）
    #   ⇒ 上面 `if '--list' in sys.argv:` 已经 `return 0` ⇒ 那段是**死代码**
    #   ⇒ 批 discipline：「同名多处顶替 ⇒ 死代码」⇒ 已删（本批落盘前清掉）。

    bad = []
    if missing:
        bad.append('实测有、登记册没有（新增未登记）%d 条：%s'
                   % (len(missing), '；'.join('%s/%s=%d' % (k[0], k[1], got[k]) for k in missing)))
    if dead:
        bad.append('登记册有、实测没有（登记册腐化）%d 条：%s'
                   % (len(dead), '；'.join('%s/%s' % (k[0], k[1]) for k in dead)))
    if drifted:
        bad.append('处数对不上 %d 条：%s'
                   % (len(drifted), '；'.join('%s/%s 登记册=%d 实测=%d'
                                              % (k[0], k[1], base[k][0], got[k]) for k in drifted)))
    if bad:
        # ⚠⚠⚨ **用 `return 1` 而不是 `sys.exit('…')`**：
        #   门项要用**整行锚定**盯住失败上报出口 ⇒ 而门项的正则参数是**单引号**包裹
        #   ⇒ 正则里**不能含字面单引号**（批 BL 教训）⇒ `sys.exit('✗ …')` 那一行
        #   **根本没法被门项整行锚定** ⇒ 改成 `return 1`（无引号）+ 入口交给
        #   `sys.exit(main())` ⇒ 退出码照样是 1 ⇒ 失败照样响亮。
        print('✗ 未验证出口盘点与登记册对不上：\n  ' + '\n  '.join(bad),
              file=sys.stderr)
        return 1
    print('✓ 未验证出口盘点与登记册逐条相等：%d 组 / %d 处（登记册 %d 行）'
          % (len(got), len(detail), len(rows)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
