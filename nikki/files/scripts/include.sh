#!/bin/sh

# paths
HOME_DIR="/etc/nikki"
PROFILES_DIR="$HOME_DIR/profiles"
SUBSCRIPTIONS_DIR="$HOME_DIR/subscriptions"
MIXIN_FILE_PATH="$HOME_DIR/mixin.yaml"
RUN_DIR="$HOME_DIR/run"
RUN_PROFILE_PATH="$RUN_DIR/config.yaml"
PROVIDERS_DIR="$RUN_DIR/providers"
RULE_PROVIDERS_DIR="$PROVIDERS_DIR/rule"
PROXY_PROVIDERS_DIR="$PROVIDERS_DIR/proxy"

# log
LOG_DIR="/var/log/nikki"
APP_LOG_PATH="$LOG_DIR/app.log"
CORE_LOG_PATH="$LOG_DIR/core.log"

# temp
TEMP_DIR="/var/run/nikki"
PID_FILE_PATH="$TEMP_DIR/nikki.pid"
STARTED_FLAG_PATH="$TEMP_DIR/started.flag"
BRIDGE_NF_CALL_IPTABLES_FLAG_PATH="$TEMP_DIR/bridge_nf_call_iptables.flag"
BRIDGE_NF_CALL_IP6TABLES_FLAG_PATH="$TEMP_DIR/bridge_nf_call_ip6tables.flag"

# ucode
UCODE_DIR="$HOME_DIR/ucode"
INCLUDE_UC="$UCODE_DIR/include.uc"
MIXIN_UC="$UCODE_DIR/mixin.uc"
HIJACK_UT="$UCODE_DIR/hijack.ut"

# scripts
SH_DIR="$HOME_DIR/scripts"
INCLUDE_SH="$SH_DIR/include.sh"
FIREWALL_INCLUDE_SH="$SH_DIR/firewall_include.sh"

# functions
format_filesize() {
	local b; b=1
	local kb; kb=$((b * 1024))
	local mb; mb=$((kb * 1024))
	local gb; gb=$((mb * 1024))
	local tb; tb=$((gb * 1024))
	local pb; pb=$((tb * 1024))
	local size; size="$1"
	if [ -n "$size" ]; then
		if [ "$size" -lt "$kb" ]; then
			echo "$(awk "BEGIN {print $size / $b}") B"
		elif [ "$size" -lt "$mb" ]; then
			echo "$(awk "BEGIN {print $size / $kb}") KB"
		elif [ "$size" -lt "$gb" ]; then
			echo "$(awk "BEGIN {print $size / $mb}") MB"
		elif [ "$size" -lt "$tb" ]; then
			echo "$(awk "BEGIN {print $size / $gb}") GB"
		elif [ "$size" -lt "$pb" ]; then
			echo "$(awk "BEGIN {print $size / $tb}") TB"
		else
			echo "$(awk "BEGIN {print $size / $pb}") PB"
		fi
	fi
}

prepare_files() {
	if [ ! -d "$LOG_DIR" ]; then
		mkdir -p "$LOG_DIR"
	fi
	if [ ! -f "$APP_LOG_PATH" ]; then
		touch "$APP_LOG_PATH"
	fi
	if [ ! -f "$CORE_LOG_PATH" ]; then
		touch "$CORE_LOG_PATH"
	fi
	if [ ! -d "$TEMP_DIR" ]; then
		mkdir -p "$TEMP_DIR"
	fi
}

log() {
	echo "[$(date "+%Y-%m-%d %H:%M:%S")] [$1] $2" >> "$APP_LOG_PATH"
}

# Only called for subscriptions that explicitly enable device headers.
get_subscription_hwid() {
	local mac
	mac=""
	if command -v fw_printenv >/dev/null 2>&1; then
		mac="$(fw_printenv ethaddr 2>/dev/null | sed -n 's/^ethaddr=//p' | tr -d '\r\n')"
	fi
	if [ -z "$mac" ] && [ -r /sys/class/net/eth0/address ]; then
		mac="$(cat /sys/class/net/eth0/address 2>/dev/null | tr -d '\r\n')"
	fi
	if [ -z "$mac" ] && [ -r /sys/class/net/wan/address ]; then
		mac="$(cat /sys/class/net/wan/address 2>/dev/null | tr -d '\r\n')"
	fi
	printf '%s\n' "$mac" | grep -Eq '^[[:xdigit:]]{2}(:[[:xdigit:]]{2}){5}$' || return 0
	[ "$mac" = '00:00:00:00:00:00' ] && return 0
	command -v sha256sum >/dev/null 2>&1 || return 0
	printf '%s\n' "$mac" | tr '[:upper:]' '[:lower:]' | tr -d ':' | sha256sum | cut -d ' ' -f 1
}

get_subscription_model() {
	if [ -r /tmp/sysinfo/model ]; then
		tr -d '\r\n' < /tmp/sysinfo/model
	else
		printf '%s' 'unknown'
	fi
}

get_subscription_os_version() {
	if [ -r /etc/openwrt_release ]; then
		(. /etc/openwrt_release; printf '%s' "${DISTRIB_RELEASE:-unknown}") | tr -d '\r\n'
	else
		printf '%s' 'unknown'
	fi
}
