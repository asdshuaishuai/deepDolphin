#!/usr/bin/env python3
"""ci-wiring-audit.py —— **门自审计**：审「门自己可不可信」。

【为什么需要它 · 第四次同一形状】
接线门判的是「某个串在不在」。⇒ 只要**同一个串在文件里出现不止一次**，
「改掉其中一处」这件事就**骗得过门**：别处还顶着呢。
这个形状在批 AS 之前已经踩了四次：
  · 批 AP —— 串出现在**注释/提示语**里（真接线被摘掉，门照样绿）
  · 批 AQ —— 串出现在**无关的另一行**里
  · 批 AR —— 串**只声明不编译**也算出现
  · 批 AS —— 同一个 `ToolArgs.flag(` 在测试文件里出现 **8 处**，
    负控的变异只动其中 1 处 ⇒ 门不红（负控当场抓到）
前三次都是**事后人工发现** ⇒ 这个工具把「事后」变成「**当场**」：
它逐条数每个门项的正则在目标文件里**命中几次**，命中 >1 ⇒ 报警。

【只审 arch_need，不审 arch_forbid】
arch_forbid 判的是「**不该有的东西没了**」⇒ 它的目标串出现 >0 本来就红，
>1 不是「被别处顶替」的隐患（是更严重的违规）⇒ 不在本工具的职责里。

【审计器自报盲区】
解析 ci-wiring.sh 时若漏掉门项（写法变了、参数换了引号），那部分门就**审不到**
⇒ 审计器自己有洞 ⇒ 比「门被骗过」更隐蔽。
⇒ 本工具比对「文件里 arch_need/arch_forbid 的行数」与「解析成功的条数」，
   不等就把差额报出来（**不许静默漏审**）。

用法：
  python3 ci-wiring-audit.py                 # 全量：人读的报告
  python3 ci-wiring-audit.py --list          # 机器可读：`相对路径|正则`（每行一条）
  python3 ci-wiring-audit.py --changed HEAD~1 # 只审 base..HEAD 里**新增**的门项
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))   # deepin/scripts
SRC = os.path.dirname(HERE)                        # deepin/（客户端源根）
REPO = os.path.dirname(SRC)                        # 仓根（macos/ 与 deepin/ 同仓）
WIRING = os.path.join(SRC, 'scripts', 'ci-wiring.sh')
# 豁免基线：已知「串不唯一」的历史门项，一行一条，键 = `相对路径|正则`。
# ⚠ **纯数据、零注释**（行首 `#` 会被当成 pattern）⇒ 说明写在别的文件里。
EXEMPT = os.path.join(SRC, 'scripts', 'wiring-multi-hit.exempt')

# 一行门项：arch_need <路径> '<正则>' '<说明>'
NEED_RE = re.compile(
    r'^\s*arch_need\s+'      # 门类型
    r'"([^"]+)"\s+'           # 目标文件（双引号）
    r"'([^']*)'\s+"           # 正则（单引号）
    r"'([^']*)'"              # 说明
)
# 兜底：目标文件与正则都用单引号
NEED_RE_SQ = re.compile(
    r"^\s*arch_need\s+"
    r"'([^']+)'\s+"
    r"'([^']*)'\s+"
    r"'([^']*)'"
)
# 兜底：说明用双引号（有人改引号就会落进这个分支）
NEED_RE_DQ = re.compile(
    r'^\s*arch_need\s+'
    r'"([^"]+)"\s+'
    r"'([^']*)'\s+"
    r'"([^"]*)"'
)
ANY_NEED_LINE = re.compile(r'^\s*arch_need\b')
ANY_FORBID_LINE = re.compile(r'^\s*arch_forbid\b')
# ⚠ **函数定义行**长得像门项（`arch_need() { # ...`）⇒ 必须排除，
#   否则审计器把工具自己的定义算成「没解析到的门项」⇒ 假盲区。
FUNC_DEF_LINE = re.compile(r'^\s*arch_(need|forbid)\w*\s*\(\)\s*\{')


def strip_comments(path):
    """剥注释 —— ⚠ **直接调 ci-wiring.sh 用的同一条 perl/sed**，不复刻。

    ⚠⚠ **为什么必须用同一条命令**（本批实测踩出来的）：
    审计器一开始用 **Python 正则复刻**了 `ci-wiring.sh` 的 `strip_comments`
    ⇒ **两套实现** ⇒ 迟早漂移。
    漂移的后果很隐蔽：审计器说「唯一」而门说「多处」（或反之）⇒ **豁免基线判错**
    ⇒ 而且**报告里的次数不可信** ⇒ 人会据此做错判断
    （本次实测：临时工具报「命中 2 次」，而手测与 shell 口径都是 4 次
      ⇒ 差点据此以为「4 行 vs 2 次」是矛盾）。
    ⇒ 复刻 = 两套口径 ⇒ **一律改成调同一条命令**。
    """
    if path.endswith('.sh') or path.endswith('.txt'):
        cmd = ["sed", "-e", r's/^[[:space:]]*#.*$//']
    else:
        cmd = ["perl", "-pe", r's{(?<!:)(//)(?!:).*$}{}']
    out = subprocess.run(cmd + [path], capture_output=True, text=True)
    return out.stdout


def resolve(p):
    p = p.replace('$ROOT', REPO).replace('$SRC', SRC)
    return p.strip('"')


def rel(path):
    try:
        return os.path.relpath(path, REPO)
    except ValueError:
        return path


def count_hits(path, rx):
    """用 grep -oE 数命中次数（与 arch_need_count 的口径一致）。"""
    if not os.path.isfile(path):
        return None
    text = strip_comments(path)
    try:
        out = subprocess.run(['grep', '-oE', '--', rx], input=text,
                             capture_output=True, text=True)
    except OSError:
        return None
    if out.returncode not in (0, 1):
        return None
    return len([ln for ln in out.stdout.split('\n') if ln])


def parse_wiring():
    """解析 ci-wiring.sh ⇒ (门项列表, arch_need 行数, 解析失败行号, arch_forbid 行数)"""
    src = open(WIRING, encoding='utf-8').read()
    lines = src.split('\n')
    items, total_lines, failed, forbid_lines = [], 0, [], 0
    for i, ln in enumerate(lines, 1):
        if ANY_FORBID_LINE.match(ln) and not FUNC_DEF_LINE.match(ln):
            forbid_lines += 1
        if not ANY_NEED_LINE.match(ln) or FUNC_DEF_LINE.match(ln):
            continue
        total_lines += 1
        m = NEED_RE.match(ln) or NEED_RE_SQ.match(ln) or NEED_RE_DQ.match(ln)
        if not m:
            failed.append(i)
            continue
        path, rx = m.group(1), m.group(2)
        items.append((i, resolve(path), rx))
    return items, total_lines, failed, forbid_lines


def changed_lines(base):
    """git diff base..HEAD 里 ci-wiring.sh 的**新增行行号**集合。"""
    try:
        out = subprocess.run(
            ['git', '-C', REPO, 'diff', '--unified=0', '%s..HEAD' % base,
             '--', 'deepin/scripts/ci-wiring.sh'],
            capture_output=True, text=True)
    except OSError:
        return None
    if out.returncode != 0:
        return None
    nums = set()
    for ln in out.stdout.split('\n'):
        m = re.match(r'^@@ -\S+ \+(\d+)(?:,(\d+))? @@', ln)
        if not m:
            continue
        start = int(m.group(1))
        cnt = int(m.group(2) or '1')
        for k in range(cnt):
            nums.add(start + k)
    return nums


def read_exempt():
    """读豁免基线 ⇒ (集合, 文件是否存在, 行数)

    ⚠ **跳过 `#` 开头的行与空行** ⇒ 基线文件可以带说明注释
    （否则注释行会被当成 pattern 去 grep 整行匹配 ⇒ 误排除）。
    """
    if not os.path.isfile(EXEMPT):
        return set(), False, 0
    with open(EXEMPT, encoding='utf-8') as fh:
        lines = [ln.rstrip('\n') for ln in fh]
    keys = set(ln for ln in lines if ln.strip() and not ln.lstrip().startswith('#'))
    return keys, True, len(lines)


def main():
    args = sys.argv[1:]
    want_list = '--list' in args
    want_list_all = '--list-all' in args
    base = None
    if '--changed' in args:
        i = args.index('--changed')
        base = args[i + 1] if i + 1 < len(args) else 'HEAD~1'

    items, total_lines, failed, forbid_lines = parse_wiring()

    if base is not None:
        nums = changed_lines(base)
        if nums is None:
            print('审计失败：git diff %s 拿不到' % base, file=sys.stderr)
            return 2
        items = [it for it in items if it[0] in nums]

    multi, zero = [], []
    for lineno, f, rx in items:
        if not os.path.isfile(f):
            zero.append((lineno, f, rx, '文件不存在'))
            continue
        n = count_hits(f, rx)
        if n is None:
            continue
        if n == 0:
            zero.append((lineno, f, rx, '命中 0 次'))
        elif n > 1:
            multi.append((lineno, f, rx, n))

    keys = ['%s|%s' % (rel(f), rx) for _, f, rx, _ in multi]
    exempt, exempt_exists, exempt_rows = read_exempt()
    outside = [k for k in keys if k not in exempt]
    stale = [k for k in exempt if k not in set(keys)]

    if want_list_all:
        for k in keys:
            print(k)
        return 0

    if want_list:
        # 硬门模式：只吐**豁免之外**的隐患；有 ⇒ 退出码 3（红）
        if not exempt_exists:
            print('豁免基线文件不在：%s' % EXEMPT, file=sys.stderr)
            return 2
        if failed:
            # ⚠ **审计器自己有盲区 ⇒ 那些门根本没被审** ⇒ 必须红。
            #   否则「审不到的门项」就成了逃逸口（批 AR「只声明不编译也算出现」的同构：
            #   判据写在那里，却没有任何机制保证它**真的被检查**）。
            print('审计器有盲区：%d 行门项没解析到（行号 %s）⇒ 它们**没被审**'
                  % (len(failed), ','.join(str(x) for x in failed)), file=sys.stderr)
            return 2
        for k in outside:
            print(k)
        return 3 if outside else 0

    print('门自审计：ci-wiring.sh 里 arch_need 门项 %d 条（解析成功 %d 条）'
          % (total_lines, len(items)))
    print('（arch_forbid 门项 %d 条**有意不审**：它判「不该有的东西没了」，'
          '目标串出现 >0 本来就红，不属于「被别处顶替」的隐患）' % forbid_lines)
    if failed:
        print('⚠ **审计器有盲区**：有 %d 行门项没解析到（行号 %s）'
              % (len(failed), ','.join(str(x) for x in failed)))
        print('   ⇒ 这些门**审不到**（写法变了？）⇒ 审计器本身要改，不能静默漏审')
    if base is not None:
        print('（只审 %s..HEAD 的新增门项）' % base)

    print('命中 >1 次 ⇒ **改一处骗得过门**：%d 条'
          % (len(multi) if base is None else len([k for k in keys if k in exempt or k in outside])))
    for lineno, f, rx, n in multi:
        mark = '（已豁免）' if '%s|%s' % (rel(f), rx) in exempt else '**⇒ 硬门会红**'
        print('  · %s:%d  命中 %d 次  %s  %s'
              % (os.path.basename(WIRING), lineno, n, rel(f), mark))
        print('      正则：%s' % rx)
    print('豁免基线：%d 条（文件：%s）'
          % (len(exempt), os.path.relpath(EXEMPT, REPO) if exempt_exists else '**缺失**'))
    if not exempt_exists:
        print('  ⚠ 豁免基线文件缺失 ⇒ 硬门会红')
    print('豁免之外（**新加的门不许落进这里**）：%d 条' % len(outside))
    for k in outside:
        print('  · %s' % k)
    if stale:
        print('豁免基线里**已失效**（门已收紧，可以清掉）：%d 条' % len(stale))
        for k in stale:
            print('  · %s' % k)
    print('命中 0 次 ⇒ **门本身就是红的**：%d 条' % len(zero))
    for lineno, f, rx, why in zero:
        print('  · %s:%d  %s  %s' % (os.path.basename(WIRING), lineno, why, rel(f)))
        print('      正则：%s' % rx)
    return 0


if __name__ == '__main__':
    sys.exit(main())
