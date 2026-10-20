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
⇒ 本工具比对「文件里各门型的行数」与「解析成功的条数」，
   不等就把差额报出来（**不许静默漏审**）。

【批 AV 扩了覆盖面】
原来只审 `arch_need`（单文件、「出现过即可」）。批 AU 给 `arch_need_min`
（单文件、「至少 N 次」）配了「下限必须 == 实际命中数」校准。
批 AV 把它**扩到全部剩下的门型**：
  · `arch_need_ml` —— 单文件、压行后匹配 ⇒ 现在查「压行后命中 >1」
  · `arch_need_any_count` —— glob 范围、**恰好** N 次 ⇒ 校准「实际 == 期望」
  · `arch_need_any_min` —— glob 范围、**至少** N 次 ⇒ 校准「下限 == 实际命中数」
  · `arch_need_count` —— 单文件、**恰好** N 次 ⇒ 校准「实际 == 期望」
⇒ 至此**五类「要出现」的门全部在校** ⇒ 覆盖缺口清零。

【⚠ 绝不复刻口径 —— 一律「抽取 ci-wiring.sh 的原文来跑」】
批 AS 实测教训：审计器一开始用 **Python 正则复刻**了 `strip_comments`
⇒ **两套实现** ⇒ 迟早漂移 ⇒ 报告里的次数不可信 ⇒ 人会据此做错判断。
⇒ 这里的做法是**从 ci-wiring.sh 里 `sed` 抽出函数原文**，
   拼成临时脚本再调 ⇒ 改门侧口径时审计侧**自动跟着变** ⇒ 零漂移。

用法：
  python3 ci-wiring-audit.py                 # 全量：人读的报告
  python3 ci-wiring-audit.py --list          # 机器可读：`相对路径|正则`（每行一条）
  python3 ci-wiring-audit.py --changed HEAD~1 # 只审 base..HEAD 里**新增**的门项
退出码：
  0 绿 / 2 审计器有盲区或缺文件 / 3 豁免外隐患（命中 >1）/ 4 次数门没配准
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))   # deepin/scripts
SRC = os.path.dirname(HERE)                        # deepin/（客户端源根）
REPO = os.path.dirname(SRC)                        # 仓根（macos/ 与 deepin/ 同仓）
WIRING = os.path.join(SRC, 'scripts', 'ci-wiring.sh')
# 豁免基线：已知「串不唯一」的历史门项，一行一条。
# ⚠ 键格式 = `<类型>:<相对路径或glob>|<正则>`
#   类型 ∈ {need, ml}（只有这两类会出「命中 >1」的隐患）
# ⚠ **纯数据、零注释**（行首 `#` 会被当成 pattern）⇒ 说明写在别的文件里。
EXEMPT = os.path.join(SRC, 'scripts', 'wiring-multi-hit.exempt')

