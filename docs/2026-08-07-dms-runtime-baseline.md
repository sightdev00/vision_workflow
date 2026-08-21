# DMS 交付制品、模型与配置基线

> 状态：草稿（基线待补齐）
> 核查日期：2026-08-07
> 维护入口：[DMS 运行时统一](../README.md)
> 关联代码仓库：Hi3519DV500 旧实现、RV1126B 旧实现、`dms-deploy`、`algo-base`

本文记录设计前能够找到的 DMS 运行库、配置和模型，并说明哪些材料已经能绑定到源码，哪些仍然缺失。后续测试和发布必须记录实际使用的整套文件，不能只写一个仓库 commit 或软件版本号。

## 1. 基线包含什么

一套可用于回归的运行基线至少包括：

- 公开头文件及其 SHA-256；
- DMS 动态库、SONAME、导出符号、直接动态依赖及 SHA-256；
- 对应的源码 commit、SDK/子模块 commit、构建类型、工具链和构建时间；
- `dsm.ini`、`blur_det.ini` 及其他实际读取的配置；
- 所有模型、标签和 prior 文件；
- 设备平台、系统镜像或关键运行库版本；
- 能成功完成初始化、送帧、回调和退出的日志；
- 用于回归的输入数据及期望输出。

缺少模型或配置内容哈希时，只能说明代码期望哪些文件，不能说明已经建立了可复现的运行基线。

## 2. 固定源码版本

| 项目 | 固定版本 | 用途 |
|---|---|---|
| Hi3519DV500 | `5eaf381e1ca66ecc7084a674ea61cfe21967e876` | Hi 源码设计基线 |
| RV1126B | `0f19bc6f805f6a5a385d877b62b531f9af32b0d0` | RV 源码设计基线 |
| RV1126B SDK | `4cc1efcaa7cbd017fd3df8313961f00e380310df` | RV 公共头和 SDK 基线 |
| RV1126B libaidsm | `fde8f6e6416d6fdcc2f324bb26037bc824ef6212` | 已固定但未进入当前 DMS 调用链 |

当前旧仓库工作区都包含后续提交或未提交修改。后续核查继续使用上述 commit，不把当前目录状态默认为固定版本。

## 3. RV1126B 制品绑定

### 3.1 已找到的运行库

位置：`/mnt/231/Data/Archived/rv1126b/data/faceid/20260805/exapp/lib/libhq_dsm_proc.so`

| 属性 | 值 |
|---|---|
| 文件大小 | 264360 bytes |
| SHA-256 | `6545b87d86c0a3057463f228058bc29dbe86e90698a50de901bcd414bba9810a` |
| ELF | AArch64，共享库，已 strip |
| SONAME | `libhq_dsm_proc.so` |
| Build ID | `32b742f5ecf454e0f8aea7c3fe543047837e3f80` |
| 清单中的源码 commit | `ba80ebb478995550aa41e2ab85a552fb80ae73fc` |
| 清单中的 build id | `20260805_164818_ba80ebb47899` |
| 清单中的版本 | `1.1.0.9` |
| 清单中的 MD5 | `f419c563e1d65389dfc2b01a7c57ee87` |

对应清单为：

`/mnt/231/Data/Archived/rv1126b/data/faceid/20260805/exapp/.internal/manifest/manifest_ba80ebb47899_2026-08-05T16:48:18+0800.json`

库内构建信息与清单中的 commit、版本和时间一致。进一步对比得到：

| 内容 | `ba80ebb...` 与固定版本 `0f19bc...` 的关系 |
|---|---|
| `bsd_dsm_core` DMS 代码树 | 相同 |
| `bsd_dsm_core/etc/dsm.ini` | 相同 blob |
| `common_core` | 相同代码树 |
| SDK 子模块 | 均为 `4cc1ef...` |

因此，这个库可以代表固定 RV DMS 源码在该构建环境下的实现。它仍不能单独构成完整运行基线，因为归档中缺少 DMS 配置和模型。

### 3.2 直接动态依赖

该库直接依赖以下运行库：

