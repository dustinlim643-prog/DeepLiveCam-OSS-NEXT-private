# DeepLiveCam OSS 功能增强迁移计划

## 目标

当前最终目标不是绕过授权，也不是复制 Pro 的编译代码，而是在无授权限制的 OSS 版本中，用开源方式重建会影响真实感、稳定性和 OBS/Telegram 实用性的功能。

生产主目录：

```text
D:\DeepLiveCam2.7-Pro-0730_OSS_READY
```

对比参考目录：

```text
D:\DeepLiveCam2.7-Pro-0730
```

## 明确边界

- 不移植、不破解、不绕过 Pro 的授权模块。
- 不反编译 `.pyd`，不从编译文件还原私有源码。
- 可以做功能级对比：看 Pro 暴露了哪些能力、有哪些模型、有哪些命令参数、运行时效果差异。
- 可以在 OSS 中用开源库、公开模型、我们自己的代码实现同类功能。
- 目标以最终效果验收：真实感、边缘、清晰度、延迟、稳定性、OBS 输出正确。

## 当前对比结论

模型文件方面，Pro 和 OSS_READY 基本一致：

- `inswapper_128.onnx`
- `inswapper_128_fp16.onnx`
- `GFPGANv1.4.onnx`
- `GFPGANv1.4.fp16.onnx`
- `GPEN-BFR-256.onnx`
- `GPEN-BFR-512.onnx`
- `hyperswap_1a_256.onnx`
- `hyperswap_1b_256.onnx`
- `hyperswap_1c_256.onnx`
- `xseg.onnx`
- `xseg_cuda_v1.onnx`
- `dfm\yangmmi.dfm`
- `insightface\buffalo_l`

主要差距在代码功能，而不是模型文件。

Pro 额外暴露出的关键业务模块：

| Pro 功能模块 | 对效果的意义 | OSS 当前状态 | 处理方式 |
| --- | --- | --- | --- |
| `face_swapper_hyperswap` | 可能提供比普通 inswapper 更好的脸部生成质量 | 模型在，处理器缺失 | 用开源方式接入 Hyperswap ONNX |
| `face_swapper_dfm` / `dfm_helper` | 支持 DFM 人物模型，特定人物拟真上限更高 | 模型在，处理器缺失 | 后续实现 DFM 推理入口 |
| `face_mask` | 更精细的脸部融合 mask | OSS 已有基础 mask/Poisson | 优先增强边缘 mask、羽化、脸型覆盖 |
| `face_occluder` | 处理眼镜、头发、手遮挡、边缘穿帮 | OSS 缺正式遮挡处理 | 用 XSeg/人脸分割模型补 |
| `face_enhancer_gfpgan` | 细节恢复、清晰度提升 | OSS 有 GFPGAN/GPEN 入口 | 优化默认参数、避免过度磨皮 |
| `face_reshape` | 调整脸型贴合度 | OSS 缺 | 后置，先解决边缘和清晰度 |
| `live_face_tracker` | 降低实时抖动、减少重复检测 | OSS 有缓存/队列，但追踪较弱 | 增强追踪和检测复用 |
| `live_landmark_tracker` | 关键点稳定，减少嘴眼边缘跳动 | OSS 缺正式追踪器 | 增强 landmark 平滑 |
| `live_performance` | 低延迟和帧率稳定 | OSS 已有队列 | 加入实际 FPS/延迟日志 |
| `provider_diagnostics` | 检测 CUDA/DirectML/CPU 是否正确跑 | OSS 有基础检查 | 加强启动前诊断 |

## 优先级

### P0：先把当前链路变成可稳定测试

验收标准：

- `启动_DeepLiveCam_OBS.bat` 能打开 DeepLiveCam UI 和项目内 OBS。
- DeepLiveCam 点 Live 后出现 `Live Preview`。
- OBS 捕获的是 `Live Preview`，不是 cmd，不是原始摄像头。
- Telegram 选择 `OBS Virtual Camera` 后对方看到换脸画面。
- 所有测试记录写入文档。

当前状态：基本完成。

### P1：提升真实感，先改最影响观感的地方

目标：

- 边缘不糊、不大片溢出。
- 嘴唇颜色不异常。
- 眼睛和嘴部不明显穿帮。
- 脸部不过度磨皮，不像贴图。
- 延迟可接受，画面不频繁波动。

实施顺序：

1. 增强 mask 控制：脸部覆盖、羽化、腐蚀/膨胀、额头/下巴边界。
2. 增强颜色匹配：减少嘴唇紫色、肤色偏色。
3. 增强锐化/细节：GFPGAN/GPEN 只对脸部区域低强度启用。
4. 增强实时稳定：检测缓存、关键点平滑、减少帧间跳动。
5. 写入测试预设：低延迟、平衡、高质量三套参数。

### P2：接入 Pro 同类高级能力的开源替代

目标：

- Hyperswap：先验证单帧效果，再接入实时。
- DFM：先验证已有 `yangmmi.dfm` 是否能在 OSS 中推理，再考虑训练 Elsa/Joanna。
- Occluder/XSeg：处理头发、眼镜、脸部边缘遮挡。

实施顺序：

1. 先做离线单帧测试，不直接改直播链路。
2. 单帧效果确认后，接入 Live Preview。
3. 观察 FPS、显存、延迟，再决定是否作为默认。

### P3：素材和训练流程

如果用少图方案：

- 重点是挑源图，不是训练。
- 源图必须高清、正脸、自然光、无遮挡、脸部比例接近摄像头里的人脸。

如果训练 DFM：

