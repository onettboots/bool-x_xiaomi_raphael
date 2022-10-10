
#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2022 Luan Halaiko (LuHaKo)
# Based on YaroST12 script

# Build Information and directories
kernel_dir="${PWD}"
builddir="${kernel_dir}/Zip-out"
last_commit=$(git rev-parse --verify --short=10 HEAD)
kVersion="-${last_commit}"
CUSTOM_ZIP_OUT_LOC="/mnt/phone_share/" # Unset if don't want to copy output zip to anywhere else

# Arch and target image
export ARCH="arm64"
TARGET_IMAGE="Image.gz-dtb"

# Toolchains
CLANG_VERSION="neutron-clang-08102022"
CLANG_LOC="/home/pwnrazr/dev-stuff/${CLANG_VERSION}"
CLANG="${CLANG_LOC}/bin:$PATH"
CT_BIN="${CLANG}/bin/"
CT="${CT_BIN}/clang"
objdir="${kernel_dir}/out"

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'
YEL='\033[1;33m'
CYN='\033[1;36m'

# CPUs
cpus=`expr $(nproc --all)`

# Separator
SEP="######################################"

function print()
{
	echo -e ${1} "\r${2}${NC}"
}

function screen()
{
	print ${RED} ${SEP}
	print ${RED} "${1}"
	print ${RED} ${SEP}
	exit
}

function parse_parameters()
{
	PARAMS="${*}"
	# Build settings
	BUILD_CASEFOLDING=true
	BUILD_CLEAN=false
	BUILD_LTO=false
	BUILD_FULL_LTO=true
	# Use verbose for bug fixing
	VERBOSE=true
	RELEASE=false
	CONFIG_FILE="raphael_defconfig"
	# Cleanup strings
	VERSION=""
	COMPILER_NAME=""

	while [[ ${#} -ge 1 ]]; do
		case ${1} in
			"-c"|"--clean")
				BUILD_CLEAN=true ;;
			"-v"|"--verbose")
				VERBOSE=true ;;
			"-l"|"--lto")
				BUILD_LTO=true
				BUILD_FULL_LTO=false ;;
			"-r")
				RELEASE=true ;;
			"-n")
				print $YEL "Input kernel name:";
				read CUSTOM_NAME; CUSTOM_NAME="-$CUSTOM_NAME";;
            		*) screen "Invalid parameter specified!" ;;
		esac

		shift
	done
	print ${LGR} ${SEP}
	print ${LGR} "Compilation started"
}

# Formats the time for the end
function format_time()
{
	MINS=$(((${2} - ${1}) / 60))
	SECS=$(((${2} - ${1}) % 60))

	TIME_STRING+="${MINS}:${SECS}"

	echo "${TIME_STRING}"
}

# Everything in here needs to be set for clang compilation,

function make_wrapper() {
		PATH=${CT_BIN}:${PATH} \
		make -s -j${cpus} \
		LLVM=1 \
		LLVM_IAS=1 \
		CROSS_COMPILE="aarch64-linux-gnu-" \
		CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
		KBUILD_COMPILER_STRING="${COMPILER_NAME}" \
		O="${objdir}" ${1}
}

