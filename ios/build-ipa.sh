#!/bin/bash
# 在 macOS 上执行，把本工程打成 iPhone 可安装的 .ipa
#
# 用法：
#   ./build-ipa.sh                  # 出免签名 ipa，给 Sideloadly / AltStore / 爱思助手自签用
#   ./build-ipa.sh --signed 1234567890 # 有付费开发者账号时，用该 Team ID 归档并导出 ipa
#
# 可选环境变量：
#   BUNDLE_ID   默认 top.rpone.qinlinopen（自签被占用时可改成自己的唯一标识）

set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="${BUNDLE_ID:-top.rpone.qinlinopen}"
CONFIG="Release"
OUT_DIR="build"
IPA_NAME="QinlinOpen.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "[!] 未找到 xcodebuild：请在 macOS 上安装 Xcode（App Store 免费）并执行 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if [[ "${1:-}" == "--signed" ]]; then
  TEAM_ID="${2:?请传入 10 位 Team ID，例如 ./build-ipa.sh --signed 1234567890}"
  echo "[*] 归档（签名归档，需要有该 Team 的证书）"
  xcodebuild -project QinlinOpen.xcodeproj \
    -scheme QinlinOpen \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' \
    -archivePath "$OUT_DIR/QinlinOpen.xcarchive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    archive

  cat > "$OUT_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</key>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

  xcodebuild -exportArchive \
    -archivePath "$OUT_DIR/QinlinOpen.xcarchive" \
    -exportPath "$OUT_DIR/export" \
    -exportOptionsPlist "$OUT_DIR/ExportOptions.plist"

  IPA=$(find "$OUT_DIR/export" -name "*.ipa" | head -n 1)
  cp "$IPA" "$OUT_DIR/$IPA_NAME"
  echo "[+] 已导出：$OUT_DIR/$IPA_NAME"
else
  echo "[*] 无签名编译（给自签工具用）"
  xcodebuild -project QinlinOpen.xcodeproj \
    -scheme QinlinOpen \
    -configuration "$CONFIG" \
    -sdk iphoneos \
    -derivedDataPath "$OUT_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    build

  APP=$(find "$OUT_DIR/DerivedData/Build/Products" -name "QinlinOpen.app" -maxdepth 3 | head -n 1)
  if [[ -z "$APP" ]]; then
    echo "[!] 编译成功但没找到 QinlinOpen.app"
    exit 1
  fi

  rm -rf "$OUT_DIR/Payload" "$OUT_DIR/$IPA_NAME"
  mkdir -p "$OUT_DIR/Payload"
  cp -R "$APP" "$OUT_DIR/Payload/"
  (cd "$OUT_DIR" && zip -qr "$IPA_NAME" Payload)
  echo "[+] 已生成免签名 ipa：$OUT_DIR/$IPA_NAME"
  echo "[i] 下一步：用 Sideloadly（Win/Mac）或 AltStore 载入这个 ipa，登录你自己的 Apple ID 完成签名后安装。"
  echo "    免费 Apple ID 的自签有效期 7 天，到期重新签名安装即可；用付费开发者账号可达 1 年。"
fi
