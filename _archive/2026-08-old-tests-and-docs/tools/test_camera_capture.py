from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from modules.video_capture import VideoCapturer


def list_windows_cameras() -> list[str]:
    try:
        from pygrabber.dshow_graph import FilterGraph

        return FilterGraph().get_input_devices()
    except Exception as exc:
        print(f"[camera-test] unable to list DirectShow cameras: {exc}", flush=True)
        return []


def write_log(line: str) -> None:
    logs = ROOT / "logs"
    logs.mkdir(exist_ok=True)
    day = time.strftime("%Y%m%d")
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with open(logs / f"camera_capture_test_{day}.txt", "a", encoding="utf-8") as handle:
        handle.write(f"{stamp} {line}\n")
    print(line, flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--camera-name", default="4k Camera")
    parser.add_argument("--camera-index", type=int, default=None)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--seconds", type=float, default=8.0)
    args = parser.parse_args()

    cameras = list_windows_cameras()
    write_log(f"[camera-test] cameras={cameras}")
    if args.camera_index is None:
        matches = [idx for idx, name in enumerate(cameras) if name == args.camera_name]
        if not matches:
            write_log(f"[camera-test] ERROR camera not found: {args.camera_name}")
            return 2
        camera_index = matches[0]
    else:
        camera_index = args.camera_index

    write_log(
        f"[camera-test] opening index={camera_index} target={args.width}x{args.height}@{args.fps}"
    )
    cap = VideoCapturer(camera_index)
    if not cap.start(args.width, args.height, args.fps):
        write_log("[camera-test] ERROR start failed")
        return 3

    write_log(
        f"[camera-test] opened actual={cap.actual_width}x{cap.actual_height}@{cap.actual_fps:.1f} "
        f"fourcc={cap.actual_fourcc} backend={cap.actual_backend}"
    )

    frames = 0
    failed_reads = 0
    start = time.perf_counter()
    deadline = start + max(1.0, args.seconds)
    while time.perf_counter() < deadline:
        ok, frame = cap.read()
        if ok and frame is not None:
            frames += 1
        else:
            failed_reads += 1
            time.sleep(0.01)

    elapsed = time.perf_counter() - start
    observed_fps = frames / elapsed if elapsed > 0 else 0.0
    write_log(
        f"[camera-test] read frames={frames} failed_reads={failed_reads} "
        f"observed_fps={observed_fps:.1f}"
    )
    cap.release()

    if cap.actual_width != args.width or cap.actual_height != args.height:
        write_log("[camera-test] FAIL wrong resolution")
        return 4
    if observed_fps < args.fps * 0.75:
        write_log("[camera-test] FAIL fps below target floor")
        return 5

    write_log("[camera-test] OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
