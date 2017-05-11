#!/bin/bash -e

# Get the required tools and headers to build the kernel
sudo apt-get install linux-headers-$(uname -r) build-essential git

if [ $(ls /dev/video* | wc -l) -ne 0 ];
then
	echo -e "\e[32m"
	read -p "First, remove all RealSense cameras attached. Hit any key when ready"
	echo -e "\e[0m"
fi

#Include usability functions
source ./scripts/patch-utils.sh

#Additional packages to build patch
require_package libusb-1.0-0-dev
require_package libssl-dev

KERNEL_DIRNAME="linux-$(uname -r | cut -d '-' -f 1)"
if [ ! -d $KERNEL_DIRNAME ]; then
    source /etc/lsb-release
    RELEASE=$DISTRIB_CODENAME
	echo -e "\e[36mEnabling sources in /etc/apt/sources.list\e[0m"
    sudo sh -c "echo \"deb-src http://us.archive.ubuntu.com/ubuntu/ $RELEASE main restricted\" >> /etc/apt/sources.list"
    sudo apt-get update
	echo -e "\e[36mDownloading Linux source code\e[0m"
    apt-get source linux-image-$(uname -r)
fi
cd $KERNEL_DIRNAME

#Check if we need to apply patches or get reload stock drivers (Developers' option)
[ "$#" -ne 0 -a "$1" == "reset" ] && reset_driver=1 || reset_driver=0

if [ $reset_driver -eq 1 ];
then 
	echo -e "\e[43mUser requested to rebuild and reinstall ubuntu stock uvcvideo driver\e[0m"
else
	#Patching kernel for RealSense devices
    MAJOR=$(uname -r| cut -d '.' -f 1)
    MINOR=$(uname -r| cut -d '.' -f 2)
    if [ $MAJOR != "4" ]; then
        echo -e "\e[36mSorry, but only kernel version 4 is supported.\e[0m"
        exit 1
    fi
    if [ $MINOR -le 2 ]; then
        echo -e "\e[36mSorry, but only kernel version > 4.2 is supported.\e[0m"
    fi
	echo -e "\e[32mApplying uvcvideo patch\e[0m"
	patch -p1 < ../"$( dirname "$0" )"/uvcvideo-$MAJOR.$MINOR.patch
fi

# Copy configuration
sudo cp /usr/src/linux-headers-$(uname -r)/.config .
sudo cp /usr/src/linux-headers-$(uname -r)/Module.symvers .

# Basic build so we can build just the uvcvideo module
#yes "" | make silentoldconfig modules_prepare
make silentoldconfig prepare modules_prepare scripts

# Build the uvc, accel and gyro modules
KERNEL_PATH=`pwd`
cd drivers/media/usb/uvc
sudo cp $KERNEL_PATH/Module.symvers .
echo -e "\e[32mCompiling uvc module\e[0m"
sudo make -C $KERNEL_PATH M=$KERNEL_PATH/drivers/media/usb/uvc/ modules

echo -e "\e[32mPatched kernel module created successfully\n\e[0m"

# Load the newly built module(s)
try_module_insert uvcvideo $KERNEL_PATH/drivers/media/usb/uvc/uvcvideo.ko /lib/modules/`uname -r`/kernel/drivers/media/usb/uvc/uvcvideo.ko

echo -e "\e[92m\n\e[1mScript has completed successfully. Please consult the installation guide for further instruction.\n\e[0m"
