#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Safer field splitting

# ============================================================================
# LOGGER
# ============================================================================
# ============ Initializations
# Log levels
declare -r LOG_NONE=99
declare -r LOG_CRITICAL=50
declare -r LOG_ERROR=40
declare -r LOG_WARNING=30
declare -r LOG_INFO=20
declare -r LOG_DEBUG=10
declare -r LOG_NOTSET=0

declare -r -A _LOG_LEVEL_NAMES=(
	[99]="NONE"
	[50]="CRITICAL"
	[40]="ERROR"
	[30]="WARNING"
	[20]="INFO"
	[10]="DEBUG"
)

# Log custom format
declare -r _TIMESTAMP_FORMAT="%H:%M:%S.%3N"

declare -r -A _LOG_COLORS=(
	[99]="\033[0m"			# Reset
	[50]="\033[1;95m"		# Magenta
	[40]="\033[1;91m"		# Red
	[30]="\033[1;93m"		# Orange
	[20]="\033[1;92m"		# Green
	[10]="\033[1;94m"		# Blue
	[0]="\033[96m"			# Cyan
)

# Default configuration values
declare LOG_LEVEL=${LOG_INFO}
declare COLORIZE_MESSAGE=true

# ============ Private functions
logger::_get_call_info() {
	# Local declarations
	local process_id
	local frame
	local caller_func
	local caller_file

	# Store process id
	process_id="$$"

	# Find caller function skipping internal logger
	frame=1
	caller_func="${FUNCNAME[$frame]}"

	while [[ "$caller_func" =~ ^_?logger:: ]]; do
		((frame++))
		caller_func="${FUNCNAME[$frame]:-main}"
	done

	# Find caller file
	caller_file="${BASH_SOURCE[$frame]}"
	caller_file="${caller_file##*/}"	# basename

	# Return call info
	echo "${process_id}:${caller_file}:${caller_func}"
}

logger::_log() {
	# Local declarations
	local log_level
	local message
	local timestamp
	local log_name
	local call_info
	local formatted_msg

	# Function parameters
	log_level="$1"
	message="$2"

	# Check log level
	if [[ ${log_level} -lt ${LOG_LEVEL} ]]; then
		return 0;
	fi

	# Gather metadata
	timestamp="$(date +"${_TIMESTAMP_FORMAT}")"
	log_name="${_LOG_LEVEL_NAMES[$log_level]}"
	call_info="$(logger::_get_call_info)"

	# Format message
	if [[ $COLORIZE_MESSAGE = true ]]; then
		# Colorized output
		formatted_msg="[${_LOG_COLORS[0]}${timestamp}${_LOG_COLORS[99]}] [${_LOG_COLORS[0]}${call_info}${_LOG_COLORS[99]}] [${_LOG_COLORS[$log_level]}${log_name}${_LOG_COLORS[99]}] \033[1m$message${_LOG_COLORS[99]}"
	else
		formatted_msg="[${timestamp}] [${call_info}] [${log_name}] $message"
	fi


	# Console output
	echo -e "$formatted_msg" >&2
	return 0;
}

# ============ Logging functions
logger::critical() {
	logger::_log ${LOG_CRITICAL} "$1"
}

logger::error() {
	logger::_log ${LOG_ERROR} "$1"
}

logger::warning() {
	logger::_log ${LOG_WARNING} "$1"
}

logger::info() {
	logger::_log ${LOG_INFO} "$1"
}

logger::debug() {
	logger::_log ${LOG_DEBUG} "$1"
}

# ============================================================================
# SYSINFO
# ============================================================================
# ============ Initializations
# System information storage
declare -g SYS_OS=""				# Operating system ID (ubuntu, debian, arch, etc.)
declare -g SYS_OS_LIKE=""			# OS family (debian, rhel, arch)
declare -g SYS_OS_VERSION=""		# OS version
declare -g SYS_OS_CODENAME=""		# OS codename
declare -g SYS_KERNEL=""			# Kernel version
declare -g SYS_ARCH=""				# Architecture (x86_64, aarch64, etc.)
declare -g PACKAGER=""				# Package manager (apt, dnf, pacman, etc.)
declare -g SYS_INIT_SYSTEM=""		# Init system (systemd, openrc, sysvinit)
declare -g SYS_IS_LIVE=0			# Running from live media (0=no, 1=yes)
declare -g SYS_IS_VM=0				# Running in virtual machine
declare -g SYS_IS_CONTAINER=0		# Running in container
declare -g SYS_HAS_NETWORK=0		# Network connectivity
declare -g SYS_IS_ROOT=0			# Running as root

