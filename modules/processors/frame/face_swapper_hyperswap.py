from typing import Any, List, Optional, Tuple
import os
import threading

import cv2
import numpy as np
import onnxruntime

import modules.globals
from modules import imread_unicode, imwrite_unicode
from modules.core import update_status
from modules.face_analyser import get_one_face, get_many_faces, default_source_face
from modules.typing import Face, Frame
from modules.utilities import is_image, is_video
from modules.processors.frame._onnx_enhancer import build_provider_config
from modules.processors.frame.face_swapper import (
    apply_color_transfer,
    apply_post_processing,
    create_face_mask,
    create_lower_mouth_mask,
    apply_mouth_area,
    draw_mouth_mask_visualization,
)


NAME = "DLC.FACE-SWAPPER"
MODEL_FILE = "hyperswap_1a_256.onnx"
MODEL_SIZE = 256
THREAD_LOCK = threading.Lock()
FACE_SWAPPER = None
XSEG_LOCK = threading.Lock()
XSEG_SESSION = None

WARP_TEMPLATE_ARCFACE_128 = np.array(
    [
        [0.36167656, 0.40387734],
        [0.63696719, 0.40235469],
        [0.50019687, 0.56044219],
        [0.38710391, 0.72160547],
        [0.61507734, 0.72034453],
    ],
    dtype=np.float32,
)

abs_dir = os.path.dirname(os.path.abspath(__file__))
models_dir = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(abs_dir))), "models"
)


def pre_check() -> bool:
    return os.path.exists(os.path.join(models_dir, MODEL_FILE))


def pre_start() -> bool:
    model_path = os.path.join(models_dir, MODEL_FILE)
    if not os.path.exists(model_path):
        update_status(f"HyperSwap model not found: {model_path}", NAME)
        return False
    return get_face_swapper() is not None


def get_face_swapper() -> Optional[onnxruntime.InferenceSession]:
    global FACE_SWAPPER
    with THREAD_LOCK:
        if FACE_SWAPPER is None:
            model_path = os.path.join(models_dir, MODEL_FILE)
            update_status(f"Loading HyperSwap 256 model from: {model_path}", NAME)
            try:
                session_options = onnxruntime.SessionOptions()
                session_options.graph_optimization_level = (
                    onnxruntime.GraphOptimizationLevel.ORT_ENABLE_ALL
                )
                FACE_SWAPPER = onnxruntime.InferenceSession(
                    model_path,
                    sess_options=session_options,
                    providers=build_provider_config(),
                )
                _validate_model_io(FACE_SWAPPER)
                _warmup_session(FACE_SWAPPER)
                update_status("HyperSwap 256 model loaded successfully.", NAME)
            except Exception as e:
                update_status(f"Error loading HyperSwap 256 model: {e}", NAME)
                FACE_SWAPPER = None
    return FACE_SWAPPER


def get_xseg_session() -> Optional[onnxruntime.InferenceSession]:
    global XSEG_SESSION
    with XSEG_LOCK:
        if XSEG_SESSION is None:
            for model_file in ("xseg_cuda_v1.onnx", "xseg.onnx"):
                model_path = os.path.join(models_dir, model_file)
                if not os.path.exists(model_path):
                    continue
                try:
                    session_options = onnxruntime.SessionOptions()
                    session_options.graph_optimization_level = (
                        onnxruntime.GraphOptimizationLevel.ORT_ENABLE_ALL
                    )
                    # This model falls back to CPU in the bundled runtime on this
                    # machine. Keep it explicit to avoid CUDA provider warnings.
                    XSEG_SESSION = onnxruntime.InferenceSession(
                        model_path,
                        sess_options=session_options,
                        providers=["CPUExecutionProvider"],
                    )
                    update_status(f"XSeg mask model loaded: {model_file}", NAME)
                    break
                except Exception as e:
                    update_status(f"Error loading XSeg mask model {model_file}: {e}", NAME)
                    XSEG_SESSION = None
    return XSEG_SESSION


def _validate_model_io(session: onnxruntime.InferenceSession) -> None:
    inputs = {inp.name: inp.shape for inp in session.get_inputs()}
    outputs = {out.name: out.shape for out in session.get_outputs()}
    if "source" not in inputs or "target" not in inputs:
        raise RuntimeError(f"Unexpected HyperSwap inputs: {inputs}")
    if "output" not in outputs:
        raise RuntimeError(f"Unexpected HyperSwap outputs: {outputs}")


