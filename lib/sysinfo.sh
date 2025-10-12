#!/bin/bash
#
# Module: sysinfo
# Description: System detection and capability checking
# Dependencies: logger.sh

if [[ "${__SYSINFO_LOADED__:-0}" -eq 1 ]]; then
    return 0
fi
readonly __SYSINFO_LOADED__=1

# ============================================================================
# USAGE DOCUMENTATION
# ============================================================================
#
# source lib/sysinfo.sh
# 
# # Detect everything
# sysinfo::detect_all
# sysinfo::print_summary
#
# # Check specific conditions
# if sysinfo::require_root; then
#	 echo "Running as root"
# fi
#
# # Use detection results
# if sysinfo::is_debian_based; then
#	 apt-get update
# elif sysinfo::is_arch_based; then
#	 pacman -Syu
# fi

# ============================================================================
# SYSTEM INFORMATION STORAGE
# ============================================================================
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

# ============================================================================
# PRIVATE DETECTION FUNCTIONS
# ============================================================================

_sysinfo::detect_os() {
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
        
        logger::debug "OS detected: ${SYS_OS} ${SYS_OS_VERSION} (${SYS_OS_CODENAME})"
	elif [[ -f /etc/lsb-release ]]; then
		source /etc/lsb-release # Parse /etc/lsb-release
        SYS_OS="${DISTRIB_ID,,}"  # lowercase
        SYS_OS_LIKE="${SYS_OS}"
        SYS_OS_VERSION="${DISTRIB_RELEASE:-unknown}"
        SYS_OS_CODENAME="${DISTRIB_CODENAME:-unknown}"

		logger::debug "OS detected via LSB: ${SYS_OS} ${SYS_OS_VERSION}"
	else
		logger::warning "Could not detect OS via standard methods"
        SYS_OS="unknown"
        SYS_OS_LIKE="unknown"
        SYS_OS_VERSION="unknown"
        SYS_OS_CODENAME="unknown"

	fi
}

_sysinfo::detect_kernel() {
	SYS_KERNEL="$(uname -r)"
	logger::debug "Kernel: ${SYS_KERNEL}"
}

_sysinfo::detect_arch() {
	SYS_ARCH="$(uname -m)"
	logger::debug "Architecture: ${SYS_ARCH}"
}

_sysinfo::detect_package_manager() {
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

_sysinfo::detect_init_system() {
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

_sysinfo::detect_live_environment() {
	# Check common live boot indicators
	logger::debug "Looking for live environment indicators"
	
	if grep -q "boot=live" /proc/cmdline 2>/dev/null || grep -q "live" /proc/cmdline 2>/dev/null || [[ -d /lib/live/mount ]] || [[ -d /run/live ]]; then
		SYS_IS_LIVE=1
		logger::debug "Live environment detected"
	fi
}

_sysinfo::detect_virtualization() {
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

_sysinfo::detect_network() {
	# Simple connectivity check
	if ping -c 1 -W 2 8.8.8.8 &> /dev/null || \
		ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
		SYS_HAS_NETWORK=1
		logger::debug "Network connectivity confirmed"
	else
		logger::warning "No network connectivity detected"
	fi
}

_sysinfo::detect_privileges() {
	if [[ $EUID -eq 0 ]]; then
		SYS_IS_ROOT=1
		logger::debug "Running as root"
	else
		logger::debug "Running as user: $(whoami)"
	fi
}

# ============================================================================
# PUBLIC API
# ============================================================================

sysinfo::detect_all() {
	logger::info "Starting full system detection..."

	_sysinfo::detect_privileges
	_sysinfo::detect_os
	_sysinfo::detect_kernel
	_sysinfo::detect_arch
	_sysinfo::detect_package_manager
	_sysinfo::detect_init_system
	_sysinfo::detect_live_environment
	_sysinfo::detect_virtualization
	_sysinfo::detect_network
	
	logger::info "System detection complete"
}

sysinfo::print_summary() {
	logger::debug "Printing sysinfo summary"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "System Information"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "OS:               ${SYS_OS} ${SYS_OS_VERSION} (${SYS_OS_CODENAME})"
	echo "Kernel:           ${SYS_KERNEL}"
	echo "Architecture:     ${SYS_ARCH}"
	echo "Package Manager:  ${PACKAGER}"
	echo "Init System:      ${SYS_INIT_SYSTEM}"
	echo "Live Environment: $([[ ${SYS_IS_LIVE} -eq 1 ]] && echo 'Yes' || echo 'No')"
	echo "Virtual Machine:  $([[ ${SYS_IS_VM} -eq 1 ]] && echo 'Yes' || echo 'No')"
	echo "Container:        $([[ ${SYS_IS_CONTAINER} -eq 1 ]] && echo 'Yes' || echo 'No')"
	echo "Network:          $([[ ${SYS_HAS_NETWORK} -eq 1 ]] && echo 'Available' || echo 'unavailable')"
	echo "Running as:       $([[ ${SYS_IS_ROOT} -eq 1 ]] && echo 'root' || echo "$(whoami)")"
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