```text
libhq_preproc.so
libvideo_source.so
libhq_infer.so
libhq_log.so
libblur_det.so
libobj_det.so
libopencv_world.so.413
libtoolkit.so
libylog.so
libstdc++.so.6
libm.so.6
libc.so.6
ld-linux-aarch64.so.1
libgcc_s.so.1
```

后续打包和整体测试必须检查这些库的实际加载路径及哈希。只核对 `libhq_dsm_proc.so` 不能排除依赖版本变化引起的行为差异。

### 3.3 版本和交付目录问题

- `DSMProc::GetVersion()` 在源码中返回硬编码的 `1.0.7.110`，与制品清单和库内构建版本 `1.1.0.9` 不同；
- 归档根目录的 `version.txt` 指向后来的 BSD 构建 `0f19...`、版本 `1.1.0.10`，不能用作这份 DMS 库的版本；
- `deliveries/dsm_rv1126b_v1.1.0.9_20260805` 混有 BSD demo、BSD 库、口罩 demo 和其他库；
- 该交付目录没有 `dsm_proc_interface.h`、`dsm.ini`、`blur_det.ini` 和 DMS 模型；
- 顶层归档也没有 `/exapp/etc/dsm.ini` 和完整 `/exapp/model/dsm`。

后续需要让运行时版本、构建清单版本和发布包版本来自同一个构建定义，并按 DMS 实际运行所需文件制作交付清单。

## 4. Hi3519DV500 现有制品

当前能找到的文件位于：

`Hi3519DV500/algo/dsm/src/install`

| 文件 | 大小 | SHA-256 |
|---|---:|---|
| `lib/libhq_dsm_lib.so` | 824064 | `5c169c1e63798fda664153d0cb465f4ff963e3920ec77927241642b8ff8b4dbd` |
| `lib/libhq_dsm_proc.so` | 207384 | `ed3de8f5edd7d501735363a5346c495e2756b10d2b2c96fd32da040d57f72eef` |
| `include/dsm_proc_interface.h` | — | `41d1b2bb7fd05d1fd019d43638a1049a19adaca6a80b427cd3922b732feaef2c` |

公开头与固定 Hi 源码及 Hi SDK 中的头文件相同。两个库的构建信息为：

- 源码 commit：`75e7513d7cf1...`；
- build id：`20260806_163934_75e7513d7cf1`；
- 版本：`1.1.0.10`；
- 构建时间：`2026-08-06T16:39:34+0800`。

这组库不能作为固定 Hi 版本 `5eaf...` 的运行基线，原因如下：

1. 构建 commit 不是固定设计版本；
2. 构建时工作区中的 DMS 文件存在未提交修改，文件时间早于库的构建时间，库可能包含这些修改；
3. 构建信息没有记录工作区是否 dirty，也没有记录未提交内容的补丁哈希；
4. 没有找到与这组库配套的完整发布清单、配置和模型。

`5eaf...` 到 `75e...` 的已提交 DMS 业务差异很少，`base/common` 代码树也相同，但这不足以证明二进制行为相同。该组文件只作为现状参考，不能用于新旧结果验收。

Hi 构建关系也需要在重构时保留检查：`libhq_dsm_proc.so` 依赖共享库 `libhq_dsm_lib.so`，而 RV 把 `hq_dsm_lib` 静态链接进 `libhq_dsm_proc.so`。Hi 现有库还包含媒体、平台推理、IVE、属性、加密和 OpenCV 等较多直接依赖；其 RPATH 中存在源码工作区 SDK 的绝对路径，发布前必须消除。

## 5. 固定配置基线

### 5.1 配置文件哈希

