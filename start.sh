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
	if ping -c 1 -W 2 8.8.8.8 &> /dev/null || ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
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
# ============ Private functions
packaging::_check_snap() {
	# Check if snap is installed
	if ! sysinfo::has_cmd "snap"; then
		logger::warning "Snap not available, installing..."
		packaging::install "snapd" || return 1
	fi

	# Check if snapd service is running
	if ! systemctl is-active --quiet snapd.socket; then
		logger::debug "Starting snapd service"
		systemctl enable --now snapd.socket 1>  /dev/null || {
			logger::error "Failed to start snapd service"
			return 1
		}
	fi

	# Create classic snap symlink if needed
	if [[ ! -L /snap ]]; then
		logger::debug "Creating /snap symlink"
		ln -s /var/lib/snapd/snap /snap 1>  /dev/null || {
			logger::error "Failed to create /snap symlink"
			return 1
		}
	fi

	return 0
}

packaging::_check_flatpak() {
	# Check if flatpak is installed
	if ! sysinfo::has_cmd "flatpak"; then
		logger::warning "Flatpak not available, installing..."
		packaging::install "flatpak" || return 1
	fi

	# Add flathub repository if not already added
	if ! flatpak remote-list | grep -q flathub; then
		logger::debug "Adding flathub repository"
		flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 1> /dev/null || {
			logger::error "Failed to add flathub repository"
			return 1
		}
	fi

	return 0
}

packaging::_is_installed() {
	local package="$1"
	local manager="${2:-auto}" # auto, apt, dnf, rpm, yum, pacman, yay, apk, snap, flatpak

	# Auto-detect manager if not specified
	if [[ "${manager}" == "auto" ]]; then
		manager="${PACKAGER}"
	fi

	case "${manager}" in
		apt)
			dpkg -l "${package}" 2>/dev/null | grep -q "^ii"
			;;
		dnf|yum)
			rpm -q "${package}" &>/dev/null
			;;
		pacman)
			pacman -Q "${package}" &>/dev/null
			;;
		# yay)
		# 	...
		# 	;;
		# apk)
		# 	...
		# 	;;
		snap)
			packaging::_check_snap || return 1
			snap list "${package}" &>/dev/null
			;;
		flatpak)
			packaging::_check_flatpak || return 1
			flatpak list 2> /dev/null | grep -q "${package}"
			;;
		*)
			logger::warning "Cannot check package installation for ${manager}"
			return 1
			;;
	esac
}

packaging::_is_available() {
	local pkg="$1"
	local manager="${2:-auto}" # auto, apt, dnf, rpm, yum, pacman, yay, apk, snap, flatpak

	# Auto-detect manager if not specified
	if [[ "${manager}" == "auto" ]]; then
		manager="${PACKAGER}"
	fi

	case "${manager}" in
		apt)
			apt show "${pkg}" &>/dev/null
			;;
		dnf)
			dnf info "${pkg}" &>/dev/null
			;;
		rpm)
			if [[ -f "$pkg" ]]; then
				return 0
			elif [[ "${pkg}" =~ ^(http|https|ftp):// ]] && sysinfo::require_network ; then
				return 0
			else
				return 1
			fi
			;;
		yum)
			yum info "${pkg}" &>/dev/null
			;;
		pacman)
			pacman -Si "${pkg}" &>/dev/null
			;;
		# yay)
		# 	pacman -Si "${pkg}" &>/dev/null
		# 	;;
		# apk)
		# 	pacman -Si "${pkg}" &>/dev/null
		# 	;;
		snap)
			packaging::_check_snap || return 1
			snap info "${pkg}" &>/dev/null
			;;
		flatpak)
			packaging::_check_flatpak || return 1
			flatpak search "${pkg}" | grep -i "${pkg}" && return 1 || return 0
			;;
		*)
			logger::error "Unsuported package manager: ${PACKAGER}"
			return 1
			;;
	esac
}

