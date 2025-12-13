#!/bin/bash
#
# Module: packaging
# Description: Package managing tools and utilities
# Dependencies: logger.sh

# ============================================================================
# INITIALIZATIONS
# ============================================================================
# ============ Avoid loading the module twice
if [[ "${__PACKAGING_LOADED__:-0}" -eq 1 ]]; then
	return 0
fi
readonly __PACKAGING_LOADED__=1

# ============ Safer field splitting
IFS=$'\n\t'

# ============================================================================
# PRIVATE FUNCTIONS
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
			flatpak list | grep -q "${package}"
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
			flatpak search "${pkg}" | grep -qi "^${pkg}"
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
	local manager="${2:-auto}" # auto, apt, dnf, rpm, yum, pacman, yay, apk, snap, flatpak

	logger::debug "Installing package (${manager}): ${package}"

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
		rpm)
			rpm -U "${package}" || {
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
				apt purge -y "${package}" || {
					logger::error "Failed to purge ${package}"
					return 1
				}
			else
				apt remove -y "${package}" || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi
			# autoremove and autoclean
			apt autoremove -y || logger::warning "apt autoremove failed"
			apt autoclean -y || logger::warning "apt autoclean failed"
			;;
		dnf)
			# Fetch config files if configured to purge
			local config_files
			if [[ ${purge} -eq 1 ]]; then
				config_files=$(rpm -ql "${package}" 2>/dev/null | grep "^/etc/" || true)
			fi

			dnf remove -y "${package}" || {
				logger::error "Failed to uninstall ${package}"
				return 1
			}

			# Purge
			if [[ -n "${config_files}" ]]; then
				echo "${config_files}" | while IFS= read -r file; do
					if [[ -f "${file}" || -d "${file}" ]]; then
						rm -rf "${file}" || logger::warning "Failed to remove ${file}"
					fi
				done
			fi

			# autoremove and clean
			dnf autoremove -y || logger::warning "dnf autoremove failed"
			dnf clean all || logger::warning "dnf clean failed"
			;;
		rpm)
			# Fetch config files if configured to purge
			local config_files
			if [[ ${purge} -eq 1 ]]; then
				config_files=$(rpm -ql "${package}" 2>/dev/null | grep "^/etc/" || true)
			fi

			rpm -e "${package}" || {
				logger::error "Failed to uninstall ${package}"
				return 1
			}

			# Purge
			if [[ -n "${config_files}" ]]; then
				echo "${config_files}" | while IFS= read -r file; do
					if [[ -f "${file}" || -d "${file}" ]]; then
						rm -rf "${file}" || logger::warning "Failed to remove ${file}"
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

			yum remove -y "${package}" || {
				logger::error "Failed to uninstall ${package}"
				return 1
			}

			# Purge
			if [[ -n "${config_files}" ]]; then
				echo "${config_files}" | while IFS= read -r file; do
					if [[ -f "${file}" || -d "${file}" ]]; then
						rm -rf "${file}" || logger::warning "Failed to remove ${file}"
					fi
				done
			fi

			yum autoremove -y || logger::warning "yum autoremove failed"
			yum clean all || logger::warning "yum clean failed"
			;;
		pacman)
			if [[ ${purge} -eq 1 ]]; then
				pacman -Rns --noconfirm "${package}" || {
					logger::error "Failed to purge ${package}"
					return 1
				}
			else
				pacman -Rs --noconfirm "${package}" || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi

			# Clean package cache
			if [[ ${purge} -eq 1 ]]; then
				pacman -Sc --noconfirm || logger::warning "pacman cache clean failed"
			fi
			;;
		yay)
			if [[ ${purge} -eq 1 ]]; then
				yay -Rns --noconfirm "${package}" || {
					logger::error "Failed to purge ${package}"
					return 1
				}
			else
				yay -Rs --noconfirm "${package}" || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi

			# Clean cache
			yay -Sc --noconfirm || logger::warning "yay cache clean failed"
			;;
		apk)
			if [[ ${purge} -eq 1 ]]; then
				apk del --purge "${package}" || {
				logger::error "Failed to purge ${package}"
				return 1
			}
			else
				apk del "${package}" || {
					logger::error "Failed to uninstall ${package}"
					return 1
				}
			fi

			# Clean cache
			apk cache clean || logger::warning "apk cache clean failed"
			;;
		snap)
			packaging::_check_snap || return 1

			if [[ ${purge} -eq 1 ]]; then
				snap remove --purge "${package}" || {
					logger::error "Failed to purge snap ${package}"
					return 1
				}
			else
				snap remove "${package}" || {
					logger::error "Failed to uninstall snap ${package}"
					return 1
				}
			fi
			;;
		flatpak)
			packaging::_check_flatpak || return 1

			flatpak uninstall -y "${package}" || {
				logger::error "Failed to uninstall flatpak ${package}"
				return 1
			}

			if [[ ${purge} -eq 1 ]]; then
				flatpak uninstall --delete-data -y "${package}" 2>/dev/null || true

				# Remove unused runtimes and dependencies
				flatpak uninstall --unused --delete-data -y || logger::warning "flatpak cleanup failed"

				# Repair and prune repo
				flatpak repair --user || logger::warning "flatpak repair failed"
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