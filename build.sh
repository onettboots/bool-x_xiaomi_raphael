#!/bin/bash 

kernel_dir="${PWD}"
rm .version
rm build.log
# Bash Color
green='\033[01;32m'
red='\033[01;31m'
blink_red='\033[05;31m'
restore='\033[0m'

clear

# Resources
export LC_ALL=C && export USE_CCACHE=1
ccache -M 10G
export SUBARCH=arm64
export ARCH=arm64
export CLANG_PATH="$HOME/toolchains/boolx-clang/bin"
export PATH=${CLANG_PATH}:${PATH}
export CLANG_TRIPLE=${CLANG_PATH}/aarch64-linux-gnu-
export CROSS_COMPILE=${CLANG_PATH}/aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=${CLANG_PATH}/arm-linux-gnueabi-
# export DTC_EXT=dtc # we don needed it again
export CC=$HOME/toolchains/boolx-clang/bin/clang
CLANG_DIR="$HOME/toolchains/boolx-clang"
CLANG="${CLANG_DIR}/bin:$PATH"
CLANG_BIN="${CLANG}/bin/"
TARGET_IMAGE="Image.gz-dtb"
cpus=`expr $(nproc --all)`
objdir="${kernel_dir}/out"
CONFIGS="raphael_defconfig"

VER="V2.3-Parvez-DSP"
KERNEL_DIR=`pwd`
REPACK_DIR=$HOME/AnyKernel3
ZIP_MOVE=$HOME/Boolx
BASE_AK_VER="Bool-X-Raphael-"
DATE=`date +"%Y%m%d-%H%M"`
AK_VER="$BASE_AK_VER$VER"
ZIP_NAME="$AK_VER"-"$DATE"
TOOLCHAINS=$HOME/toolchains/boolx-clang
SAVEHERE=$HOME/toolchains
CONFIG=out/.config
KERNEL=out/arch/arm64/boot/Image.gz-dtb
DTBO=out/arch/arm64/boot/dtbo.img
upl=$kernel_dir/upl.sh
export THINLTO_CACHE_PATH=$SAVEHERE/thincache
KER_VER=$(grep -oP '(?<=VERSION = )\d+|(?<=PATCHLEVEL = )\d+|(?<=SUBLEVEL = )\d+' Makefile | paste -sd '.')
KSU_VER=$(cat drivers/kernelsu/kernel/dksu 2>/dev/null || echo "Disabled")
SUSFS_VER=$(grep -oP '(?<=#define SUSFS_VERSION ")[^"]*' include/linux/susfs.h 2>/dev/null || echo "Disabled")
OCDS=$(grep -qP "timing@1\s*{" arch/arm64/boot/dts/qcom/dsi-panel-ss-fhd-ea8076-cmd.dtsi && echo "OCD" || echo "Non OCD")
export THINLTO_CACHE_DIR=$HOME/toolchains/thincache

#functions
function makeconfig() {
                PATH=${CLANG_BIN}:${PATH} \
                make -s -j${cpus} \
                LLVM=1 \
                LLVM_IAS=1 \
                CC="ccache clang" \
                CROSS_COMPILE="aarch64-linux-gnu-" \
                CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
                O="${objdir}" ${1}
}

function build() {
		PATH=${CLANG_BIN}:${PATH} \
		make -s -j${cpus} \
		LLVM=1 \
		LLVM_IAS=1 \
		CC="ccache clang" \
		CROSS_COMPILE="aarch64-linux-gnu-" \
		CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
		O="${objdir}" ${1} \
		KBUILD_BUILD_USER="OnettBoots" \
		KBUILD_BUILD_HOST="OpenELA" \
		dtbo.img
}

function create_out {
		echo
		git clone https://github.com/onettboots/boolx_anykernel.git $REPACK_DIR && mkdir $ZIP_MOVE
}
function clean_all {
		echo
		echo -e "${red}Cleaning Kernel Projects .... ${restore}"
		cd ${kernel_dir}
		make -s clean
		make -s -j${cpus} mrproper O=${objdir}
		rm -rf out
}
function make_config {
		echo
		makeconfig ${CONFIGS}
}
function make_boot {
		cp $KERNEL $REPACK_DIR && cp $DTBO $REPACK_DIR
}
function make_zip {
		cd $REPACK_DIR
		zip -r9 `echo $ZIP_NAME`.zip *
		mv  `echo $ZIP_NAME`*.zip $ZIP_MOVE
		cd $KERNEL_DIR
}

function upload()
{
curl bashupload.com -T $ZIP_NAME*.zip
}