| 平台 | 文件 | SHA-256 | 说明 |
|---|---|---|---|
| Hi | `algo/etc/dsm.ini` | `f5430ef8f4b9c52c5ad2009f81b8a2b82c553d6797990bab081b21354045beb3` | `DSMProc::Init` 实际读取 |
| Hi | `publish/etc/dsm.ini` | `f5430ef8f4b9c52c5ad2009f81b8a2b82c553d6797990bab081b21354045beb3` | 与源码配置相同 |
| RV | `bsd_dsm_core/etc/dsm.ini` | `e18afea841891c99189d901fa2abe6765cbe999a5a0386fdfecfb62caba6003b` | `DSMProc::Init` 实际读取 |
| Hi | `blur_det.ini` | `6b1947cb4d14076a08f368e9c460b39a74f80376f17c95c4a4ad68847e26292e` | 引用 OM 模型 |
| RV | `blur_det.ini` | `2dce9494f7044d73fbc0a12dacec62419d3d0c5c10d58d9debb1f800af0d59ae` | 引用 RKNN 模型 |
| Hi | `algo/etc/hq_ai.cfg` | `d463fc7bb69f91fb21371506841340817272ebc70251b796b5e1f16211b33d54` | 历史配置，不是自测 `Init` 传入文件 |
| Hi | `publish/etc/hq_ai.cfg` | `aaa27d7c10fc7cd6c26de041bf02e8790ba7be5415f2f1770377e768f58c6713` | 与 `algo/etc` 中的文件不同 |

两端 `dsm.ini` 都包含 12 个键，并使用 `/exapp` 绝对目录。路径中的 `sphere_model` 都有重复的 `//`，当前系统通常能够解析，但新实现应在保持配置兼容的同时规范内部路径。

源码中还保留 `/data/hq/model/dsm/...rknn` 默认值，包括 Hi 代码。正常配置完整时这些默认值不应生效；需要增加缺键测试，确认配置解析器的返回语义和实际报错方式。

### 5.2 配置键和文件要求

| 配置键 | Hi3519DV500 | RV1126B | 使用模块 |
|---|---|---|---|
| `dsm_model` | `dsm_objectDet.om` | `dsm_objectDet.rknn` | DMS 目标检测 |
| `det3_model` | `dsm_headPose.om` | `dsm_headPose.rknn` | 头姿 |
| `det4_model` | `dsm_keypoints.om` | `dsm_keypoints.rknn` | 关键点 |
| `sphere_model` | `dsm_recognition.om` | `dsm_recognition.rknn` | 人脸识别 |
| `fatigue_model` | `dsm_fatigue.om` | `dms_fatigue.rknn` | 疲劳检测；前缀不同 |
| `label_model` | `dsm_objectDet_labels.txt` | 同名 | 标签 |
| `priorbox_model` | `dsm_objectDet_priors.txt` | 同名 | prior box |
| `sbd_model` | `dsm_safetyBelt.om` | `dsm_safetyBelt.rknn` | 安全带；RV 固定源码未实际初始化 |
| `sunglasses_model` | `dsm_sunglasses.om` | `dms_sunglasses.rknn` | 墨镜；前缀不同 |
| `dsm_blur_det` | `/exapp/etc/blur_det.ini` | 同路径 | 模糊检测配置 |
| `mask_model` | `dsm_mask.om` | `dms_mask.rknn` | 口罩；前缀不同 |
| `livedetection_model` | `dsm_livedetection.om` | `dsm_livedetection.rknn` | 活体检测 |

额外的硬编码文件：

| 文件 | Hi | RV | 说明 |
|---|---|---|---|
| `dsm_faceDet` | 固定 `.om`，受 `FACEDET` 宏控制 | 按 basename 查扩展名 | 人脸检测 |
| `dsm_faceBlur` | 固定 `.om`，受 `FACEDET` 宏控制 | 按 basename 查扩展名 | 人脸模糊 |
| `/exapp/model/bsd/cam_blur.*` | `.om` | `.rknn` | `blur_det.ini` 引用，DMS 对 BSD 模型目录形成依赖 |

DMS 使用 `/exapp/model/bsd/cam_blur.*` 是当前真实依赖，但目标目录设计不应继续用业务名表达共享能力。兼容层可以继续接受旧路径，安装清单另行配置到统一目录；迁移前先确认模型由谁维护、是否与 BSD 共用同一内容和版本。

`hq_ai.cfg` 中部分文件名使用 `dms_fatigue`、`dms_sunglasses` 和 `dms_mask`，而 Hi `dsm.ini` 使用 `dsm_*`。后续必须以产品实际传给 `Init` 的配置为准，不能混用两份文件猜测模型名。

## 6. 模型搜索结果

已检查 Hi 仓库、RV 仓库和 `/mnt/231/Data/Archived` 中与上述路径同名的 `.om`、`.rknn`、标签和 prior 文件，没有找到一套与固定源码及配置相匹配的完整板端文件。仓库也没有相应的 Git LFS 记录。

