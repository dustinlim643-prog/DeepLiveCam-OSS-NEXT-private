# WhatsApp + DroidCam Video 方案记录

更新时间：2026-08-17

## 最终确认链路

```text
DeepLiveCam Live Preview
  -> OBS 捕获 OBS Output 窗口
  -> DroidCam Virtual Output 插件
  -> Windows 摄像头设备 DroidCam Video
  -> WhatsApp Desktop 选择 DroidCam Video
```

## 结论

- WhatsApp Desktop 使用 `OBS Virtual Camera` 时不稳定，通话页可能只显示真实摄像头，或提示摄像头被占用。
- 改用 `DroidCam Video` 后，WhatsApp 可以正常识别和切换，且不再弹出“camera is being used by another app”。
- OBS 仍然保留在链路中，用来做画面捕获、比例调整、锐化、颜色稳定和后续美颜滤镜。

## 当前关键配置

- 项目目录：`D:\DeepLiveCam2.7-Pro-0730_OSS_READY`
- 启动入口：`1_START.cmd`
- 停止入口：`2_STOP.cmd`
- OBS 场景：`DeepLiveCam`
- OBS 捕获源：`DeepLiveCam OBS Output`
- OBS 捕获窗口：`OBS Output:HighGUI class:python.exe`
- OBS 画布：`1280x720`
- OBS FPS：`30`
- WhatsApp 摄像头：`DroidCam Video`
- 不再推荐 WhatsApp 使用：`OBS Virtual Camera`

## 当前 WhatsApp 比例设置

由于 WhatsApp 会对摄像头画面做自己的预览缩放/裁切，所以 OBS 里不能把画面铺满，否则手机端会显得脸太大。

当前已经调成留安全边距：

```text
画布：1280x720
画面区域：970x546
位置 X：155
位置 Y：86
```

如果还觉得大，可以继续缩小：

```text
画面区域：900x506
位置 X：190
位置 Y：107
```

如果太小，可以回到：

```text
画面区域：1100x619
位置 X：90
位置 Y：50
```

## 手动调比例

在 OBS 里操作：

1. 选中源 `DeepLiveCam OBS Output`
2. 右键 -> `变换` -> `编辑变换`
3. 调整 `位置` 和 `边框框大小 / Bounds`
4. WhatsApp 的 `DroidCam Video` 会同步变化

常用判断：

- 画面太大：减小 Bounds 宽高
- 脸太靠上：增加 Y
- 脸太靠下：减小 Y
- 左右被裁：减小 Bounds 宽高并居中

## 对方手机画面更模糊的原因

这是正常现象，但可以优化。主要原因不是单一软件坏了，而是链路里有多次压缩和缩放：

1. DeepLiveCam 换脸模型本身会损失一部分脸部细节。
2. OBS 捕获窗口后会重新缩放到 1280x720。
3. DroidCam Virtual Output 再输出成虚拟摄像头流。
4. WhatsApp 会根据网络和手机端显示尺寸再次压缩码率。
5. 手机端小窗/通话界面可能再做裁切和锐化/降噪。

所以电脑本地 OBS 里看清楚，对方手机看到更糊，是视频通话软件里常见的现象。

## 后续优化方向

优先级从高到低：

1. 改善真实摄像头光线，保证脸部亮、稳定、不过曝。
2. OBS 输出继续保持 1280x720/30fps，先不要盲目升 1080p。
3. 避免 WhatsApp 同时使用真实摄像头麦克风设备，视频只选 `DroidCam Video`。
4. 如果网络差，WhatsApp 会自动降码率，画面会明显糊。
5. 如果需要更清晰，后续再测试 1080p DroidCam/OBS 输出，但要观察延迟和稳定性。
6. 换更强显卡后，可以提高 DeepLiveCam 的增强质量，但 WhatsApp 压缩仍然存在。

## 稍后待做测试

当前先不急着改 1080p。下一轮画质测试按这个顺序：

1. 保持当前 720p / 30fps / DroidCam Video 链路，连续通话 5-10 分钟。
2. 观察对方手机端是否稳定：不黑屏、不掉设备、不明显音画不同步。
3. 如果只是画面偏糊，再测试 1080p 输出。
4. 如果 1080p 延迟明显变大、掉帧或 WhatsApp 降码率，回到 720p，优先优化灯光、摄像头位置和 OBS 锐化/颜色。
5. 每次测试记录：分辨率、FPS、对方观感、延迟、是否掉线、是否糊。

## 摄像头分辨率判断

当前摄像头优先固定为 `1920x1080 / 30fps`，不优先使用 4K。

原因：

1. 当前链路最终进入 WhatsApp 后会被二次压缩，4K 输入不会等比例变成对方看到的 4K 清晰度。
2. 4K 会明显增加 DeepLiveCam 换脸、OBS 捕获、DroidCam 输出和 WhatsApp 编码的负担。
3. 实测目标是实时稳定，1080p 比 4K 更容易保持低延迟和稳定帧率。
4. 如果 1080p 本地画面干净，最终观感通常比 4K 输入后掉帧、降码率、自动压缩更好。

后续测试优先级：

```text
首选：1920x1080 / 30fps 摄像头输入
OBS 输出：1280x720 / 30fps 先稳定
稳定后再测：OBS / DroidCam 1920x1080 / 30fps
不建议默认：4K 摄像头输入
```

结论：当前摄像头不是越高越好。为了 WhatsApp 实时视频，优先限制到 1080p。

## 硬件升级判断记录

当前项目本地检查结果：

- 当前项目没有安装 PyTorch。
- 当前实时链路主要依赖 `onnxruntime`，可用 providers 包括 `TensorrtExecutionProvider`、`CUDAExecutionProvider`、`CPUExecutionProvider`。
- 因此显卡兼容性重点不是单纯 PyTorch，而是 NVIDIA 驱动、CUDA、ONNX Runtime、TensorRT/CUDA provider 是否匹配。

初步结论：

- 如果追求“最少兼容性风险、今天买今天用”，RTX 4080 / 4080 SUPER 更稳，因为 Ada 40 系软件生态成熟。
- 如果愿意保持较新的驱动和 AI 框架版本，RTX 5070 Ti 不应被简单判断为比 4070 Ti/4080 更差；它是 Blackwell，AI TOPS 和新 Tensor Core 更强，但要求新软件栈。
- RTX 4070 Ti 只有 12GB 显存，不建议作为长期主力；后续开更高分辨率、增强、遮罩、OBS/WhatsApp 同跑时余量不如 16GB 卡。
- 采购优先级暂定：RTX 4080 SUPER / RTX 4080 稳定优先；RTX 5070 Ti 性能和新架构优先；不优先 RTX 4070 Ti。

后续买卡前必须确认：

1. 驱动版本支持目标显卡。
2. ONNX Runtime GPU 版本支持当前 CUDA 大版本。
3. 如果未来换 PyTorch 工具，PyTorch 必须是支持 Blackwell/CUDA 12.8 或更新的版本。
4. 新电脑至少 32GB 内存，建议 64GB；电源按显卡要求预留余量。

## 当前状态

- DeepLiveCam -> OBS：已通
- OBS -> DroidCam Video：已通
- DroidCam Video -> WhatsApp：已通
- WhatsApp 不弹摄像头占用提示：已解决
- 当前剩余问题：手机端显示比本地 OBS 更模糊，属于通话压缩和多级缩放问题，需要继续按画质测试优化
