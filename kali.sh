#!/bin/bash

set -euo pipefail	# Exit on error, undefined vars, pipe failures
IFS=$'\n\t'			# Safer field splitting

# ============================================================================
# UTILITIES
# ============================================================================
# ================ Custom colored output
cprint() {
	# Initializations
	local msg="$1"
	local default_color="\033[1;37m" # Bright White
	local reset="\033[0m"
	local pattern='(.*)[{][{]([A-Za-z]+):([^}]+)[}][}](.*)'
	# Pattern matching
	while [[ "$msg" =~ $pattern ]]; do
		local prefix="${BASH_REMATCH[1]}"
		local color="${BASH_REMATCH[2]}"
		local text="${BASH_REMATCH[3]}"
		local suffix="${BASH_REMATCH[4]}"

		local ansi_color=""
		
		case "${color,,}" in
			black)		ansi_color="\033[1;30m" ;;
			white)		ansi_color="\033[1;37m" ;;
			magenta)	ansi_color="\033[1;95m"	;;
			red)		ansi_color="\033[1;91m" ;;
			yellow)		ansi_color="\033[1;93m" ;;
			green)		ansi_color="\033[1;92m" ;;
			blue)		ansi_color="\033[1;94m" ;;
			cyan)		ansi_color="\033[1;96m" ;;
			*)			ansi_color="$default_color" ;; # Fallback for invalid colors
		esac
		# Build message
		msg="${prefix}${ansi_color}${text}${reset}${default_color}${suffix}"
	done
	# Print message
	echo -e "${default_color}${msg}${reset}"
}

# ============================================================================
# SYSINFO
# ============================================================================
# ================ Fetch current system information
fetch_sysinfo() {
	cprint "{{BLUE:[*] Fetching}} system information"
	# ======== Initializations
	local os_id=""
	local os_upstream=""
	local os_version=""
	local os_codename=""
	local os_kernel=""
	local init_system=""
	local kernel=""
	local arch=""
	local is_live=0
	local is_virt=0
	# ======== Fetch operating system information
	if [[ -f /etc/os-release ]]; then
		source /etc/os-release

		os_id="${ID}"
		os_upstream="${ID_LIKE:-${ID}}"

		# Version detection with fallbacks
		if [[ -n "${VERSION_ID:-}" ]]; then
			os_version="${VERSION_ID}"
		elif [[ -n "${VARIANT_ID:-}" ]]; then
			os_version="${VARIANT_ID}"
		elif [[ -n "${BUILD_ID:-}" ]]; then
			os_version="${BUILD_ID}"
		else
			os_version="rolling"
		fi

		# Codename detection with fallbacks
		if [[ -n "${VERSION_CODENAME:-}" ]]; then
			os_codename="${VERSION_CODENAME}"
		elif [[ -n "${VARIANT:-}" ]]; then
			os_codename="${VARIANT}"
		elif [[ -n "${VERSION:-}" ]]; then
			os_codename=$(echo "${VERSION}" | grep -oP '\(\K[^)]+' || echo "unknown")
		else
			os_codename="unknown"
		fi

	elif [[ -f /etc/lsb-release ]]; then
		source /etc/lsb-release 
		os_id="${DISTRIB_ID,,}" 
		os_upstream="${os_id}"
		os_version="${DISTRIB_RELEASE:-unknown}"
		os_codename="${DISTRIB_CODENAME:-unknown}"
	else
		cprint "{{MAGENTA:[!] CRITICAL:}} Failed to detect current operating system"
		exit 1
	fi

	# ======== Fetch init system
	if [[ -d /run/systemd/system ]]; then
		init_system="systemd"
	elif [[ -f /sbin/openrc ]]; then
		init_system="openrc"
	elif [[ -f /sbin/init && ! -L /sbin/init ]]; then
		init_system="sysvinit"
	else
		init_system="unknown"
	fi

	# ======== Fetch kernel version
	kernel="$(uname -r)"

	# ======== Fetch architecture
	arch="$(uname -m)"

	# ======== Detect live environment
	if grep -q "boot=live" /proc/cmdline 2>/dev/null || grep -q "live" /proc/cmdline 2>/dev/null || [[ -d /lib/live/mount ]] || [[ -d /run/live ]]; then
		is_live=1
	fi

	# ======== Detect virtual environment
	if command -v systemd-detect-virt &> /dev/null; then
		if [[ "$(systemd-detect-virt 2>/dev/null)" != "none" ]]; then
			is_virt=1
			cprint "\t{{BLUE:[+] Virtual Environment:}} $(systemd-detect-virt)"
		fi
	elif [[ -f /sys/class/dmi/id/product_name ]]; then
		local product_name
		product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
		if [[ "$product_name" =~ (VirtualBox|VMware|KVM|QEMU) ]]; then
			is_virt=1
			cprint "\t{{BLUE:[+] Virtual Environment:}} $product_name"
		fi
	elif [[ -f /.dockerenv ]] || \
		grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
		is_virt=1
		cprint "\t{{BLUE:[+] Containerized Environment}}"
	fi

	# ======== Build array
	declare -g -A SYSINFO=(
		["os"]="${os_id}"
		["upstream"]="${os_upstream}"
		["version"]="${os_version}"
		["codename"]="${os_codename}"
		["kernel"]="${kernel}"
		["arch"]="${arch}"
		["is_live"]="${is_live}"
		["is_virt"]="${is_virt}"
	)
}

# ============================================================================
# INITIALIZATIONS
# ============================================================================
# Network
if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null && ! ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
	cprint "{{MAGENTA:[!] CRITICAL}} This script requires internet connection"
	exit 1
fi
# Root
if [[ $EUID -ne 0 ]]; then
	cprint "{{MAGENTA:[!] CRITICAL}} This script requires elevated privileges"
	exit 1
fi
# Tools

# OS
fetch_sysinfo
