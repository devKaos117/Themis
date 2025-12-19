#!/bin/bash
#
# Workstation setup and configuration
# Dependencies: logger.sh, sysinfo.sh, packaging.sh

# ============================================================================
# INITIALIZATIONS
# ============================================================================
# ============ Avoid loading the module twice
if [[ "${__WORKSTATION_LOADED__:-0}" -eq 1 ]]; then
	return 0
fi
readonly __WORKSTATION_LOADED__=1

# ============ Safer field splitting
IFS=$'\n\t'

# ============================================================================
# FEDORA
# ============================================================================
# ============ DNF plugins, RPM Fusion, Brave, Microsoft, Docker
fedora::sources() {
	logger::info "Setting up sources"
	# ====== DNF
	packaging::install "dnf-plugins-core"
	sed -i '/^max_parallel_downloads=/c\max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
	echo "fastestmirror=True" >> /etc/dnf/dnf.conf
	echo "defaultyes=True" >> /etc/dnf/dnf.conf
	# ====== RPM Fusion
	if [[ ! -e /etc/yum.repos.d/rpmfusion-free.repo ]]; then packaging::install "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"; fi
	if [[ ! -e /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then packaging::install "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; fi
	dnf config-manager setopt fedora-cisco-openh264.enabled=1
	# ====== Brave
	# https://brave.com/linux/
	if [[ ! -f "/etc/yum.repos.d/brave-browser.repo" ]]; then
		dnf config-manager addrepo --from-repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
	fi
	# ====== Microsoft
	# https://learn.microsoft.com/pt-br/powershell/scripting/install/install-rhel?view=powershell-7.5
	# https://code.visualstudio.com/docs/setup/linux
	packaging::install "https://packages.microsoft.com/config/rhel/$(if [ $SYS_OS_VERSION -lt 8 ]; then echo 7 ; elif [ $SYS_OS_VERSION -lt 9 ]; then echo 8; else echo 9; fi )/packages-microsoft-prod.rpm" "rpm"
	rpm --import https://packages.microsoft.com/keys/microsoft.asc
	echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee /etc/yum.repos.d/vscode.repo > /dev/null
	# ====== Docker
	dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
	# ====== Update
	packaging::update
}

# ============ 
fedora::texlive() {
	return
}

# ============ 
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
		cp "$_SCRIPT_DIR/profiles/.config/alacritty.toml" "$(getent passwd 1000 | cut -d : -f 6)/.config/alacritty/alacritty.toml"
		cp "$_SCRIPT_DIR/profiles/.config/alacritty.toml" "$(getent passwd 0 | cut -d : -f 6)/.config/alacritty/alacritty.toml"
	fi
	if packaging::install btop ; then
		if [[ ! -d "$(getent passwd 1000 | cut -d : -f 6)/.config/btop" ]]; then mkdir "$(getent passwd 1000 | cut -d : -f 6)/.config/btop"; fi
		if [[ ! -d "$(getent passwd 0 | cut -d : -f 6)/.config/btop" ]]; then mkdir "$(getent passwd 0 | cut -d : -f 6)/.config/btop"; fi
		cp "$_SCRIPT_DIR/profiles/.config/btop.conf" "$(getent passwd 1000 | cut -d : -f 6)/.config/btop/btop.conf"
		cp "$_SCRIPT_DIR/profiles/.config/btop.conf" "$(getent passwd 0 | cut -d : -f 6)/.config/btop/btop.conf"
	fi
	packaging::install neovim
	packaging::install bat
	packaging::install tldr
	packaging::install cpufetch
	packaging::install fastfetch
	packaging::install mc
	packaging::install trash-cli
	packaging::install ascii
}

# ============ 
fedora::gaming() {
	packaging::install steam
}

# ============ 
fedora::gpu() {
	dnf swap mesa-va-drivers mesa-va-drivers-freeworld && dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
	dnf copr enable ilyaz/LACT # Check AMD OC
	packaging::install vulkan-tools
	packaging::install radeontop
	packaging::install lact && sudo systemctl enable --now lactd
}

# ============ QEMU/KVM, virt-manager, VirtualBox, Docker
fedora::virt() { 
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
	packaging::install docker-ce
	packaging::install docker-ce-cli
	packaging::install containerd.io
	packaging::install docker-buildx-plugin
	packaging::install docker-compose-plugin
	systemctl enable --now docker
}

# ============================================================================
# KALI
# ============================================================================

# ============================================================================
# ARCH
# ============================================================================

# ============================================================================
# AGNOSTIC
# ============================================================================

all::vpn() {
	sh <(wget -qO - https://downloads.nordcdn.com/apps/linux/install.sh) -p nordvpn-gui
	sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
	usermod -aG nordvpn $USER
}

# ============================================================================
# PUBLIC API
# ============================================================================
chef::list_recipes() {
	list=$(compgen -A function "$SYS_OS::" | cut -d : -f 3)
}