def _warmup_session(session: onnxruntime.InferenceSession) -> None:
    try:
        session.run(
            None,
            {
                "source": np.zeros((1, 512), dtype=np.float32),
                "target": np.zeros((1, 3, MODEL_SIZE, MODEL_SIZE), dtype=np.float32),
            },
        )
    except Exception as e:
        print(f"{NAME}: HyperSwap warmup skipped: {e}")


def _estimate_affine(face_landmark_5: np.ndarray, crop_size: int) -> np.ndarray:
    fit_scale = float(getattr(modules.globals, "face_fit_scale", 1.06))
    fit_scale = max(0.96, min(1.18, fit_scale))
    if abs(fit_scale - 1.0) > 0.001:
        center = face_landmark_5.astype(np.float32).mean(axis=0, keepdims=True)
        face_landmark_5 = center + (face_landmark_5.astype(np.float32) - center) * fit_scale
    dst = WARP_TEMPLATE_ARCFACE_128 * crop_size
    matrix = cv2.estimateAffinePartial2D(
        face_landmark_5.astype(np.float32),
        dst.astype(np.float32),
        method=cv2.RANSAC,
        ransacReprojThreshold=100,
    )[0]
    if matrix is None:
        matrix = cv2.estimateAffinePartial2D(
            face_landmark_5.astype(np.float32),
            dst.astype(np.float32),
            method=cv2.LMEDS,
        )[0]
    if matrix is None:
        raise RuntimeError("Unable to estimate HyperSwap face affine matrix")
    return matrix.astype(np.float32)


def _prepare_target(crop_frame: np.ndarray) -> np.ndarray:
    crop_frame = crop_frame[:, :, ::-1].astype(np.float32) / 255.0
    crop_frame = (crop_frame - 0.5) / 0.5
    crop_frame = crop_frame.transpose(2, 0, 1)
    return np.expand_dims(crop_frame, axis=0).astype(np.float32)


def _normalize_output(output_tensor: np.ndarray) -> np.ndarray:
    crop_frame = output_tensor[0].transpose(1, 2, 0)
    crop_frame = crop_frame * 0.5 + 0.5
    crop_frame = crop_frame.clip(0, 1)
    crop_frame = crop_frame[:, :, ::-1] * 255.0
    return crop_frame.astype(np.uint8)


def _source_embedding(source_face: Face) -> Optional[np.ndarray]:
    embedding = getattr(source_face, "normed_embedding", None)
    if embedding is None:
        return None
    embedding = np.asarray(embedding, dtype=np.float32).reshape(1, -1)
    norm = np.linalg.norm(embedding)
    if not np.isfinite(norm) or norm <= 0:
        return None
    return embedding / norm


def _soft_crop_mask(size: int) -> np.ndarray:
    scale = float(getattr(modules.globals, "face_mask_scale", 0.44))
    scale = max(0.36, min(0.52, scale))
    blur_size = int(getattr(modules.globals, "face_mask_blur", 31))
    blur_size = max(3, blur_size | 1)
    mask = np.zeros((size, size), dtype=np.float32)
    center = (size // 2, size // 2)
    axes = (int(size * scale), int(size * scale))
    cv2.ellipse(mask, center, axes, 0, 0, 360, 1.0, -1)
    mask = cv2.GaussianBlur(mask, (blur_size, blur_size), blur_size / 3.0)
    return mask.clip(0, 1)


def _xseg_crop_mask(crop_frame: np.ndarray) -> Optional[np.ndarray]:
    if not getattr(modules.globals, "live_xseg_mask", False):
        return None
    session = get_xseg_session()
    if session is None:
        return None

    try:
        input_name = session.get_inputs()[0].name
        model_input = crop_frame.astype(np.float32) / 255.0
        model_input = np.expand_dims(model_input, axis=0)
        mask = session.run(None, {input_name: model_input})[0][0, :, :, 0]
        mask = np.nan_to_num(mask).astype(np.float32)
        mask = np.clip(mask, 0.0, 1.0)

        dilate_size = int(getattr(modules.globals, "face_xseg_mask_dilate", 5))
        if dilate_size > 1:
            dilate_size = dilate_size | 1
            kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (dilate_size, dilate_size))
            mask = cv2.dilate(mask, kernel, iterations=1)

        blur_size = int(getattr(modules.globals, "face_xseg_mask_blur", 13))
        if blur_size > 1:
            blur_size = blur_size | 1
            mask = cv2.GaussianBlur(mask, (blur_size, blur_size), blur_size / 3.0)
        return np.clip(mask, 0.0, 1.0)
    except Exception as e:
        print(f"{NAME}: XSeg mask skipped: {e}")
        return None