- 需要稳定、多角度、足够清晰的人物素材。
- 训练质量和素材一致性强相关。
- 模型大小本身不是唯一关键，更重要的是分辨率、迭代、素材质量、遮挡和角度覆盖。

## 测试方法

每次测试只改一类变量：

| 测试项 | 固定项 | 变化项 | 记录 |
| --- | --- | --- | --- |
| 源图测试 | 摄像头、灯光、参数 | 换不同授权源图 | 真实感、脸型、嘴色、边缘 |
| Mask 测试 | 同一源图、同一摄像头 | mask/羽化参数 | 边缘、头发、额头、下巴 |
| 增强器测试 | 同一源图、同一摄像头 | None/GFPGAN/GPEN | 清晰度、磨皮、延迟 |
| 性能测试 | 同一源图、同一参数 | 720p/1080p、FPS | GPU、显存、延迟、卡顿 |
| OBS 测试 | 同一 DeepLiveCam 输出 | OBS 滤镜/缩放 | 是否更清晰、是否增加延迟 |

## 下一步执行清单

1. 保持当前 OSS_READY 为唯一主方案。
2. 不再从 Pro 拿授权相关文件。
3. 建立 `presets` 或配置记录，保存低延迟/平衡/高质量参数。
4. 先实现 P1：mask、颜色、增强、稳定性。
5. 再做 P2：Hyperswap/DFM/Occluder 的开源实现验证。
6. 每次改动后做一次本地启动测试，并记录结果。

## 固定验证规则

以后每次修改代码、启动脚本、OBS 配置或模型配置后，必须先运行：

```text
D:\DeepLiveCam2.7-Pro-0730_OSS_READY\更新后自检验证.bat
```

或者直接运行：

```text
powershell -NoProfile -ExecutionPolicy Bypass -File D:\DeepLiveCam2.7-Pro-0730_OSS_READY\tools\update_verify.ps1
```

自检内容包括：

- 本地 Python 是否存在。
- ffmpeg 是否存在。
- 项目内便携 OBS 是否存在。
- OBS 便携模式标记是否存在。
- `inswapper` 模型是否存在。
- OBS 是否捕获 `Live Preview`。
- OBS 是否保留锐化/颜色滤镜。
- 启动脚本是否带 CUDA、实时 FPS debug 参数。
- Python 关键文件是否能编译通过。

自检报告位置：

```text
D:\DeepLiveCam2.7-Pro-0730_OSS_READY\logs\update_verify.txt
```

只有 `RESULT: PASS` 后，才进入人工画面测试。

## 当前判断

能做，但不是“把 Pro 代码复制过来”这种做法。正确做法是：以 Pro 的功能表现为参照，在 OSS 里重建功能。这样最终目录仍然是无授权限制的开源项目，也更适合迁移到生产电脑。

## 已执行改动记录

### 2026-08-14：补齐 Pro 同类测试诊断参数

已在 OSS_READY 中增加：

- `--live-fps-debug`
  - 每 5 秒在 DeepLiveCam cmd 窗口输出一次实时处理 FPS。
  - 同时输出摄像头 FPS、检测间隔、输入/输出队列长度。
  - 用来判断卡顿来自模型处理、摄像头读取，还是窗口/OBS 输出。

- `--similar-face-distance`
  - 默认值：`1.5`
  - 用于 map faces 多脸匹配时限制相似度距离。
  - 作用是避免目标脸距离过远还被强行匹配，减少误换和跳脸。

启动脚本已更新：

```text
启动_DeepLiveCam_OBS.bat
```

当前启动参数包含：

```text
--execution-provider cuda --execution-threads 2 --live-resizable --live-fps-debug --similar-face-distance 1.5 -l zh
```

验证结果：

- `run.py --help` 已能看到 `--live-fps-debug`。
- `run.py --help` 已能看到 `--similar-face-distance`。
- `modules\globals.py`、`modules\core.py`、`modules\ui.py`、`modules\processors\frame\face_swapper.py` 均通过 Python 编译检查。

### 2026-08-14：新增更新后自检验证

新增：

```text
D:\DeepLiveCam2.7-Pro-0730_OSS_READY\tools\update_verify.ps1
D:\DeepLiveCam2.7-Pro-0730_OSS_READY\更新后自检验证.bat
```

已运行验证，结果：

```text
RESULT: PASS
```

### 2026-08-14：P1 真实感预设与边缘/颜色增强

新增 `--quality-preset` 参数：

```text
low_latency
balanced
high_quality
```

当前启动脚本默认使用：

```text
--quality-preset balanced
```

`balanced` 当前策略：

- 开启颜色修正。
- 颜色迁移强度：`0.35`。
- 换脸区域锐化：`0.25`。
- mask 覆盖比例：`0.44`。
- mask 羽化：`31`。
- 开启轻度帧间稳定。
- 帧间权重：`0.72`。

本次实际改动：

- 将 mask 大小和羽化从固定值改为预设控制。
- 颜色迁移改为使用摄像头当前帧的目标脸区域作为参考，避免嘴唇发紫、肤色不贴。
- 修正开启颜色修正时必须保留原始帧副本，避免后续融合参考被 in-place 贴回污染。
- UI 中 Sharpness 滑块初始值改为读取当前预设值，不再固定为 0。
- 更新自检脚本，检查 `--quality-preset` 和启动脚本的 `balanced` 预设。

验证结果：

```text
RESULT: PASS
```

下一轮人工画面测试重点：

- 嘴唇是否还发紫。
- 脸部边缘是否更自然。
- 是否因为颜色修正增加明显延迟。
- 如果边缘仍糊，下一步测试 `high_quality`。
- 如果延迟明显，下一步测试 `low_latency`。
