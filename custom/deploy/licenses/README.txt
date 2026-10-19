无人车地面站 —— 开源许可声明
==============================

本软件基于开源地面站 QGroundControl（https://github.com/mavlink/qgroundcontrol）开发，
QGroundControl 的许可证为 Apache License 2.0 和 GNU General Public License v3（GPLv3）。

本软件还使用了以下开源软件和数据：
  - Qt 框架（https://www.qt.io），GNU Lesser General Public License v3（LGPLv3）；
    Qt 自带的第三方组件见 Qt_third_party.txt（其中 FFmpeg 为 LGPL-2.1 或更高版本）
  - MAVLink 通信协议库，MIT 许可证
  - QGroundControl 编译时引入的其它开源库（zlib、zstd、libarchive、expat、
    GeographicLib、SDL3、shapelib 等），许可文件见 third_party 文件夹
  - opengl32sw.dll：Mesa 软件渲染器（llvmpipe），MIT 许可证
  - 地图数据来自天地图（https://www.tianditu.gov.cn）
  - 字体：HarmonyOS Sans（© 华为终端有限公司，HarmonyOS Sans 字体许可协议，
    见 HarmonyOS_Sans_LICENSE.txt）和 Barlow（SIL Open Font License 1.1，见 Barlow_OFL-1.1.txt）

开源部分的源代码可应要求提供。

各许可证原文在安装目录的 licenses 文件夹中：
  QGroundControl_LICENSE-APACHE.txt     QGroundControl（Apache License 2.0）
  QGroundControl_LICENSE-GPL-3.0.txt    QGroundControl（GPLv3）
  Qt_LGPL-3.0.txt                       Qt（LGPLv3）
  Qt_third_party.txt                    Qt 自带的第三方组件
  FFmpeg_LGPL-2.1.txt                   FFmpeg（LGPL-2.1）
  HarmonyOS_Sans_LICENSE.txt            HarmonyOS Sans 字体
  Barlow_OFL-1.1.txt                    Barlow 字体
  third_party\                          其它开源库


Unmanned Vehicle Ground Station — Open Source Notices
=====================================================

This software is based on QGroundControl (https://github.com/mavlink/qgroundcontrol),
licensed under the Apache License 2.0 and the GNU General Public License v3.

It also uses the following open source software and data:
  - the Qt framework (https://www.qt.io) under the GNU Lesser General Public License v3;
    third-party code bundled in Qt is listed in Qt_third_party.txt (FFmpeg: LGPL-2.1-or-later)
  - MAVLink (MIT License)
  - other open source libraries built into QGroundControl (zlib, zstd, libarchive, expat,
    GeographicLib, SDL3, shapelib and others), license files in the third_party folder
  - opengl32sw.dll: the Mesa software renderer (llvmpipe), MIT License
  - map data from TianDiTu (https://www.tianditu.gov.cn)
  - fonts: HarmonyOS Sans (© Huawei Device Co., Ltd., HarmonyOS Sans Fonts License Agreement,
    see HarmonyOS_Sans_LICENSE.txt) and Barlow (SIL Open Font License 1.1, see Barlow_OFL-1.1.txt)

The source code of the open source parts is available on request.

The license texts are in the licenses folder of the installation directory (see the list above).
