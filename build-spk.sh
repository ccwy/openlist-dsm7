#!/bin/bash
#
# build-spk.sh — Build Synology SPK package for OpenList
#
# Usage: ./build-spk.sh <version> <arch> <binary_path>
#   version:      OpenList version (e.g. 4.2.9)
#   arch:         Target architecture: x64, arm64
#   binary_path:  Path to the extracted openlist binary
#
set -euo pipefail

VERSION="${1:?Usage: build-spk.sh <version> <arch> <binary_path>}"
ARCH="${2:?arch must be x64 or arm64}"
BINARY_PATH="${3:?binary_path is required}"

PKG_NAME="openlist"
SPK_FILE="${PKG_NAME}_${ARCH}_${VERSION}.spk"

# ── DSM arch platform codes per architecture ─────────────────────────
case "$ARCH" in
  x64)
    DSM_ARCH="apollolake avoton braswell broadwell broadwellnk broadwellnkv2 broadwellntbap bromolow cedarview denverton dockerx64 epyc7002 geminilake grantley kvmx64 purley r1000 v1000 x86 x86_64"
    ;;
  arm64)
    DSM_ARCH="armada37xx armada7040 armada8080 rtd1296 rtd1619 rtd1619b"
    ;;
  *)
    echo "ERROR: Unsupported arch: $ARCH (use x64 or arm64)"
    exit 1
    ;;
esac

WORK_DIR="$(mktemp -d)"
STAGING_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR $STAGING_DIR" EXIT

echo "=== Building OpenList SPK ==="
echo "  Version: $VERSION"
echo "  Arch:    $ARCH"
echo "  Binary:  $BINARY_PATH"

# ── 1. Prepare staging (package.tgz contents) ───────────────────────
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/etc" "$STAGING_DIR/ui/images"

# Binary
cp "$BINARY_PATH" "$STAGING_DIR/bin/openlist"
chmod 755 "$STAGING_DIR/bin/openlist"

# Config
cp etc/config.json "$STAGING_DIR/etc/config.json"
chmod 644 "$STAGING_DIR/etc/config.json"

# UI config + images
cp ui/config "$STAGING_DIR/ui/config"
chmod 755 "$STAGING_DIR/ui/config"
cp ui/images/*.png "$STAGING_DIR/ui/images/"
chmod 755 "$STAGING_DIR/ui/images/"*.png

# ── 2. Create package.tgz ───────────────────────────────────────────
mkdir -p "$WORK_DIR/scripts" "$WORK_DIR/conf" "$WORK_DIR/WIZARD_UIFILES"

# package.tgz (files at root level, no ./ prefix)
cd "$STAGING_DIR"
tar cpf - --sort=name --owner=root --group=root bin etc ui | gzip -n > "$WORK_DIR/package.tgz"
cd - > /dev/null

CHECKSUM=$(md5sum "$WORK_DIR/package.tgz" | cut -d' ' -f1)
echo "  package.tgz MD5: $CHECKSUM"

# ── 3. Create INFO ──────────────────────────────────────────────────
cat > "$WORK_DIR/INFO" << EOF
package="${PKG_NAME}"
version="${VERSION}"
description="OpenList 是一款支持多存储的文件列表程序，由社区驱动的 AList 分支，开箱即用。"
displayname="OpenList"
maintainer="OpenList Team"
maintainer_url="https://github.com/openlistteam/openlist"
distributor="OpenList Team"
distributor_url="https://github.com/openlistteam/openlist"
helpurl="https://github.com/openlistteam/openlist"
arch="${DSM_ARCH}"
os_min_ver="7.2-64570"
dsmappname="SYNO.SDS.OpenList.Application"
dsmuidir="ui"
checksum="${CHECKSUM}"
EOF
chmod 755 "$WORK_DIR/INFO"

# ── 4. Copy scripts, conf, wizard, icons ────────────────────────────
cp scripts/* "$WORK_DIR/scripts/"
chmod 755 "$WORK_DIR/scripts/"*

cp conf/privilege "$WORK_DIR/conf/privilege"
cp conf/resource "$WORK_DIR/conf/resource"
chmod 755 "$WORK_DIR/conf/"*

cp WIZARD_UIFILES/uninstall_uifile "$WORK_DIR/WIZARD_UIFILES/uninstall_uifile"
chmod 755 "$WORK_DIR/WIZARD_UIFILES/uninstall_uifile"

cp icons/PACKAGE_ICON.PNG "$WORK_DIR/PACKAGE_ICON.PNG"
cp icons/PACKAGE_ICON_256.PNG "$WORK_DIR/PACKAGE_ICON_256.PNG"
chmod 755 "$WORK_DIR/PACKAGE_ICON.PNG" "$WORK_DIR/PACKAGE_ICON_256.PNG"

# ── 5. Assemble SPK ─────────────────────────────────────────────────
cd "$WORK_DIR"
tar cpf "$OLDPWD/$SPK_FILE" --sort=name --owner=root --group=root \
  package.tgz INFO scripts WIZARD_UIFILES conf PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG
cd - > /dev/null

echo ""
echo "=== Done ==="
echo "  Output: $SPK_FILE ($(du -h "$SPK_FILE" | cut -f1))"

# Verify checksum
INFO_CS=$(grep '^checksum=' "$WORK_DIR/INFO" | cut -d'"' -f2)
ACT_CS=$(md5sum "$WORK_DIR/package.tgz" | cut -d' ' -f1)
if [ "$INFO_CS" = "$ACT_CS" ]; then
  echo "  Checksum: VALID ✓"
else
  echo "  Checksum: MISMATCH ✗"
  exit 1
fi
