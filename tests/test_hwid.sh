#!/bin/sh
set -eu

repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/fw_printenv" <<'EOF'
#!/bin/sh
printf 'ethaddr=%s\n' "$MOCK_MAC"
EOF
chmod +x "$tmp/fw_printenv"
PATH="$tmp:$PATH"
export PATH

. "$repo/nikki/files/scripts/include.sh"

MOCK_MAC='AA:BB:CC:DD:EE:FF'
export MOCK_MAC
actual="$(get_subscription_hwid)"
expected="$(printf 'aabbccddeeff\n' | sha256sum | cut -d ' ' -f 1)"
[ "$actual" = "$expected" ] || { echo 'HWID hash mismatch' >&2; exit 1; }

MOCK_MAC='not-a-mac'
export MOCK_MAC
[ -z "$(get_subscription_hwid)" ] || { echo 'invalid MAC accepted' >&2; exit 1; }

echo 'HWID tests passed'