# Capability flags
declare -g SYS_HAS_GIT=0

# ============ Private functions
sysinfo::_detect_os() {
	if [[ -f /etc/os-release ]]; then
		source /etc/os-release # Parse /etc/os-release

		SYS_OS="${ID}"
		SYS_OS_LIKE="${ID_LIKE:-${ID}}"

		# Version detection with fallbacks
		if [[ -n "${VERSION_ID:-}" ]]; then
			SYS_OS_VERSION="${VERSION_ID}"
		elif [[ -n "${VARIANT_ID:-}" ]]; then
			SYS_OS_VERSION="${VARIANT_ID}"
		elif [[ -n "${BUILD_ID:-}" ]]; then
			SYS_OS_VERSION="${BUILD_ID}"
		else
			SYS_OS_VERSION="rolling"
		fi

		# Codename detection with fallbacks
		if [[ -n "${VERSION_CODENAME:-}" ]]; then
			SYS_OS_CODENAME="${VERSION_CODENAME}"
		elif [[ -n "${VARIANT:-}" ]]; then
			SYS_OS_CODENAME="${VARIANT}"
		elif [[ -n "${VERSION:-}" ]]; then
			SYS_OS_CODENAME=$(echo "${VERSION}" | grep -oP '\(\K[^)]+' || echo "unknown")
		else
			SYS_OS_CODENAME="unknown"
		fi

		logger::debug "OS: ${SYS_OS} ${SYS_OS_VERSION} (${SYS_OS_CODENAME})"
	elif [[ -f /etc/lsb-release ]]; then
		source /etc/lsb-release # Parse /etc/lsb-release
		SYS_OS="${DISTRIB_ID,,}" # lowercase
		SYS_OS_LIKE="${SYS_OS}"
		SYS_OS_VERSION="${DISTRIB_RELEASE:-unknown}"
		SYS_OS_CODENAME="${DISTRIB_CODENAME:-unknown}"

		logger::debug "OS (LSB): ${SYS_OS} ${SYS_OS_VERSION}"
	else
		logger::warning "Could not detect OS via standard methods"
		SYS_OS="unknown"
		SYS_OS_LIKE="unknown"
		SYS_OS_VERSION="unknown"
		SYS_OS_CODENAME="unknown"

	fi
}

sysinfo::_detect_kernel() {
	SYS_KERNEL="$(uname -r)"
	logger::debug "Kernel: ${SYS_KERNEL}"
}

sysinfo::_detect_arch() {
	SYS_ARCH="$(uname -m)"
	logger::debug "Architecture: ${SYS_ARCH}"
}

sysinfo::_detect_package_manager() {
	if command -v apt &> /dev/null; then
		PACKAGER="apt"
	elif command -v dnf &> /dev/null; then
		PACKAGER="dnf"
	elif command -v yum &> /dev/null; then
		PACKAGER="yum"
	elif command -v pacman &> /dev/null; then
		PACKAGER="pacman"
	elif command -v yay &> /dev/null; then
		PACKAGER="yay"
	elif command -v apk &> /dev/null; then
		PACKAGER="apk"
	else
		logger::warning "No supported package manager detected"
		PACKAGER="unknown"
	fi

	logger::debug "Package manager: ${PACKAGER}"
}

sysinfo::_detect_init_system() {
	if [[ -d /run/systemd/system ]]; then
		SYS_INIT_SYSTEM="systemd"
	elif [[ -f /sbin/openrc ]]; then
		SYS_INIT_SYSTEM="openrc"
	elif [[ -f /sbin/init && ! -L /sbin/init ]]; then
		SYS_INIT_SYSTEM="sysvinit"
	else
		SYS_INIT_SYSTEM="unknown"
	fi

	logger::debug "Init system: ${SYS_INIT_SYSTEM}"
}

sysinfo::_detect_live_environment() {
	# Check common live boot indicators
	logger::debug "Looking for live environment indicators"

	if grep -q "boot=live" /proc/cmdline 2>/dev/null || grep -q "live" /proc/cmdline 2>/dev/null || [[ -d /lib/live/mount ]] || [[ -d /run/live ]]; then
		SYS_IS_LIVE=1
		logger::debug "Live environment detected"
	fi
}

