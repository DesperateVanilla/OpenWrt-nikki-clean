#!/bin/sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/packages" "$tmp/bad-packages"
cat > "$tmp/bin/fw4" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$tmp/bin/opkg" <<'EOF'
#!/bin/sh
case "$1" in
    update)
        printf '%s\n' update >> "$OPKG_LOG"
        if [ "${OPKG_UPDATE_FAIL_ONCE:-0}" = 1 ] && [ ! -e "$OPKG_UPDATE_MARKER" ]; then
            : > "$OPKG_UPDATE_MARKER"
            exit 1
        fi
        [ "${OPKG_UPDATE_FAIL:-0}" = 0 ]
        ;;
    install)
        printf '%s\n' "$*" >> "$OPKG_LOG"
        [ "${OPKG_FAIL:-0}" = 0 ]
        ;;
    list-installed)
        case "${2:-}" in
            yq|kmod-inet-diag)
                [ "${MOCK_MISSING_DEPS:-0}" = 1 ] || printf '%s - 1\n' "$2"
                ;;
            ca-bundle|curl|ip-full|kmod-nft-socket|kmod-nft-tproxy|kmod-tun|kmod-dummy|luci-i18n-base-ru)
                printf '%s - 1\n' "$2"
                ;;
        esac
        ;;
esac
EOF
cat > "$tmp/bin/wget" <<'EOF'
#!/bin/sh
[ "$1" = -O ] || exit 2
printf '%s\n' "$3" > "$WGET_LOG"
cp "$TEST_ARCHIVE" "$2"
EOF
chmod +x "$tmp/bin/fw4" "$tmp/bin/opkg" "$tmp/bin/wget"

make_archive() {
    arch="$1"
    directory="$2"
    : > "$directory/mihomo-meta_1_${arch}.ipk"
    : > "$directory/nikki_1_${arch}.ipk"
    : > "$directory/luci-app-nikki_1_all.ipk"
    : > "$directory/luci-i18n-nikki-ru_1_all.ipk"
    tar -czf "$tmp/$arch.tar.gz" -C "$directory" .
}
make_archive aarch64_generic "$tmp/packages"
make_archive aarch64_cortex-a53 "$tmp/bad-packages"

cat > "$tmp/release" <<'EOF'
DISTRIB_RELEASE='24.10.4'
DISTRIB_ARCH='aarch64_generic'
EOF
export PATH="$tmp/bin:$PATH"
export NIKKI_OPENWRT_RELEASE_FILE="$tmp/release"
export OPKG_LOG="$tmp/opkg.log"
export OPKG_UPDATE_MARKER="$tmp/opkg-update-failed-once"
export WGET_LOG="$tmp/wget.log"

NIKKI_ARCHIVE_FILE="$tmp/aarch64_generic.tar.gz" sh "$repo/install.sh" > "$tmp/output"
grep -q 'Nikki installed for aarch64_generic' "$tmp/output"
grep -q 'mihomo-meta_1_aarch64_generic.ipk' "$OPKG_LOG"
grep -q 'luci-i18n-nikki-ru_1_all.ipk' "$OPKG_LOG"
[ ! -e "$WGET_LOG" ]

: > "$OPKG_LOG"
MOCK_MISSING_DEPS=1 NIKKI_ARCHIVE_FILE="$tmp/aarch64_generic.tar.gz" sh "$repo/install.sh" > "$tmp/output"
[ "$(sed -n '1p' "$OPKG_LOG")" = update ]
[ "$(sed -n '2p' "$OPKG_LOG")" = 'install yq kmod-inet-diag' ]
grep -q 'mihomo-meta_1_aarch64_generic.ipk' "$OPKG_LOG"

: > "$OPKG_LOG"
OPKG_UPDATE_FAIL_ONCE=1 MOCK_MISSING_DEPS=1 NIKKI_ARCHIVE_FILE="$tmp/aarch64_generic.tar.gz" sh "$repo/install.sh" > "$tmp/output" 2>&1
[ "$(sed -n '1p' "$OPKG_LOG")" = update ]
[ "$(sed -n '2p' "$OPKG_LOG")" = update ]
[ "$(sed -n '3p' "$OPKG_LOG")" = 'install yq kmod-inet-diag' ]

if MOCK_MISSING_DEPS=1 OPKG_UPDATE_FAIL=1 NIKKI_ARCHIVE_FILE="$tmp/aarch64_generic.tar.gz" sh "$repo/install.sh" > "$tmp/output" 2>&1; then
    echo 'opkg update failure unexpectedly ignored' >&2
    exit 1
fi
grep -q 'opkg update failed' "$tmp/output"

printf "DISTRIB_RELEASE='24.10.4'\nDISTRIB_ARCH='mips_24kc'\n" > "$tmp/release"
if NIKKI_ARCHIVE_FILE="$tmp/aarch64_generic.tar.gz" sh "$repo/install.sh" > "$tmp/output" 2>&1; then
    echo 'unsupported architecture unexpectedly accepted' >&2
    exit 1
fi
grep -q 'unsupported architecture' "$tmp/output"

printf "DISTRIB_RELEASE='24.10.4'\nDISTRIB_ARCH='aarch64_cortex-a53'\n" > "$tmp/release"
export TEST_ARCHIVE="$tmp/aarch64_cortex-a53.tar.gz"
sh "$repo/install.sh" > "$tmp/output"
grep -q 'https://github.com/DesperateVanilla/OpenWrt-nikki-clean/releases/latest/download/nikki_aarch64_cortex-a53-openwrt-24.10.tar.gz' "$WGET_LOG"
grep -q 'Nikki installed for aarch64_cortex-a53' "$tmp/output"

mkdir -p "$tmp/incomplete"
: > "$tmp/incomplete/nikki_1_aarch64_cortex-a53.ipk"
tar -czf "$tmp/incomplete.tar.gz" -C "$tmp/incomplete" .
if NIKKI_ARCHIVE_FILE="$tmp/incomplete.tar.gz" sh "$repo/install.sh" > "$tmp/output" 2>&1; then
    echo 'incomplete archive unexpectedly accepted' >&2
    exit 1
fi
grep -q 'expected exactly one mihomo-meta package' "$tmp/output" || { cat "$tmp/output" >&2; exit 1; }

mkdir -p "$tmp/symlink"
if ln -s /etc/passwd "$tmp/symlink/mihomo-meta_1_aarch64_cortex-a53.ipk" 2>/dev/null; then
    tar -czf "$tmp/symlink.tar.gz" -C "$tmp/symlink" .
    if NIKKI_ARCHIVE_FILE="$tmp/symlink.tar.gz" sh "$repo/install.sh" > "$tmp/output" 2>&1; then
        echo 'archive symlink unexpectedly accepted' >&2
        exit 1
    fi
    grep -q 'archive contains a symbolic link' "$tmp/output"
fi

if OPKG_FAIL=1 NIKKI_ARCHIVE_FILE="$tmp/aarch64_cortex-a53.tar.gz" sh "$repo/install.sh" > "$tmp/output" 2>&1; then
    echo 'opkg failure unexpectedly ignored' >&2
    exit 1
fi
grep -q 'package installation failed' "$tmp/output"

echo 'installer tests passed'