# ⚠⚠⚠ **门项行数基线**（批 BH）——
# ⚠ **起因（实测，不是推演）**：把 ci-wiring.sh 里**任意一条门项**改成注释
#   ⇒ 接线门 **rc=0**、审计器 **rc=0**、**CI 全流程 rc=0** ⇒ **全绿**
#   ⇒ 「门项被悄悄删」这件事，**没有任何机制会发现**。
# ⚠ **为什么基线要放在**另一个文件**里（而不是写死在审计器里）：
#   写死 ⇒ 审计器既是「执行者」又是「裁判」⇒ 改审计器就能同时改标准。
#   ⇒ 基线放在**独立文件** ⇒ 删基线文件 ⇒ 门与审计器**双双红**。
GATE_BASELINE = os.path.join(SRC, 'scripts', 'ci-wiring-gates.baseline')
# ⚠⚠⚠ **注意**：这里**不要**再定义 `GATE_LINE` —— 文件下方**已经有一个**
#   `GATE_LINE`（带捕获组，`check_rx_syntax` 在用）⇒ 同名 ⇒ **后者覆盖前者**
#   ⇒ 先定义的那个成了**死代码**。
#   ⚠⚠⚠ **本批自己就踩了这个**（批 AS 起反复出现的那一族：同名互相顶替）——
#   当时定义的 `GATE_LINE` 被下面的同名定义覆盖 ⇒ 它成了死代码 ⇒
#   「物理门项行」的口径用不上它（真正用的是下面那个**不撞名**的常量）⇒
#   ⇒ 差点让**审计器的对拍口径**与实现脱节。
#   ⇒ 现在有「模块级重名自检」（**模块级赋值名不许重复**）当场抓住。
#   ⚠ 物理门项行的口径在下面叫另一个名字（**故意不撞**）。
#   ⚠⚠⚠ **注意**：本文件里的 `#` 注释**也算进** count 族门项的命中数
#     （strip_comments 对 `.py` 只剥 `//`、**不剥 `#`）
#     ⇒ ⚠⚠⚠ **注释里千万别重复写被门盯的常量名** ⇒ 期望值会漂
#     ⇒ ⚠ 本批就因此踩了一次（期望 2、实际 4 ⇒ 门当场报失准）。

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
# ⚠ `arch_need_min`（至少 N 次）：**天然**多点 ⇒ 不查「串是否唯一」，
#   但要**校准下限**：下限必须 == 当前命中数。
#   · 下限 < 命中数 ⇒ **门没牙**（删一处仍够 ⇒ 不红）—— 批 AU 实测踩到：
#     `Canvas2D` 在 HeatmapWidget.cpp 里命中 4 次（include + 3 处构造），
#     而下限写的是 3 ⇒ 删掉一处构造仍剩 3 ⇒ 门照样绿。
#   · 下限 > 命中数 ⇒ **门恒红**。
NEED_MIN_LINE = re.compile(
    r'^\s*arch_need_min\s+"([^"]+)"\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠ `arch_need_ml`（单文件、**压行后**匹配）：批 AV 起纳入覆盖
#   —— 压行后命中 >1 ⇒ 改一处骗得过门（实测：`platform::dpiPixmap(` 压行后 2 次）。
ML_LINE = re.compile(
    r'^\s*arch_need_ml\s+"([^"]+)"\s+\'([^\']*)\'\s+')
# ⚠ `arch_need_any_count`（glob 范围、**恰好** N 次）/ `arch_need_any_min`（**至少** N 次）
#   —— 批 AV 起纳入覆盖（它们是「跨文件」门 ⇒ 命中数是**所有匹配文件加总**）。
ANY_COUNT_LINE = re.compile(
    r'^\s*arch_need_any_count\s+\'([^\']*)\'\s+(\d+)\s+\'([^\']*)\'(?:\s+\'([^\']*)\')?\s*$')
ANY_MIN_LINE = re.compile(
    r'^\s*arch_need_any_min\s+\'([^\']*)\'\s+(\d+)\s+\'([^\']*)\'(?:\s+\'([^\']*)\')?\s*$')
# ⚠ `arch_need_count`（单文件、**恰好** N 次）：批 AV 起纳入校准。
COUNT_LINE = re.compile(
    r'^\s*arch_need_count\s+"([^"]+)"\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠ `arch_need_count_in_fn`（**函数体内**恰好 N 次）：它**自己数次数** ⇒ 天然有牙，
#   但「把期望从 1 改成 2 来躲变异」这种手法没人盯 ⇒ 批 AV 起也校准。
#   ⚠ 期望值校准要复刻「切函数体」那段 awk ⇒ **从 ci-wiring.sh 里抽取原文**（零漂移）。
COUNT_IN_FN_LINE = re.compile(
    r'^\s*arch_need_count_in_fn\s+"([^"]+)"\s+\'([^\']*)\'\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠ `arch_need_count_in_step`（**某一步的正文里**恰好 N 次）：批 BE 新门型。
#   它盯的是「这个标记串**还在这一步里**」⇒ 文件级门盯不到的「被挪到别处」由它抓。
#   ⚠ **新门型必须进审计覆盖**（批 AR/AV 纪律：「审计器自己有盲区 ⇒ 那些门根本没被审」）
#   ⇒ 这里加解析 + 配准校准；切步骤正文用的 awk **从 ci-wiring.sh 原文抽取**（零漂移）。
COUNT_IN_STEP_LINE = re.compile(
    r'^\s*arch_need_count_in_step\s+"([^"]+)"\s+(\d+)\s+\'([^\']*)\'\s+(\d+)\s+')
# ⚠⚠ **count 族的兜底盲区检测**（批 BE）：
#   `ANY_NEED_LINE`（`arch_need\b`）**匹配不到** count 族（`_` 是单词字符 ⇒ 没有词边界）⇒
#   以前一条**写坏**的 `arch_need_count*` 门项会**静默被忽略** ⇒
#   **审计器审不到它 ⇒ 没人知道它没被审**（批 AR 说的「审计器自己有盲区」）。
#   ⇒ 这里加兜底：凡是 count 族、却没被上面任何一个门型解析到 ⇒ 记成盲区 ⇒ 硬门红。
COUNT_FAMILY_LINE = re.compile(r'^\s*arch_need_count\w*\s')
# ⚠ **函数定义行**长得像门项（`arch_need() { # ...`）⇒ 必须排除，
#   否则审计器把工具自己的定义算成「没解析到的门项」⇒ 假盲区。
FUNC_DEF_LINE = re.compile(r'^\s*arch_\w+\s*\(\)\s*\{')
# ⚠⚠⚠ 批 BH：门型清单 —— 「审计器认出来的门项行数」要能对上「文件里实际的门项行数」
#   ⇒ **每一种门型都要有一条自己的正则** ⇒ 将来新增一种门型而忘了在审计器里登记
#   ⇒ 审计器数出来的门项数会**少于**文件里的实际行数 ⇒ **当场红**（覆盖缺口）。
# ⚠ forbid 家族是**有意不审**（它判「不该有的东西没了」⇒ 目标串出现 >0 本来就红），
#   但**行数仍然要计入** ⇒ 否则「物理行数」对不上 ⇒ 假红。
FORBID_FAMILY = {
    'forbid': re.compile(r'^\s*arch_forbid\s'),
    'forbid_tree': re.compile(r'^\s*arch_forbid_tree\s'),
    'forbid_han': re.compile(r'^\s*arch_forbid_han\s'),
    'forbid_raw': re.compile(r'^\s*arch_forbid_raw\s'),
    'forbid_ml': re.compile(r'^\s*arch_forbid_ml\s'),
    'forbid_text_dup': re.compile(r'^\s*arch_forbid_text_dup\s'),
}

DEFAULT_ANY_GLOB = 'src/app/SelfCheck*.cpp'


def resolve(p):
    p = p.replace('$ROOT', REPO).replace('$SRC', SRC)
    return p.strip('"')


def rel(path):
    try:
        return os.path.relpath(path, REPO)
    except ValueError:
        return path


def strip_comments(path):
    """剥注释 —— ⚠ **直接调 ci-wiring.sh 用的同一条 perl/sed**，不复刻。

    ⚠⚠ **为什么必须用同一条命令**（批 AS 实测踩出来的）：
    审计器一开始用 **Python 正则复刻**了 `ci-wiring.sh` 的 `strip_comments`
    ⇒ **两套实现** ⇒ 迟早漂移。
    漂移的后果很隐蔽：审计器说「唯一」而门说「多处」（或反之）⇒ **豁免基线判错**
    ⇒ 而且**报告里的次数不可信** ⇒ 人会据此做错判断
    （本次实测：临时工具报「命中 2 次」，而手测与 shell 口径都是 4 次
      ⇒ 差点据此以为「4 行 vs 2 次」是矛盾）。
    ⇒ 复刻 = 两套口径 ⇒ **一律改成调同一条命令**。
    """
    # ⚠⚠⚨ **`.py` 也要剥 `#` 注释**（批 BK）：python 的注释是 `#`
    #   ⇒ 不剥 ⇒ **注释里的串会顶替真代码** ⇒ 盯串的门项**假绿**
    #   （实测：真代码换成 `pass  # 串` ⇒ 命中数不变 ⇒ 门照样绿）。
    # ⚠⚠⚨ **两侧必须同步**（门侧 `ci-wiring.sh` 的 `strip_comments` 同款）
    #   ⇒ 不一致 ⇒ 同一串两侧算得不一样 ⇒ 配准校准失准。
    # ⚠ **行首锚定** ⇒ 字符串里的 `#` 不受影响 ⇒ 安全。
    if path.endswith('.sh') or path.endswith('.txt') or path.endswith('.py'):
        cmd = ["sed", "-e", r's/^[[:space:]]*#.*$//']
    else:
        cmd = ["perl", "-pe", r's{(?<!:)(//)(?!:).*$}{}']
    out = subprocess.run(cmd + [path], capture_output=True, text=True)
    return out.stdout


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


def count_hits_ml(path, rx):
    """数**压行后**的命中次数（与 arch_need_ml 的口径一致：先剥注释再压成一行）。"""
    if not os.path.isfile(path):
        return None
    text = strip_comments(path).replace('\n', ' ')
    try:
        out = subprocess.run(['grep', '-oE', '--', rx], input=text,
                             capture_output=True, text=True)
    except OSError:
        return None
    if out.returncode not in (0, 1):
        return None
    return len([ln for ln in out.stdout.split('\n') if ln])


# ⚠⚠ **抽取而非复刻**（批 AV 起）：把 ci-wiring.sh 里的 shell 函数**原文**抠出来，
#   拼成临时脚本再调 ⇒ 门侧改了口径，审计侧自动跟着变 ⇒ 零漂移。
def extract_shell_func(name):
    """从 ci-wiring.sh 里 `sed` 抽出名为 <name> 的 shell 函数原文。"""
    out = subprocess.run(
        ['sed', '-n', '/^%s() {/,/^}/p' % re.escape(name), WIRING],
        capture_output=True, text=True)
    return out.stdout


def extract_fn_body_awk():
    """从 `arch_need_count_in_fn` 原文里抠出那段 awk 程序（切函数体用）。"""
    fn = extract_shell_func('arch_need_count_in_fn')
    m = re.search(r"awk -v sig=\"\$sig\" '(.*?)'\)\"", fn, re.S)
    return m.group(1) if m else None


def extract_step_awk():
    """从 `arch_need_count_in_step` 原文里抠出那段 awk 程序（切**步骤正文**用）。

    ⚠⚠ **必须抽取，不许复刻**（批 AV 起的纪律）：审计器自己写一套切段逻辑
      ⇒ 两套口径 ⇒ 迟早漂移 ⇒ 审计器报的次数不可信 ⇒ 人会据此做错判断。
    """
    fn = extract_shell_func('arch_need_count_in_step')
    if not fn:
        return None
    m = re.search(r"awk -v step=\"\$step\" '(.*?)'\)", fn, re.S)
    return m.group(1) if m else None


class AnyCounter(object):
    """批量数「glob 范围内**总命中数**」—— 口径 = ci-wiring.sh 的 `any_hits`（抽取原文）。"""

    def __init__(self, pairs):
        """pairs = [(rx, glob), ...]"""
        self.pairs = list(pairs)
        self.values = {}
        self._run()

    def _script(self):
        parts = ["#!/bin/bash", "SRC=%s" % shlex.quote(SRC)]
        for fn in ('strip_comments', 'any_hits'):
            body = extract_shell_func(fn)
            if not body:
                raise RuntimeError('抽不出 ci-wiring.sh 里的 %s() ⇒ 口径会漂移' % fn)
            parts.append(body)
        for i, (rx, gl) in enumerate(self.pairs):
            parts.append("printf '%d\\t%%s\\n' \"$(any_hits %s %s)\""
                         % (i, shlex.quote(rx), shlex.quote(gl)))
        return '\n'.join(parts) + '\n'

    def _run(self):
        if not self.pairs:
            return
        tmpd = tempfile.mkdtemp(prefix='wiring-audit-')
        try:
            path = os.path.join(tmpd, 'count.sh')
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(self._script())
            out = subprocess.run(['bash', path], capture_output=True, text=True)
            if out.returncode != 0:
                raise RuntimeError('any_hits 批量计数失败：%s' % out.stderr.strip()[:400])
            for ln in out.stdout.split('\n'):
                if '\t' not in ln:
                    continue
                idx, cnt = ln.split('\t', 1)
                try:
                    self.values[int(idx)] = int(cnt.strip())
                except ValueError:
                    continue
            missing = [i for i in range(len(self.pairs)) if i not in self.values]
            if missing:
                raise RuntimeError('any_hits 批量计数少 %d 条 ⇒ 对不上' % len(missing))
        finally:
            shutil.rmtree(tmpd, ignore_errors=True)

    def get(self, rx, gl):
        return self.values.get(self.pairs.index((rx, gl)))


# ⚠⚠⚠ **门型登记处**（批 BH）——「每一种门型一条正则」。
#   ⇒ 审计器**认领**的门项行数（total）必须 == 文件里**实际**的门项行数（物理行数）
#   ⇒ 不等 = **有一种门型没被登记** ⇒ 那些门项**根本没被审**（批 AR 说的「审计器自己有盲区」）。
#   ⇒ ⚠ **将来新增门型时，必须在这里登记一条** ⇒ 忘了登记 ⇒ 当场红。
#   ⚠ 这 14 条正则**互斥**（门型名后要求空白 ⇒ 家族成员之间不会互相命中），
#     且**天然排除函数定义行**（定义行里门型名后是 `(` 不是空白）⇒ 不会把工具自己的
#     定义算成门项。
GATE_TYPES = [
    ('need', ANY_NEED_LINE),
    ('need_ml', ML_LINE),
    ('need_any_count', ANY_COUNT_LINE),
    ('need_any_min', ANY_MIN_LINE),
    ('need_count', COUNT_LINE),
    ('need_count_in_fn', COUNT_IN_FN_LINE),
    ('need_count_in_step', COUNT_IN_STEP_LINE),
    ('need_min', NEED_MIN_LINE),
] + sorted(FORBID_FAMILY.items())

# ⚠ **物理门项行**的口径：行首（去前导空白）以 `arch_` 开头、**后接空白**
#   ⇒ 与门型知识**完全无关** ⇒ 这是审计器认领数的**独立对拍口径**。
GATE_CALL_LINE = re.compile(r'^\s*arch_\w+\s')


def count_gate_types(path):
    """数门项 ⇒ (各门型条数, 审计器认领总数, 物理门项行数)。

    ⚠⚠ **两个数必须相等**：
      · 「审计器认领总数」= 上面 14 条门型正则各数一遍（互斥 ⇒ 不会重复计数）；
      · 「物理门项行数」= 用**不认识门型**的口径数一遍（只看「长得像门项」）。
      ⇒ 不等 ⇒ **有一种门型没被登记** ⇒ 那些门项**没被审**（批 BH 抓的就是这个）。
    """
    src = open(path, encoding='utf-8').read()
    lines = src.split('\n')
    counts = {}
    for name, rx in GATE_TYPES:
        # ⚠⚠ **必须排除函数定义行**（`arch_need() { …}`）：
        #   `ANY_NEED_LINE`（`arch_need\b`）里 `\b` 允许后接 `(` ⇒ 定义行**会被它命中**
        #   ⇒ 不排除就把「工具自己的定义」算成门项 ⇒ 与物理行数对不上。
        #   ⚠ `FUNC_DEF_LINE` 已改成通用版（`arch_\w+`）⇒ 覆盖**所有**门型的定义行。
        counts[name] = sum(1 for ln in lines
                           if rx.match(ln) and not FUNC_DEF_LINE.match(ln))
    total = sum(counts.values())
    physical = sum(1 for ln in lines if GATE_CALL_LINE.match(ln))
    return counts, total, physical


def read_gate_baseline():
    """读门项行数基线文件 ⇒ (数字, 错误原因)。

    ⚠⚠ **基线文件里不许写注释**（门项会管）⇒ 这里**直接读原文**，
      不走 strip_comments ⇒ 门侧（strip_comments）与审计侧（原文）看到的是同一行。
    """
    path = GATE_BASELINE
    if not os.path.isfile(path):
        return None, '基线文件不存在：%s' % path
    raw = open(path, encoding='utf-8').read()
    txt = raw.strip()
    if not txt:
        return None, '基线文件是空的'
    if not txt.isdigit():
        return None, '基线文件内容不是纯数字：%r' % txt
    if len(raw.strip().split('\n')) != 1:
        return None, '基线文件不止一行'
    return int(txt), None


def check_dup_module_names():
    """模块级赋值名不许重复（同名 ⇒ 后定义覆盖先定义 ⇒ 先那个成了**死代码**）。

    ⚠⚠⚠ **为什么要有这条**（本批自己踩出来的，不是推演）：
      本批加「物理门项行」口径时用的常量名**撞了**文件下方已有的同名常量
      ⇒ 后者覆盖前者 ⇒ 前者成了**死代码** ⇒ 差点让**对拍口径**与实现脱节
      （而且**没有任何门会红** ⇒ 因为「串还在」，只是不生效了）。
      ⚠ 这一族（「同名互相顶替」）从批 AS 起反复出现 ⇒ 值得让机器盯。
    ⚠ **只看模块级赋值**（函数内的局部同名是正常的）⇒ 用 ast 精确判定，
      不用正则（正则分不清「赋值」和「比较」）。
    """
    import ast
    with open(os.path.abspath(__file__), encoding='utf-8') as fh:
        tree = ast.parse(fh.read())
    seen = {}
    dups = []
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for t in node.targets:
            if not isinstance(t, ast.Name):
                continue
            if t.id in seen:
                dups.append((t.id, seen[t.id], node.lineno))
            else:
                seen[t.id] = node.lineno
    return dups


def check_gate_totals():
    """核门项行数 ⇒ 结果字典。

    ⚠⚠ **判定逻辑只有一份**（批 BF/BG 纪律）：硬门模式与报告模式**都调它**
      ⇒ 报告里印的数就是硬门判的数 ⇒ 两边不会漂。
    ⚠⚠ **两条核对，互补**：
      ① 「审计器认领的门项数」==「文件里实际的门项行数」
         ⇒ 不等 = **有一种门型没在门型清单里登记** ⇒ 那些门项**根本没被审**
           （批 AR 说的「审计器自己有盲区」）⇒ 退出码 2（盲区）。
      ② 「文件里实际的门项行数」==「基线文件里的数字」
         ⇒ 不等 = **有门项被删了 / 被改成注释了** ⇒ 那些承诺**没人守了**
           ⇒ 退出码 6（门项总数失配）。
    """
    gcounts, gtotal, gphysical = count_gate_types(WIRING)
    gbase, gwhy = read_gate_baseline()
    msgs = []
    blind = False
    total_bad = False
    # ⚠⚠⚠ **模块级重名**（本批自己踩出来的洞）⇒ 排在**最前**：
    #   有重名 ⇒ 那个常量是**死代码** ⇒ 下面的核对可能**用错常量** ⇒
    #   ⇒ 必须先说「审计器自己有洞」，再说别的。
    dups = check_dup_module_names()
    if dups:
        blind = True
        for name, first, second in dups:
            msgs.append('审计器有**重名常量**：`%s` 在第 %d 行与第 %d 行各定义一次'
                        ' ⇒ 后者覆盖前者 ⇒ **前者是死代码**'
                        % (name, first, second))
    if gtotal != gphysical:
        blind = True
        msgs.append('审计器有门型盲区：认领 %d 条 vs 文件里实际 %d 条门项行'
                    ' ⇒ 有门型没登记 ⇒ 那些门项**不会被审**'
                    % (gtotal, gphysical))
    if gbase is None:
        total_bad = True
        msgs.append('门项行数基线不可用：%s' % gwhy)
    elif gphysical != gbase:
        total_bad = True
        msgs.append('门项行数与基线不符：文件里 %d 条 vs 基线 %d 条'
                    ' ⇒ **有门项被删了 / 被改成注释了** ⇒ 那些承诺**没人守了**'
                    % (gphysical, gbase))
    return {
        'counts': gcounts, 'claimed': gtotal, 'physical': gphysical,
        'baseline': gbase, 'baseline_why': gwhy,
        'blind': blind, 'total_bad': total_bad, 'dups': dups, 'msgs': msgs,
    }


def parse_wiring():
    """解析 ci-wiring.sh ⇒ (need 门项, ml 门项, any_count 门项, any_min 门项,
    count 门项, count_in_fn 门项, count_in_step 门项, 各门型行数,
    解析失败行号, arch_forbid 行数)"""
    src = open(WIRING, encoding='utf-8').read()
    lines = src.split('\n')
    need, ml, anyc, anym, cnt, cif, cis = [], [], [], [], [], [], []
    totals = {'need': 0, 'ml': 0, 'any_count': 0, 'any_min': 0,
              'count': 0, 'count_in_fn': 0, 'count_in_step': 0}
    failed, forbid_lines = [], 0
    for i, ln in enumerate(lines, 1):
        if ANY_FORBID_LINE.match(ln) and not FUNC_DEF_LINE.match(ln):
            forbid_lines += 1
        if FUNC_DEF_LINE.match(ln):
            continue
        if ANY_NEED_LINE.match(ln):
            totals['need'] += 1
            m = NEED_RE.match(ln) or NEED_RE_SQ.match(ln) or NEED_RE_DQ.match(ln)
            if not m:
                failed.append((i, 'need'))
                continue
            need.append((i, resolve(m.group(1)), m.group(2)))
            continue
        if ML_LINE.match(ln):
            totals['ml'] += 1
            m = ML_LINE.match(ln)
            ml.append((i, resolve(m.group(1)), m.group(2)))
            continue
        if ANY_COUNT_LINE.match(ln):
            totals['any_count'] += 1
            m = ANY_COUNT_LINE.match(ln)
            anyc.append((i, m.group(1), int(m.group(2)), m.group(4) or DEFAULT_ANY_GLOB))
            continue
        if ANY_MIN_LINE.match(ln):
            totals['any_min'] += 1
            m = ANY_MIN_LINE.match(ln)
            anym.append((i, m.group(1), int(m.group(2)), m.group(4) or DEFAULT_ANY_GLOB))
            continue
        if COUNT_LINE.match(ln):
            totals['count'] += 1
            m = COUNT_LINE.match(ln)
            cnt.append((i, resolve(m.group(1)), m.group(2), int(m.group(3))))
            continue
        if COUNT_IN_STEP_LINE.match(ln):
            totals['count_in_step'] += 1
            m = COUNT_IN_STEP_LINE.match(ln)
            cis.append((i, resolve(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4))))
            continue
        if COUNT_IN_FN_LINE.match(ln):
            totals['count_in_fn'] += 1
            m = COUNT_IN_FN_LINE.match(ln)
            cif.append((i, resolve(m.group(1)), m.group(2), m.group(3), int(m.group(4))))
            continue
        if COUNT_FAMILY_LINE.match(ln):
            # ⚠⚠ 走到这里 = 这一行**没被任何 count 门型解析到** ⇒ 审计器有盲区
            #   （批 BE：写坏的 count 族门项以前是**静默忽略** ⇒ 没人知道它没被审）
            failed.append((i, 'count-family'))
            continue
    return need, ml, anyc, anym, cnt, cif, cis, totals, failed, forbid_lines


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
    return keys, True, len(keys)


def check_min_gates(min_items):
    """校准 `arch_need_min` 的下限：必须 **== 当前命中数**。

    ⚠ 下限 < 命中数 ⇒ **门没牙**（删一处仍够 ⇒ 不红）——
      批 AU 实测踩到：`Canvas2D` 在 HeatmapWidget.cpp 里命中 4 次
      （include + 3 处构造），下限写 3 ⇒ 删掉一处构造仍剩 3 ⇒ 门照样绿。
    ⚠ 下限 > 命中数 ⇒ **门恒红**。
    ⇒ 这条校准把「`arch_need_min` 不在审计覆盖内」那个缺口补上了一半：
      它的「串不唯一」是**语义允许**的，但**下限必须配得准**。
    """
    bad = []
    for lineno, f, rx, want in min_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, rx, want, None, '文件不存在'))
            continue
        got = count_hits(f, rx)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, f, rx, want, got,
                        '下限 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