发现的情况包括：

- Hi `publish/model/dsm/model` 只有 `dsm_facePartsDet.om`，不在当前 `dsm.ini` 的 12 个路径中；
- RV 的模型 zoo 含 ONNX、Caffe 等源模型候选，但不是当前配置要求的板端 RKNN 交付文件；
- RV 2026-08-05 DMS 交付目录没有包含上述模型；
- Hi 没有找到与当前库相配套的完整发布包。

因此，当前只能固定“应当有哪些文件和路径”，不能固定模型内容、量化版本、转换参数和 SHA-256。没有这些信息时，不应开始跨平台精度结论或最终行为合并。

## 7. 需要从工作设备补齐的文件

### 7.1 Hi3519DV500

从一台当前产品可正常运行的设备或其发布包复制：

```text
/exapp/lib/libhq_dsm_proc.so
/exapp/lib/libhq_dsm_lib.so
/exapp/etc/dsm.ini
/exapp/etc/blur_det.ini
/exapp/model/dsm/ 下实际使用的全部文件
/exapp/model/bsd/cam_blur.om
产品实际使用的 dsm_proc_interface.h
最小上层调用程序或对应源码
```

同时保存 `ldd` 或等价依赖信息、DMS 版本输出、初始化日志、系统/SDK 版本和每个文件的 SHA-256。

### 7.2 RV1126B

从一台当前产品可正常运行的设备或其发布包复制：

```text
/exapp/lib/libhq_dsm_proc.so
/exapp/etc/dsm.ini
/exapp/etc/blur_det.ini
/exapp/model/dsm/ 下实际使用的全部文件
/exapp/model/bsd/cam_blur.rknn
产品实际使用的 dsm_proc_interface.h
libhq_preproc.so、libhq_infer.so、libblur_det.so、libobj_det.so 等实际加载依赖
最小上层调用程序或对应源码
```

同样保存依赖、版本、日志、系统/SDK 版本和 SHA-256。现有 2026-08-05 DMS 库可以先作为候选，但要确认设备实际加载的就是该哈希。

## 8. 文件清单格式

补齐文件后，为每个平台保存一份清单，至少包含：

| 字段 | 示例含义 |
|---|---|
| `platform` | `hi3519dv500`、`rv1126b` 或 `x86_64` |
| `product_version` | 产品发布版本 |
| `source_commit` | DMS 源码完整 commit |
| `algo_base_commit` | 引入后填写 |
| `sdk_commit` | SDK 或工具链版本 |
| `build_id` | 构建系统生成的唯一标识 |
| `dirty` | 构建时是否有未提交修改；必须为 false 才能发布 |
| `path` | 设备实际加载路径 |
| `sha256` | 文件内容哈希 |
| `elf_build_id` | ELF 文件填写 |
| `model_input` / `model_output` | 模型输入输出定义 |
| `converter` | 模型转换工具及参数 |
| `config_owner` | 配置维护责任人 |

清单由构建过程自动产生，发布包校验脚本逐项检查。安装根目录以后可以统一，但清单必须记录逻辑文件、最终安装路径和哈希三者的对应关系。

## 9. 当前状态

| 项目 | Hi3519DV500 | RV1126B |
|---|---|---|
| 固定源码 | 已完成 | 已完成 |
| 固定 SDK/子模块 | Hi SDK commit 仍需正式列入发布清单 | 已完成 |
| 公开头源码基线 | 已完成 | 已完成，且两端结构有 ABI 差异 |
| 可追溯运行库 | 未完成；现有库仅供参考 | DMS 主库已找到并能绑定到固定代码树 |
| 完整动态依赖 | 未完成 | 已列直接依赖，依赖文件哈希未完成 |
| 配置源码基线 | 已完成 | 已完成 |
| 设备实际配置 | 未完成 | 未完成 |
| 模型文件和哈希 | 未完成 | 未完成 |
| 可复现运行样本 | 未完成 | 未完成 |

当前可以据此设计制品清单、配置解析和平台接口，但不能把模型精度、最终回调行为和性能基线判定为已经完成。