# ============ Public functions
packaging::install() {
	local package="$1"
	local manager="${2:-auto}" # auto, apt, dnf, rpm, yum, pacman, yay, apk, snap, flatpak

	logger::debug "Installing package (${manager}): ${package}"

	sysinfo::require_root || return 1
	sysinfo::require_network || return 1

	# Auto-detect manager if not specified
	if [[ "${manager}" == "auto" ]]; then
		manager="${PACKAGER}"
	fi

	if packaging::_is_installed "${package}" "${manager}" ; then
		logger::debug "Package '${package}' already installed"
		return 0
	fi

	if ! packaging::_is_available "${package}" "${manager}" ; then
		logger::error "Package '${package}' not available in repositories"
		return 1
	fi

	case "${manager}" in
		apt)
			apt install -y "${package}" 1> /dev/null || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		dnf)
			dnf install -y "${package}" 1> /dev/null || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		rpm)
			rpm -U "${package}" 1> /dev/null || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		yum)
			yum install -y "${package}" 1> /dev/null || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		pacman)
			pacman -S --noconfirm "${package}" 1> /dev/null || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		# yay)
		# 	... || {
		# 		logger::error "Failed to install ${package}"
		# 		return 1
		# 	}
		# 	;;
		# apk)
		# 	... || {
		# 		logger::error "Failed to install ${package}"
		# 		return 1
		# 	}
		# 	;;
		snap)
			packaging::_check_snap || return 1
			snap install "${package}" 1> /dev/null || {
				logger::error "Failed to install snap ${package}"
				return 1
			}
			;;
		flatpak)
			packaging::_check_flatpak || return 1
			flatpak install -y flathub "${package}" 1> /dev/null || {
				logger::error "Failed to install flatpak ${package}"
				return 1
			}
			;;
		*)
			logger::error "Unsupported package manager: ${manager}"
			return 1
			;;
	esac

	logger::info "Successfully installed ${package}"
	return 0
}