def _combined_crop_mask(crop_frame: np.ndarray) -> np.ndarray:
    base_mask = _soft_crop_mask(MODEL_SIZE)
    xseg_mask = _xseg_crop_mask(crop_frame)
    if xseg_mask is None:
        return base_mask

    strength = float(getattr(modules.globals, "face_xseg_mask_strength", 0.85))
    strength = max(0.0, min(1.0, strength))
    semantic_mask = np.minimum(base_mask, xseg_mask)
    return (base_mask * (1.0 - strength) + semantic_mask * strength).clip(0, 1)


def _paste_back(target_img: Frame, bgr_fake: np.ndarray, affine_matrix: np.ndarray, crop_frame: np.ndarray) -> Frame:
    h, w = target_img.shape[:2]
    inv = cv2.invertAffineTransform(affine_matrix)
    corners = np.array(
        [[0, 0], [MODEL_SIZE, 0], [MODEL_SIZE, MODEL_SIZE], [0, MODEL_SIZE]],
        dtype=np.float32,
    )
    transformed = (inv[:, :2] @ corners.T).T + inv[:, 2]
    x1 = int(np.floor(transformed[:, 0].min()))
    x2 = int(np.ceil(transformed[:, 0].max()))
    y1 = int(np.floor(transformed[:, 1].min()))
    y2 = int(np.ceil(transformed[:, 1].max()))
    if x1 >= x2 or y1 >= y2:
        return target_img

    pad = 2
    y1p, y2p = max(0, y1 - pad), min(h, y2 + pad + 1)
    x1p, x2p = max(0, x1 - pad), min(w, x2 + pad + 1)
    crop_w, crop_h = x2p - x1p, y2p - y1p
    if crop_w <= 0 or crop_h <= 0:
        return target_img

    inv_crop = inv.copy()
    inv_crop[0, 2] -= x1p
    inv_crop[1, 2] -= y1p

    fake_crop = cv2.warpAffine(
        bgr_fake,
        inv_crop,
        (crop_w, crop_h),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_REPLICATE,
    )
    alpha = cv2.warpAffine(
        _combined_crop_mask(crop_frame),
        inv_crop,
        (crop_w, crop_h),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=0,
    )
    alpha = alpha[:, :, np.newaxis].astype(np.float32)
    target_crop = target_img[y1p:y2p, x1p:x2p].astype(np.float32)
    blended = fake_crop.astype(np.float32) * alpha + target_crop * (1.0 - alpha)
    target_img[y1p:y2p, x1p:x2p] = blended.clip(0, 255).astype(np.uint8)
    return target_img


