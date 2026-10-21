# 小米平板 5（nabu）Ubuntu

[English](README.md)

适用于 Ubuntu 26.04 ARM64、内核 `6.17.0-xiaomi-nabu-tmm-UFS-slowdown+`，包含驱动、运行文件和源码修改。仅适用于**小米平板 5**，不适用于 Pad 5 Pro。使用纯 Linux 系统，Ubuntu 镜像另行下载。

## 安装

1. 解锁 BL，按上游说明安装 [nabu Ubuntu 26.04 基础镜像](https://github.com/TheMojoMan/xiaomi-nabu/releases/tag/ubuntu-26.04-v1.0.0)。根分区名称须为 `linux`，EFI 分区挂载到 `/boot/efi`。保留高通固件分区和本机的 `persist` 分区。
2. 完成桌面账户设置并连接 Wi-Fi。系统须已安装匹配的 6.17 BSP 内核文件 `/boot/vmlinuz-6.17.0-xiaomi-nabu-tmm-UFS-slowdown+`，再将本仓库复制到平板。
3. 在仓库目录执行：

   ```sh
   sudo bash install.sh "$USER"
   sudo reboot
   ```

安装程序会设置 EFI 启动项、安装修复文件、启用美式键盘和中文拼音输入，并将 Ubuntu 软件源设为中科大镜像，APT 不走代理。原有文件备份在 `/var/lib/nabu-ubuntu/before-install`。

独立 Linux UEFI 启动镜像和 TWRP 恢复镜像以单独文件放在 [Releases](https://github.com/DavidMastrenet/nabu-ubuntu/releases)。`boot/EFI/BOOT` 包含 EFI 启动管理器。仓库不包含 Ubuntu 系统镜像。

请从已登录的桌面终端运行安装程序。如果通过其他会话安装，登录桌面后再执行：

```sh
systemctl --user daemon-reload
systemctl --user enable --now nabu-autorotate.service
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'libpinyin')]"
```

## 修复内容

- 前后摄取景、后摄自动对焦、颜色与方向、拍照和有声录像。
- 相机切换、休眠后的相机恢复，以及相机故障导致音频服务阻塞的问题。
- 自动旋转、触屏坐标及休眠后的恢复。
- 原装磁吸键盘休眠唤醒后自动恢复连接。
- 扬声器、麦克风配置、RTC 选择和启动成功标记。
- rEFInd 快速启动：`timeout 2`、引入主题图标（`include themes/refind-theme-regular/theme.conf` 并显式指定 Ubuntu 图标）、只保留 `GopRotate` 驱动，消除"找不到图标"导致的长时间卡顿。
- Wi-Fi MAC 固定：`ath10k` 在本机没有板级地址，NetworkManager 配置为 `wifi.cloned-mac-address=stable`，不再每次启动随机。
- Type-C 取电角色：一次性服务加 udev 规则向 `/sys/class/typec/port0/power_role` 写入 `sink`，让充电器被正常接受，而不是由平板对外供电。

本次 6.17 更新已在平板启动验证。前后摄取帧、音频播放和旋转传感器读取均通过，桌面显示、触屏和 USB 网络正常。连续 180 秒的 37 次采样均显示电池正在充电，USB 输入电流为 480–483mA，温度保持 29°C，充电器健康状态为 Good。本次按设备所有者要求跳过 PD 硬件实测。

Type-C 角色属性用方括号标记当前值，`source [sink]` 表示平板已处于受电模式。SMB5 负责普通 5V USB 充电，输入限制为 500mA，充电电压目标为 4.35V。输入超过 5.5V 时，保护服务暂停 SMB5；LN8000 从 8V 起接管充电泵路径。驱动源码与来源见 [source/kernel/charging](source/kernel/charging/README.md)。

## 亮度与磁吸保护盖

桌面将亮度保存在 `~/.local/state/nabu-brightness.json`，登录后恢复上次设置。安装程序会关闭闲置调暗和环境光调节。磁吸保护盖合上时关闭屏幕，打开时点亮，合盖期间 USB 网络和 SSH 保持连接。

已有系统可以单独安装这组修复，内核、启动镜像和已装应用均保持原样。在已登录的 GNOME 桌面终端执行：

```sh
sudo bash configure-display.sh "$USER"
```

如果在桌面登录前通过 SSH 安装，登录后执行：

```sh
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action nothing
gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action nothing
systemctl --user restart nabu-display-state.service
```

本版设备树将错误的 `1,code` 和 `1,input-type` 改为 `linux,code` 和 `linux,input-type`，由内核直接注册 GPIO9 霍尔开关和音量上键。此前模拟盖子开关的 GPIO 服务已移除。

`nabu-display-state` 读取 UPower 上报的原生开合状态，再调用 Mutter 控制屏幕电源。亮度保存跳过合盖和息屏状态，防止把屏幕关闭时的数值记作用户亮度。

## 编译

在 Ubuntu 26.04 ARM64 上编译。先安装运行文件，再执行：

```sh
bash build.sh
bash build-kernel.sh
```

`build.sh` 下载指定版本的 Ubuntu 源码包，应用仓库内的源码修改，编译并安装用户态组件。`build-kernel.sh` 将修改后的内核模块和 EFI 文件生成到 `.build/kernel`，不会自动安装；需要已有匹配的 BSP 文件 `/boot/vmlinuz-6.17.0-xiaomi-nabu-tmm-UFS-slowdown+`。脚本准备 Linux 6.17 编译头文件并重建驱动模块，EFI 使用本机已有的 BSP 内核镜像。

`rootfs/` 存放运行文件，`boot/` 存放 EFI 和设备树，`source/` 存放修改后的源码及配套库。编译下载文件保存在 `.build/`。

## 恢复

保留基础镜像的 EFI 启动文件。需要恢复原启动项时，将 `/boot/efi/EFI/BOOT/refind.conf` 中 Ubuntu 的 `loader` 改回原路径；安装程序已将原配置保存在上述备份目录。无法启动 Ubuntu 时，可从恢复环境挂载 EFI 分区并恢复该配置。

BSP 内核固定为 `6.17.0-xiaomi-nabu-tmm-UFS-slowdown+`。更换内核前需重新编译并验证这些模块。

## 来源

维护者：洪宇轩 <yuxuan.hong@ieee.org>。

基于 [TheMojoMan/xiaomi-nabu](https://github.com/TheMojoMan/xiaomi-nabu)、[sm8150-mainline Linux](https://gitlab.com/sm8150-mainline/linux)（提交 `5181e1358ddd6ea8028e841d928942373e6aebc8`）、Ubuntu 的 libcamera `0.7.0-1ubuntu2` 和 GNOME Snapshot `50.0-0ubuntu1`，以及 libssc、hexagonrpc、iio-sensor-proxy、qbootctl。软件自动对焦改编自 Robin Snyders 在 [hotdog-linux-bringup](https://github.com/Sr-0w/hotdog-linux-bringup) 中的实现。传感器固件来自 [nabu firmware](https://gitlab.com/panpanpanpan/nabu-firmware)。

各组件保留原许可证和版权声明，见对应目录中的许可证文件及源码头部。
