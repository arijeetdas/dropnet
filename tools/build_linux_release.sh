#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.dropnet"
APP_NAME="DropNet"
BINARY_NAME="dropnet"
ICON_SOURCE="assets/icon/app_icon.png"
DEB_STAGING_DIR="deb_pkg"
DEB_OUTPUT_DIR="deb_build"
APPDIR="AppDir"
APPIMAGE_OUTPUT_DIR="."
APPIMAGETOOL="tools/appimagetool-x86_64.AppImage"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

version_line="$(grep -E '^version:[[:space:]]*' pubspec.yaml | head -n 1 || true)"
[[ -n "$version_line" ]] || fail "Could not read version from pubspec.yaml"
VERSION="$(printf '%s\n' "$version_line" | sed -E 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/')"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([~-][A-Za-z0-9.+-]+)?$ ]] || fail "Invalid pubspec version: $VERSION"

DEB_NAME="${APP_NAME}-v${VERSION}-linux-amd64.deb"
APPIMAGE_NAME="${APP_NAME}-v${VERSION}-x86_64.AppImage"
DEB_PATH="${DEB_OUTPUT_DIR}/${DEB_NAME}"
APPIMAGE_PATH="${APPIMAGE_OUTPUT_DIR}/${APPIMAGE_NAME}"
BUILD_BUNDLE="build/linux/x64/release/bundle"

require_command flutter
require_command dpkg-deb
require_command sed
require_command grep
require_command find
require_command du
require_command install
require_command chmod
require_command mktemp
require_command timeout

[[ -f "$ICON_SOURCE" ]] || fail "Missing Linux icon: $ICON_SOURCE"
[[ -f "$APPIMAGETOOL" ]] || fail "Missing appimagetool: $APPIMAGETOOL"

write_desktop_file() {
  local path="$1"
  cat >"$path" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=${BINARY_NAME}
Icon=${APP_ID}
Categories=Network;Utility;
StartupNotify=true
StartupWMClass=${APP_ID}
Terminal=false
EOF
}

format_size() {
  if [[ -e "$1" ]]; then
    du -h "$1" | awk '{print $1}'
  else
    printf '-'
  fi
}

print_status() {
  local artifact="$1"
  local status="$2"
  local path="$3"
  printf '| %s | %s | %s | %s |\n' "$artifact" "$status" "$(format_size "$path")" "$path"
}

echo "==> Building ${APP_NAME} ${VERSION} for Linux"
flutter clean
rm -rf build/linux
rm -rf linux/flutter/ephemeral
flutter pub get
flutter build linux --release

[[ -x "$BUILD_BUNDLE/$BINARY_NAME" ]] || fail "Missing built executable: $BUILD_BUNDLE/$BINARY_NAME"
[[ -d "$BUILD_BUNDLE/data" ]] || fail "Missing Flutter data directory: $BUILD_BUNDLE/data"
[[ -d "$BUILD_BUNDLE/lib" ]] || fail "Missing Flutter lib directory: $BUILD_BUNDLE/lib"

echo "==> Rebuilding Debian staging directory"
rm -rf "$DEB_STAGING_DIR"
install -d "$DEB_STAGING_DIR/DEBIAN"
install -d "$DEB_STAGING_DIR/usr/bin"
install -d "$DEB_STAGING_DIR/usr/share/${BINARY_NAME}"
install -d "$DEB_STAGING_DIR/usr/share/applications"
install -d "$DEB_STAGING_DIR/usr/share/icons/hicolor/256x256/apps"

cp -a "$BUILD_BUNDLE/." "$DEB_STAGING_DIR/usr/share/${BINARY_NAME}/"
cat >"$DEB_STAGING_DIR/usr/bin/${BINARY_NAME}" <<EOF
#!/usr/bin/env sh
exec /usr/share/${BINARY_NAME}/${BINARY_NAME} "\$@"
EOF
chmod 0755 "$DEB_STAGING_DIR/usr/bin/${BINARY_NAME}"

write_desktop_file "$DEB_STAGING_DIR/usr/share/applications/${APP_ID}.desktop"
install -m 0644 "$ICON_SOURCE" "$DEB_STAGING_DIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"

installed_size="$(du -sk "$DEB_STAGING_DIR/usr" | awk '{print $1}')"
cat >"$DEB_STAGING_DIR/DEBIAN/control" <<EOF
Package: ${BINARY_NAME}
Version: ${VERSION}
Section: net
Priority: optional
Architecture: amd64
Maintainer: Arijeet Das
Installed-Size: ${installed_size}
Depends: libgtk-3-0, libglib2.0-0, libstdc++6, libc6
Description: Cross-platform file sharing application
 DropNet provides local cross-platform file sharing from a Flutter desktop app.
