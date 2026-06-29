#!/bin/bash

set -euo pipefail	# Exit on error, undefined vars, pipe failures
IFS=$'\n\t'			# Safer field splitting

TIMEFORMAT=$'\033[1;92m[*]\033[1;37m Execution time: %2lR\033[0m'

# ============================================================================
# UTILITIES
# ============================================================================
# ================ Custom colored output
cprint() {
	# ======== Initializations
	local msg="$1"
	local default_color="\033[1;37m" # Bright White
	local reset="\033[0m"
	local pattern='(.*)[{][{]([A-Za-z]+):([^}]+)[}][}](.*)'
	# ======== Build text
	while [[ "$msg" =~ $pattern ]]; do
		local prefix="${BASH_REMATCH[1]}"
		local color="${BASH_REMATCH[2]}"
		local text="${BASH_REMATCH[3]}"
		local suffix="${BASH_REMATCH[4]}"
		# Coloring
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
		# Assemble
		msg="${prefix}${ansi_color}${text}${reset}${default_color}${suffix}"
	done
	# ======== Print text
	echo -e "${default_color}${msg}${reset}"
}

# ================ Assert the availability of a command
has_cmd() {
	command -v ${1} &> /dev/null
}

# ================ Fetch current system information
fetch_sysinfo() {
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

	cprint "{{BLUE:[*]}} Fetching system information"

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
			cprint "\t{{BLUE:[+]}} Virtual environment detected: $(systemd-detect-virt)"
		fi
	elif [[ -f /sys/class/dmi/id/product_name ]]; then
		local product_name
		product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
		if [[ "$product_name" =~ (VirtualBox|VMware|KVM|QEMU) ]]; then
			is_virt=1
			cprint "\t{{BLUE:[+]}} Virtual environment detected: $product_name"
		fi
	elif [[ -f /.dockerenv ]] || \
		grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
		is_virt=1
		cprint "\t{{BLUE:[+]}} Containerized environment detected"
	fi

	# ======== Build array
	declare -g -A SYSINFO=(
		["os"]="${os_id}"
		["upstream"]="${os_upstream}"
		["version"]="${os_version}"
		["codename"]="${os_codename}"
		["kernel"]="${kernel}"
		["arch"]="${arch}"
		["init"]="${init_system}"
		["is_live"]="${is_live}"
		["is_virt"]="${is_virt}"
	)
}

# ================ Prompt for a new password
get_new_password() {
	# ======== Initializations
	local pass1
	local pass2
	# ======== Prompt for password and confirmation
	read -rs -p "	Enter the new password: " pass1
	echo "" >&2

	read -rs -p "	Confirm the new password: " pass2
	echo "" >&2

	# ======== Verifications
	if [[ -z "${pass1}" ]]; then # Password is empty
		cprint "\t{{RED:[!] ERROR:}} Password cannot be empty, try again" >&2
		echo "" >&2
		get_new_password # Recursive call
		return
	fi

	if [[ "${pass1}" != "${pass2}" ]]; then # Passwords are different
		cprint "\t{{RED:[!] ERROR:}} Passwords do not match, try again" >&2
		echo "" >&2
		get_new_password # Recursive call
		return
	fi

	# ======== Return the password
	printf "%s\n" "${pass1}"
}

