import argparse
import os
import subprocess
import sys
import threading
import time
from pathlib import Path


PROVIDER_PROCESS = "android.hardware.camera.provider@2.7-service-google"
WIDTH = 1280
HEIGHT = 720
FRAME_SIZE = WIDTH * HEIGHT * 3 // 2

SCRIPT = r"""
const symbol = '_ZN7android11framesource16VideoFrameSource12ProduceFrameEjlRKNS_14SensorSettingsEPNS_12SensorBufferEPKS5_';
const module = Process.getModuleByName('libgooglecamerahwl_impl.so');
const produceFrame = module.getExportByName(symbol);
let latestFrame = null;
let receivedFrames = 0;
let injectedFrames = 0;

function receiveNextFrame() {
  recv('frame', (message, data) => {
    if (data !== null && data.byteLength === 1382400) {
      latestFrame = data;
      receivedFrames++;
    }
    receiveNextFrame();
  });
}
receiveNextFrame();

Interceptor.attach(produceFrame, {
  onEnter(args) {
    this.buffer = args[4];
  },
  onLeave(result) {
    if (result.toInt32() !== 0 || latestFrame === null) return;

    const buffer = this.buffer;
    const width = buffer.add(8).readU32();
    const height = buffer.add(12).readU32();
    if (width !== 1280 || height !== 720) return;

    const y = buffer.add(352).readPointer();
    const u = buffer.add(360).readPointer();
    const v = buffer.add(368).readPointer();
    const yStride = buffer.add(376).readU32();
    const chromaStride = buffer.add(380).readU32();
    if (yStride !== 1280 || chromaStride !== 640) return;

    const frame = new Uint8Array(latestFrame);
    y.writeByteArray(frame.subarray(0, 921600));
    u.writeByteArray(frame.subarray(921600, 1152000));
    v.writeByteArray(frame.subarray(1152000, 1382400));

    injectedFrames++;
    if (injectedFrames === 1 || injectedFrames % 90 === 0) {
      send({event: 'status', receivedFrames, injectedFrames, width, height});
    }
  }
});

send({event: 'ready', address: produceFrame.toString()});
"""


def read_exact(stream, size: int) -> bytes | None:
    chunks = bytearray(size)
    view = memoryview(chunks)
    offset = 0
    while offset < size:
        count = stream.readinto(view[offset:])
        if not count:
            return None
        offset += count
    return bytes(chunks)


def drain_stderr(stream) -> None:
    for line in iter(stream.readline, b""):
        text = line.decode("utf-8", errors="replace").strip()
        if text:
            print(f"[ffmpeg] {text}", flush=True)


def start_ffmpeg(command: list[str]) -> subprocess.Popen:
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    threading.Thread(
        target=drain_stderr, args=(process.stderr,), daemon=True
    ).start()
    return process


def stop_ffmpeg(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=float, default=0.0)
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument(
        "--scale-flags",
        choices=("fast_bilinear", "bilinear", "bicubic"),
        default="bilinear",
        help="FFmpeg scaler used after the phone-sensor crop",
    )
    parser.add_argument("--window", default="OBS Output")
    parser.add_argument("--wait-for-window", type=float, default=180.0)
    parser.add_argument(
        "--raw-landscape",
        action="store_true",
        help="skip the phone-sensor crop and pre-rotation",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    ffmpeg = repo_root / "ffmpeg" / "bin" / "ffmpeg.exe"
    if not ffmpeg.exists():
        raise FileNotFoundError(ffmpeg)

    frida_path = Path(
        os.environ.get(
            "MOBILE_HAL_FRIDA_PY",
            str(Path(__file__).resolve().parent / "runtime" / "frida_py"),
        )
    )
    if not frida_path.exists():
        raise FileNotFoundError(
            f"Frida Python runtime is missing: {frida_path}. "
            "Run tools/mobile_phone/setup_mobile_phone.ps1 first."
        )
    sys.path.insert(0, str(frida_path))
    import frida

    device = frida.get_device_manager().add_remote_device("127.0.0.1:27042")
    session = device.attach(PROVIDER_PROCESS)
    script = session.create_script(SCRIPT)
    script.on("message", lambda message, _data: print(message, flush=True))
    script.load()

    if not 1 <= args.fps <= 30:
        parser.error("--fps must be between 1 and 30")

    video_filter = (
        f"scale=1280:720:flags={args.scale_flags},format=yuv420p"
    )
    if not args.raw_landscape:
        # A portrait phone uses a 9:16 slice of its landscape-oriented sensor.
        # Pre-rotate that slice so Android's Front/270 transform displays it upright.
        video_filter = (
            "crop=404:720:438:0,transpose=clock,vflip,"
            f"scale=1280:720:flags={args.scale_flags},format=yuv420p"
        )

    command = [
        str(ffmpeg),
        "-hide_banner",
        "-loglevel",
        "warning",
        "-f",
        "gdigrab",
        "-draw_mouse",
        "0",
        "-framerate",
        str(args.fps),
        "-i",
        f"title={args.window}",
        "-vf",
        video_filter,
        "-pix_fmt",
        "yuv420p",
        "-f",
        "rawvideo",
        "pipe:1",
    ]
    started = time.monotonic()
    sent = 0
    process = None
    try:
        window_deadline = time.monotonic() + args.wait_for_window
        first_frame = None
        while first_frame is None:
            process = start_ffmpeg(command)
            first_frame = read_exact(process.stdout, FRAME_SIZE)
            if first_frame is not None:
                break
            process.wait(timeout=5)
            if time.monotonic() >= window_deadline:
                raise RuntimeError(
                    f"Window {args.window!r} did not produce a frame within "
                    f"{args.wait_for_window:.0f} seconds"
                )
            time.sleep(1)

        script.post({"type": "frame"}, data=first_frame)
        sent = 1
        stream_started = time.monotonic()
        print("[bridge] sent=1 first_frame_ready", flush=True)

        while args.seconds <= 0 or time.monotonic() - started < args.seconds:
            frame = read_exact(process.stdout, FRAME_SIZE)
            if frame is None:
                print("[bridge] FFmpeg capture stopped; reconnecting", flush=True)
                stop_ffmpeg(process)
                recovery_deadline = time.monotonic() + 15
                frame = None
                while frame is None and time.monotonic() < recovery_deadline:
                    time.sleep(0.5)
                    process = start_ffmpeg(command)
                    frame = read_exact(process.stdout, FRAME_SIZE)
                    if frame is None:
                        stop_ffmpeg(process)
                if frame is None:
                    raise RuntimeError(
                        "FFmpeg could not recover the OBS Output capture within 15 seconds"
                    )
                print("[bridge] FFmpeg capture recovered", flush=True)
            script.post({"type": "frame"}, data=frame)
            sent += 1
            if sent % (args.fps * 5) == 0:
                elapsed = max(time.monotonic() - stream_started, 0.001)
                print(
                    f"[bridge] sent={sent} rate={sent / elapsed:.1f} fps",
                    flush=True,
                )
    finally:
        stop_ffmpeg(process)
        session.detach()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
