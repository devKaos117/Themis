#!/usr/bin/env bash
#
# Module: packaging
# Description: Package managing tools and utilities
# Dependencies: logger.sh

if [[ "${__PACKAGING_LOADED__:-0}" -eq 1 ]]; then
	return 0
fi
readonly __PACKAGING_LOADED__=1

# ============================================================================
# PACKAGE MANAGEMENT FUNCTIONS
# ============================================================================

packaging::_check_snap() {
	# Check if snap is installed
	if ! sysinfo::has_cmd "snap"; then
		logger::warning "Snap not available, installing..."
		packaging::install "snapd" || return 1
	fi

	# Check if snapd service is running
	if ! systemctl is-active --quiet snapd.socket; then
		logger::debug "Starting snapd service"
		systemctl enable --now snapd.socket || {
			logger::error "Failed to start snapd service"
			return 1
		}
	fi

	# Create classic snap symlink if needed
	if [[ ! -L /snap ]]; then
		logger::debug "Creating /snap symlink"
		ln -s /var/lib/snapd/snap /snap || {
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
		flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || {
			logger::error "Failed to add flathub repository"
			return 1
		}
	fi

	return 0
}

packaging::_is_installed() {
	local package="$1"
	local manager="${2:-auto}" # auto, apt, dnf, yum, pacman, yay, apk, snap, flatpak

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
			flatpak list | grep -q "${package}"
			;;
		*)
			logger::warning "Cannot check package installation for ${PACKAGER}"
			return 1
			;;
	esac
}

packaging::_is_available() {
	local pkg="$1"
	local manager="${2:-auto}" # auto, apt, dnf, yum, pacman, yay, apk, snap, flatpak
	
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
			flatpak search "${pkg}" | grep -q "^Name: ${pkg}"
			;;
		*)
			logger::error "Unsuported package manager: ${PACKAGER}"
			return 1
			;;
	esac
}

# ============================================================================
# PUBLIC API
# ============================================================================

packaging::install() {
	local package="$1"
	local manager="${2:-auto}" # auto, apt, dnf, pacman, snap, flatpak
	
	logger::debug "Installing package: ${package} (manager: ${manager})"
	
	sysinfo::require_root || return 1
	sysinfo::require_network || return 1
	
	# Auto-detect manager if not specified
	if [[ "${manager}" == "auto" ]]; then
		manager="${PACKAGER}"
	fi
	
	if packaging::_is_installed "${package}" "${manager}"; then
		logger::debug "Package '${package}' already installed"
		return 0
	fi

	if ! packaging::_is_available "${package}" "${manager}"; then
		logger::error "Package '${package}' not available in repositories"
		return 1
	fi

	case "${manager}" in
		apt)	
			apt install -y "${package}" || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		dnf)
			dnf install -y "${package}" || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		yum)
			yum install -y "${package}" || {
				logger::error "Failed to install ${package}"
				return 1
			}
			;;
		pacman)
			pacman -S --noconfirm "${package}" || {
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
			snap install "${package}" || {
				logger::error "Failed to install snap ${package}"
				return 1
			}
			;;
		flatpak)
			packaging::_check_flatpak || return 1
			flatpak install -y flathub "${package}" || {
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
		snap refresh || logger::warning "snap refresh failed"
	fi

	if sysinfo::has_cmd "flatpak"; then
		flatpak update -y || logger::warning "flatpak update failed"
	fi

	logger::info "System updated"
}