# ================
regenSSH() {
	# ====== Initializations
	local ROOT_SSH=false

	cprint "{{BLUE:[*]}} Regenerating SSH"

	# Check if Root SSH login is enabled
	if grep -qE "^\s*PermitRootLogin\s+yes" /etc/ssh/sshd_config; then
		cprint "{{YELLOW:[!]}} Root SSH login is currently enabled"
		ROOT_SSH=true
	fi

	# ====== Machine Host Keys
	cprint "\t{{BLUE:[*]}} Host keys"
	rm -f /etc/ssh/ssh_host_*
	DEBIAN_FRONTEND=noninteractive dpkg-reconfigure openssh-server && systemctl restart ssh

	# ====== User Keys
	cprint "\t{{BLUE:[*]}} ${INVOKER} keys"
	# Ensure .ssh directory permissions
	mkdir -p "${INVOKER_HOME}/.ssh"
	chmod 700 "${INVOKER_HOME}/.ssh"

	# Generate pair of ED25519 keys
	ssh-keygen -t ed25519 -N "" -f "${INVOKER_HOME}/.ssh/id_ed25519" -C "regenSSH" -q

	# Fix ownership
	chown -R "${INVOKER}:${INVOKER}" "${INVOKER_HOME}/.ssh"

	# ====== Root Keys
	cprint "\t{{BLUE:[*]}} Root keys"
	# Ensure .ssh directory permissions
	mkdir -p "${ROOT_HOME}/.ssh"
	chmod 700 "${ROOT_HOME}/.ssh"

	# Generate pair of ED25519 keys
	ssh-keygen -t ed25519 -N "" -f "${ROOT_HOME}/.ssh/id_ed25519" -C "regenSSH" -q

	# Fix ownership
	chown -R "0:0" "${ROOT_HOME}/.ssh"
}

# ================ Install a package with apt
install() {
	# ======== Initializations
	local package="$1"

	cprint "{{BLUE:[*]}} Installing {{CYAN:${package}}}"

	# ======== Verifications
	dpkg -l "${package}" 2>/dev/null | grep -q "^ii" && { # Already installed
		cprint "\t{{GREEN:[+]}} Package already installed"
		return 0
	}

	apt show "${package}" &>/dev/null || { # Not found in apt
		cprint "\t{{RED:[!] ERROR:}} {{CYAN:${package}}} is not available in current repositories"
		return 1
	}

	# ======== Install
	apt install -y "${package}" 1> /dev/null || {
		cprint "\t{{RED:[!] ERROR:}} Failed installing {{CYAN:${package}}}"
		return 1
	}

	# ======== Log and end call
	cprint "\t{{GREEN:[+]}} Successfully installed {{CYAN:${package}}}"
	return 0
}

# ================ Uninstall and purge a package
uninstall() {
	# ======== Initializations
	local package="$1"

	cprint "{{BLUE:[*]}} Uninstalling {{CYAN:${package}}}"

	# ======== Verifications
	dpkg -l "${package}" 2>/dev/null | grep -q "^ii" || { # Not installed
		cprint "\t{{GREEN:[-]}} Package not found"
		return 0
	}

	# ======== Uninstall
	apt purge -y "${package}" 1> /dev/null || {
		cprint "\t{{RED:[!] ERROR:}} Failed purging {{CYAN:${package}}}"
		return 1
	}
	# autoremove and autoclean
	apt autoremove -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoremove}}"
	apt autoclean -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoclean}}"

	# ======== Log and end call
	cprint "\t{{GREEN:[-]}} Successfully uninstalled ${package}"
	return 0
}

# ================ Update system with apt
update() {
	cprint "{{BLUE:[*]}} Updating system packages"

	apt update || {
		cprint "\t{{RED:[!] ERROR:}} {{CYAN:apt update}} failed"
		return 1
	}
	apt full-upgrade -y || {
		cprint "\t{{RED:[!] ERROR:}} {{CYAN:apt full-upgrade}} failed"
		return 1
	}
	apt autoremove -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoremove}}"
	apt autoclean -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoclean}}"

	cprint "\t{{GREEN:[+]}} System updated"
}

# ================ Wrapper function execute xfconf-query
set_user_xfconf() {
	local channel="$1"
	local prop="$2"
	local type="$3"
	local val="$4"
	sudo -u "${INVOKER}" dbus-run-session xfconf-query -c "${channel}" -p "${prop}" -n -t "${type}" -s "${val}" || cprint "\t{{RED:ERROR:}} Failed setting xfce4: ${channel} ${prop}"
}

