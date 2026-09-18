# airdrop-cli

在终端里用一行命令唤起 macOS AirDrop 发送文件：

```bash
airdrop 文件1 [文件2 ...]
```

`airdrop` 是一个自包含的小工具：它编译出一个极简的 `NSApplication`（`AirDropHelper.app`），
通过 `NSSharingService(.sendViaAirDrop)` 托管 AirDrop 共享面板；命令行包装脚本负责校验文件并拉起它。

> **仅限 macOS。** 本工具依赖 Apple 的 `AppKit` / `NSSharingService` 框架与 AirDrop 共享面板，
> 因此只能在 macOS 上使用。

## 环境与测试版本

在下列环境构建并验证通过：

| 组件 | 版本 |
|------|------|
| macOS | 14.7.2（Build 23H311） |
| 架构 | x86_64 |
| Swift（`swiftc`） | Apple Swift 6.0.3（swiftlang-6.0.3.1.10, clang-1600.0.30.1） |
| xcode-select | 2408 |
| Command Line Tools（CLT） | 16.2.0.0.1.1733547573 |
| 可用 SDK | MacOSX13 … MacOSX15.2 |

仅需要 Command Line Tools（提供 `swiftc`），无需安装完整的 Xcode。

## 安装

```bash
# 1. 装编译工具（新电脑一般没有）
xcode-select --install

# 2. 跑构建脚本（位置无所谓，直接 bash 路径就行，无需 sudo）
bash /path/to/build-airdrop.sh
```

跑完即可在任意目录使用 `airdrop`。

## 用法

```bash
airdrop 文件1 文件2        # 弹出 AirDrop 面板发送多个文件
airdrop -n 文件1          # 只打印将执行的命令，不弹面板（dry-run）
```

生成的东西（均在用户目录 / 用户可写位置，不碰系统目录、不需要 sudo）：

| 文件 | 路径 | 作用 |
|------|------|------|
| Swift 助手 app | `~/airdrop_build/AirDropHelper.app` | 实际托管 AirDrop 传输 |
| 命令 | `/usr/local/bin/airdrop` | `airdrop` 命令本体 |

## 已知坑：Command Line Tools 16.2 自带缺陷

新版 macOS 自带的 CLT 16.2 包存在固有缺陷，会导致 swift 编译直接报错、且重装 CLT 也修不好：

1. 编译器版本与 SDK 构建版本错配
   `error: failed to build module 'CoreFoundation'; this SDK is not supported by the compiler`
2. `usr/include/swift/module.modulemap` 与 `bridging.modulemap` 重复定义 `SwiftBridging`
   `error: redefinition of module 'SwiftBridging'`

本脚本已自动处理：先试系统 `swiftc`；若失败，自动把 toolchain + SDK 拷贝到家目录
（`~/clt_patched`、`~/macosx_patched.sdk`），就地把 SDK 记录的编译器版本号对齐到当前 swiftc、
并去掉重复模块定义，再用补丁版 toolchain 编译。全程不需要 sudo，也不改动 `/Library` 下的系统文件。

> 如果你手动重装过 CLT 仍报错，属于上述 16.2 包本身的缺陷，不要反复重装 —— 直接跑本脚本即可。

## 清理（可选）

家目录补丁分支只用一次编译，app 运行时不依赖它们。要释放空间可删：

```bash
rm -rf ~/clt_patched ~/macosx_patched.sdk
```

之后若换了 macOS 大版本需要重编译，再跑一次 `bash build-airdrop.sh` 会自动重新生成。

## 协议

基于 [MIT License](LICENSE) 发布。
