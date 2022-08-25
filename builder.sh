
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

# Arch and target image
export ARCH="arm64"
TARGET_IMAGE="Image.gz-dtb"

# Toolchains
CLANG_VERSION="azure-clang"
CLANG="$HOME/workfolder/${CLANG_VERSION}/bin:$PATH"
CT_BIN="${CLANG}/bin/"
CT="${CT_BIN}/clang"
objdir="${kernel_dir}/out"
export THINLTO_CACHE=${PWD}/../thinlto_cache

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'
YEL='\033[1;33m'

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
	BUILD_CASEFOLDING=false
	BUILD_CLEAN=false
	BUILD_LTO=true
	BUILD_FULL_LTO=false
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
				BUILD_LTO=true ;;
			"-r")
				RELEASE=true ;;
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
# clang triple currently not use since i'm using proton-clang
# based toolchains.
function make_wrapper() {
		PATH=${CT_BIN}:${PATH} \
		make -s -j${cpus} \
	    AR="llvm-ar" \
		AS="llvm-as" \
	    NM="llvm-nm" \
	    STRIP="llvm-strip" \
    	OBJCOPY="llvm-objcopy" \
    	OBJDUMP="llvm-objdump" \
		OBJSIZE="llvm-size" \
		READELF="llvm-readelf" \
    	LD="ld.lld" \
		LDLLD="ld.lld" \
		HOSTCC="clang" \
		HOSTCXX="clang++" \
    	CC="clang" \
		CXX="clang++" \
		CROSS_COMPILE="aarch64-linux-gnu-" \
		CROSS_COMPILE_COMPAT="arm-linux-gnueabi-" \
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

    if [[ ${BUILD_LTO} == true && ${BUILD_CASEFOLDING} == true ]]; then
		print ${LGR} "Enabling ThinLTO + Casefolding"
		# Check if ThinLTO + Casefolding support is present in defconfig
		SUPPORTS_CLANG=$(grep CONFIG_ARCH_SUPPORTS_THINLTO ${objdir}/.config)
		if [[ ${SUPPORTS_CLANG} ]]; then
			# Enable LTO and ThinLTO + Casefolding
			for i in THINLTO LTO_CLANG LD_LLD CONFIG_UNICODE; do
				./scripts/config --file ${objdir}/.config -e $i
			done
			for i in LTO_NONE LTO_CLANG_FULL LD_GOLD LD_BFD CONFIG_SDCARD_FS; do
				./scripts/config --file ${objdir}/.config -d $i
			done
			# Regen defconfig with all our changes (again)
			make_wrapper olddefconfig
		else
			print ${RED} "ThinLTO + Casefolding support not present"
		fi

	else if [ ${BUILD_LTO} == true ]; then
		print ${LGR} "Enabling ThinLTO"
		# Check if ThinLTO support is present in defconfig
		SUPPORTS_CLANG=$(grep CONFIG_ARCH_SUPPORTS_THINLTO ${objdir}/.config)
		if [[ ${SUPPORTS_CLANG} ]]; then
			# Enable LTO and ThinLTO
			for i in THINLTO LTO_CLANG LD_LLD; do
				./scripts/config --file ${objdir}/.config -e $i
			done
			for i in LTO_NONE LTO_CLANG_FULL LD_GOLD LD_BFD; do
				./scripts/config --file ${objdir}/.config -d $i
			done
			# Regen defconfig with all our changes (again)
			make_wrapper olddefconfig
		else
			print ${RED} "ThinLTO support not present"
		fi
	fi
	
#	else if [ ${BUILD_FULL_LTO} == true ]; then
#		print ${LGR} "Enabling FULL LTO"
#			# Enable LTO and
#			for i in LTO_CLANG LD_DEAD_CODE_DATA_ELIMINATION LD_LLD; do
#				./scripts/config --file ${objdir}/.config -e $i
#			done
#			for i in LTO_NONE THINLTO LD_GOLD LD_BFD; do
#				./scripts/config --file ${objdir}/.config -d $i
#			done
#			# Regen defconfig with all our changes (again)
#			make_wrapper olddefconfig
#		else
#			print ${RED} "ThinLTO support not present"
#		fi
	fi

	# Clang versioning
	VERSION=$($HOME/workfolder/${CLANG_VERSION}/bin/clang --version | grep -wom 1 "[0-99][0-99].[0-99].[0-99]")
	COMPILER_NAME="Clang-${VERSION}"
	if [ ${BUILD_LTO} == true ]; then
		COMPILER_NAME+="+LTO"
	fi
	print ${LGR} "Compiling with ${YEL}${COMPILER_NAME}"
	cd ${kernel_dir}
	make_wrapper ${TARGET_IMAGE}

	completion "${START}" "$(date +%s)"
}

function completion()
{
	cd ${objdir}
	COMPILED_IMAGE=arch/arm64/boot/${TARGET_IMAGE}
	TIME=$(format_time "${1}" "${2}")
	if [[ -f ${COMPILED_IMAGE} && ${BUILD_CASEFOLDING} == false ]]; then
		cd ..
		cd $builddir/main
		make clean &>/dev/null
		cd ..
		cd ${objdir}
		mv -f ${COMPILED_IMAGE} ${builddir}/main/${TARGET_IMAGE}
		print ${LGR} "Build completed in ${TIME}!"
		SIZE=$(ls -s ${builddir}/main/${TARGET_IMAGE} | sed 's/ .*//')
		cd ..
		cd $builddir/main
  		make &>/dev/null
  		make sign &>/dev/null
  		cd ..
  		print ${LGR} "(i)Flashable zip generated under $builddir/main"
		if [ ${VERBOSE} == true ]; then
			print ${LGR} "Build: ${YEL}INFINITY${kVersion}"
			print ${LGR} "Img size: ${YEL}${SIZE}K"
		fi
		print ${LGR} ${SEP}
	else if [[ -f ${COMPILED_IMAGE} && ${BUILD_CASEFOLDING} == true ]]; then
			cd ..
			cd $builddir/casefolding
			make clean &>/dev/null
			cd ..
			cd ${objdir}
			mv -f ${COMPILED_IMAGE} ${builddir}/casefolding/${TARGET_IMAGE}
			print ${LGR} "Build completed in ${TIME}!"
			SIZE=$(ls -s ${builddir}/casefolding/${TARGET_IMAGE} | sed 's/ .*//')
			cd ..
			cd $builddir/casefolding
  			make &>/dev/null
  			make sign &>/dev/null
  			cd ..
  			print ${LGR} "(i)Flashable zip generated under $builddir/casefolding"
			if [ ${VERBOSE} == true ]; then
				print ${LGR} "Build: ${YEL}INFINITY-CASEFOLDING${kVersion}"
				print ${LGR} "Img size: ${YEL}${SIZE}K"
			fi
			print ${LGR} ${SEP}
		else
			print ${RED} ${SEP}
			print ${RED} "Something went wrong"
			print ${RED} ${SEP}
		fi
	fi

}
parse_parameters "${@}"
make_image
cd ${kernel_dir}