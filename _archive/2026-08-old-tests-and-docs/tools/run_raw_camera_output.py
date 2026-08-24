import argparse
import time

import cv2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--camera", default="4k Camera")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=int, default=30)
    args = parser.parse_args()

    cap = cv2.VideoCapture(args.camera, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    if not cap.isOpened():
        print("ERROR: failed to open camera")
        return 1

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_FPS, args.fps)

    window_name = "OBS Output"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(window_name, args.width, args.height)

    last = time.time()
    frames = 0
    shown_fps = 0.0

    print(f"Raw camera output started: camera={args.camera} size={args.width}x{args.height} fps={args.fps}")
    print("Press q in the preview window to stop.")

    while True:
        ok, frame = cap.read()
        if not ok or frame is None:
            print("WARN: camera frame read failed")
            time.sleep(0.05)
            continue

        if frame.shape[1] != args.width or frame.shape[0] != args.height:
            frame = cv2.resize(frame, (args.width, args.height), interpolation=cv2.INTER_AREA)

        frames += 1
        now = time.time()
        if now - last >= 1.0:
            shown_fps = frames / (now - last)
            frames = 0
            last = now

        cv2.putText(
            frame,
            f"RAW CAMERA {args.width}x{args.height} FPS:{shown_fps:.1f}",
            (16, 42),
            cv2.FONT_HERSHEY_SIMPLEX,
            1.0,
            (0, 255, 0),
            2,
            cv2.LINE_AA,
        )
        cv2.imshow(window_name, frame)
        key = cv2.waitKey(1) & 0xFF
        if key == ord("q") or key == 27:
            break

    cap.release()
    cv2.destroyAllWindows()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
