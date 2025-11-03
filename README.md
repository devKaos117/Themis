# Themis ![v0](https://img.shields.io/badge/version-0-informational)
<a href="https://github.com/devKaos117/Themis/blob/main/LICENSE" target="_blank">![Static Badge](https://img.shields.io/badge/License-%23FFFFFF?style=flat&label=MIT&labelColor=%23000000&color=%23333333&link=https%3A%2F%2Fwww.github.com%2FdevKaos117%2FThemis%2Fblob%2Fmain%2FLICENSE)</a>
## Index

-	[About](#about)
	-	[Summary](#about-summary)
	-	[Features](#about-features)
- [Usage](#usage)
	-	[Setup](#usage-installation)
-	[Technical Description](#technical-description)
	-	[Applied Technologies](#technical-description-techs)

---

## About <a name = "about"></a>

### Summary <a name = "about-summary"></a>
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus placerat massa vitae orci gravida, in porttitor.

uname to differ from offsec to personal env (kali or fedora/arch)

update

zsh -> zsh-autosuggestions zsh-syntax-highlighting
alacritty*

vscode*
git # git config --global init.defaultBranch master, git config --global user.name, git config --global user.email
gcc
rust
python3

neovim
bat
tldr
cpufetch
fastfetch

flatpak
snapd

bpytop
rclone

brave*
discord
obsidian
gimp
vlc
ranger
trash-cli
LibreOffice
qbittorrent
7z
libavcodec-freeworld
openrgb -> Effects plugin

texlive-all -> (minify) latexmk pdflatex texlive-lastpage texlive-fancyhdr texlive-multirow texlive-enumitem texlive-mathtools texlive-amsfonts texlive-hyperref texlive-titlesec texlive-tkz-euclide


*virt*
virtualbox

sudo dnf install qemu-kvm libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools libosinfo tuned

for drv in qemu interface network nodedev nwfilter secret storage; do \
	sudo systemctl enable virt${drv}d.service; \
	sudo systemctl enable virt${drv}d{,-ro,-admin}.socket; \
done

sudo virt-host-validate qemu

virt-v2v -> OVA to QCOW2



/etc/sudoers
/etc/fstab

check for fedora RPM Fusion
Nvidia or AMD GPU and drivers
Show errors and warnings

xfce panel profile
desktop and workspace
keyboard and keyboard shortcurts
home custom dirs
numpad and touchpad
energy settings
keep awake mode (for long processes)
kali tweaks

openRGB

install i2c-tools
modprobe i2c-piix4
echo "i2c-piix4" | sudo tee /etc/modules-load.d/i2c-piix4.conf
echo "i2c-i801"

/etc/udev/rules.d/60-openrgb.rules
/usr/lib/udev/rules.d/60-openrgb.rules

sudo udevadm control --reload-rules
sudo udevadm trigger

/etc/systemd/system/openrgb.service
systemctl enable openrgb.service

sudo useradd --system -g i2c -s /sbin/nologin -c "OpenRGB Service User" --no-create-home openrgb

sudo mkdir -p /etc/openrgb
sudo chown -R openrgb:i2c /etc/openrgb


sudo usermod -aG i2c kaos

### Features <a name = "about-features"></a>

- **Lorem ipsum**
	- dolor sit amet
	- consectetur adipiscing elit

- **Phasellus placerat massa**
	- vitae orci gravida

---

## Usage <a name = "usage"></a>

### Setup <a name = "usage-installation"></a>
Lorem ipsum dolor sit amet

```txt
Themis/
├── lib/
│	├── logger.sh
│	└── sysinfo.sh
├── log/
│	└── yyyy-MM-ddThh-mm-ss.log
├── profiles/
│	└── <...>
├── themes/
│	└── <...>
├── LICENSE
├── README.md
└── start.sh
```

---

## Technical Description <a name = "technical-description"></a>

### Applied Technologies <a name = "technical-description-techs"></a>

#### Development Environment
&emsp;&emsp;<a href="https://fedoraproject.org/">![Static Badge](https://img.shields.io/badge/v42-%23FFFFFF?style=flat&logo=fedora&logoColor=%1793D1&logoSize=auto&label=Fedora&labelColor=%23000000&color=%23333333&link=https%3A%2F%2Fwww.fedoraproject.org)</a>
<br>
&emsp;&emsp;<a href="https://www.zsh.org" target="_blank">![Static Badge](https://img.shields.io/badge/v5.9-%23FFFFFF?style=flat&logo=zsh&logoColor=%23F15A24&logoSize=auto&label=zsh&labelColor=%23000000&color=%23333333&link=https%3A%2F%2Fwww.zsh.org)</a>
<br>
&emsp;&emsp;<a href="https://code.visualstudio.com" target="_blank">![Static Badge](https://img.shields.io/badge/v1.104.3-%23FFFFFF?style=flat&logo=codecrafters&logoColor=%230065A9&logoSize=auto&label=VS%20Code&labelColor=%23000000&color=%23333333&link=https%3A%2F%2Fcode.visualstudio.com)</a>


#### Application Components
&emsp;&emsp;<a href="https://www.github.com/devKaos117" target="_blank">![Static Badge](https://img.shields.io/badge/vXX-%23FFFFFF?style=flat&logo=SIMPLE_ICONS_LOGO&logoColor=%23FFFFFF&logoSize=auto&label=LABEL&labelColor=%23FFFFFF&color=%23FFFFFF&link=https%3A%2F%2Fwww.github.com%2FdevKaos117)</a>