packaging::uninstall() {
	local package="$1"
	local manager="${2:-auto}" # auto, apt, dnf, rpm, yum, pacman, yay, apk, snap, flatpak
	local purge="${3:-0}" # 1=purge, 0=keep configs

	logger::debug "Uninstalling $(if [[ ${purge} -eq 1 ]] ;then echo "(purge)"; fi) package (${manager}): ${package}"

	sysinfo::require_root || return 1

	# Auto-detect manager if not specified
	if [[ "${manager}" == "auto" ]]; then
		manager="${PACKAGER}"
	fi

	if ! packaging::_is_installed "${package}" "${manager}"; then
		logger::debug "Package '${package}' is not installed"
		return 0
	fi

	case "${manager}" in
		apt)
			if [[ ${purge} -eq 1 ]]; then
				apt purge -y "${package}" 1> /dev/null || {
					logger::error "Failed to purge ${package}"
					return 1
				}
			else
				apt remove -y "${package}" 1> /dev/null || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi
			# autoremove and autoclean
			apt autoremove -y 1> /dev/null || logger::warning "apt autoremove failed"
			apt autoclean -y 1> /dev/null || logger::warning "apt autoclean failed"
			;;
		dnf)
			# Fetch config files if configured to purge
			local config_files
			if [[ ${purge} -eq 1 ]]; then
				config_files=$(rpm -ql "${package}" 2>/dev/null | grep "^/etc/" || true)
			fi

			dnf remove -y "${package}" 1> /dev/null || {
				logger::error "Failed to uninstall ${package}"
				return 1
			}

			# Purge
			if [[ -n "${config_files}" ]]; then
				echo "${config_files}" | while IFS= read -r file; do
					if [[ -f "${file}" || -d "${file}" ]]; then
						rm -rf "${file}" 1> /dev/null || logger::warning "Failed to remove ${file}"
					fi
				done
			fi

			# autoremove and clean
			dnf autoremove -y 1> /dev/null || logger::warning "dnf autoremove failed"
			dnf clean all 1> /dev/null || logger::warning "dnf clean failed"
			;;
		rpm)
			# Fetch config files if configured to purge
			local config_files
			if [[ ${purge} -eq 1 ]]; then
				config_files=$(rpm -ql "${package}" 2>/dev/null | grep "^/etc/" || true)
			fi

			rpm -e "${package}" 1> /dev/null || {
				logger::error "Failed to uninstall ${package}"
				return 1
			}

			# Purge
			if [[ -n "${config_files}" ]]; then
				echo "${config_files}" | while IFS= read -r file; do
					if [[ -f "${file}" || -d "${file}" ]]; then
						rm -rf "${file}" 1> /dev/null || logger::warning "Failed to remove ${file}"
					fi
				done
			fi
			;;
		yum)
			# Fetch config files if configured to purge
			local config_files
			if [[ ${purge} -eq 1 ]]; then
				config_files=$(rpm -ql "${package}" 2>/dev/null | grep "^/etc/" || true)
			fi

			yum remove -y "${package}" 1> /dev/null || {
				logger::error "Failed to uninstall ${package}"
				return 1
			}

			# Purge
			if [[ -n "${config_files}" ]]; then
				echo "${config_files}" | while IFS= read -r file; do
					if [[ -f "${file}" || -d "${file}" ]]; then
						rm -rf "${file}" 1> /dev/null || logger::warning "Failed to remove ${file}"
					fi
				done
			fi

			yum autoremove -y 1> /dev/null || logger::warning "yum autoremove failed"
			yum clean all 1> /dev/null || logger::warning "yum clean failed"
			;;
		pacman)
			if [[ ${purge} -eq 1 ]]; then
				pacman -Rns --noconfirm "${package}" 1> /dev/null || {
					logger::error "Failed to purge ${package}"
					return 1
				}
			else
				pacman -Rs --noconfirm "${package}" 1> /dev/null || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi

			# Clean package cache
			if [[ ${purge} -eq 1 ]]; then
				pacman -Sc --noconfirm 1> /dev/null || logger::warning "pacman cache clean failed"
			fi
			;;
		yay)
			if [[ ${purge} -eq 1 ]]; then
				yay -Rns --noconfirm "${package}" 1> /dev/null || {
					logger::error "Failed to purge ${package}"
					return 1
				}
			else
				yay -Rs --noconfirm "${package}" 1> /dev/null || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi

			# Clean cache
			yay -Sc --noconfirm 1> /dev/null || logger::warning "yay cache clean failed"
			;;
		apk)
			if [[ ${purge} -eq 1 ]]; then
				apk del --purge "${package}" 1> /dev/null || {
				logger::error "Failed to purge ${package}"
				return 1
			}
			else
				apk del "${package}" 1> /dev/null || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi

			# Clean cache
			apk cache clean 1> /dev/null || logger::warning "apk cache clean failed"
			;;
		snap)
			packaging::_check_snap || return 1

			if [[ ${purge} -eq 1 ]]; then
				snap remove --purge "${package}" 1> /dev/null || {
					logger::error "Failed to purge snap ${package}"
					return 1
				}
			else
				snap remove "${package}" 1> /dev/null || {
					logger::error "Failed to uninstall snap ${package}"
					return 1
				}
			fi
			;;
		flatpak)
			packaging::_check_flatpak || return 1

			flatpak uninstall -y "${package}" 1> /dev/null || {
				logger::error "Failed to uninstall flatpak ${package}"
				return 1
			}

			if [[ ${purge} -eq 1 ]]; then
				flatpak uninstall --delete-data -y "${package}" &>/dev/null || true

				# Remove unused runtimes and dependencies
				flatpak uninstall --unused --delete-data -y 1> /dev/null || logger::warning "flatpak cleanup failed"

				# Repair and prune repo
				flatpak repair --user 1> /dev/null || logger::warning "flatpak repair failed"
			fi
			;;
		*)
			logger::error "Unsupported package manager: ${manager}"
			return 1
			;;
	esac

	logger::info "Successfully uninstalled ${package}"
	return 0
}

