# DeepLiveCam OSS_READY 最终可用性检查报告

检查时间：2026-08-14

## 当前主方案

只使用这个目录：

```text
D:\DeepLiveCam2.7-Pro-0730_OSS_READY
```

主启动入口：

```text
启动_DeepLiveCam_OBS.bat
```

停止入口：

```text
停止_DeepLiveCam_OBS.bat
```

更新后自检入口：

```text
更新后自检验证.bat
```

## 已验证结果

### 1. 更新后自检

结果：

```text
RESULT: PASS
```

已确认：

- 项目内 Python 存在。
- 项目内 ffmpeg 存在。
- 项目内 OBS 存在。
- OBS 便携模式标记存在。
- `inswapper_128.onnx` 和 `inswapper_128_fp16.onnx` 存在。
- OBS 场景捕获目标是 `Live Preview`。
- OBS 锐化和颜色滤镜存在。
- 启动脚本包含 CUDA、实时 FPS debug、balanced 质量预设。
- 关键 Python 文件能编译通过。

### 2. 生产环境快速检查

结果：

```text
OK python\python.exe
OK ffmpeg\bin\ffmpeg.exe
OK obs-studio\bin\64bit\obs64.exe
OK obs-studio\portable_mode.txt
OK models\inswapper_128.onnx
OK OBS Virtual Camera found
```

### 3. 主链路启动检查

已实际运行主启动脚本，确认：

- DeepLiveCam 使用项目内 Python 启动。
- 启动参数包含：

```text
--execution-provider cuda
--execution-threads 2
--live-resizable
--live-fps-debug
--similar-face-distance 1.5
--quality-preset balanced
-l zh
```

- OBS 使用项目内便携版启动。
- OBS 启动参数包含：

```text
--portable
--collection DeepLiveCam
--scene DeepLiveCam
--startvirtualcam
```

验证完成后已运行停止脚本，项目内 DeepLiveCam/OBS 进程已停止。

## 与 Pro 参考版本的功能对比

参考目录：

```text
D:\DeepLiveCam2.7-Pro-0730
```

当前 OSS_READY 与 Pro 的主要差距不在模型文件，而在处理逻辑。模型文件基本齐全，但 Pro 多了编译模块。

### 已补齐或已具备

| 功能 | 当前状态 |
| --- | --- |
| 基础实时换脸 | 已具备 |
| 项目内 Python/ffmpeg/OBS | 已具备 |
| OBS 捕获 Live Preview | 已配置 |
| OBS Virtual Camera | 已检测到 |
| CUDA 启动 | 已配置 |
| 中文 UI 参数 | 已配置 |
| 实时 FPS debug | 已补齐 |
| similar-face-distance | 已补齐 |
| balanced/low_latency/high_quality 质量预设 | 已补齐 |
| mask 大小/羽化预设控制 | 已补齐 |
| 颜色迁移到目标脸肤色 | 已补齐 |
| OBS 锐化和颜色稳定滤镜 | 已配置 |

### 仍未完全补齐

| Pro 能力 | 当前状态 | 影响 |
| --- | --- | --- |
| `face_swapper_hyperswap` | 模型存在，处理器未接入 | 可能影响单图换脸质量上限 |
| `face_swapper_dfm` | DFM 模型存在，处理器未接入 | 影响特定人物模型能力 |
| `face_occluder` | 未完整实现 | 头发、眼镜、遮挡处仍可能穿帮 |
| `face_reshape` | 未实现 | 脸型贴合度可调空间有限 |
| `live_face_tracker` | 仅有缓存/检测复用 | 快速移动时稳定性仍可能弱 |
| `live_landmark_tracker` | 未完整实现 | 嘴眼边缘可能轻微跳动 |
| Pro Qt6 UI | 未复制 | 不影响主链路，但操作体验不同 |

## 当前可用性判断

当前版本可以作为最终可测试版本使用：

- 启动链路可用。
- OBS/Telegram 链路可用。
- 参数有默认质量预设。
- 自检脚本可复用。
- 运行环境已放入同一项目目录。

但如果目标是继续逼近 Pro 质量，下一阶段应按这个顺序补：

1. 遮挡/边缘：接入或实现 XSeg/occluder。
2. 稳定性：增强 live face/landmark tracking。
3. 清晰度：细调 GFPGAN/GPEN 的低强度实时增强。
4. 高级换脸：先离线验证 Hyperswap，再决定是否接实时。
5. DFM：先验证已有 DFM 推理入口，再考虑训练授权人物模型。

## 当前测试时要观察

人工画面测试时只看这几项：

- 嘴唇是否还偏紫。
- 脸部边缘是否比之前自然。
- 头发/眼镜/脸边是否穿帮。
- 画面是否抖动。
- cmd 每 5 秒输出的 `[live-fps]` 是否稳定。
- Telegram 对方看到的是 OBS Virtual Camera 输出，而不是原摄像头或 cmd。
