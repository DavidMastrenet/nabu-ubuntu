# 小米平板 5（nabu）Ubuntu

[English](README.md)

适用于 Ubuntu 26.04 ARM64、内核 `6.14.11-nabu-tmm`，包含驱动、运行文件和源码修改。仅适用于**小米平板 5**，不适用于 Pad 5 Pro。使用纯 Linux 系统，Ubuntu 镜像另行下载。

## 安装

1. 解锁 BL，按上游说明安装 [nabu Ubuntu 26.04 基础镜像](https://github.com/TheMojoMan/xiaomi-nabu/releases/tag/ubuntu-26.04-v1.0.0)。根分区名称须为 `linux`，EFI 分区挂载到 `/boot/efi`。保留高通固件分区和本机的 `persist` 分区。
2. 完成桌面账户设置并连接 Wi-Fi，将本仓库复制到平板。
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

已在本机检查重启、休眠唤醒、相机切换、自动对焦、显示、触屏、旋转、键盘、扬声器和麦克风，也检查了 USB-PD 充电。

## 编译

在 Ubuntu 26.04 ARM64 上编译。先安装运行文件，再执行：

```sh
bash build.sh
bash build-kernel.sh
```

`build.sh` 下载指定版本的 Ubuntu 源码包，应用仓库内的源码修改，编译并安装用户态组件。`build-kernel.sh` 将修改后的内核模块和 EFI 文件生成到 `.build/kernel`，不会自动安装；需要已有 `/boot/vmlinuz-6.14.11-nabu-tmm`。

`rootfs/` 存放运行文件，`boot/` 存放 EFI 和设备树，`source/` 存放修改后的源码及配套库。编译下载文件保存在 `.build/`。

## 恢复

保留基础镜像的 EFI 启动文件。需要恢复原启动项时，将 `/boot/efi/EFI/BOOT/refind.conf` 中 Ubuntu 的 `loader` 改回原路径；安装程序已将原配置保存在上述备份目录。无法启动 Ubuntu 时，可从恢复环境挂载 EFI 分区并恢复该配置。

内核固定为 `6.14.11-nabu-tmm`。更换内核前需重新编译并验证这些模块。

## 来源

维护者：洪宇轩 <yuxuan.hong@ieee.org>。

基于 [TheMojoMan/xiaomi-nabu](https://github.com/TheMojoMan/xiaomi-nabu)、[sm8150-mainline Linux](https://gitlab.com/sm8150-mainline/linux)（提交 `5181e1358ddd6ea8028e841d928942373e6aebc8`）、Ubuntu 的 libcamera `0.7.0-1ubuntu2` 和 GNOME Snapshot `50.0-0ubuntu1`，以及 libssc、hexagonrpc、iio-sensor-proxy、qbootctl。软件自动对焦改编自 Robin Snyders 在 [hotdog-linux-bringup](https://github.com/Sr-0w/hotdog-linux-bringup) 中的实现。传感器固件来自 [nabu firmware](https://gitlab.com/panpanpanpan/nabu-firmware)。

各组件保留原许可证和版权声明，见对应目录中的许可证文件及源码头部。