def swap_face(source_face: Face, target_face: Face, temp_frame: Frame) -> Frame:
    session = get_face_swapper()
    if session is None or source_face is None or target_face is None:
        return temp_frame

    source = _source_embedding(source_face)
    if source is None:
        return temp_frame
    kps = getattr(target_face, "kps", None)
    if kps is None:
        return temp_frame

    opacity = max(0.0, min(1.0, float(getattr(modules.globals, "opacity", 1.0))))
    mouth_mask_enabled = getattr(modules.globals, "mouth_mask", False)
    color_correction_enabled = getattr(modules.globals, "color_correction", False)
    needs_original = opacity < 1.0 or mouth_mask_enabled or color_correction_enabled
    original_frame = temp_frame.copy() if needs_original else temp_frame

    try:
        if temp_frame.dtype != np.uint8:
            temp_frame = np.clip(temp_frame, 0, 255).astype(np.uint8)
        if not temp_frame.flags["C_CONTIGUOUS"]:
            temp_frame = np.ascontiguousarray(temp_frame)

        affine_matrix = _estimate_affine(np.asarray(kps), MODEL_SIZE)
        crop_frame = cv2.warpAffine(
            temp_frame,
            affine_matrix,
            (MODEL_SIZE, MODEL_SIZE),
            flags=cv2.INTER_AREA,
            borderMode=cv2.BORDER_REPLICATE,
        )
        target = _prepare_target(crop_frame)

        input_feed = {"source": source, "target": target}
        if any("DmlExecutionProvider" in p for p in modules.globals.execution_providers):
            with modules.globals.dml_lock:
                outputs = session.run(None, input_feed)
        else:
            outputs = session.run(None, input_feed)
        bgr_fake = _normalize_output(outputs[0])

        if color_correction_enabled:
            corrected = apply_color_transfer(bgr_fake, crop_frame)
            strength = max(0.0, min(1.0, float(getattr(modules.globals, "color_transfer_strength", 0.35))))
            if strength > 0.0:
                bgr_fake = cv2.addWeighted(bgr_fake, 1.0 - strength, corrected, strength, 0)

        swapped_frame = _paste_back(temp_frame, bgr_fake, affine_matrix, crop_frame)
    except Exception as e:
        print(f"{NAME}: Error during HyperSwap face swap: {e}")
        return original_frame

    if mouth_mask_enabled:
        face_mask = create_face_mask(target_face, original_frame)
        mouth_mask, mouth_cutout, mouth_box, lower_lip_polygon = create_lower_mouth_mask(target_face, original_frame)
        if mouth_cutout is not None and mouth_box != (0, 0, 0, 0):
            swapped_frame = apply_mouth_area(
                swapped_frame, mouth_cutout, mouth_box, face_mask, lower_lip_polygon
            )
            if getattr(modules.globals, "show_mouth_mask_box", False):
                swapped_frame = draw_mouth_mask_visualization(
                    swapped_frame, target_face, (mouth_mask, mouth_cutout, mouth_box, lower_lip_polygon)
                )

    if opacity >= 1.0:
        return swapped_frame.astype(np.uint8)
    return cv2.addWeighted(original_frame.astype(np.uint8), 1.0 - opacity, swapped_frame.astype(np.uint8), opacity, 0)


def process_frame(source_face: Face, temp_frame: Frame, target_face: Face = None) -> Frame:
    if getattr(modules.globals, "opacity", 1.0) == 0:
        return temp_frame

    swapped_bboxes = []
    if target_face is None:
        target_face = get_one_face(temp_frame)
    if target_face:
        temp_frame = swap_face(source_face, target_face, temp_frame)
        if hasattr(target_face, "bbox") and target_face.bbox is not None:
            swapped_bboxes.append(target_face.bbox.astype(int))
    return apply_post_processing(temp_frame, swapped_bboxes)


def process_frame_v2(temp_frame: Frame, temp_frame_path: str = "") -> Frame:
    source_face = default_source_face()
    target_face = get_one_face(temp_frame)
    return process_frame(source_face, temp_frame, target_face)


def process_frames(source_path: str, temp_frame_paths: List[str], progress: Any = None) -> None:
    source_face = None
    if source_path and os.path.exists(source_path):
        source_img = imread_unicode(source_path)
        if source_img is not None:
            source_face = get_one_face(source_img)
    if source_face is None:
        update_status("No source face detected for HyperSwap processing.", NAME)
        return

    total = len(temp_frame_paths)
    for index, temp_frame_path in enumerate(temp_frame_paths):
        temp_frame = imread_unicode(temp_frame_path)
        if temp_frame is None:
            if progress:
                progress.update(1)
            continue
        target_face = get_one_face(temp_frame)
        if target_face:
            temp_frame = process_frame(source_face, temp_frame, target_face)
            imwrite_unicode(temp_frame_path, temp_frame)
        if progress:
            progress.update(1)
        elif total > 0:
            update_status(f"HyperSwap processing frame {index + 1}/{total}", NAME)


def process_image(source_path: str, target_path: str, output_path: str) -> None:
    source_img = imread_unicode(source_path)
    target_img = imread_unicode(target_path)
    if source_img is None or target_img is None:
        update_status("Unable to read source or target image for HyperSwap.", NAME)
        return
    source_face = get_one_face(source_img)
    target_face = get_one_face(target_img)
    if source_face is None or target_face is None:
        update_status("No source or target face detected for HyperSwap.", NAME)
        return
    result = process_frame(source_face, target_img, target_face)
    imwrite_unicode(output_path, result)


def process_video(source_path: str, temp_frame_paths: List[str]) -> None:
    process_frames(source_path, temp_frame_paths)