function upload_boolx_action()
{
                ziped=$ZIP_MOVE/`echo $ZIP_NAME`.zip
		cd $kernel_dir
		#wget
		chmod +x $upl
		sed -i "4i\FILE_PATH=$ziped" $upl
		BUILDDATE=`date +"%Y-%m-%d"`
		sed -i '5i\CAPTION="* Build Date: '$BUILDDATE'' $upl
		sed -i '6i\* Kernel Version: '$KER_VER'' $upl
		sed -i '7i\* KSU+NEXT: '$KSU_VER'' $upl
		sed -i '8i\* SUSFS: '$SUSFS_VER'' $upl
		sed -i '9i\* Type: DSP, Mi Thermal, '$OCDS'' $upl
		sed -i '10i\* Changes: https://github.com/onettboots/bool-x_xiaomi_raphael/commits/14-DSPcr' $upl
                sed -i '11i\* Clang: Boolx Clang 21.0.0"' $upl
                bash $upl
}

DATE_START=$(date +"%s")

echo -e "${green}"
echo "----------------------"
echo "Checking Toolchains:"
echo "----------------------"
echo -e "${restore}"

if [ -d $TOOLCHAINS ]; then
   echo -e "${green}"
   echo "Bool-x clang is ready..!!"
   echo -e "${restore}"
else
   echo -e "${red}"
   echo "Toolchains Architecture Host:"
   echo "1. ARCH64"
   echo "2. X86"
   while read -p "Choose your architecture (1 / 2)? " cchoice
do
case "$cchoice" in
        1 )
                echo
                echo "Downloading Boolx-clang for Aarch64 host."
                git clone https://gitlab.com/onettboots/boolx-clang.git -b Clang-15.0 $TOOLCHAINS
                break
                ;;
        2 )
                echo
                echo "Downloading Boolx-clang for X86 host."
                wget https://github.com/onettboots/boolx-clang-build/releases/download/Boolx-21/boolx-clang21.tar.gz -P $SAVEHERE
                cd $SAVEHERE
                echo "Extracting Boolx Clang 21.0.0 to $HOME/toolchains/:"
                tar -xf boolx-clang21.tar.gz
                break
                ;;
        * )
                echo
                echo "Invalid try again!"
                echo
                ;;
esac
done
   echo -e "${restore}"
fi

echo -e "${green}"
echo "----------------------------------"
echo "Checking for Anykernel flashable:"
echo "----------------------------------"
echo -e "${restore}"


if [ -d $REPACK_DIR ] && [ -d $ZIP_MOVE ]; then
   echo -e "${green}"
   echo "Anykernel is ready skipping..!!"
   echo -e "${restore}"
else
   echo -e "${red}"
   echo "Adding Anykernel flashable.!!"
   create_out
   echo -e "${restore}"
fi

echo -e "${green}"
echo "------------------"
echo "CLEAN OPTIONS:"
echo "------------------"
while read -p "Do you want to clean build (y/n)? " cchoice
do
case "$cchoice" in
	y|Y )
	    echo -e "${red}"
		clean_all
		echo -e "${restore}"
		echo -e "${green}"
		echo "All Cleaned now."
		echo -e "${restore}"
		break
		;;
	n|N )
		rm $KERNEL
		break
		;;
	* )
		echo -e "${red}"
		echo "Invalid try again!"
		echo -e "${restore}"
		;;
esac
done
echo -e "${restore}"

if [ -f $CONFIG ]; then
   echo -e "${green}"
   while read -p "Old config is exist do you want replace with new config ? (y/n)? " cchoice
do
case "$cchoice" in
	y|Y )
		make_config
		echo
		break
		;;
	n|N )
		break
		;;
	* )
		echo
		echo "Invalid try again!"
		echo
		;;
esac
done
   echo -e "${restore}"
else
   echo -e "${green}"
   echo -e "${restore}"
fi

if [ -f $CONFIG ]; then
   echo -e "${green}"
   echo -e "${restore}"
else
   echo -e "${green}"
   echo "-------------------------------------"
   echo "Making Configs:"
   echo "-------------------------------------"
   echo -e "${restore}"
   echo -e "${red}"
   make_config
   echo -e "${restore}"
fi

echo -e "${green}"
echo "-----------------"
echo "Building Kernel:"
echo "-----------------"
echo -e "${restore}"

cd ${kernel_dir}
build ${TARGET_IMAGE}

function build_time {
   DATE_END=$(date +"%s")
   DIFF=$(($DATE_END - $DATE_START))
   echo "Time: $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
}

echo -e "${green}"
echo "----------------------"
echo "Checking output files"
echo "----------------------"
echo -e "${restore}"
sleep 3
    
if [ -f $KERNEL ]; then
   echo -e "${green}"
   echo "------------------------------------------"
   echo "Succesed Build, make flashable zip"
   echo "------------------------------------------"
   echo -e "${restore}"
   make_boot
   make_zip
   cd $ZIP_MOVE
   echo -e "${blink_red}"
   echo $ZIP_MOVE
   echo "------------------------------------------"
   echo $ZIP_NAME*.zip
   echo "------------------------------------------"
   echo -e "${restore}"
   build_time
   if [ -f $upl ]; then
   	upload_boolx_action
   else
   	upload
   fi
   echo
else
   echo -e "${red}"
   echo "-------------------------------------"
   echo "Building failed, Fix it and rebuild...!!!"
   echo "-------------------------------------"
   echo -e "${restore}"
   build_time
fi

echo

rm -rf $upl
