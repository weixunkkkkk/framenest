#!/usr/bin/env python3
"""End-to-end MCP checks over stdio. Uses synthetic files in temporary folders."""
import argparse
import json
import queue
import subprocess
import tempfile
import threading
from pathlib import Path


class JSONLineClient:
    def __init__(self, command):
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1)
        self.messages = queue.Queue()
        self.notifications = []
        self.errors = []
        self.sequence = 0
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._errors, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except Exception as error:
                self.messages.put({"invalid_stdout": line, "parse_error": str(error)})

    def _errors(self):
        for line in self.process.stderr:
            self.errors.append(line.rstrip())

    def send(self, message):
        self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.process.stdin.flush()

    def request(self, method, params=None, timeout=20, jsonrpc=True):
        self.sequence += 1
        request = {"id": self.sequence, "method": method, "params": params or {}}
        if jsonrpc:
            request["jsonrpc"] = "2.0"
        self.send(request)
        while True:
            message = self.messages.get(timeout=timeout)
            if "invalid_stdout" in message:
                raise AssertionError(message)
            if message.get("id") == self.sequence:
                return message
            self.notifications.append(message)

    def tool(self, name, arguments=None, error=False, progress=False):
        params = {"name": name, "arguments": arguments or {}}
        if progress:
            params["_meta"] = {"progressToken": "copy-test"}
        response = self.request("tools/call", params)
        assert "error" not in response, response
        value = response["result"]
        assert bool(value.get("isError")) == error, value
        if error:
            return value
        return value.get("structuredContent") or json.loads(value["content"][0]["text"])

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)


