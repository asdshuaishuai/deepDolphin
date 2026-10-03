// CrashHandler.cpp — M4c 最小崩溃 handler 实现（PLAN M4「崩溃可观测」，
// journal appender 已在 main 注册（M0-9），这里补进程崩溃这一段）。
//
// 取舍（诚实记录）：
// · 回溯打 stderr 用 backtrace_symbols_fd 而非 backtrace_symbols：后者要把整段
//   字符串 malloc 出来——崩溃点若正持有分配锁，signal 里再 malloc 就是死锁；
//   fd 变体直接 write 到 stderr，是本家族里最接近 async-signal-safe 的形态。
//   backtrace() 本身（栈展开）不保证 signal 安全，属 PLAN M4c「尽量」口径的
//   实践可接受项：读不到栈的风险远小于一行栈都没有。
// · 进 handler 第一件事是把两个信号都摘回 SIG_DFL：若回溯途中再崩（展开不总
//   安全），按默认处置直落，绝不递归。任务口径写的「打完再恢复」在观测效果上
//   等价（打栈→按默认语义终止），只是把恢复动作提前到入口更稳。
// · 打完栈 raise(原信号)：此刻处置已是默认 → 内核按信号语义终止（shell 报
//   139/134，ulimit -c 允许时落 core）。既不"优雅退出"也不吞崩溃。
// · 已知边界：栈溢出型 SIGSEGV 可能连 handler 都没有栈可跑（未上 sigaltstack，
//   最小 handler 不做）；主程序帧符号名需 -rdynamic，未开时只有地址
//   （libc 帧可解析；地址可用 addr2line 人工定位）。
#include "platform/CrashHandler.h"

#include <execinfo.h>
#include <signal.h>
#include <sys/types.h>
#include <unistd.h>

#include <cstddef>

namespace {

constexpr int kMaxFrames = 64; // 上限：定位足够，同时控制 signal 里的工作量

// signal 安全的字符串输出：只 write，不碰 stdio（其内部锁非 signal 安全）。
void writeStr(const char *s)
{
    size_t len = 0;
    while (s[len] != '\0')
        ++len;
    size_t off = 0;
    while (off < len) {
        const ssize_t n = ::write(STDERR_FILENO, s + off, len - off);
        if (n <= 0)
            return; // stderr 写不进就放弃：观测失败不阻挠崩溃收尾
        off += static_cast<size_t>(n);
    }
}

const char *signalName(int sig)
{
    switch (sig) {
    case SIGSEGV:
        return "SIGSEGV";
    case SIGABRT:
        return "SIGABRT";
    default:
        return "?"; // 只装了这两个信号，理论不可达；防御性兜底
    }
}

void handler(int sig)
{
    // 先摘链再干活：回溯途中再崩按默认处置直落，不递归（见文件头取舍）
    ::signal(SIGSEGV, SIG_DFL);
    ::signal(SIGABRT, SIG_DFL);

    writeStr("\n[crash] deepDolphin 收到 ");
    writeStr(signalName(sig));
    writeStr("，栈回溯（主程序帧为地址，可 addr2line 定位）：\n");

    void *frames[kMaxFrames];
    const int n = ::backtrace(frames, kMaxFrames);
    ::backtrace_symbols_fd(frames, n, STDERR_FILENO);

    // 恢复默认处置后重发：退出语义与未装 handler 一致（WIFSIGNALED + 可 core）
    ::raise(sig);
}

} // namespace

namespace CrashHandler {

void install()
{
    static bool installed = false;
    if (installed)
        return;
    installed = true;

    struct sigaction sa {};
    sa.sa_handler = handler;
    ::sigemptyset(&sa.sa_mask);
    // 不设 SA_RESETHAND/SA_NODEFER：handler 自身第一步摘链，语义等价且更显式；
    // 不置 SA_RESTART——崩溃路径上没有需要重启的系统调用。
    ::sigaction(SIGSEGV, &sa, nullptr);
    ::sigaction(SIGABRT, &sa, nullptr);
}

} // namespace CrashHandler
