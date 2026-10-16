历史测试归档

本目录只用于追溯，不是日常入口。正式入口只在项目根目录。

已验证结论：

1. 官方 AVD + DroidCam
能通话，但 Windows 摄像头通常只以 640x480 / 4:3 提供给 WhatsApp；无法形成真正手机竖屏全屏。

2. 官方 AVD + WeCam / OBS Virtual Camera
能出现画面，但仍受 640x480、黑边、裁切和方向语义限制；增加桥接却没有解决根因。

3. BlueStacks
WhatsApp 可运行，摄像头可接入，但远端保持横屏视频语义；窗口改竖屏不等于手机摄像头方向。

4. MEmu
摄像头选择和网络/应用稳定性不足，不能稳定读取目标虚拟摄像头，停止采用。

5. VCam / e2eSoft
未形成可复用的稳定 WDM 链路，停止采用。

6. OBS 竖屏画布或在 1280x720 内预先加黑边
只能改变像素内容，不能改变 Android Camera HAL 向 WhatsApp 报告的前置摄像头方向和流规格。

7. 固定 MP4 -> AVD Camera HAL
证明 Front / 270 度且仅提供 1280x720 时，WhatsApp 对方手机能够真正竖屏全屏。这是定位根因的关键实验。

8. 最终成功方案
DeepLiveCam OBS Output -> FFmpeg I420 -> Frida -> 固定 API 37 Camera HAL -> WhatsApp Android。
远端竖屏全屏、方向和镜像均已验证。OBS 软件、DroidCam、WeCam、VCam、BlueStacks、MEmu 均不在最终链路内。

本目录内旧 CMD 已修正为从子目录引用 tools，但除回归排障外不要运行。
