loadkeys br-abnt2
setfont ter-112n
case cat /sys/firmware/efi/fw_platform_size in
  64) ARCH="x64" ;;
  32) ARCH="x32" ;;
  *) ARCH="CSM" ;;
esac

timedatectl set-timezone America/Sao_Paulo

if ping -c 1 -W 2 8.8.8.8 &> /dev/null || ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
	NETWORK=1
else
	NETWORK=0
fi

# connect to internet

# Select disk to install, or perform manual partitioning