#!/bin/bash
# build-airdrop.sh — 自包含构建脚本, 一键重建 airdrop 命令 (无需 sudo)
#
# 用法:
#   bash build-airdrop.sh
#   airdrop 文件1 [文件2 ...]
#
# 设计要点:
#   * 优先用系统 swiftc 直接编译。
#   * 若系统 Command Line Tools 存在已知缺陷 —— 编译器/SDK 版本错配
#     (Apple CLT 16.2: 编译器 swiftlang-6.0.3.1.10 vs SDK 6.0.3.1.5)
#     或 usr/include/swift/module.modulemap 重复定义 SwiftBridging ——
#     则自动把 toolchain + SDK 拷贝到家目录 (~/clt_patched, ~/macosx_patched.sdk),
#     就地打补丁后用补丁版 toolchain 编译。全程不需要 sudo。
#   * 生成的文件:
#       ~/airdrop_build/AirDropHelper.app   (Swift 助手 app)
#       /usr/local/bin/airdrop               (命令; /usr/local/bin 普通用户可写)
#
# 换电脑时, 只需把这一个脚本文件拷过去, 装好 Xcode 命令行工具后运行:
#     xcode-select --install      # 若还没有 swiftc
#     bash build-airdrop.sh
set -uo pipefail

APP="$HOME/airdrop_build/AirDropHelper.app"
BIN="$APP/Contents/MacOS/AirDropHelper"
PLIST="$APP/Contents/Info.plist"
WRAPPER_DST="/usr/local/bin/airdrop"
TMP_SWIFT="$(mktemp /tmp/airdrophelper.XXXXXX.swift)"

cleanup() { rm -f "$TMP_SWIFT"; }
trap cleanup EXIT

echo "==> 检查工具链 (swiftc)"
command -v swiftc >/dev/null 2>&1 || {
    echo "错误: 未找到 swiftc。请先安装 Xcode 命令行工具:" >&2
    echo "    xcode-select --install" >&2
    exit 1
}

# 1. 写 Swift 源码 (极简 NSApplication, 托管 AirDrop 共享服务)
cat > "$TMP_SWIFT" <<'SWIFT_EOF'
import AppKit
import Foundation

/// 接收 NSSharingService 的回调, 在用户发送完成或取消时退出整个 App。
final class SharingDelegate: NSObject, NSSharingServiceDelegate {
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        NSApplication.shared.terminate(nil)
    }

    func sharingService(_ sharingService: NSSharingService, didNotShareItems items: [Any]) {
        NSApplication.shared.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sharingDelegate = SharingDelegate()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // CommandLine.arguments 的第一项是程序路径, 其余是待发送的文件
        let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }

        guard !urls.isEmpty else {
            let msg = "用法: AirDropHelper file1 [file2 ...]\n"
            FileHandle.standardError.write(Data(msg.utf8))
            NSApplication.shared.terminate(nil)
            return
        }

        guard let svc = NSSharingService(named: .sendViaAirDrop),
              svc.canPerform(withItems: urls) else {
            let msg = "AirDrop 无法处理所提供的文件, 请确认文件存在且系统支持 AirDrop\n"
            FileHandle.standardError.write(Data(msg.utf8))
            NSApplication.shared.terminate(nil)
            return
        }

        svc.delegate = sharingDelegate
        svc.perform(withItems: urls)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
SWIFT_EOF

# 2. 探测工具链是否健康
toolchain_ok() {
    swiftc -e 'import AppKit; print("ok")' >/dev/null 2>&1
}

if toolchain_ok; then
    echo "==> 系统工具链正常, 直接编译"
    SWIFT_BIN="$(command -v swiftc)"
    SDK_FLAG=""