function make_image()
{
	cd ${kernel_dir}

	# After we run savedefconfig in sources folder
	if [[ -f ${kernel_dir}/.config && ${BUILD_CLEAN} == false ]]; then
		print ${LGR} "Removing misplaced defconfig... "
		make -s -j${cpus} mrproper
	fi
	if [ ${BUILD_CLEAN} == true ]; then
		print ${LGR} "Cleaning up mess... "
		make -s -j${cpus} mrproper O=${objdir}
	fi

	START=$(date +%s)
	print ${LGR} "Generating Defconfig "
	make_wrapper ${CONFIG_FILE}

	SUPPORTS_THINLTO_CLANG=$(grep CONFIG_ARCH_SUPPORTS_THINLTO ${objdir}/.config)
	SUPPORTS_FULL_CLANG=$(grep CONFIG_ARCH_SUPPORTS_LTO_CLANG ${objdir}/.config)
	EROFS_STATE=$(grep CONFIG_EROFS_FS= ${objdir}/.config)

	if [[ ${BUILD_LTO} == true && ${BUILD_FULL_LTO} == true  ||  ${BUILD_LTO} == false && ${BUILD_FULL_LTO} == false ]]; then
		print ${RED} "Both LTO and FULL_LTO is true/false!"

	else
		ENABLE_CONF="LTO_CLANG"
		DISABLE_CONF="LTO_NONE LD_GOLD LD_BFD"

		if [ ${BUILD_FULL_LTO} == true ]; then
			if [[ ${SUPPORTS_FULL_CLANG} == CONFIG_ARCH_SUPPORTS_LTO_CLANG=y ]]; then
				print ${LGR} "${CYN}Enabling ${YEL}Full LTO"
				DISABLE_CONF+=" THINLTO"
			else
				print ${RED} "Full LTO Unsupported"
			fi

		else if [ ${BUILD_LTO} == true ]; then
			if [[ ${SUPPORTS_THINLTO_CLANG} == CONFIG_ARCH_SUPPORTS_THINLTO=y ]]; then
				print ${LGR} "${CYN}Enabling ${YEL}ThinLTO"
				ENABLE_CONF+=" THINLTO"
			else
				print ${RED} "ThinLTO Unsupported"
			fi
		fi
	fi
	fi

	if [ ${BUILD_CASEFOLDING} == true ]; then
		print ${LGR} "${CYN}Enabling ${YEL}Casefolding"
		ENABLE_CONF+=" CONFIG_UNICODE"
		DISABLE_CONF+=" CONFIG_SDCARD_FS"

	else
		print ${LGR} "${LRD}Disabling ${YEL}Casefolding"
		ENABLE_CONF+=" CONFIG_SDCARD_FS"
		DISABLE_CONF+=" CONFIG_UNICODE"
	fi

	if [[ ${EROFS_STATE} == CONFIG_EROFS_FS=y ]]; then
		print "${YEL}EROFS ${CYN}enabled"
	fi

	# enable/disable stuff
	for i in ${ENABLE_CONF}; do
		./scripts/config --file ${objdir}/.config -e $i
	done
	for i in ${DISABLE_CONF}; do
		./scripts/config --file ${objdir}/.config -d $i
	done
	make_wrapper olddefconfig

	# Clang versioning
	if [[ -d ${CLANG_LOC} ]]; then
		VERSION=$(${CLANG_LOC}/bin/clang --version | grep -wom 1 "[0-99][0-99].[0-99].[0-99]")
		COMPILER_NAME="Clang-${VERSION}"
		if [ ${BUILD_LTO} == true ]; then
			COMPILER_NAME+="+LTO"
		fi
		print ${LGR} "Compiling with ${YEL}${COMPILER_NAME}"
		cd ${kernel_dir}
		make_wrapper ${TARGET_IMAGE}
	else
		screen "Clang dir ${CLANG_LOC} does not exist.\nPlease set in CLANG_LOC"
	fi
	completion "${START}" "$(date +%s)"
}

function completion()
{
	COMPILED_IMAGE=${objdir}/arch/arm64/boot/${TARGET_IMAGE}
	TIME=$(format_time "${1}" "${2}")

	if [[ -f ${COMPILED_IMAGE} ]]; then

		DATE=$(date '+%d%m%y')
		DATE_TIME=$(date '+%d%m%y_%H%M%S')

		KERNEL_NAME=$(grep CONFIG_LOCALVERSION= ${objdir}/.config)
		KERNEL_NAME="${KERNEL_NAME//*=/}"
		KERNEL_NAME="${KERNEL_NAME//[-'"']/}"

		ZIP_NAME="${KERNEL_NAME}"

		if [[ ${BUILD_CASEFOLDING} == true ]]; then
			ZIP_NAME+="-CASEFOLDING"
		fi

		if [[ ${EROFS_STATE} == CONFIG_EROFS_FS=y ]]; then
			ZIP_NAME+="-EROFS"
		fi

		if [[ ${RELEASE} == true ]]; then
			ZIP_NAME+="-${DATE}-RELEASE${CUSTOM_NAME}"
		else
			ZIP_NAME+="-${DATE_TIME}${kVersion}${CUSTOM_NAME}"
		fi

		mv -f ${COMPILED_IMAGE} ${builddir}/anykernel/${TARGET_IMAGE}
		print ${LGR} "Build completed in ${TIME}!"
		SIZE=$(ls -s ${builddir}/anykernel/${TARGET_IMAGE} | sed 's/ .*//')

                # Zip up
                cd ${builddir}/anykernel
                zip -r -q "${ZIP_NAME}.zip" .
                rm ${builddir}/anykernel/${TARGET_IMAGE}
                mv ${builddir}/anykernel/"${ZIP_NAME}.zip" ${builddir}/

		if [[ ${CUSTOM_ZIP_OUT_LOC} != "" ]]; then
			cp ${builddir}/"${ZIP_NAME}.zip" ${CUSTOM_ZIP_OUT_LOC}
		fi

		print ${LGR} "(i)Flashable zip generated under $builddir"
		if [ ${VERBOSE} == true ]; then
			print ${LGR} "Build: ${YEL}${ZIP_NAME}"
			print ${LGR} "Img size: ${YEL}${SIZE}K"
		fi
		print ${LGR} ${SEP}

	else
		print ${RED} ${SEP}
		print ${RED} "Something went wrong"
		print ${RED} ${SEP}
	fi
}

parse_parameters "${@}"
make_image
cd ${kernel_dir}
