#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mpv-advance 本地 mock 摄像头 API 服务
=====================================

用 Python 标准库实现一个最小可用的 NVR/摄像头平台 REST 接口，供 mpv 监控脚本
(surveillance.lua) 作为“真实 API”来调用。脚本在此服务不可用时会自动回退到直接
读取 cameras.json，因此本服务是**可选**的，但运行它能得到更贴近真实产品的体验。

接口一览
--------
  GET  /                              服务信息 / 健康检查
  GET  /cameras                       摄像头列表；?q= 关键字搜索（名称/分组/位置/标签/ID）
  GET  /cameras/<id>                  单个摄像头详情
  GET  /cameras/<id>/stream?mode=live|playback[&start=<秒>]
                                      取流地址；返回 { source: <绝对路径>, ... }
                                      mock 中 live 与 playback 使用同一样本文件，
                                      playback 额外回传 start 偏移，模拟录像回放。

启动
----
  python surveillance/api/mock_camera_api.py
  python surveillance/api/mock_camera_api.py --port 8777 --samples <样本目录>

默认监听 127.0.0.1:8777，样本目录默认解析到仓库的 test/samples。
"""

import argparse
import hashlib
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

RECORDING_DAYS = 7          # 虚拟录像可回放的天数
EVENT_TYPES = ["移动侦测", "人形检测", "越界告警", "车辆识别", "逗留检测"]

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))          # surveillance/api -> repo 根
DEFAULT_DATA = os.path.join(HERE, "..", "data", "cameras.json")
DEFAULT_SAMPLES = os.path.join(REPO_ROOT, "test", "samples")


def load_db(data_file):
    with open(data_file, "r", encoding="utf-8") as f:
        return json.load(f)


def camera_matches(cam, q):
    """在 名称/分组/位置/ID/标签 上做大小写不敏感的子串搜索。"""
    if not q:
        return True
    q = q.lower()
    haystack = " ".join([
        str(cam.get("id", "")),
        str(cam.get("name", "")),
        str(cam.get("group", "")),
        str(cam.get("location", "")),
        str(cam.get("status", "")),
        " ".join(cam.get("tags", []) or []),
    ]).lower()
    return q in haystack


def _seed(*parts):
    """由入参派生一个稳定的整数种子（用于确定性地生成事件/偏移）。"""
    h = hashlib.md5("|".join(str(p) for p in parts).encode("utf-8")).hexdigest()
    return int(h[:12], 16)


def offset_percent_for(cam_id, start_epoch):
    """把一个墙钟时间戳确定性地映射到样本内的 0..100 百分比位置。

    样本很短（数秒），无法真正承载数天录像；这里用哈希把“时段”映射到样本
    内一个稳定且可见的位置，从而让基于时间的回放在演示中直观可见。
    """
    return _seed(cam_id, int(start_epoch) // 1) % 100


def generate_events(cam, now=None, count=8):
    """为某路摄像头确定性地生成最近 24 小时内的“事件”列表。"""
    now = now or time.time()
    seed = _seed(cam.get("id", ""))
    events = []
    for i in range(count):
        # 在最近 24h 内均匀分布并加入确定性抖动
        span = 24 * 3600
        base = now - span * (i + 1) / (count + 1)
        jitter = ((seed >> (i * 3)) % 1200) - 600
        t = base + jitter
        etype = EVENT_TYPES[(seed >> i) % len(EVENT_TYPES)]
        events.append({
            "time": int(t),
            "time_str": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)),
            "type": etype,
        })
    events.sort(key=lambda e: e["time"], reverse=True)
    return events


class Handler(BaseHTTPRequestHandler):
    server_version = "mpv-advance-mock/1.0"

    # ---- 基础工具 ---------------------------------------------------------
    def _send(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _error(self, code, message):
        self._send({"error": message, "code": code}, code)

    def log_message(self, fmt, *args):
        sys.stderr.write("[mock-api] %s - %s\n" % (self.address_string(), fmt % args))

    def _find_camera(self, cam_id):
        for cam in self.server.db.get("cameras", []):
            if cam.get("id", "").lower() == cam_id.lower():
                return cam
        return None

    def _resolve_source(self, cam):
        """把样本文件名解析为 mpv 可直接播放的绝对路径。"""
        path = os.path.join(self.server.samples_dir, cam.get("file", ""))
        return os.path.abspath(path).replace("\\", "/")

    # ---- 路由 -------------------------------------------------------------
    def do_GET(self):
        parsed = urlparse(self.path)
        parts = [unquote(p) for p in parsed.path.strip("/").split("/") if p != ""]
        query = parse_qs(parsed.query)

        # GET /
        if not parts:
            return self._send({
                "service": "mpv-advance mock camera API",
                "version": self.server.db.get("api_version", "1.0"),
                "camera_count": len(self.server.db.get("cameras", [])),
                "samples_dir": self.server.samples_dir,
                "endpoints": [
                    "GET /cameras?q=<关键字>",
                    "GET /cameras/<id>",
                    "GET /cameras/<id>/stream?mode=live|playback&start=<秒>",
                    "GET /cameras/<id>/recordings",
                    "GET /cameras/<id>/playback?start=<epoch>&duration=<秒>",
                ],
            })

        # GET /cameras  和  /cameras/<id>[/stream]
        if parts[0] == "cameras":
            if len(parts) == 1:
                q = (query.get("q", [""])[0] or "").strip()
                cams = [c for c in self.server.db.get("cameras", [])
                        if camera_matches(c, q)]
                return self._send({"count": len(cams), "query": q, "cameras": cams})

            cam = self._find_camera(parts[1])
            if cam is None:
                return self._error(404, "camera not found: %s" % parts[1])

            if len(parts) == 2:
                return self._send(cam)

            if len(parts) == 3 and parts[2] == "stream":
                mode = (query.get("mode", ["live"])[0] or "live").lower()
                if mode not in ("live", "playback"):
                    return self._error(400, "mode must be live or playback")
                start = 0.0
                try:
                    start = float(query.get("start", ["0"])[0])
                except ValueError:
                    start = 0.0
                return self._send({
                    "id": cam.get("id"),
                    "name": cam.get("name"),
                    "mode": mode,
                    "protocol": "file",
                    "source": self._resolve_source(cam),
                    "start": start if mode == "playback" else 0.0,
                    "loop": mode == "live",
                })

            # GET /cameras/<id>/recordings —— 可回放时间范围 + 事件列表
            if len(parts) == 3 and parts[2] == "recordings":
                now = time.time()
                return self._send({
                    "id": cam.get("id"),
                    "name": cam.get("name"),
                    "available": {
                        "start": int(now - RECORDING_DAYS * 86400),
                        "end": int(now),
                        "start_str": time.strftime(
                            "%Y-%m-%d %H:%M:%S",
                            time.localtime(now - RECORDING_DAYS * 86400)),
                        "end_str": time.strftime("%Y-%m-%d %H:%M:%S",
                                                 time.localtime(now)),
                    },
                    "events": generate_events(cam, now),
                })

            # GET /cameras/<id>/playback?start=<epoch>&duration=<秒>
            #   按墙钟时间回放：返回样本地址 + 该时段对应的样本内百分比位置
            if len(parts) == 3 and parts[2] == "playback":
                now = time.time()
                try:
                    start = float(query.get("start", [str(now - 900)])[0])
                except ValueError:
                    start = now - 900
                duration = None
                if query.get("duration"):
                    try:
                        duration = float(query["duration"][0])
                    except ValueError:
                        duration = None
                avail_start = now - RECORDING_DAYS * 86400
                clamped = max(avail_start, min(start, now))
                return self._send({
                    "id": cam.get("id"),
                    "name": cam.get("name"),
                    "mode": "playback",
                    "protocol": "file",
                    "source": self._resolve_source(cam),
                    "start": int(clamped),
                    "start_str": time.strftime("%Y-%m-%d %H:%M:%S",
                                               time.localtime(clamped)),
                    "start_percent": offset_percent_for(cam.get("id", ""), clamped),
                    "duration": duration,
                    "in_range": avail_start <= start <= now,
                    "loop": False,
                })

            return self._error(404, "unknown resource: /%s" % "/".join(parts))

        return self._error(404, "unknown resource: /%s" % "/".join(parts))

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.end_headers()


def main():
    ap = argparse.ArgumentParser(description="mpv-advance mock camera API")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8777)
    ap.add_argument("--data", default=DEFAULT_DATA, help="cameras.json 路径")
    ap.add_argument("--samples", default=os.environ.get("MPV_SURV_SAMPLES", DEFAULT_SAMPLES),
                    help="样本视频目录（解析 file 字段）")
    args = ap.parse_args()

    data_file = os.path.abspath(args.data)
    samples_dir = os.path.abspath(args.samples)

    if not os.path.isfile(data_file):
        sys.exit("找不到摄像头数据文件: %s" % data_file)

    db = load_db(data_file)

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    httpd.db = db
    httpd.samples_dir = samples_dir

    print("mpv-advance mock camera API 已启动")
    print("  地址:     http://%s:%d" % (args.host, args.port))
    print("  摄像头:   %d 路 (来自 %s)" % (len(db.get("cameras", [])), data_file))
    print("  样本目录: %s" % samples_dir)
    print("  按 Ctrl+C 停止。")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止。")


if __name__ == "__main__":
    main()
