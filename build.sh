#!/bin/bash 

KERNEL_DIR="${PWD}"
KERNEL=out/arch/arm64/boot/Image.gz-dtb
DTBO=out/arch/arm64/boot/dtbo.img
rm .version
rm build.log
rm $KERNEL
rm $DTBO
# Bash Color
yellow='\033[01;33m'
green='\033[01;32m'
red='\033[01;31m'
blink_red='\033[05;31m'
restore='\033[0m'

# Simpan info ke variabel
HELP=$(cat <<EOF
--------------------------------
       Boolx Kernel Build
================================
  --clean  : Clean build
  --ksu    : Build KSU Next Only
  --susfs  : Build KSU and SUSFS
--------------------------------
EOF
)

clear
echo -e "${green}"
echo "$HELP"
echo -e "${restore}"

# Resources
export ARCH=arm64
export PATH="$HOME/toolchains/boolx-clang/bin/:$PATH"
export CC=$HOME/toolchains/boolx-clang/bin/clang
export LC_ALL=C
export USE_CCACHE=1
export CCACHE_EXEC=$(command -v ccache)
export THINLTO_CACHE_DIR=/home/onettboots/toolchains/thincache
#export CCACHE_DIR="$HOME/toolchains/boolx_ccache" #localbuild
ccache -M 10G

# Variables
TARGET_IMAGE="Image.gz-dtb"
cpus=`expr $(nproc --all)`
objdir="${KERNEL_DIR}/out"
CONFIGS="raphael_defconfig"
CFG=arch/arm64/configs/raphael_defconfig
VER="V2.3-Alarabi-DSP"
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
upl=$KERNEL_DIR/upl.sh
KER_VER=$(grep -oP '(?<=VERSION = )\d+|(?<=PATCHLEVEL = )\d+|(?<=SUBLEVEL = )\d+' Makefile | paste -sd '.')
OCDS=$(grep -qP "timing@1\s*{" arch/arm64/boot/dts/qcom/dsi-panel-ss-fhd-ea8076-cmd.dtsi && echo "OCD" || echo "No-OCD")

# functions
function build_ocd() {
      		[ -f $REPACK_DIR/ocd ] && rm $REPACK_DIR/ocd
      		[ -f $REPACK_DIR/dtbo.img ] && rm $REPACK_DIR/dtbo.img
      		[ -f $REPACK_DIR/Image.gz-dtb ] && rm $REPACK_DIR/Image.gz-dtb
      		ocd_patch
      		cook dtbo.img
      		cp $DTBO $REPACK_DIR/ocd
      		git restore arch/arm64/boot/dts/qcom/dsi-panel-ss-fhd-ea8076-cmd.dtsi
      		git restore arch/arm64/boot/dts/qcom/dsi-panel-ss-fhd-ea8076-global-cmd.dtsi
}

function cook() {
                PATH=${CLANG_BIN}:${PATH} \
                make -s -j${cpus} \
                LLVM=1 \
                LLVM_IAS=1 \
                CC="ccache clang" \
                CROSS_COMPILE="aarch64-linux-gnu-" \
                CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
                O="${objdir}" ${1} \
                KBUILD_BUILD_USER="OnettBoots" \
                KBUILD_BUILD_HOST="OpenELA"
}

function build() {
		make -j$(nproc) \
    		O=out \
    		ARCH=arm64 \
    		CC="ccache clang" \
    		LLVM=1 \
    		LLVM_IAS=1 \
    		CROSS_COMPILE=aarch64-linux-gnu- \
    		CROSS_COMPILE_ARM32=arm-linux-gnueabi-
		KBUILD_BUILD_USER="OnettBoots" \
                KBUILD_BUILD_HOST="OpenELA"
}