packaging::update() {
	logger::debug "Updating system packages"

	sysinfo::require_root || return 1
	sysinfo::require_network || return 1

	case "${PACKAGER}" in
		apt)
			apt update -y || {
				logger::error "apt update failed"
				return 1
			}
			apt upgrade -y || {
				logger::error "apt upgrade failed"
				return 1
			}
			apt autoremove -y || logger::warning "apt autoremove failed"
			;;
		dnf)
			dnf update -y || {
				logger::error "dnf update failed"
				return 1
			}
			dnf upgrade -y || {
				logger::error "dnf upgrade failed"
				return 1
			}
			dnf autoremove -y || logger::warning "dnf autoremove failed"
			;;
		yum)
			yum update -y || {
				logger::error "yum update failed"
				return 1
			}
			yum autoremove -y || logger::warning "yum autoremove failed"
			;;
		pacman)
			pacman -Syu --noconfirm || {
				logger::error "pacman update failed"
				return 1
			}
			;;
		# yay)
		# 	...
		# 	;;
		# apk)
		# 	...
		# 	;;
		*)
			logger::error "Unsupported package manager: ${PACKAGER}"
			return 1
			;;
	esac

	if sysinfo::has_cmd "snap"; then
		logger::debug "Refreshing snaps"
		snap refresh || logger::warning "snap refresh failed"
	fi

	if sysinfo::has_cmd "flatpak"; then
		logger::debug "Updating flatpak packages"
		flatpak update -y || logger::warning "flatpak update failed"
	fi

	logger::info "System updated"
}

# ============================================================================
# CHEF
# ============================================================================

