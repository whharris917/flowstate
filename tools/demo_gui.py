"""Live operator GUI for the fill-loop plant.

Launch from the project root:

    .venv\\Scripts\\python.exe tools\\demo_gui.py

A browser window opens with an operator graphic and live trends of the
supply-tank loop (tank, float switch, relay, pump). The page renders
only what this server reports: live values straight from the sim, trend
data straight from the historian. Nothing is computed client-side.

Standard library only — no dependencies.
"""
from __future__ import annotations

import json
import sys
import threading
import time as wallclock
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from sim.components import FloatSwitch, Pump, Relay, Tank  # noqa: E402
from sim.core import Simulation  # noqa: E402
from sim.historian import Historian  # noqa: E402

PAGE_PATH = Path(__file__).with_name("demo_gui.html")
TICK_S = 0.05  # 20 Hz, matching the kernel's reference rate
SPEEDS = (1, 4, 16, 64)  # sim ticks per real 50 ms slice


class LivePlant:
    """The fill-loop plant plus a real-time pacing loop and thread safety.

    All mutation and reading happens under one lock; the HTTP threads and
    the tick thread never see a half-updated scan.
    """

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.paused = False
        self.speed = 1
        self.epoch = 0  # bumped on reset so clients drop stale buffers
        self._build(low=40.0, high=80.0, drain=1.5, mode="auto")

    def _build(self, low: float, high: float, drain: float, mode: str) -> None:
        self.sim = Simulation(dt=TICK_S)
        self.tank = Tank("tank", capacity_l=100.0, level_l=70.0, drain_lps=drain)
        self.switch = FloatSwitch("switch", low_l=low, high_l=high)
        self.relay = Relay("relay")
        self.pump = Pump("pump", rated_lps=4.0, mode=mode)
        for component in (self.tank, self.switch, self.relay, self.pump):
            self.sim.add(component)
        self.sim.connect(self.tank, "level", self.switch, "level")
        self.sim.connect(self.switch, "contact", self.relay, "coil")
        self.sim.connect(self.relay, "contact", self.pump, "run")
        self.sim.connect(self.pump, "flow", self.tank, "in_flow")
        self.historian = self.sim.attach_historian(Historian())

    def loop(self) -> None:
        next_slice = wallclock.perf_counter()
        while True:
            next_slice += TICK_S
            with self.lock:
                if not self.paused:
                    for _ in range(self.speed):
                        self.sim.tick()
            delay = next_slice - wallclock.perf_counter()
            if delay > 0:
                wallclock.sleep(delay)
            else:  # fell behind (heavy speed on a slow box) — don't spiral
                next_slice = wallclock.perf_counter()

    def state(self, since: int) -> dict[str, Any]:
        with self.lock:
            hist = self.historian
            since = max(0, min(since, len(hist)))
            return {
                "epoch": self.epoch,
                "since": since,
                "count": len(hist),
                "time": hist.time[since:],
                "tags": {tag: hist.data[tag][since:] for tag in hist.tags},
                "config": {
                    "low_l": self.switch.low_l,
                    "high_l": self.switch.high_l,
                    "drain_lps": self.tank.drain_lps,
                    "mode": self.pump.mode,
                    "capacity_l": self.tank.capacity_l,
                    "rated_lps": self.pump.rated_lps,
                    "speed": self.speed,
                    "paused": self.paused,
                    "dt": self.sim.dt,
                },
                "live": {
                    "sim_time": self.sim.time,
                    "level_l": self.tank.level_l,
                    "switch_closed": self.switch.closed,
                    "relay_energized": self.relay.energized,
                    "relay_cycles": self.relay.cycles,
                    "pump_running": self.pump.running,
                    "pump_flow_lps": float(self.pump.flow.value),
                    "pump_starts": self.pump.starts,
                    "overflowed_l": self.tank.overflowed_l,
                    "ran_dry_s": self.tank.ran_dry_ticks * self.sim.dt,
                },
            }

    def command(self, name: str, value: str) -> dict[str, Any]:
        with self.lock:
            try:
                if name == "pause":
                    self.paused = True
                elif name == "resume":
                    self.paused = False
                elif name == "speed":
                    speed = int(value)
                    if speed not in SPEEDS:
                        raise ValueError(f"speed must be one of {SPEEDS}")
                    self.speed = speed
                elif name == "low":
                    self.switch.set_band(float(value), self.switch.high_l)
                elif name == "high":
                    self.switch.set_band(self.switch.low_l, float(value))
                elif name == "drain":
                    drain = float(value)
                    if not 0.0 <= drain <= 10.0:
                        raise ValueError("drain must be 0-10 L/s")
                    self.tank.drain_lps = drain
                elif name == "mode":
                    self.pump.set_mode(value)
                elif name == "reset":
                    self._build(
                        low=self.switch.low_l,
                        high=self.switch.high_l,
                        drain=self.tank.drain_lps,
                        mode=self.pump.mode,
                    )
                    self.epoch += 1
                else:
                    raise ValueError(f"unknown command {name!r}")
            except ValueError as exc:
                return {"ok": False, "error": str(exc)}
            return {"ok": True}

    def csv(self) -> str:
        with self.lock:
            return self.historian.to_csv_text()


PLANT = LivePlant()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        pass  # keep the console quiet; the page is the interface

    def _send(self, body: bytes, content_type: str, extra: dict[str, str] | None = None) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, val in (extra or {}).items():
            self.send_header(key, val)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 (http.server API)
        url = urlparse(self.path)
        query = parse_qs(url.query)
        if url.path == "/":
            self._send(PAGE_PATH.read_bytes(), "text/html; charset=utf-8")
        elif url.path == "/api/state":
            since = int(query.get("since", ["0"])[0])
            body = json.dumps(PLANT.state(since)).encode()
            self._send(body, "application/json")
        elif url.path == "/api/command":
            name = query.get("name", [""])[0]
            value = query.get("value", [""])[0]
            body = json.dumps(PLANT.command(name, value)).encode()
            self._send(body, "application/json")
        elif url.path == "/export.csv":
            self._send(
                PLANT.csv().encode(),
                "text/csv; charset=utf-8",
                {"Content-Disposition": "attachment; filename=flowstate_history.csv"},
            )
        else:
            self.send_error(404)


def main() -> None:
    threading.Thread(target=PLANT.loop, daemon=True).start()
    server = None
    port = 8765
    for candidate in range(port, port + 20):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", candidate), Handler)
            port = candidate
            break
        except OSError:
            continue
    if server is None:
        raise SystemExit("no free port found in 8765-8784")
    url = f"http://127.0.0.1:{port}/"
    print(f"flowstate demo running at {url}  (Ctrl+C to stop)")
    if "--no-browser" not in sys.argv:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
