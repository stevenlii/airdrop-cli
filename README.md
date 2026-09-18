# airdrop-cli

Launch macOS AirDrop from the terminal with a single command and send files:

```bash
airdrop file1 [file2 ...]
```

`airdrop` is a small, self-contained tool. It compiles a minimal `NSApplication`
(`AirDropHelper.app`) that hosts the AirDrop share sheet via
`NSSharingService(.sendViaAirDrop)`. A thin shell wrapper validates the files you
pass and launches the helper.

> **macOS only.** This tool uses Apple's `AppKit` / `NSSharingService` frameworks
> and the AirDrop share sheet, so it only works on macOS.

## Requirements / tested environment

Built and verified on:

| Component | Version |
|-----------|---------|
| macOS | 14.7.2 (Build 23H311) |
| Architecture | x86_64 |
| Swift (`swiftc`) | Apple Swift 6.0.3 (swiftlang-6.0.3.1.10, clang-1600.0.30.1) |
| xcode-select | 2408 |
| Command Line Tools (CLT) | 16.2.0.0.1.1733547573 |
| Available SDKs | MacOSX13 … MacOSX15.2 |

It needs the Command Line Tools (for `swiftc`). No Xcode app install required.

## Install

```bash
# 1. Install the compiler (a fresh Mac usually doesn't have it)
xcode-select --install

# 2. Run the build script (no sudo needed; just point bash at the file)
bash /path/to/build-airdrop.sh
```

After it finishes, `airdrop` is available from any directory.

## Usage

```bash
airdrop file1 file2        # open the AirDrop sheet and send multiple files
airdrop -n file1           # print the command it would run, without opening the sheet (dry-run)
```

What gets created (all in your home directory or user-writable locations —
no system directories touched, no sudo):

| Artifact | Path | Purpose |
|----------|------|---------|
| Swift helper app | `~/airdrop_build/AirDropHelper.app` | actually hosts the AirDrop transfer |
| Command | `/usr/local/bin/airdrop` | the `airdrop` command itself |

## Known issue: Command Line Tools 16.2 is broken

The CLT 16.2 package shipped with newer macOS has an intrinsic defect that makes
`swiftc` fail to compile, and **reinstalling CLT does not fix it**:

1. Compiler version vs. SDK build version mismatch
   `error: failed to build module 'CoreFoundation'; this SDK is not supported by the compiler`
2. `usr/include/swift/module.modulemap` and `bridging.modulemap` both define `SwiftBridging`
   `error: redefinition of module 'SwiftBridging'`

This script handles it automatically: it first tries the system `swiftc`; if that
fails, it copies the toolchain + SDK into your home directory
(`~/clt_patched`, `~/macosx_patched.sdk`), rewrites the SDK's recorded compiler
version to match the current `swiftc`, removes the duplicate module definition,
and compiles with the patched toolchain. No sudo, and no changes to the
`/Library` system files.

> If you've manually reinstalled CLT and it still errors, that's the 16.2 package
> defect itself — don't keep reinstalling. Just run this script.

## Cleanup (optional)

The home-directory patched copies are only used during one build; the compiled
app does not depend on them at runtime. To reclaim space:

```bash
rm -rf ~/clt_patched ~/macosx_patched.sdk
```

If you later upgrade macOS across a major version and need to recompile, just run
`bash build-airdrop.sh` again — it will regenerate them automatically.

## License

Released under the [MIT License](LICENSE).