# ============================================================================
# INITIALIZATIONS
# ============================================================================
time {
	# ======== Requirements
	# Execution call
	if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
		cprint "{{MAGENTA:[!] CRITICAL:}} This script requires direct execution"
		exit 1
	fi
	# Tools
	# Network
	if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null && ! ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
		cprint "{{MAGENTA:[!] CRITICAL:}} This script requires internet connection"
		exit 1
	fi
	# Root
	if [[ $EUID -ne 0 ]]; then
		cprint "{{MAGENTA:[!] CRITICAL:}} This script requires elevated privileges"
		exit 1
	fi
	# OS
	fetch_sysinfo
	if [[ "${SYSINFO[os]}" != "kali" ]]; then
		cprint "{{MAGENTA:[!] CRITICAL:}} This script was designed for Kali Linux"
		exit 1
	fi
	# ======== User information
	declare -r INVOKER="${SUDO_USER:-$(getent passwd 1000 | cut -d : -f 1)}" # Fallback to UID 1000 if SUDO_USER isn't set
	declare -r INVOKER_HOME=$(getent passwd "${INVOKER}" | cut -d : -f 6)
	declare -r ROOT_HOME=$(getent passwd 0 | cut -d : -f 6)

	if [[ ! -d "${INVOKER_HOME}" ]]; then
		cprint "{{MAGENTA:[!] CRITICAL:}} Failed to find invoking home directory"
	elif [[ ! -d "${ROOT_HOME}" ]]; then
		cprint "{{MAGENTA:[!] CRITICAL:}} Failed to find root home directory"
	fi

# ============================================================================
# MAIN
# ============================================================================
	# ================ Security concerns
	# ======== Change password
	if [[ $"{SYSINFO[is_live]}" == 0 ]]; then
		cprint "{{BLUE:[*]}} Requesting new password"
		new_password=$(get_new_password)
		echo "${INVOKER}:${new_password}" | chpasswd
		unset new_password
	fi
	# ======== Sudoers
	cprint "{{BLUE:[*]}} Altering /etc/sudoers"
	sed -i.bak 's/%sudo.*ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD:ALL/' /etc/sudoers && visudo -c
	# ======== Force a new machine-id generation
	cprint "{{BLUE:[*]}} Forcing new machine-id generation"
	truncate -s 0 /etc/machine-id
	truncate -s 0 /var/lib/dbus/machine-id
	# ======== Generate new SSH keys
	regenSSH

	# ================ Creating custom dirs
	mkdir -p "${INVOKER_HOME}"/tools

	# ================ Sources and repositories
	cprint "{{BLUE:[*]}} Setting up sources"
	# ====== Debian
	echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list.d/debian.list
	printf "Package: *\nPin: release o=Debian\nPin-Priority: 100\n" > /etc/apt/preferences.d/debian
	# ====== Update
	update

	# ================ Installing tools
	cprint "{{BLUE:[*]}} Installing {{CYAN:kali-linux-everything}}"
	install "kali-linux-everything"
	# ======== CLI
	cprint "{{BLUE:[*]}} Setting CLI tools"
	# Shell
	if install "zsh"; then
		chsh -s "/bin/zsh" $INVOKER
		chsh -s "/bin/zsh" $(id -nu 0)
		if curl -sSf "https://raw.githubusercontent.com/devKaos117/Themis/refs/heads/main/files/zshrc" -o /tmp/zshrc; then
			cp "/tmp/zshrc" "${INVOKER_HOME}/.zshrc" || cprint "\t{{YELLOW:[!]}} Failed to set up user .zshrc"
			cp "/tmp/zshrc" "${ROOT_HOME}/.zshrc" || cprint "\t{{YELLOW:[!]}} Failed to set up root .zshrc"
			rm /tmp/zshrc
		else
			cprint "\t{{RED:[!] ERROR:}} Failed to download .zshrc"
		fi
	fi
	install "zsh-autosuggestions"
	install "zsh-syntax-highlighting"
	# Tools
	install "neovim"
	install "bat"
	install "tldr"
	install "mc"
	install "ascii"
	install "asciinema"
	install "xxd"
	# ======== Platform
	cprint "{{BLUE:[*]}} Setting platform tools"
	# ====== Monitoring
	# ====== Information
	install cpufetch
	install fastfetch
	# ======== Networking
	cprint "{{BLUE:[*]}} Setting networking tools"
	# ====== VPN
	install wireguard
	install wireguard-tools
	install openvpn
	install python3-proton-vpn-cli
	install tor && systemctl enable --now tor 1> /dev/null
	# ======== Development tools
	cprint "{{BLUE:[*]}} Setting development tools"
	# ====== Git
	install git && git config --global init.defaultBranch main
	# ====== Languages
	install gcc
	install rust
	install golang-go
	install golang-src
	install python3
	install powershell
	# ======= GPU
	if [[ ${SYSINFO[is_virt]} == 0 ]]; then
		cprint "{{BLUE:[*]}} Setting GPU"
		# Intel
		# AMD
		# NVIDIA
	fi
	# ======= Virtualization
	cprint "{{BLUE:[*]}} Setting virtualization tools"
	# Docker
	install docker.io
	install docker-compose
	install docker-cli
	install docker-buildx
	install docker-clean
	install docker-doc
	systemctl enable --now docker
	# Wine
	# ======= General
	cprint "{{BLUE:[*]}} Setting general tools"
	# Browsers
	install firefox
	install chromium
	install lynx
	# Tools
	install 7zip
	# ======= Security
	cprint "{{BLUE:[*]}} Setting security tools"
	# osint
	# reconnaissance
	install feroxbuster
	install photon
	install gospider
	CGO_ENABLED=1 go install github.com/projectdiscovery/katana/cmd/katana@latest && "${INVOKER_HOME}"/go/bin/katana --version || cprint "\t{{RED:[!]}} Failed to install katana"
	# assessment
	install zaproxy
	# execution
	# access
	install cupp
	install seclists
	# ====== maneuver
	install proxychains-ng
	install ligolo-ng
	install chisel
	install chisel-common-binaries
	# reporting
	install flameshot
	# ================ Tweaking xfce4
	cprint "{{BLUE:[*]}} Tweaking xfce4 tools"
	# load panel
	if curl -sSf "https://raw.githubusercontent.com/devKaos117/Themis/refs/heads/main/files/Kaos_KaliPanel.tar.bz2" -o /tmp/Kaos_KaliPanel.tar.bz2; then
		sudo -u "${INVOKER}" dbus-run-session xfce4-panel-profiles load /tmp/Kaos_KaliPanel.tar.bz2 || cprint "\t{{RED:ERROR:}} Failed setting xfce4 panel" && rm /tmp/Kaos_KaliPanel.tar.bz2
	fi
	# alter workspace count
	set_user_xfconf "xfwm4" "/general/workspace_count" "int" 2
	# disable screensaver
	set_user_xfconf "xfce4-screensaver" "/saver/enabled" "bool" false
	set_user_xfconf "xfce4-screensaver" "/lock-screen/enabled" "bool" false
	# disable power management
	set_user_xfconf "xfce4-power-manager" "/xfce4-power-manager/blank-on-ac" "int" 0
	set_user_xfconf "xfce4-power-manager" "/xfce4-power-manager/dpms-on-ac-sleep" "int" 0
	set_user_xfconf "xfce4-power-manager" "/xfce4-power-manager/dpms-on-ac-off" "int" 0
	set_user_xfconf "xfce4-power-manager" "/xfce4-power-manager/lock-screen-suspend-hibernate" "bool" false
	# disable lock screen
	set_user_xfconf "xfce4-session" "/general/LockCommand" "string" ""
	# keyboard layout
	localectl -layout br -variant abnt2
	set_user_xfconf "keyboard-layout" "/Default/XkbLayout" "string" "br"
	# ================ Done
	cprint "{{GREEN:[*]}} Done"
}