EOF

find "$DEB_STAGING_DIR" -type d -exec chmod 0755 {} +
find "$DEB_STAGING_DIR" -type f -not -path '*/DEBIAN/*' -exec chmod 0644 {} +
chmod 0755 "$DEB_STAGING_DIR/usr/bin/${BINARY_NAME}" "$DEB_STAGING_DIR/usr/share/${BINARY_NAME}/${BINARY_NAME}"

mkdir -p "$DEB_OUTPUT_DIR"
rm -f "$DEB_OUTPUT_DIR"/DropNet-v*-linux-amd64.deb "$DEB_OUTPUT_DIR"/DropNet-v*-amd64.deb
dpkg-deb --build "$DEB_STAGING_DIR" "$DEB_PATH"
dpkg-deb --info "$DEB_PATH" >/dev/null
deb_contents="$(mktemp)"
dpkg-deb --contents "$DEB_PATH" >"$deb_contents"
grep -q "usr/share/applications/${APP_ID}.desktop" "$deb_contents"
grep -q "usr/share/icons/hicolor/256x256/apps/${APP_ID}.png" "$deb_contents"
rm -f "$deb_contents"

echo "==> Rebuilding AppImage AppDir"
rm -rf "$APPDIR"
install -d "$APPDIR/usr/bundle"
cp -a "$BUILD_BUNDLE/." "$APPDIR/usr/bundle/"
write_desktop_file "$APPDIR/${APP_ID}.desktop"
install -m 0644 "$ICON_SOURCE" "$APPDIR/${APP_ID}.png"
install -m 0644 "$ICON_SOURCE" "$APPDIR/.DirIcon"
cat >"$APPDIR/AppRun" <<EOF
#!/usr/bin/env sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
export APPDIR="\$HERE"
exec "\$HERE/usr/bundle/${BINARY_NAME}" "\$@"
EOF
chmod 0755 "$APPDIR/AppRun" "$APPDIR/usr/bundle/${BINARY_NAME}"

[[ -x "$APPDIR/usr/bundle/$BINARY_NAME" ]] || fail "Missing AppDir executable"
[[ -d "$APPDIR/usr/bundle/data" ]] || fail "Missing AppDir Flutter data directory"
[[ -d "$APPDIR/usr/bundle/lib" ]] || fail "Missing AppDir Flutter lib directory"
grep -q '^Name=DropNet$' "$APPDIR/${APP_ID}.desktop"
grep -q "^Icon=${APP_ID}$" "$APPDIR/${APP_ID}.desktop"
grep -q "^StartupWMClass=${APP_ID}$" "$APPDIR/${APP_ID}.desktop"

chmod 0755 "$APPIMAGETOOL"
rm -f ./DropNet-v*-x86_64.AppImage
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$APPIMAGE_PATH"
[[ -x "$APPIMAGE_PATH" ]] || chmod 0755 "$APPIMAGE_PATH"

tmp_extract="$(mktemp -d)"
(
  cd "$tmp_extract"
  "$ROOT_DIR/${APPIMAGE_PATH#./}" --appimage-extract >/dev/null
  [[ -x "squashfs-root/usr/bundle/$BINARY_NAME" ]]
  [[ -d "squashfs-root/usr/bundle/data" ]]
  [[ -d "squashfs-root/usr/bundle/lib" ]]
  [[ -f "squashfs-root/${APP_ID}.desktop" ]]
  [[ -f "squashfs-root/${APP_ID}.png" ]]
)
rm -rf "$tmp_extract"

echo
echo "==> Validation"
timeout 5s "$BUILD_BUNDLE/$BINARY_NAME" --help >/dev/null 2>&1 || true
timeout 5s "$APPDIR/AppRun" --help >/dev/null 2>&1 || true
printf '| Artifact | Status | Size | Output Path |\n'
printf '| -------- | ------ | ---- | ----------- |\n'
print_status "$DEB_NAME" "built" "$DEB_PATH"
print_status "$APPIMAGE_NAME" "built" "$APPIMAGE_PATH"

cat <<EOF

Desktop identity:
  Application ID: ${APP_ID}
  Desktop file: ${APP_ID}.desktop
  Icon name: ${APP_ID}
  StartupWMClass: ${APP_ID}

X11 diagnostic:
  xprop WM_CLASS

Wayland diagnostic:
  WAYLAND_DEBUG=1 ${APPDIR}/AppRun 2>&1 | grep 'set_app_id'
  WAYLAND_DEBUG=1 ./${APPIMAGE_NAME} 2>&1 | grep 'set_app_id'
EOF