else
    echo "==> 检测到工具链缺陷, 自动把 toolchain+SDK 拷贝到家目录并打补丁 (无需 sudo)"
    PATCHED_CLT="$HOME/clt_patched"
    PATCHED_SDK="$HOME/macosx_patched.sdk"

    if [ ! -x "$PATCHED_CLT/usr/bin/swiftc" ]; then
        echo "    复制 toolchain -> $PATCHED_CLT"
        rm -rf "$PATCHED_CLT"
        cp -R "$(xcode-select -p)" "$PATCHED_CLT"
        rm -rf "$PATCHED_CLT/SDKs"
        # 去掉与 bridging.modulemap 重复的 SwiftBridging 定义
        MM="$PATCHED_CLT/usr/include/swift/module.modulemap"
        if [ -f "$MM" ] && grep -q "module SwiftBridging" "$MM"; then
            cp "$MM" "$MM.bak" 2>/dev/null || true
            perl -0pi -e 's/module SwiftBridging \{.*?\n\}\n//s' "$MM"
        fi
    fi

    if [ ! -d "$PATCHED_SDK" ]; then
        echo "    复制 SDK -> $PATCHED_SDK"
        SRC=$(readlink -f "$(xcrun --show-sdk-path)")
        cp -R "$SRC" "$PATCHED_SDK"
        # 把 SDK 记录的编译器版本号对齐到当前 swiftc (消除 "SDK not supported" 报错)
        COMPVER=$(swiftc --version | grep -oE 'swiftlang-[0-9.]+' | head -1)
        SDKVER=$(grep -rhoE 'swiftlang-[0-9.]+' "$PATCHED_SDK/usr/lib/swift/CoreFoundation.swiftmodule/x86_64-apple-macos.swiftinterface" 2>/dev/null | head -1)
        if [ -n "$SDKVER" ] && [ "$SDKVER" != "$COMPVER" ]; then
            echo "    SDK 版本 $SDKVER -> $COMPVER"
            find "$PATCHED_SDK" -name '*.swiftinterface' -print0 | xargs -0 sed -i '' "s/${SDKVER}/${COMPVER}/g"
        fi
    fi

    SWIFT_BIN="$PATCHED_CLT/usr/bin/swiftc"
    SDK_FLAG="-sdk $PATCHED_SDK"
fi

# 3. 创建 app bundle 目录结构 + Info.plist
echo "==> 创建 bundle: $APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$PLIST" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AirDropHelper</string>
    <key>CFBundleDisplayName</key>
    <string>AirDropHelper</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.airdrophelper</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AirDropHelper</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST_EOF

# 4. 编译
echo "==> 编译 Swift ($SWIFT_BIN $SDK_FLAG)"
"$SWIFT_BIN" $SDK_FLAG -O "$TMP_SWIFT" -o "$BIN" || {
    echo "错误: 编译失败。若系统 Command Line Tools 损坏, 可尝试: sudo xcode-select --install 重装, 或安装完整 Xcode 后 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
}

# 5. ad-hoc 签名 + 去除 quarantine
echo "==> 代码签名 / 去 quarantine"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# 6. 生成命令行包装脚本并安装到 /usr/local/bin (普通用户可写, 无需 sudo)
cat > "$WRAPPER_DST" <<'WRAPPER_EOF'
#!/bin/bash
# airdrop — 通过 AirDrop 分享一个或多个文件
# 用法: airdrop [-n|--dry-run] file1 [file2 ...]
set -euo pipefail

DRY_RUN=0
if [ "$#" -eq 0 ]; then
    echo "用法: $0 [-n|--dry-run] file1 [file2 file3 ...]" >&2
    echo "  -n, --dry-run  只打印将执行的命令, 不弹出 AirDrop 面板" >&2
    echo "  至少提供一个存在的文件路径" >&2
    exit 1
fi

args=()
for a in "$@"; do
    case "$a" in
        -n|--dry-run) DRY_RUN=1 ;;
        *) args+=("$a") ;;
    esac
done
if [ ${#args[@]} -eq 0 ]; then set --; else set -- "${args[@]}"; fi

if [ "$#" -eq 0 ]; then
    echo "错误: 未提供任何文件" >&2
    exit 1
fi

paths=()
for f in "$@"; do
    f="${f/#\~/$HOME}"
    case "$f" in
        /*) abs="$f" ;;
        *)  abs="$PWD/$f" ;;
    esac
    if [ ! -e "$abs" ]; then
        echo "错误: 文件不存在 -> $f" >&2
        exit 1
    fi
    if [ ! -f "$abs" ]; then
        echo "错误: 不是普通文件(可能是目录) -> $f" >&2
        exit 1
    fi
    paths+=("$abs")
done

APP="$HOME/airdrop_build/AirDropHelper.app"
BIN="$APP/Contents/MacOS/AirDropHelper"

if [ ! -x "$BIN" ]; then
    echo "错误: AirDrop 助手程序不存在或不可执行 -> $BIN" >&2
    echo "请确认 $APP 已正确安装" >&2
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "$BIN" "${paths[@]}"
    exit 0
fi

# 直接执行助手程序: 它会以真正的 NSApplication 托管 AirDrop 共享服务,
# 弹出选择面板并在发送/取消后自行退出; exec 让脚本等待其结束并透传退出码。
exec "$BIN" "${paths[@]}"
WRAPPER_EOF
chmod +x "$WRAPPER_DST"
echo "==> 已安装命令: $WRAPPER_DST"

echo
echo "完成。用法:  airdrop 文件1 [文件2 ...]"
echo "首次运行若被 Gatekeeper 拦截, 去 系统设置→隐私与安全性 点\"仍要打开\"即可。"
echo "(若使用了家目录补丁版 toolchain, 重新构建可删 ~/clt_patched 与 ~/macosx_patched.sdk 释放空间, app 运行不依赖它们)"