function progress() {
		filezip=$(ls $ZIP_MOVE/*.zip 2>/dev/null | wc -l)

		if (( filezip == 1 )); then
		  total_lines=16
		elif (( filezip > 1 )); then
		  total_lines=65
		else
  		  total_lines=4250
		fi

		count=0
		bar_length=50
		while IFS= read -r line; do

		    ((count++))
		    percent=$(( count * 100 / total_lines ))
		    (( percent > 100 )) && percent=100

		    filled=$(( percent * bar_length / 100 ))
		    empty=$(( bar_length - filled ))

		    #echo "$line"

		    printf "\rBuilding: [%-${bar_length}s] %3d%%" \
		        "$(printf '#%.0s' $(seq 1 $filled))$(printf '.%.0s' $(seq 1 $empty))" \
		        "$percent"

		done

}
#function progress() {
#		total=35
#		pos=0
#		direction=1
#
#		while true; do
#		  bar=$(printf '%*s' "$total" '')
#		  bar="${bar:0:pos}*################*${bar:pos+1}"
#
#		  printf "\r Building: [%s]" "$bar"
#
#		  ((pos += direction))
#		  if (( pos == total - 1 )); then
#		    direction=-1
#		  elif (( pos == 0 )); then
#		    direction=1
#		  fi
#
#		  if [ -f "$KERNEL" ]; then
#		  exit 0
#		  fi
#		  sleep 0.1
#		done
#}
function create_out {
		echo
		git clone https://github.com/onettboots/boolx_anykernel.git $REPACK_DIR && mkdir $ZIP_MOVE
}
function make_config {
		echo
		make -s O=out ARCH=arm64 ${CONFIGS}
}
function make_boot {
		cp $KERNEL $REPACK_DIR && cp $DTBO $REPACK_DIR
}
function make_zip {
		cd $REPACK_DIR
		ksu=$(cd $KERNEL_DIR && grep -q '^CONFIG_KSU=y' $CFG && echo "y" || echo "n")
		susfs=$(cd $KERNEL_DIR && grep -q '^CONFIG_KSU_SUSFS=y' $CFG && echo "y" || echo "n")

		if [[ $ksu == "y" && $susfs == "y" ]]; then
		  ZIPED=$ZIP_MOVE/`echo $ZIP_NAME-KSUNEXT-SUSFS`.zip
		  ZIPSTRING=`echo $ZIP_NAME-KSUNEXT-SUSFS`
		  zip -r9 `echo $ZIP_NAME-KSUNEXT-SUSFS`.zip *
		  KSU_VER=$(cat $KERNEL_DIR/drivers/kernelsu/kernel/dksu 2>/dev/null)
		  SUSFS_VER=$(grep -oP '(?<=#define SUSFS_VERSION ")[^"]*' $KERNEL_DIR/include/linux/susfs.h 2>/dev/null)
		elif [[ $ksu == "y" && $susfs == "n" ]]; then
		  ZIPED=$ZIP_MOVE/`echo $ZIP_NAME-KSUNEXT`.zip
		  ZIPSTRING=`echo $ZIP_NAME-KSUNEXT`
		  zip -r9 `echo $ZIP_NAME-KSUNEXT`.zip *
		  KSU_VER=$(cat $KERNEL_DIR/drivers/kernelsu/kernel/dksu 2>/dev/null)
		  SUSFS_VER=Disabled
		elif [[ $ksu == "n" && $susfs == "n" ]]; then
		  ZIPED=$ZIP_MOVE/`echo $ZIP_NAME`.zip
		  ZIPSTRING=`echo $ZIP_NAME`
		  zip -r9 `echo $ZIP_NAME`.zip *
		  KSU_VER=Disabled
                  SUSFS_VER=Disabled
		else
		  ZIPED=$ZIP_MOVE/`echo $ZIP_NAME`.zip
		  ZIPSTRING=`echo $ZIP_NAME`
		  zip -r9 `echo $ZIP_NAME`.zip *
		  KSU_VER=Disabled
                  SUSFS_VER=Disabled
		fi
		mv  `echo $ZIP_NAME`*.zip $ZIP_MOVE
		cd $KERNEL_DIR
}

function upload()
{
		#curl bashupload.com -T $ZIP_NAME*.zip
		source $KERNEL_DIR/.dump
		#ziped=$ZIP_MOVE/`echo $ZIP_NAME`.zip
	        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$ZIPED" "$USER@$HOST:$REMOTE_DIR"
}

function upload_boolx_action()
{
                #ziped=$ZIP_MOVE/`echo $ZIP_NAME`.zip
		cd $KERNEL_DIR
		#wget
		chmod +x $upl
		sed -i "4i\FILE_PATH=$ZIPED" $upl
		BUILDDATE=`date +"%Y-%m-%d"`
		sed -i '5i\CAPTION="* Build Date: '$BUILDDATE'' $upl
		sed -i '6i\* Kernel Version: '$KER_VER'' $upl
		sed -i '7i\* KSU+NEXT: '$KSU_VER'' $upl
		sed -i '8i\* SUSFS: '$SUSFS_VER'' $upl
		sed -i '9i\* Type: DSP, Mi Thermal, '$OCDS'' $upl
		sed -i '10i\* Changes: https://github.com/onettboots/bool-x_xiaomi_raphael/commits/14-DSPcr' $upl
            sed -i '11i\* Clang: Boolx Clang 22.0.0' $upl
            sed -i '12i\' $upl
            sed -i '13i\*NOTES: Rename the file '$ZIPSTRING'.zip to '$ZIPSTRING'-ocd.zip to support OverClock Display up to 90hz"' $upl
            bash $upl
}

function ocd_patch {
sed -i '/qcom,default-topology-index = <0>;/a \
         }; \
\
         timing@1 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <69>;\
            qcom,mdss-dsi-panel-clockrate = <1150000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
         };\
\
         timing@2 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <72>;\
            qcom,mdss-dsi-panel-clockrate = <1200000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
         };\
\
         timing@3 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <81>;\
            qcom,mdss-dsi-panel-clockrate = <1350000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
         };\
\
         timing@4 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <90>;\
            qcom,mdss-dsi-panel-clockrate = <1500000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
' arch/arm64/boot/dts/qcom/dsi-panel-ss-fhd-ea8076-cmd.dtsi

sed -i '/qcom,default-topology-index = <0>;/a \
         }; \
\
         timing@1 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <69>;\
            qcom,mdss-dsi-panel-clockrate = <1150000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
         };\
\
         timing@2 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <72>;\
            qcom,mdss-dsi-panel-clockrate = <1200000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
         };\
\
         timing@3 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <81>;\
            qcom,mdss-dsi-panel-clockrate = <1350000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
         };\
\
         timing@4 {\
            qcom,mdss-dsi-panel-width = <1080>;\
                                qcom,mdss-dsi-panel-height = <2340>;\
                                qcom,mdss-dsi-h-front-porch = <42>;\
                                qcom,mdss-dsi-h-back-porch = <42>;\
                                qcom,mdss-dsi-h-pulse-width = <12>;\
                                qcom,mdss-dsi-h-sync-skew = <0>;\
                                qcom,mdss-dsi-v-back-porch = <42>;\
                                qcom,mdss-dsi-v-front-porch = <42>;\
                                qcom,mdss-dsi-v-pulse-width = <12>;\
                                qcom,mdss-dsi-h-left-border = <0>;\
                                qcom,mdss-dsi-h-right-border = <0>;\
                                qcom,mdss-dsi-v-top-border = <0>;\
                                qcom,mdss-dsi-v-bottom-border = <0>;\
            qcom,mdss-dsi-panel-framerate = <90>;\
            qcom,mdss-dsi-panel-clockrate = <1500000000>;\
            qcom,mdss-dsi-panel-jitter = <0x05 0x01>;\
            qcom,mdss-dsi-on-command = [05 01 00 00 0a 00 02 11 00 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 35 00 39 00 00 00 00 00 03 b7 01 4b 39 01 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 05 2b 00 00 09 23 39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 1a b8 39 00 00 00 00 00 07 e1 00 00 02 02 42 02 39 00 00 00 00 00 07 e2 00 00 00 00 00 00 39 00 00 00 00 00 02 b0 0c 39 00 00 00 00 00 02 e1 19 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5 39 00 00 00 00 00 02 53 20 39 00 00 00 00 00 03 51 00 00 39 01 00 00 43 00 02 55 00 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-timing-switch-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 03 fc 5a 5a 39 00 00 00 00 00 02 b0 23 39 00 00 00 00 00 02 d1 0f 39 00 00 00 00 00 0c e9 11 55 a6 75 a3 a9 a1 4a 00 8a 18 39 00 00 00 00 00 03 f0 a5 a5 39 01 00 00 00 00 03 fc a5 a5];\
            qcom,mdss-dsi-timing-switch-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command = [05 01 00 00 00 00 02 28 00 05 01 00 00 78 00 02 10 00];\
            qcom,mdss-dsi-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-hbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 22 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-doze-lbm-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 d4 8b 39 00 00 00 00 00 02 b0 a5 39 00 00 00 00 00 02 c7 00 39 00 00 00 00 00 02 b0 69 39 00 00 00 00 00 03 b9 08 8f 39 01 00 00 01 00 02 53 23 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-nolp-command = [05 01 00 00 10 00 02 28 00 39 01 00 00 00 00 02 53 20 05 01 00 00 00 00 02 29 00];\
            qcom,mdss-dsi-doze-hbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-doze-lbm-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-nolp-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-off-command = [39 01 00 00 00 00 02 55 00];\
            qcom,mdss-dsi-dispparam-acl-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l1-command = [39 01 00 00 00 00 02 55 01];\
            qcom,mdss-dsi-dispparam-acl-l1-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l2-command = [39 01 00 00 00 00 02 55 02];\
            qcom,mdss-dsi-dispparam-acl-l2-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-acl-l3-command = [39 01 00 00 00 00 02 55 03];\
            qcom,mdss-dsi-dispparam-acl-l3-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-off-command = [39 01 00 00 00 00 02 53 28];\
            qcom,mdss-dsi-dispparam-hbm-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-hbm-on-command = [39 01 00 00 00 00 02 53 e8];\
            qcom,mdss-dsi-dispparam-hbm-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingon-command = [39 01 00 00 01 00 02 53 28];\
            qcom,mdss-dsi-dispparam-dimmingon-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-dimmingoff-command = [39 01 00 00 01 00 02 53 20];\
            qcom,mdss-dsi-dispparam-dimmingoff-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command = [39 01 00 00 00 00 02 81 90 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 bd 02 00 14 d1 00 04 07 aa 0c ec cb c8 0f dd d9 e4 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-srgb-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command = [39 01 00 00 00 00 02 81 91 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 00 39 01 00 00 00 00 02 b0 01 39 01 00 00 00 00 16 b1 ae 0c 05 3f c6 14 05 07 aa 4a dd c8 c3 14 c0 e8 dc 19 ff f4 d9 39 01 00 00 00 00 02 b0 16 39 01 00 00 00 00 16 b1 d2 0a 05 1a e6 00 04 07 f5 0c dc db e8 0f dd ee e9 05 ff ff ff 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-dcip3-on-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-crc-off-command = [39 01 00 00 00 00 02 81 00 39 01 00 00 00 00 03 f0 5a 5a 39 01 00 00 00 00 02 b1 01 39 01 00 00 00 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-crc-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command = [39 00 00 00 00 00 03 f0 5a 5a 39 00 00 00 00 00 02 b0 07 39 00 00 00 00 00 02 b7 91 39 01 00 00 01 00 03 f0 a5 a5];\
            qcom,mdss-dsi-dispparam-elvss-dimming-off-command-state = "dsi_lp_mode";\
            qcom,mdss-dsi-h-sync-pulse = <0>;\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command = [15 01 00 00 10 00 02 53 20];\
            qcom,mdss-dsi-dispparam-hbm-fod-off-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command = [39 00 00 00 00 00 03 f0 5a 5a 15 00 00 00 00 00 02 b0 03 15 00 00 00 00 00 02 b7 c9 39 00 00 00 00 00 03 f0 a5 a5 15 01 00 00 10 00 02 53 e0];\
            qcom,mdss-dsi-dispparam-hbm-fod-on-command-state = "dsi_hs_mode";\
            qcom,mdss-dsi-panel-phy-timings = [00 24 0a 0a 26 25 09 0a 06 03 04 00 1e 1a];\
            qcom,display-topology = <1 0 1>;\
            qcom,default-topology-index = <0>;\
' arch/arm64/boot/dts/qcom/dsi-panel-ss-fhd-ea8076-global-cmd.dtsi
}

DATE_START=$(date +"%s")

echo -e "${green}"
echo "----------------------"
echo "Checking Toolchains:"
echo "----------------------"
echo -e "${restore}"
sleep 1
if [ -d $TOOLCHAINS ]; then
   echo -e "${red}"
   echo "Bool-x clang is ready..!!"
   echo -e "${restore}"
else
   echo -e "${green}"
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
                echo "Downloading Boolx-clang 22.0.0 for X86 host."
                wget https://github.com/onettboots/boolx-clang-build/releases/download/Boolx-22/boolx-clang22.tar.zst -P $SAVEHERE
                cd $SAVEHERE
                echo "Extracting Boolx Clang 22.0.0 to $HOME/toolchains/:"
                tar --use-compress-program=unzstd -xf boolx-clang22.tar.zst
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
sleep 1
clear
echo -e "${green}"
#echo "-----------------------"
echo "$HELP"
#echo "-----------------------"
echo -e "${restore}"

echo -e "${green}"
echo "----------------------------------"
echo "Checking for Anykernel flashable:"
echo "----------------------------------"
echo -e "${restore}"
sleep 1
if [ -d $REPACK_DIR ] && [ -d $ZIP_MOVE ]; then
   echo -e "${red}"
   echo "Anykernel is ready skipping..!!"
   echo -e "${restore}"
else
   echo -e "${red}"
   echo "Adding Anykernel flashable.!!"
   create_out
   echo -e "${restore}"
fi
sleep 1
clear
echo -e "${green}"
echo "$HELP"
echo -e "${restore}"
echo -e "${green}"

echo "-----------------------"
echo " USAGE :"
echo "-----------------------"
echo -e "${restore}"

sleep 1
enable_ksu=n
enable_susfs=n

function clean_all {
	rm -rf out
    echo -e "${red}""- Clean build""${restore}"
}

for arg in "$@"; do
    case "$arg" in
        --ksu) enable_ksu=y;;
        --susfs) enable_susfs=y;;
	--clean) clean_all;;
    esac
done

if grep -q "^CONFIG_KSU=" "$CFG"; then
    sed -i "s/^CONFIG_KSU=.*/CONFIG_KSU=$enable_ksu/" "$CFG"
else
    echo "CONFIG_KSU=$enable_ksu" >> "$CFG"
fi
sleep 0.5
echo -e "${red}- KSU $( [ $enable_ksu = y ] && echo Enabled || echo Disabled )${restore}"

sleep 0.5
if grep -q "^CONFIG_KSU_SUSFS=" "$CFG"; then
    sed -i "s/^CONFIG_KSU_SUSFS=.*/CONFIG_KSU_SUSFS=$enable_susfs/" "$CFG"
else
    echo "CONFIG_KSU_SUSFS=$enable_susfs" >> "$CFG"
fi
sleep 0.5
echo -e "${red}- SUSFS $( [ $enable_susfs = y ] && echo Enabled || echo Disabled )${restore}"
sleep 0.5
echo -e "${red}""- 60HZ by default""${restore}"
sleep 0.5
echo -e "${red}""- Patch OCD Support by renaming zip file""${restore}"
sleep 0.5
echo -e "${green}"
echo "-----------------------"
echo " Starting Build !"
echo "-----------------------"
echo -e "${restore}"

cd ${KERNEL_DIR}
make_config
build_ocd
echo -e "${yellow}"
build ${TARGET_IMAGE} | tee logs.txt | progress
echo -e "${restore}"
function build_time {
   DATE_END=$(date +"%s")
   DIFF=$(($DATE_END - $DATE_START))
   echo "Time: $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
}

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
   if [[ -f "$KERNEL_DIR/.dump" ]]; then
    upload
   elif [[ -f "$upl" ]]; then
    upload_boolx_action
   else
    echo ""
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

# End
#rm -rf $upl
cd $KERNEL_DIR
git restore $CFG
