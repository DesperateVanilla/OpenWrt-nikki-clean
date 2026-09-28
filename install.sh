#!/bin/sh

# Install the supported OpenWrt 24.10 builds from this fork's GitHub release.
set -eu

die() {
    printf 'nikki installer: %s\n' "$*" >&2
    exit 1
}

release_file="${NIKKI_OPENWRT_RELEASE_FILE:-/etc/openwrt_release}"
[ -r "$release_file" ] || die "cannot read $release_file"
. "$release_file"

case "${DISTRIB_RELEASE:-}" in
    *24.10*) ;;
    *) die "unsupported OpenWrt release: ${DISTRIB_RELEASE:-unknown}; expected 24.10" ;;
esac
case "${DISTRIB_ARCH:-}" in
    aarch64_generic|aarch64_cortex-a53) arch="$DISTRIB_ARCH" ;;
    *) die "unsupported architecture: ${DISTRIB_ARCH:-unknown}" ;;
esac
command -v fw4 >/dev/null 2>&1 || die 'firewall4 (fw4) is required'
command -v opkg >/dev/null 2>&1 || die 'opkg is required; APK builds are not supported'

repo="${NIKKI_RELEASE_REPO:-DesperateVanilla/OpenWrt-nikki-clean}"
tag="${NIKKI_RELEASE_TAG:-latest}"
case "$repo" in
    */*) ;;
    *) die 'NIKKI_RELEASE_REPO must be owner/repository' ;;
esac
case "$repo" in
    /*|*/|*/*/*|*[!A-Za-z0-9._/-]*) die 'invalid NIKKI_RELEASE_REPO' ;;
esac
case "$tag" in
    ''|*[!A-Za-z0-9._-]*) die 'invalid NIKKI_RELEASE_TAG' ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/nikki-install.XXXXXX")" || die 'cannot create temporary directory'
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

asset="nikki_${arch}-openwrt-24.10.tar.gz"
if [ -n "${NIKKI_ARCHIVE_FILE:-}" ]; then
    [ -r "$NIKKI_ARCHIVE_FILE" ] || die "cannot read archive: $NIKKI_ARCHIVE_FILE"
    archive="$NIKKI_ARCHIVE_FILE"
else
    if [ "$tag" = latest ]; then
        url="https://github.com/$repo/releases/latest/download/$asset"
    else
        url="https://github.com/$repo/releases/download/$tag/$asset"
    fi
    archive="$work/$asset"
    printf 'Downloading %s\n' "$url"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$archive" "$url" || die 'download failed'
    elif command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 -o "$archive" "$url" || die 'download failed'
    else
        die 'wget or curl is required'
    fi
fi

# The release archive contains only root-level files. Reject path traversal
# before extraction, including for user-supplied offline archives.
tar -tzf "$archive" > "$work/members" || die 'archive is not a readable tar.gz'
while IFS= read -r member; do
    case "$member" in
        ./) ;;
        ./*)
            name="${member#./}"
            case "$name" in ''|*/*|..) die "unsafe archive member: $member" ;; esac
            ;;
        *) die "unsafe archive member: $member" ;;
    esac
done < "$work/members"
tar -xzf "$archive" -C "$work" || die 'archive extraction failed'
[ -z "$(find "$work" -type l -print)" ] || die 'archive contains a symbolic link'

pick_package() {
    package_label="$2"
    set -- "$work"/"$1"_*.ipk
    [ "$#" -eq 1 ] && [ -f "$1" ] || die "expected exactly one $package_label package in archive"
    printf '%s\n' "$1"
}

mihomo="$(pick_package mihomo-meta mihomo-meta)"
nikki="$(pick_package nikki nikki)"
luci="$(pick_package luci-app-nikki luci-app-nikki)"
case "$mihomo" in *_"$arch".ipk) ;; *) die 'mihomo-meta architecture mismatch' ;; esac
case "$nikki" in *_"$arch".ipk) ;; *) die 'nikki architecture mismatch' ;; esac
case "$luci" in *_all.ipk) ;; *) die 'LuCI package architecture mismatch' ;; esac

opkg install "$mihomo" "$nikki" "$luci" || die 'package installation failed'

for translation in "$work"/luci-i18n-nikki-*.ipk; do
    [ -f "$translation" ] || continue
    lang="${translation##*/}"
    lang="${lang#luci-i18n-nikki-}"
    lang="${lang%%_*}"
    if opkg list-installed "luci-i18n-base-$lang" | grep -q "^luci-i18n-base-$lang "; then
        opkg install "$translation" || die "failed to install translation: $lang"
    fi
done

printf 'Nikki installed for %s (OpenWrt 24.10).\n' "$arch"
