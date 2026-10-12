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
	else
		is_live=0
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
	else
		is_virt=0
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
		cprint "\t{{RED:[!] ERROR:}} The package is not available in current repositories"
		return 1
	}

	# ======== Install
	# Force debian to suppress prompts from the debconf and automatically restart services without asking
	DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${package}" 1> /dev/null || {
		cprint "\t{{RED:[!] ERROR:}} Package installation failed"
		return 1
	}

	# ======== Log and end call
	cprint "\t{{GREEN:[+]}} Package installed"
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
		cprint "\t{{RED:[!] ERROR:}} Failed purging package"
		return 1
	}
	# autoremove and autoclean
	apt autoremove -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoremove}}"
	apt autoclean -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoclean}}"

	# ======== Log and end call
	cprint "\t{{GREEN:[-]}} Package uninstalled"
	return 0
}

# ================ Update system with apt
update() {
	cprint "{{BLUE:[*]}} Updating system packages"

	apt-get update || {
		cprint "\t{{RED:[!] ERROR:}} {{CYAN:apt update}} failed"
		return 1
	}
	# Force debian to suppress prompts from the debconf and automatically restart services without asking
	DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get full-upgrade || {
		cprint "\t{{RED:[!] ERROR:}} {{CYAN:apt full-upgrade}} failed"
		return 1
	}
	apt autoremove -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoremove}}"
	apt autoclean -y 1> /dev/null || cprint "\t{{YELLOW:[!] WARNING:}} Failed during {{CYAN:apt autoclean}}"

	cprint "\t{{GREEN:[+]}} System updated"
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
	if [[ "${SYSINFO[os]}" != "debian" ]]; then
		cprint "{{MAGENTA:[!] CRITICAL:}} This script was designed for Debian"
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
	# ====== Sudo
	adduser "${INVOKER}" sudo
	# ================ Sources and repositories
	cprint "{{BLUE:[*]}} Setting up sources"
	# ====== extrepo
	install extrepo
	# ====== Brave
	# https://brave.com/linux/
	curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg && curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
	# ====== LibreWolf
	# https://librewolf.net/
	extrepo enable librewolf && sudo extrepo update librewolf
	# ====== Microsoft
	# https://learn.microsoft.com/pt-br/powershell/scripting/install/install-debian?view=powershell-7.5
	wget -q "https://packages.microsoft.com/config/debian/${SYSINFO[version]}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb && dpkg -i /tmp/packages-microsoft-prod.deb && rm /tmp/packages-microsoft-prod.deb
	# ====== Docker
	# https://docs.docker.com/desktop/setup/install/linux/debian/
	if [[ ! -f /etc/apt/sources.list.d/docker.sources ]]; then curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && chmod a+r /etc/apt/keyrings/docker.asc && echo -e "Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: ${SYSINFO[codename]}\nComponents: stable\nArchitectures: $(dpkg --print-architecture)\nSigned-By: /etc/apt/keyrings/docker.asc" > /etc/apt/sources.list.d/docker.sources ; fi
	# ====== Flatpak
	install flatpak
	flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 1> /dev/null || cprint "\t{{YELLOW:[!] Warning:}} Failed to add Flathub remote"
	# ====== Snapcraft
	install snapd && snap install snapd
	# ====== Update
	update
	# ================ CLI
	cprint "{{BLUE:[*]}} Setting CLI tools"
	# ====== Shell
	if install "zsh"; then
		chsh -s "/bin/zsh" $INVOKER
		chsh -s "/bin/zsh" $(id -nu 0)
		if curl -sSf "https://raw.githubusercontent.com/devKaos117/Themis/refs/heads/main/files/zshrc" -o /tmp/zshrc; then
			sudo -u "${INVOKER}" cp "/tmp/zshrc" "${INVOKER_HOME}/.zshrc" || cprint "\t{{YELLOW:[!] Warning:}} Failed to set up user .zshrc"
			cp "/tmp/zshrc" "${ROOT_HOME}/.zshrc" || cprint "\t{{YELLOW:[!] Warning:}} Failed to set up root .zshrc"
			rm /tmp/zshrc
		else
			cprint "\t{{RED:[!] ERROR:}} Failed to download .zshrc"
		fi
	fi
	install "zsh-autosuggestions"
	install "zsh-syntax-highlighting"
	# ====== Terminal
	if install alacritty ; then
		mkdir -p "${INVOKER_HOME}/.config/alacritty"
		mkdir -p "${ROOT_HOME}/.config/alacritty"
		if curl -sSf "https://raw.githubusercontent.com/devKaos117/Themis/refs/heads/main/files/alacritty.toml" -o /tmp/alacritty.toml; then
			cp "/tmp/alacritty.toml" "${INVOKER_HOME}/.config/alacritty/alacritty.toml" || cprint "\t{{YELLOW:[!] Warning:}} Failed to set up user alacritty.toml"
			cp "/tmp/alacritty.toml" "${ROOT_HOME}/.config/alacritty/alacritty.toml" || cprint "\t{{YELLOW:[!] Warning:}} Failed to set up root alacritty.toml"
			rm /tmp/alacritty.toml
		else
			cprint "\t{{RED:[!] ERROR:}} Failed to download alacritty.toml"
		fi
	fi
	# tmux
	# ====== Tools
	install "neovim"
	install "bat"
	install "tldr"
	install "mc"
	install "ascii"
	install "asciinema"
	install "xxd"
	# ================ Platform
	cprint "{{BLUE:[*]}} Setting platform tools"
	# ====== Monitoring
	if install btop ; then
		mkdir -p "${INVOKER_HOME}/.config/btop"
		mkdir -p "${ROOT_HOME}/.config/btop"
		if curl -sSf "https://raw.githubusercontent.com/devKaos117/Themis/refs/heads/main/files/btop.conf" -o /tmp/btop.conf; then
			cp "/tmp/btop.conf" "${INVOKER_HOME}/.config/btop/btop.conf" || cprint "\t{{YELLOW:[!] Warning:}} Failed to set up user btop.conf"
			cp "/tmp/btop.conf" "${ROOT_HOME}/.config/btop/btop.conf" || cprint "\t{{YELLOW:[!] Warning:}} Failed to set up root btop.conf"
			rm /tmp/btop.conf
		else
			cprint "\t{{RED:[!] ERROR:}} Failed to download btop.conf"
		fi
	fi
	# ====== Information
	install cpufetch
	install fastfetch
	# ====== Managing
	install trash-cli
	install rclone
	install openrgb
	# ====== Smartcards and token suport
	install opensc
	install pcscd
	install pcsc-tools
	install vsmartcard-vpcd
	# ====== GPU
	if [[ ${SYSINFO[is_virt]} == 0 ]]; then
		cprint "{{BLUE:[*]}} Setting GPU"
		# https://github.com/ilya-zlobintsev/LACT
		# Intel
		# AMD
		install rocm
		install rocm-core
		install rocm-llvm
		install rocminfo
		install rocm-docs-core
		install vulkan
		install vulkan-tools
		install radeontool
		install radeontop
		# NVIDIA
	fi
	# ====== Sound
	install ffmpeg
	# ================ Networking
	cprint "{{BLUE:[*]}} Setting networking tools"
	# ====== Tools
	install netcat-openbsd
	install hping3
	# ====== Monitoring
	install mtr
	# install smokeping
	# ====== VPN
	install wireguard
	install openvpn
	install tor && systemctl enable --now tor 1> /dev/null
	# NordVPN
	sh <(curl -sSf "https://downloads.nordcdn.com/apps/linux/install.sh") -n || cprint "\t{{RED:[!] ERROR:}} Failed to install NordVPN CLI"
	sh <(curl -sSf "https://downloads.nordcdn.com/apps/linux/install.sh") -p nordvpn-gui -n || cprint "\t{{RED:[!] ERROR:}} Failed to install NordVPN GUI"
	usermod -aG nordvpn $(id -nu 1000)
	# Proton
	install proton-vpn-cli
	# ====== Kerberos
	install cntlm
	install krb5-*
	# ====== Time
	install ntpdate
	install chronyd
	# ====== Torrent
	install qbittorrent
	install qbittorrent-cli
	# LAN transfering
	flatpak install flathub org.localsend.localsend_app
	# ================ Development tools
	cprint "{{BLUE:[*]}} Setting development tools"
	# ====== Languages
	install gcc
	sudo -u "${INVOKER}" bash <(curl -sSf https://sh.rustup.rs) -y || cprint "\t{{RED:[!] ERROR:}} Failed to install rust"
	install golang-go
	install golang-src
	install python3
	install powershell
	sh <(curl -fsSL "https://d2lang.com/install.sh") || cprint "\t{{RED:[!] ERROR:}} Failed to install D2"
	# TexLive
	install latexmk
	# tlmgr install lastpage fancyhdr multirow enumitem mathtools amsfonts hyperref titlesec tkz-euclide
	install texlive-latex-base
	install texlive-latex-recommended
	install texlive-latex-extra
	install texlive-science
	# ====== Tools
	if install git ; then
		sudo -u "${INVOKER}" git config --global init.defaultBranch main
		sudo -u "${INVOKER}" git config --global user.name "kaos"
		sudo -u "${INVOKER}" git config --global user.email "gustavo.s.aragao.2003@gmail.com"
	else
		cprint "\t{{RED:[!] ERROR:}} Failed to install git"
	fi
	install gh
	install just
	install cmake
	install jq
	# ================ Virtualization
	cprint "{{BLUE:[*]}} Setting virtualization tools"
	# ====== VMWare
	# ====== Docker
	# docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	install docker.io
	install docker-compose
	install docker-cli
	install docker-buildx
	install docker-clean
	install docker-doc
	systemctl enable --now docker
	# ====== Wine
	# ================ General
	cprint "{{BLUE:[*]}} Setting general tools"
	# ====== Browsers
	install lynx
	install chromium
	install brave-browser
	install firefox-esr
	install librewolf
	install torbrowser-launcher
	if [[ ! -f "${INVOKER_HOME}/Documents/bookmarks.html" ]]; then curl -sSf "https://raw.githubusercontent.com/devKaos117/Themis/refs/heads/main/files/bookmarks.html" -o "${INVOKER_HOME}/Documents/bookmarks.html" || cprint "\t{{RED:[!] ERROR:}} Failed to download bookmarks.html"; fi
	# ====== Media
	install vlc
	install gimp
	install v4l-utils
	install guvcview
	install libreoffice
	install qpdf
	# ====== Others
	flatpak install flathub md.obsidian.Obsidian
	flatpak install flathub com.discordapp.Discord
	# ====== Tools
	install 7zip
	install flameshot
	# ================ Security
	# ====== Networking
	install nmap
	install wireshark
	install tcpdump
	# ====== Hash cracking
	# hashcat
	# john
	# ====== Wordlists
	install cupp
	install seclists
	# ====== Hardening
	install debsecan
	install auditd
	install audispd-plugins
	install ssh-audit
	# https://github.com/netblue30/firejail
	# https://github.com/CISOfy/lynis
	# https://github.com/ossec/ossec-hids
	# https://www.snort.org/