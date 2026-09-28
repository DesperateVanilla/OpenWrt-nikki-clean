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
    install)
        printf '%s\n' "$*" >> "$OPKG_LOG"
        [ "${OPKG_FAIL:-0}" = 0 ]
        ;;
    list-installed)
        [ "${2:-}" = luci-i18n-base-ru ] && printf '%s\n' 'luci-i18n-base-ru - 1'
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
export WGET_LOG="$tmp/wget.log"

NIKKI_ARCHIVE_FILE="$tmp/aarch64_generic.tar.gz" sh "$repo/install.sh" > "$tmp/output"
grep -q 'Nikki installed for aarch64_generic' "$tmp/output"
grep -q 'mihomo-meta_1_aarch64_generic.ipk' "$OPKG_LOG"
grep -q 'luci-i18n-nikki-ru_1_all.ipk' "$OPKG_LOG"
[ ! -e "$WGET_LOG" ]

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