def check_count_gates(count_items):
    """校准 `arch_need_count` 的期望次数：必须 **== 当前命中数**。

    ⚠ 期望 < 实际 ⇒ 门**没牙**（删一处仍够 ⇒ 不红）；
      期望 > 实际 ⇒ 门**恒红**。
    ⚠ 这条门自己数次数 ⇒ 天然有牙，但「把期望改大来躲变异」没人盯 ⇒ 这里补上。
    """
    bad = []
    for lineno, f, rx, want in count_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, rx, want, None, '文件不存在'))
            continue
        got = count_hits(f, rx)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, f, rx, want, got,
                        '期望 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


def check_count_in_fn_gates(cif_items):
    """校准 `arch_need_count_in_fn` 的期望次数（函数体内）。

    ⚠ 切函数体的那段 awk **从 ci-wiring.sh 原文抽取** ⇒ 零漂移。
    """
    awk_src = extract_fn_body_awk()
    if awk_src is None:
        return []
    bad = []
    for lineno, f, sig, rx, want in cif_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, sig, rx, want, None, '文件不存在'))
            continue
        out = subprocess.run(
            ['awk', '-v', 'sig=' + sig, awk_src],
            input=strip_comments(f), capture_output=True, text=True)
        body = out.stdout
        if not body.strip():
            bad.append((lineno, f, sig, rx, want, None, '找不到函数体'))
            continue
        r = subprocess.run(['grep', '-oE', '--', rx], input=body,
                           capture_output=True, text=True)
        got = len([x for x in r.stdout.split('\n') if x])
        if got != want:
            bad.append((lineno, f, sig, rx, want, got,
                        '期望 %d ≠ 函数体内实际 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


def check_count_in_step_gates(cis_items):
    """校准 `arch_need_count_in_step` 的期望次数：必须 == **该步正文里**的实际命中数。

    ⚠⚠ **切步骤正文的那段 awk 从 ci-wiring.sh 原文抽取** ⇒ 零漂移
      （门侧改了切段口径，审计侧自动跟着变 ⇒ 不会两套口径打架）。
    ⚠ 期望值被改大来躲变异（例如 1 改成 2）⇒ 这里立刻报「没配准」⇒ 红。
    """
    awk_src = extract_step_awk()
    if awk_src is None:
        return []
    bad = []
    for lineno, f, step, rx, want in cis_items:
        if not os.path.isfile(f):
            bad.append((lineno, f, rx, want, None, '文件不存在'))
            continue
        out = subprocess.run(
            ['awk', '-v', 'step=%d' % step, awk_src],
            input=strip_comments(f), capture_output=True, text=True)
        body = out.stdout
        if not body.strip():
            bad.append((lineno, f, rx, want, None,
                        '抽不出第 %d 步的正文（打点行没找到？）' % step))
            continue
        r = subprocess.run(['grep', '-oE', '--', rx], input=body,
                           capture_output=True, text=True)
        got = len([x for x in r.stdout.split('\n') if x])
        if got != want:
            bad.append((lineno, f, rx, want, got,
                        '第 %d 步正文里期望 %d ≠ 实际 %d ⇒ %s'
                        % (step, want, got, '门没牙（挪走仍够）' if got > want else '门恒红')))
    return bad


def check_any_gates(anyc_items, anym_items, counter):
    """校准跨文件的两个门型：
      · `arch_need_any_count`：实际总命中 == 期望
      · `arch_need_any_min`：下限 == 实际总命中（否则门没牙/恒红）

    ⚠ **总命中数** = glob 范围内**所有**匹配文件命中数**加总**
      —— 跨文件多现**同样是洞**（批 AV 实测的老 `arch_need_any` 洞就在这）。
    """
    bad = []
    for lineno, rx, want, gl in anyc_items:
        got = counter.get(rx, gl)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, 'any_count', gl, rx, want, got,
                        '期望 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    for lineno, rx, want, gl in anym_items:
        got = counter.get(rx, gl)
        if got is None:
            continue
        if got != want:
            bad.append((lineno, 'any_min', gl, rx, want, got,
                        '下限 %d ≠ 实际命中 %d ⇒ %s'
                        % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
    return bad


def main():
    args = sys.argv[1:]
    want_list = '--list' in args
    want_list_all = '--list-all' in args
    base = None
    if '--changed' in args:
        i = args.index('--changed')
        base = args[i + 1] if i + 1 < len(args) else 'HEAD~1'

    (need, ml, anyc, anym, cnt, cif, cis,
     totals, failed, forbid_lines) = parse_wiring()

    if base is not None:
        nums = changed_lines(base)
        if nums is None:
            print('审计失败：git diff %s 拿不到' % base, file=sys.stderr)
            return 2
        need = [x for x in need if x[0] in nums]
        ml = [x for x in ml if x[0] in nums]
        anyc = [x for x in anyc if x[0] in nums]
        anym = [x for x in anym if x[0] in nums]
        cnt = [x for x in cnt if x[0] in nums]
        cif = [x for x in cif if x[0] in nums]
        cis = [x for x in cis if x[0] in nums]

    # ⚠ 跨文件命中数：一次批量算（口径 = 抽取自 ci-wiring.sh 的 any_hits）
    pairs = [(rx, gl) for _, rx, _, gl in anyc] + [(rx, gl) for _, rx, _, gl in anym]
    try:
        counter = AnyCounter(pairs)
    except RuntimeError as e:
        print('审计失败：%s' % e, file=sys.stderr)
        return 2

    multi, zero = [], []
    for lineno, f, rx in need:
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

    mlmulti = []
    for lineno, f, rx in ml:
        if not os.path.isfile(f):
            zero.append((lineno, f, rx, '文件不存在'))
            continue
        n = count_hits_ml(f, rx)
        if n is None:
            continue
        if n == 0:
            zero.append((lineno, f, rx, '命中 0 次'))
        elif n > 1:
            mlmulti.append((lineno, f, rx, n))

    # 豁免键：`<类型>:<相对路径|glob>|<正则>`
    keys = ['need:%s|%s' % (rel(f), rx) for _, f, rx, _ in multi]
    keys += ['ml:%s|%s' % (rel(f), rx) for _, f, rx, _ in mlmulti]
    exempt, exempt_exists, exempt_rows = read_exempt()
    outside = [k for k in keys if k not in exempt]
    stale = [k for k in exempt if k not in set(keys)]

    if want_list_all:
        for k in keys:
            print(k)
        return 0

    if want_list:
        # ⚠⚠⚠ **门项总数核对**（批 BH）——「门项被悄悄删」此前**无人发现**。
        #   ⚠ 只在**全量**模式下做（--changed 只审新增门项 ⇒ 门项总数本就不全）
        if base is None:
            # ⚠⚠⚠ **门项总数核对**（批 BH）——「门项被悄悄删」此前**无人发现**。
            #   ⚠ 只在**全量**模式下做（--changed 只审新增门项 ⇒ 门项总数本就不全）
            #   ⚠ 判定逻辑在 `check_gate_totals()` 里（**只有一份** ⇒ 报告与硬门不漂）
            g = check_gate_totals()
            if g['dups']:
                for m in g['msgs']:
                    print(m, file=sys.stderr)
                return 7
            if g['blind']:
                for m in g['msgs']:
                    print(m, file=sys.stderr)
                return 2
            if g['total_bad']:
                for m in g['msgs']:
                    print(m, file=sys.stderr)
                return 6
        # 硬门模式：只吐**豁免之外**的隐患；有 ⇒ 退出码 3（红）
        if not exempt_exists:
            print('豁免基线文件不在：%s' % EXEMPT, file=sys.stderr)
            return 2
        if failed:
            # ⚠ **审计器自己有盲区 ⇒ 那些门根本没被审** ⇒ 必须红。
            #   否则「审不到的门项」就成了逃逸口（批 AR「只声明不编译也算出现」的同构：
            #   判据写在那里，却没有任何机制保证它**真的被检查**）。
            print('审计器有盲区：%d 行门项没解析到（%s）⇒ 它们**没被审**'
                  % (len(failed), ','.join('%d行/%s' % x for x in failed)), file=sys.stderr)
            return 2
        # ⚠⚠⚠ **门项正则的写法体检**（批 AX）：正则里写了 GNU grep -E **不认**的转义
        #   （`\d` / `\D`）⇒ 那条门**永远匹配不到任何东西** ⇒ **门形同虚设**。
        #   ⚠ 对 `arch_forbid` 门这是**静默**失效（forbid 本来就常年绿 ⇒ 写坏了跟没写一样）。
        rxsyn = check_rx_syntax()
        if rxsyn:
            print('门项正则里有 grep -E **不认**的转义（%d 条）⇒ 这些门**永远匹配不到**'
                  % len(rxsyn), file=sys.stderr)
            for lineno, kind, rx, be in rxsyn:
                print('  · %s:%d  [%s] 正则=%s  危险转义=%s'
                      % (os.path.basename(WIRING), lineno, kind, rx,
                         ','.join(t for _, t in be)), file=sys.stderr)
            print('  ⇒ 改用 POSIX 写法：`\\d` → `[0-9]`、`\\D` → `[^0-9]`', file=sys.stderr)
            return 5
        # ⚠⚠ **「命中 0 次」也是红**（批 AX 补的第二个盲区）：
        #   `arch_need` / `arch_need_ml` 的语义是「**必须存在**这个串」
        #   ⇒ 命中 0 次 = 门永远匹配不到 = 门是空的。
        #   （这两类门在 ci-wiring.sh 里自己就会红 ⇒ 不是静默失效；
        #     但在**提交前**由审计器明确指出「哪条门是空的」比让 CI 报一堆 ✗ 更好。）
        if zero:
            print('有门项**命中 0 次**（%d 条）⇒ 那些门**永远匹配不到**（形同虚设）'
                  % len(zero), file=sys.stderr)
            for lineno, f, rx, why in zero:
                print('  · %s:%d  %s  %s | %s'
                      % (os.path.basename(WIRING), lineno, why, rel(f), rx), file=sys.stderr)
            return 5
        # ⚠ 次数门的**配准校准**（下限/期望 必须 == 实际命中数）
        minbad = []
        for lineno, f, rx, want in parse_min_gates():
            if not os.path.isfile(f):
                minbad.append((lineno, f, rx, want, None, '文件不存在'))
                continue
            got = count_hits(f, rx)
            if got is None:
                continue
            if got != want:
                minbad.append((lineno, f, rx, want, got,
                               '下限 %d ≠ 实际命中 %d ⇒ %s'
                               % (want, got, '门没牙（删一处仍够）' if got > want else '门恒红')))
        cntbad = check_count_gates(cnt)
        cifbad = check_count_in_fn_gates(cif)
        cisbad = check_count_in_step_gates(cis)
        anybad = check_any_gates(anyc, anym, counter)
        bad_all = minbad + cntbad + cifbad + cisbad + anybad
        if bad_all:
            print('次数门没配准（%d 条）：' % len(bad_all), file=sys.stderr)
            for b in bad_all:
                if b[1] == 'any_count' or b[1] == 'any_min':
                    _, kind, gl, rx, want, got, why = b
                    print('  · %s:%d  [%s] %s | %s ⇒ %s'
                          % (os.path.basename(WIRING), _, kind, gl, rx, why),
                          file=sys.stderr)
                elif len(b) == 6:
                    lineno, f, rx, want, got, why = b
                    print('  · %s:%d  %s | %s ⇒ %s'
                          % (os.path.basename(WIRING), lineno, rel(f), rx, why),
                          file=sys.stderr)
                else:
                    lineno, f, sig, rx, want, got, why = b
                    print('  · %s:%d  %s  fn=%s | %s ⇒ %s'
                          % (os.path.basename(WIRING), lineno, rel(f), sig, rx, why),
                          file=sys.stderr)
            return 4
        for k in outside:
            print(k)
        return 3 if outside else 0

    print('门自审计：ci-wiring.sh 里的门项')
    print('  arch_need %d 条 / arch_need_ml %d 条 / arch_need_any_count %d 条 / '
          'arch_need_any_min %d 条' % (totals['need'], totals['ml'],
                                        totals['any_count'], totals['any_min']))
    print('  arch_need_count %d 条 / arch_need_count_in_fn %d 条'
          % (totals['count'], totals['count_in_fn']))
    print('  arch_need_count_in_step %d 条（批 BE 新门型：盯「标记串**还在这一步里**」）'
          % totals['count_in_step'])
    print('（arch_forbid 门项 %d 条**有意不审**：它判「不该有的东西没了」，'
          '目标串出现 >0 本来就红，不属于「被别处顶替」的隐患）' % forbid_lines)
    # ⚠⚠⚠ 门项行总数（批 BH）：三个数摆在一起 ⇒ 差在哪一眼看得出
    g = check_gate_totals()
    print('门项行总数：文件里 **%d** 条（审计器认领 %d 条）｜基线 %s'
          % (g['physical'], g['claimed'],
             ('%d' % g['baseline']) if g['baseline'] is not None
             else ('**不可用（%s）**' % g['baseline_why'])))
    for m in g['msgs']:
        print('  ⚠ %s' % m)
    if failed:
        print('⚠ **审计器有盲区**：有 %d 行门项没解析到（%s）'
              % (len(failed), ','.join('%d行/%s' % x for x in failed)))
        print('   ⇒ 这些门**审不到**（写法变了？）⇒ 审计器本身要改，不能静默漏审')
    rxsyn = check_rx_syntax()
    print('门项正则写法体检（grep -E 认不认）：%d 条危险' % len(rxsyn))
    for lineno, kind, rx, be in rxsyn:
        print('  · %s:%d  [%s] 正则=%s  危险转义=%s'
              % (os.path.basename(WIRING), lineno, kind, rx,
                 ','.join(t for _, t in be)))
    if rxsyn:
        print('   ⇒ 这些门**永远匹配不到**（形同虚设）⇒ 改用 POSIX 写法（`\\d` → `[0-9]`）')
    if base is not None:
        print('（只审 %s..HEAD 的新增门项）' % base)

    print('arch_need 命中 >1 次 ⇒ **改一处骗得过门**：%d 条' % len(multi))
    for lineno, f, rx, n in multi:
        mark = '（已豁免）' if 'need:%s|%s' % (rel(f), rx) in exempt else '**⇒ 硬门会红**'
        print('  · %s:%d  命中 %d 次  %s  %s'
              % (os.path.basename(WIRING), lineno, n, rel(f), mark))
        print('      正则：%s' % rx)
    print('arch_need_ml 压行后命中 >1 次 ⇒ **改一处骗得过门**：%d 条' % len(mlmulti))
    for lineno, f, rx, n in mlmulti:
        mark = '（已豁免）' if 'ml:%s|%s' % (rel(f), rx) in exempt else '**⇒ 硬门会红**'
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

    minbad = check_min_gates(parse_min_gates())
    print('arch_need_min 下限校准（须 == 实际命中数）：%d 条失准' % len(minbad))
    for lineno, f, rx, want, got, why in minbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), rx, why))

    cntbad = check_count_gates(cnt)
    print('arch_need_count 期望校准（须 == 实际命中数）：%d 条失准' % len(cntbad))
    for lineno, f, rx, want, got, why in cntbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), rx, why))

    cifbad = check_count_in_fn_gates(cif)
    print('arch_need_count_in_fn 期望校准（须 == 函数体内实际次数）：%d 条失准' % len(cifbad))
    for lineno, f, sig, rx, want, got, why in cifbad:
        print('  · %s:%d  %s  fn=%s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), sig, rx, why))

    cisbad = check_count_in_step_gates(cis)
    print('arch_need_count_in_step 期望校准（须 == **该步正文里**实际次数）：%d 条失准'
          % len(cisbad))
    for lineno, f, rx, want, got, why in cisbad:
        print('  · %s:%d  %s | %s ⇒ %s'
              % (os.path.basename(WIRING), lineno, rel(f), rx, why))

    anybad = check_any_gates(anyc, anym, counter)
    print('arch_need_any_count / arch_need_any_min 配准校准：%d 条失准' % len(anybad))
    for b in anybad:
        _, kind, gl, rx, want, got, why = b
        print('  · %s:%d  [%s] %s | %s ⇒ %s'
              % (os.path.basename(WIRING), _, kind, gl, rx, why))

    if stale:
        print('豁免基线里**已失效**（门已收紧，可以清掉）：%d 条' % len(stale))
        for k in stale:
            print('  · %s' % k)
    print('命中 0 次 ⇒ **门本身就是红的**：%d 条' % len(zero))
    for lineno, f, rx, why in zero:
        print('  · %s:%d  %s  %s' % (os.path.basename(WIRING), lineno, why, rel(f)))
        print('      正则：%s' % rx)
    return 0


def parse_min_gates():
    """解析所有 `arch_need_min` 门项 ⇒ [(行号, 文件, 正则, 下限)]"""
    out = []
    src = open(WIRING, encoding='utf-8').read()
    for i, ln in enumerate(src.split('\n'), 1):
        m = NEED_MIN_LINE.match(ln)
        if m:
            out.append((i, resolve(m.group(1)), m.group(2), int(m.group(3))))
    return out


# ⚠⚠⚠ **门项正则的「写法体检」**（批 AX）——
# ⚠ **起因（本批实测抓到）**：门是用 `grep -E` 匹配的 ⇒ 只有 **GNU grep -E 认的**
#   转义才有效。实测（GNU grep 3.11）：
#     `\s` `\S` `\w` `\W` `\b` **都有效**（GNU 扩展），
#     ⚠⚠ **`\d` / `\D` 无效**（那是 `grep -P` 的 Perl 扩展）⇒
#     写了 `\d` 的门 **永远匹配不到任何东西** ⇒ **门形同虚设**。
# ⚠⚠ **为什么这是「静默」失效（比批 AS 那种更隐蔽）**：
#   · `arch_need` 门写坏了 ⇒ 匹配不到 ⇒ **门自己会红** ⇒ CI 能发现（不算静默）；
#   · ⚠ **`arch_forbid` 门写坏了 ⇒ 永远零命中 ⇒ 永远绿** ⇒
#     **没有任何信号** ⇒ 而 forbid 门判的正是「不该有的东西没了」⇒
#     这类门**本来就是绿的** ⇒ 写坏了跟没写一样 ⇒ **静默**。
#     （本批实测：仓里现有 forbid 门**一条都没写坏** ⇒ 批 AP 那 11 条
#      「不许再开 1x 位图」的门**是真门**，不是空门。）
# ⇒ 下面这项检查把「写坏了」当场抓出来。
#
# ⚠ **只列实测确认无效的**（`\s`/`\S`/`\w`/`\W`/`\b` 都有效 ⇒ 不许误报）。
BAD_ESCAPES = ('d', 'D')


def split_args(rest):
    """把门项行的参数部分切成列表（支持 '…' 与 "…" 两种引号；引号本身不入参）。"""
    args, cur, i, q = [], '', 0, None
    while i < len(rest):
        c = rest[i]
        if q:
            if c == q:
                q = None
            else:
                cur += c
        else:
            if c in "'\"":
                q = c
            elif c.isspace():
                if cur:
                    args.append(cur)
                    cur = ''
            else:
                cur += c
        i += 1
    if cur:
        args.append(cur)
    return args


# 门型 → **正则参数**在参数列表里的下标（0-based）。
# ⚠ `arch_forbid_han`（盯内容不看写法）与 `arch_forbid_text_dup`（盯重复文本）没有正则参数。
RX_ARG_IDX = {
    'arch_need': 1, 'arch_need_ml': 1, 'arch_need_min': 1,
    'arch_need_count': 1, 'arch_need_count_in_fn': 2,
    # ⚠ 批 BE 新门型：<文件> <步号> <正则> <期望次数> ⇒ 正则在第 3 个参数（index 2）
    'arch_need_count_in_step': 2,
    'arch_need_any_count': 0, 'arch_need_any_min': 0,
    'arch_forbid': 1, 'arch_forbid_ml': 1, 'arch_forbid_raw': 1,
    'arch_forbid_tree': 0,
}
GATE_LINE = re.compile(r'^\s*(arch_[a-z_]+)\s+(.*)$')


def bad_escapes(rx):
    """找出「**单个**反斜杠 + d/D」的位置 —— GNU grep -E 不认 ⇒ 门永远匹配不到。

    ⚠ `\\\\d`（**两个**反斜杠）是「字面反斜杠 + d」⇒ 合法，不算。
    ⇒ 判据 = 「连续反斜杠数为**奇数**」⇒ 最后一个反斜杠是转义符。
    """
    out = []
    i = 0
    while i < len(rx):
        if rx[i] == '\\':
            j = i
            while j < len(rx) and rx[j] == '\\':
                j += 1
            n = j - i
            if j < len(rx) and rx[j] in BAD_ESCAPES and n % 2 == 1:
                out.append((i, '\\' + rx[j]))
            i = j
        else:
            i += 1
    return out


def check_rx_syntax():
    """体检**所有**门项的正则参数 ⇒ [(行号, 门型, 正则, 危险转义)]"""
    bad = []
    src = open(WIRING, encoding='utf-8').read()
    for i, ln in enumerate(src.split('\n'), 1):
        m = GATE_LINE.match(ln)
        if not m:
            continue
        kind, rest = m.group(1), m.group(2)
        idx = RX_ARG_IDX.get(kind)
        if idx is None:
            continue
        args = split_args(rest)
        if len(args) <= idx:
            continue
        rx = args[idx]
        be = bad_escapes(rx)
        if be:
            bad.append((i, kind, rx, be))
    return bad


if __name__ == '__main__':
    sys.exit(main())