fedora::sources() { # DNF plugins, RPM Fusion, Brave, Microsoft, Docker
	logger::info "Setting up sources"
	# ====== DNF
	packaging::install "dnf-plugins-core"
	sed -i '/^max_parallel_downloads=/c\max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
	echo "fastestmirror=True" >> /etc/dnf/dnf.conf
	echo "defaultyes=True" >> /etc/dnf/dnf.conf
	# ====== RPM Fusion
	if [[ ! -e /etc/yum.repos.d/rpmfusion-free.repo ]]; then packaging::install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"; fi
	if [[ ! -e /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then packaging::install "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; fi
	dnf config-manager setopt fedora-cisco-openh264.enabled=1
	# ====== Brave
	# https://brave.com/linux/
	if [[ ! -f "/etc/yum.repos.d/brave-browser.repo" ]]; then
		dnf config-manager addrepo --from-repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
	fi
	# ====== Microsoft
	# https://learn.microsoft.com/pt-br/powershell/scripting/install/install-rhel?view=powershell-7.5
	# https://code.visualstudio.com/docs/setup/linux
	# ------- Add verification for the Microsoft repository
	rpm --import https://packages.microsoft.com/keys/microsoft.asc
	echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee /etc/yum.repos.d/vscode.repo > /dev/null
	packaging::install "https://packages.microsoft.com/config/rhel/$(if [ $SYS_OS_VERSION -lt 8 ]; then echo 7 ; elif [ $SYS_OS_VERSION -lt 9 ]; then echo 8; else echo 9; fi )/packages-microsoft-prod.rpm" "rpm"
	# ====== Docker
	# ------- Add verification for the Docker repository
	dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
	# ====== Update
	packaging::update
}

fedora::cli() {
	if packaging::install zsh ; then
		chsh -s "/bin/zsh" $(id -nu 1000)
		chsh -s "/bin/zsh" $(id -nu 0)
		cp "$_SCRIPT_DIR/profiles/zshrc" "$(getent passwd 1000 | cut -d : -f 6)/.zshrc"
		cp "$_SCRIPT_DIR/profiles/zshrc" "$(getent passwd 0 | cut -d : -f 6)/.zshrc"
	fi
	packaging::install zsh-autosuggestions
	packaging::install zsh-syntax-highlighting
	if packaging::install alacritty ; then
		if [[ ! -d "$(getent passwd 1000 | cut -d : -f 6)/.config/alacritty" ]]; then mkdir "$(getent passwd 1000 | cut -d : -f 6)/.config/alacritty"; fi
		if [[ ! -d "$(getent passwd 0 | cut -d : -f 6)/.config/alacritty" ]]; then mkdir "$(getent passwd 0 | cut -d : -f 6)/.config/alacritty"; fi
		cp "$_SCRIPT_DIR/profiles/alacritty.toml" "$(getent passwd 1000 | cut -d : -f 6)/.config/alacritty/alacritty.toml"
		cp "$_SCRIPT_DIR/profiles/alacritty.toml" "$(getent passwd 0 | cut -d : -f 6)/.config/alacritty/alacritty.toml"
	fi
	if packaging::install btop ; then
		if [[ ! -d "$(getent passwd 1000 | cut -d : -f 6)/.config/btop" ]]; then mkdir "$(getent passwd 1000 | cut -d : -f 6)/.config/btop"; fi
		if [[ ! -d "$(getent passwd 0 | cut -d : -f 6)/.config/btop" ]]; then mkdir "$(getent passwd 0 | cut -d : -f 6)/.config/btop"; fi
		cp "$_SCRIPT_DIR/profiles/btop.conf" "$(getent passwd 1000 | cut -d : -f 6)/.config/btop/btop.conf"
		cp "$_SCRIPT_DIR/profiles/btop.conf" "$(getent passwd 0 | cut -d : -f 6)/.config/btop/btop.conf"
	fi
	packaging::install neovim
	packaging::install bat
	packaging::install tldr
	packaging::install cpufetch
	packaging::install fastfetch
	packaging::install 7z
	packaging::install rclone
	packaging::install mc
	packaging::install trash-cli
	packaging::install ascii
	packaging::install xxd
}

fedora::dev() {
	if packaging::install git ; then
		git config --global init.defaultBranch main
		git config --global user.name "kaos"
		git config --global user.email "gustavo.s.aragao.2003@gmail.com"
	fi
	packaging::install code
	packaging::install gh
	packaging::install gcc
	packaging::install rust
	packaging::install python3
	packaging::install powershell
}

fedora::gpu() {
	# ------- Diferentiate Intel, AMD, NVIDIA
	logger::info "Setting up GPU tools"
	dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld && dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
	dnf copr enable -y ilyaz/LACT # Check AMD OC
	packaging::install vulkan-tools
	packaging::install radeontop
	packaging::install lact && sudo systemctl enable --now lactd
}

fedora::virt() { # QEMU/KVM, virt-manager, VirtualBox, Docker
	logger::info "Setting up virtualization"
	# ====== QEMU/KVM
	packaging::install qemu-kvm
	packaging::install libvirt
	packaging::install edk2-ovmf
	packaging::install swtpm
	packaging::install qemu-img
	packaging::install guestfs-tools
	packaging::install libosinfo
	packaging::install tuned
	for drv in qemu interface network nodedev nwfilter secret storage; do \
		systemctl enable virt${drv}d.service; \
		systemctl enable virt${drv}d{,-ro,-admin}.socket; \
	done
	logger::info "QEMU/KVM validation"
	virt-host-validate qemu
	# ====== virt-manager
	packaging::install virt-install
	packaging::install virt-manager
	packaging::install virt-viewer
	# ====== VirtualBox
	packaging::install virtualbox
	packaging::install akmod-VirtualBox
	packaging::install kernel-devel-$(uname -r)
	akmods
	systemctl restart vboxdrv.service
	# ====== Docker
	packaging::install docker.io
	packaging::install docker-compose
	packaging::install docker-cli
	packaging::install docker-buildx
	packaging::install docker-clean
	packaging::install docker-doc
	systemctl enable --now docker
}

fedora::vpn() {
	packaging::install tor && systemctl enable --now tor 1> /dev/null
	packaging::install openvpn
	packaging::install proxychains-ng
	all::vpn
}

fedora::texlive() {
	packaging::install latexmk
	packaging::install texlive-lastpage
	packaging::install texlive-fancyhdr
	packaging::install texlive-multirow
	packaging::install texlive-enumitem
	packaging::install texlive-mathtools
	packaging::install texlive-amsfonts
	packaging::install texlive-hyperref
	packaging::install texlive-titlesec
	packaging::install texlive-tkz-euclide
}

fedora::browsers() {
	packaging::install brave-browser
	packaging::install firefox
	packaging::install lynx
}

fedora::general() {
	packaging::install discord
	packaging::install md.obsidian.Obsidian flatpak
	packaging::install libreoffice
	packaging::install qbittorrent
	packaging::install openrgb
	packaging::install qpdf
}

fedora::media() {
	packaging::install vlc
	packaging::install gimp
	packaging::install libavcodec-freeworld
	packaging::install ffmpeg-free
}

fedora::gaming() {
	packaging::install steam
}

chef::list_recipes() {
	list=$(compgen -A function "$SYS_OS::" | cut -d : -f 3)
}

# ============================================================================
# TUI
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

	logger::info "Done"
}

# Run main if executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