def run(binary):
    count = 0

    def check(condition, label):
        nonlocal count
        assert condition, label
        count += 1
        print("PASS " + label)

    client = JSONLineClient([str(binary.resolve())])
    try:
        initialize = client.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                                     "clientInfo": {"name": "framenest-check", "version": "1.0"}})
        check(initialize["result"]["protocolVersion"] == "2025-11-25", "MCP initialization")
        check(initialize["result"]["serverInfo"]["name"] == "framenest", "server identity")
        client.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        check(client.request("ping")["result"] == {}, "ping")
        tools = client.request("tools/list")["result"]["tools"]
        check(len(tools) == 6, "six tools discovered")
        check({t["name"] for t in tools} == {"get_template", "create_project", "classify_files", "preview_organize", "get_plan", "execute_organize"}, "tool names")
        check(all(t["inputSchema"]["type"] == "object" for t in tools), "input schemas")
        check(next(t for t in tools if t["name"] == "preview_organize")["annotations"]["readOnlyHint"], "preview is read-only")
        check(next(t for t in tools if t["name"] == "execute_organize")["annotations"]["destructiveHint"], "execution declares move capability")
        template = client.tool("get_template")
        check("05_字幕" in template["default_folders"], "shared folder template")
        values = client.tool("classify_files", {"paths": ["口播精剪.mp4", "BGM/啸叫原声.wav", "外壳.step"]})["items"]
        check(values[0]["category"] == "07_导出/成片", "shared video classification")
        check(values[1]["category"] == "03_音频/配音与现场声", "filename precedence")
        check(values[2]["category"] == "06_工程/产品模型与PCB", "product model classification")
        client.tool("classify_files", {"paths": ["demo.mp4"], "unexpected": True}, error=True)
        check(True, "unexpected argument rejected")
        check(client.request("unknown/method")["error"]["code"] == -32601, "unknown method error")
        check(client.request("tools/call", {"name": "unknown"})["error"]["code"] == -32602, "unknown tool error")

        with tempfile.TemporaryDirectory(prefix="framenest-mcp-check-") as temporary:
            root = Path(temporary).resolve()
            source = root / "source"
            source.mkdir()
            created = client.tool("create_project", {"parent_path": str(root), "name": "评测项目", "folders": template["default_folders"]})
            destination = Path(created["project_path"])
            check(destination.is_dir() and destination.name == "评测项目", "project created through MCP")
            check(Path(created["note_path"]).is_file(), "Markdown project note")
            client.tool("create_project", {"parent_path": str(root), "name": "评测项目"}, error=True)
            check(True, "existing project is not overwritten")
            client.tool("create_project", {"parent_path": str(root), "name": "../escape"}, error=True)
            check(not (root.parent / "escape").exists(), "project path traversal rejected")
            client.tool("create_project", {"parent_path": "relative", "name": "bad"}, error=True)
            check(not (root / "bad").exists(), "relative root path rejected")
            fixtures = ["口播精剪.mp4", "BGM/啸叫原声.wav", "原始/C0001.mp4", "KM003C_烤机60W.parquet", "外壳.step"]
            for name in fixtures:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("synthetic filename fixture: " + name)
            engine = source / "HyperFrames动画"
            engine.mkdir()
            (engine / "hyperframes.json").write_text("{}")
            (engine / "assets").mkdir()
            (engine / "assets/frame.png").write_text("synthetic animation resource")
            preview = client.tool("preview_organize", {"source_path": str(source), "destination_path": str(destination), "limit": 2})
            check(preview["total_items"] == 6 and len(preview["items"]) == 2 and preview["has_more"], "bounded preview and project grouping")
            check(not list(destination.rglob("口播精剪.mp4")), "preview makes no destination writes")
            page = client.tool("get_plan", {"plan_id": preview["plan_id"], "offset": 2, "limit": 200})
            check(len(page["items"]) == 4 and not page["has_more"], "plan pagination")
            check(any(i["whole_directory"] for i in preview["items"] + page["items"]), "complete engineering directory in plan")
            client.tool("execute_organize", {"plan_id": "unknown"}, error=True)
            check(True, "execution requires a valid preview")
            client.tool("execute_organize", {"plan_id": preview["plan_id"], "include_paths": ["not-in-plan"]}, error=True)
            check(True, "files outside plan rejected")
            client.tool("execute_organize", {"plan_id": preview["plan_id"], "overrides": [{"relative_path": "外壳.step", "category": "../escape"}]}, error=True)
            check(True, "unsafe category rejected before copying")
            selected = ["原始/C0001.mp4", "HyperFrames动画", "KM003C_烤机60W.parquet"]
            execute_args = {"plan_id": preview["plan_id"], "include_paths": selected,
                            "overrides": [{"relative_path": "原始/C0001.mp4", "category": "02_原始素材/产品实拍"}]}
            result = client.tool("execute_organize", execute_args, progress=True)
            check(result["copied"] == 3 and result["failed"] == 0, "selected copy and category override")
            check((destination / "02_原始素材/产品实拍/原始/C0001.mp4").read_bytes() == (source / "原始/C0001.mp4").read_bytes(), "copied contents and source preserved")
            check((destination / "06_工程/动画/HyperFrames动画/assets/frame.png").is_file(), "project internal references preserved")
            check(not list(destination.rglob("口播精剪.mp4")), "unselected files not copied")
            check(Path(result["report_path"]).suffix == ".md" and Path(result["report_path"]).is_file(), "structured result and Markdown report")
            check(any(n.get("method") == "notifications/progress" for n in client.notifications), "progress notifications")
            reports = list(destination.rglob("素材归类_*.md"))
            replay = client.tool("execute_organize", execute_args)
            check(replay["reused_result"] and list(destination.rglob("素材归类_*.md")) == reports, "idempotent repeated execution")
            client.tool("execute_organize", {"plan_id": preview["plan_id"]}, error=True)
            check(True, "changed execution options require a new preview")
            fresh = client.tool("preview_organize", {"source_path": str(source), "destination_path": str(destination)})
            (engine / "assets/frame.png").write_text("modified nested resource")
            client.tool("execute_organize", {"plan_id": fresh["plan_id"]}, error=True)
            check(list(destination.rglob("素材归类_*.md")) == reports, "stale nested source rejected before writing")
            client.tool("preview_organize", {"source_path": str(source), "destination_path": str(source / "BGM")}, error=True)
            check(True, "overlapping roots rejected")
            fresh = client.tool("preview_organize", {"source_path": str(source), "destination_path": str(destination)})
            destination.rename(root / "previous-destination")
            destination.mkdir()
            client.tool("execute_organize", {"plan_id": fresh["plan_id"]}, error=True)
            check(not list(destination.iterdir()), "replaced destination identity rejected")
            source_file = source / "外壳.step"
            fresh = client.tool("preview_organize", {"source_path": str(source), "destination_path": str(destination)})
            source_file.unlink()
            source_file.symlink_to(engine / "assets/frame.png")
            client.tool("execute_organize", {"plan_id": fresh["plan_id"], "include_paths": ["外壳.step"]}, error=True)
            check(not list(destination.iterdir()), "source symlink substitution rejected")
        with tempfile.TemporaryDirectory(prefix="framenest-mcp-move-") as temporary:
            root = Path(temporary).resolve()
            created = client.tool("create_project", {"parent_path": str(root), "name": "移动项目", "folders": template["default_folders"]})
            project = Path(created["project_path"])
            inbox = project / template["inbox_folder"]
            check(inbox.is_dir() and template["supported_modes"] == ["copy", "move"], "shared inbox and supported modes")
            source = inbox / "字幕.srt"
            source.write_text("caption")
            engine = inbox / "HyperFrames工程"
            engine.mkdir()
            (engine / "hyperframes.json").write_text("{}")
            (engine / "asset.png").write_text("test-resource")
            client.tool("preview_organize", {"source_path": str(inbox), "destination_path": str(project), "mode": "delete"}, error=True)
            check(True, "invalid organization mode rejected")
            preview = client.tool("preview_organize", {"source_path": str(inbox), "destination_path": str(project), "mode": "move"})
            check(preview["mode"] == "move" and preview["total_items"] == 2, "inbox move plan generated")
            moved = client.tool("execute_organize", {"plan_id": preview["plan_id"]})
            check(moved["moved"] == 2 and moved["copied"] == 0 and moved["failed"] == 0, "MCP moves files and engineering folders")
            check(not source.exists() and not engine.exists(), "moved items leave the source")
            check((project / "06_工程/动画/HyperFrames工程/asset.png").read_text() == "test-resource", "move preserves engineering resources")
            replay = client.tool("execute_organize", {"plan_id": preview["plan_id"]})
            check(replay["reused_result"] and replay["report_path"] == moved["report_path"], "repeating move is idempotent")
            source.write_text("caption")
            duplicate = client.tool("preview_organize", {"source_path": str(inbox), "destination_path": str(project), "mode": "move"})
            result = client.tool("execute_organize", {"plan_id": duplicate["plan_id"]})
            check(result["skipped"] == 1 and result["moved"] == 0 and source.exists(), "duplicate move keeps source")
            source.write_text("changed-caption")
            conflict = client.tool("preview_organize", {"source_path": str(inbox), "destination_path": str(project), "mode": "move"})
            result = client.tool("execute_organize", {"plan_id": conflict["plan_id"]})
            check(result["moved"] == 1 and (project / "05_字幕/字幕__2.srt").read_text() == "changed-caption", "move conflict receives a suffix")
            check((project / "05_字幕/字幕.srt").read_text() == "caption", "move conflict preserves existing content")
    finally:
        client.close()
    check(client.process.returncode == 0, "clean shutdown on stdin EOF")
    legacy = JSONLineClient([str(binary.resolve())])
    try:
        check(legacy.request("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "legacy-check", "version": "1"}})["result"]["protocolVersion"] == "2025-03-26", "legacy version negotiation")
        response = legacy.request("tools/call", {"name": "get_template", "arguments": {}})["result"]
        check("structuredContent" not in response and json.loads(response["content"][0]["text"])["name"] == "FrameNest", "legacy-compatible text results")
    finally:
        legacy.close()
    print(f"ALL {count} MCP CHECKS PASSED")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, default=Path("FrameNest.app/Contents/MacOS/FrameNestMCP"))
    run(parser.parse_args().binary)
