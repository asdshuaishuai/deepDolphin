# deepDolphin AI 通道端到端测试用的**假 provider**。
#
# 它不是 mock 的一半：它会**逐项校验**客户端发来的请求体，
# 校验不过就返回 "E2E-WRONG" 让判据红。所以它能抓住
# 「请求拼错了但客户端没察觉」这一族缺陷 ——
# 那正是纯函数判据（只测组装逻辑）盖不到的。
import http.server
import json
import os
import sys

PORT = int(os.environ.get("MOCK_PORT", "18742"))
LOG = open(os.environ.get("MOCK_LOG", "/tmp/deepdolphin-mock-agent.log"), "w")
MODE = os.environ.get("MOCK_MODE", "agent")


def log(msg):
    LOG.write(msg + "\n")
    LOG.flush()


class Handler(http.server.BaseHTTPRequestHandler):
    def _reply(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        log("PATH=%s AUTH=%s CTYPE=%s" % (
            self.path, self.headers.get("Authorization"), self.headers.get("Content-Type")))
        try:
            body = json.loads(raw.decode("utf-8"))
        except Exception as e:
            log("PARSE_FAIL=%s" % e)
            self._reply({"error": "bad json"}, 400)
            return
        log("BODY=%s" % json.dumps(body, ensure_ascii=False))
        if MODE == "plain":
            # 一次性补全：校验请求体每一个字段，含中文与转义。
            msgs = body.get("messages", [])
            ok = (body.get("model") == "test-model"
                  and body.get("stream") is False
                  and body.get("max_tokens") == 100
                  and len(msgs) == 2
                  and msgs[1]["content"] == "中文提问：项目群现在怎么样？带 \"引号\" 和换行\n")
            log("PLAIN_CORRECT=%s" % ok)
            self._reply({"choices": [{"message": {"content": "E2E-OK" if ok else "E2E-WRONG"}}]})
            return
        # agent 模式：第一轮要工具，第二轮收尾。
        if MODE == "multi" and not any(m["role"] == "tool" for m in body["messages"]):
            # 一次要**三个**工具：用来验「按停止之后剩下那几个不执行」。
            # 三个都是读操作 —— 真去跑写操作会改用户仓库，不该由测试触发。
            log("MULTI_CALLS=3")
            msg = {"role": "assistant", "content": "我并行看三处。",
                   "tool_calls": [
                       {"id": "c1", "type": "function",
                        "function": {"name": "get_milestones", "arguments": "{}"}},
                       {"id": "c2", "type": "function",
                        "function": {"name": "get_group_context", "arguments": "{}"}},
                       {"id": "c3", "type": "function",
                        "function": {"name": "get_milestones", "arguments": "{}"}}]}
            self._reply({"choices": [{"message": msg}]})
            return
        has_tool = any(m["role"] == "tool" for m in body["messages"])
        if has_tool:
            tool_text = [m for m in body["messages"] if m["role"] == "tool"][0]["content"]
            log("TOOL_RESULT_LEN=%d" % len(tool_text))
            msg = {"role": "assistant",
                   "content": "工具返回了 %d 字符，这是收尾答案。" % len(tool_text)}
        else:
            msg = {"role": "assistant", "content": "",
                   "tool_calls": [{"id": "call_1", "type": "function",
                                   "function": {"name": "get_milestones", "arguments": "{}"}}]}
        self._reply({"choices": [{"message": msg}]})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