sysinfo::_detect_virtualization() {
	# Check if running in VM
	logger::debug "Looking for virtual environment indicators"

	if command -v systemd-detect-virt &> /dev/null; then
		if [[ "$(systemd-detect-virt 2>/dev/null)" != "none" ]]; then
			SYS_IS_VM=1
			logger::debug "Virtualization detected: $(systemd-detect-virt)"
		fi
	elif [[ -f /sys/class/dmi/id/product_name ]]; then
		local product_name
		product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
		if [[ "$product_name" =~ (VirtualBox|VMware|KVM|QEMU) ]]; then
			SYS_IS_VM=1
			logger::debug "VM detected: $product_name"
		fi
	fi

	# Check if running in container
	logger::debug "Looking for containerized environment indicators"

	if [[ -f /.dockerenv ]] || \
		grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
		SYS_IS_CONTAINER=1
		logger::debug "Container environment detected"
	fi
}

sysinfo::_detect_network() {
	# Simple connectivity check
	if ping -c 1 -W 2 8.8.8.8 &> /dev/null || \
		ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
		SYS_HAS_NETWORK=1
		logger::debug "Network connectivity confirmed"
	else
		logger::warning "No network connectivity detected"
	fi
}

sysinfo::_detect_privileges() {
	if [[ $EUID -eq 0 ]]; then
		SYS_IS_ROOT=1
		logger::debug "Running as root"
	else
		logger::debug "Running as user: $(whoami)"
	fi
}

# ============ Public functions
sysinfo::detect_all() {
	logger::info "Starting full system detection..."

	sysinfo::_detect_privileges
	sysinfo::_detect_os
	sysinfo::_detect_kernel
	sysinfo::_detect_arch
	sysinfo::_detect_package_manager
	sysinfo::_detect_init_system
	sysinfo::_detect_live_environment
	sysinfo::_detect_virtualization
	sysinfo::_detect_network

	logger::info "System detection complete"
}

sysinfo::print_summary() {
	logger::debug "Printing sysinfo summary"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "System Information"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "OS:			${SYS_OS} ${SYS_OS_VERSION} (${SYS_OS_CODENAME})"
	echo "Kernel:			${SYS_KERNEL}"
	echo "Architecture:		${SYS_ARCH}"
	echo "Package Manager:	${PACKAGER}"
	echo "Init System:		${SYS_INIT_SYSTEM}"
	echo "Live Environment:	$([[ ${SYS_IS_LIVE} -eq 1 ]] && echo 'Yes' || echo 'No')"
	echo "Virtual Machine:	$([[ ${SYS_IS_VM} -eq 1 ]] && echo 'Yes' || echo 'No')"
	echo "Container:		$([[ ${SYS_IS_CONTAINER} -eq 1 ]] && echo 'Yes' || echo 'No')"
	echo "Network:		$([[ ${SYS_HAS_NETWORK} -eq 1 ]] && echo 'Available' || echo 'unavailable')"
	echo "Running as:		$([[ ${SYS_IS_ROOT} -eq 1 ]] && echo 'root' || echo "$(whoami)")"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

sysinfo::require_root() {
	if [[ ${SYS_IS_ROOT} -ne 1 ]]; then
		logger::error "This operation requires root privileges"
		return 1
	fi
	return 0
}

sysinfo::require_network() {
	if [[ ${SYS_HAS_NETWORK} -ne 1 ]]; then
		logger::error "This operation requires network connectivity"
		return 1
	fi
	return 0
}

sysinfo::is_debian_based() {
	[[ "${SYS_OS_LIKE}" =~ debian ]] && return 0 || return 1
}

sysinfo::is_arch_based() {
	[[ "${SYS_OS_LIKE}" =~ arch ]] && return 0 || return 1
}

sysinfo::is_redhat_based() {
	[[ "${SYS_OS_LIKE}" =~ (rhel|fedora) ]] && return 0 || return 1
}

sysinfo::has_cmd() {
	command -v ${1} &> /dev/null
}

# ============================================================================
# PACKAGING
# ============================================================================



# ============================================================================
# CHEF
# ============================================================================



# ============================================================================
# INTERACTION
# ============================================================================



# ============================================================================
# MAIN
# ============================================================================



# Configure logger
LOG_LEVEL=${LOG_DEBUG}
COLORIZE_MESSAGE=true

# Main execution
main() {
    # Detect system
    sysinfo::detect_all
	sysinfo::print_summary

	# fedora::sources
	# fedora::cli
	# fedora::virt
	# fedora::gpu
	# fedora::gaming
	# all::vpn
	# fedora::dev
	# fedora::general
	# fedora::media
	# fedora::vpn
	# fedora::texlive
	# fedora::browsers

	logger::info "Done"
}

# Run main if executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
