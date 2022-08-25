
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
CLANG_VERSION="aosp-clang-15"
CLANG_LOC="/home/pwnrazr/dev-stuff/${CLANG_VERSION}"
CLANG="${CLANG_LOC}/bin:$PATH"
CT_BIN="${CLANG}/bin/"
CT="${CT_BIN}/clang"
objdir="${kernel_dir}/out"
#export THINLTO_CACHE=${PWD}/../thinlto_cache

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

	SUPPORTS_THINLTO_CLANG=$(grep CONFIG_ARCH_SUPPORTS_THINLTO ${objdir}/.config)
	SUPPORTS_FULL_CLANG=$(grep CONFIG_ARCH_SUPPORTS_LTO_CLANG ${objdir}/.config)

	if [[ ${BUILD_LTO} == true && ${BUILD_FULL_LTO} == true  ||  ${BUILD_LTO} == false && ${BUILD_FULL_LTO} == false ]]; then
		print ${RED} "Both LTO and FULL_LTO is true/false!"

	else
		ENABLE_CONF="LTO_CLANG LD_LLD"
		DISABLE_CONF="LTO_NONE LD_GOLD LD_BFD"

		if [ ${BUILD_FULL_LTO} == true ]; then
			if [ ${SUPPORTS_FULL_CLANG} == CONFIG_ARCH_SUPPORTS_LTO_CLANG=y ]; then
				print ${LGR} "Enabling Full LTO"
				ENABLE_CONF="${ENABLE_CONF}"
				DISABLE_CONF="${DISABLE_CONF} THINLTO"
			else
				print ${RED} "Full LTO Unsupported"
			fi

		else if [ ${BUILD_LTO} == true ]; then
			if [ ${SUPPORTS_THINLTO_CLANG} == CONFIG_ARCH_SUPPORTS_THINLTO=y ]; then
				print ${LGR} "Enabling ThinLTO"
				ENABLE_CONF="${ENABLE_CONF} THINLTO"
				DISABLE_CONF="${DISABLE_CONF}"
			else
				print ${RED} "ThinLTO Unsupported"
			fi
		fi
	fi
	fi

	if [ ${BUILD_CASEFOLDING} == true ]; then
		print ${LGR} "Enabling Casefolding"
		ENABLE_CONF="${ENABLE_CONF} CONFIG_UNICODE"
		DISABLE_CONF="${DISABLE_CONF} CONFIG_SDCARD_FS"

	else
		print ${LGR} "Disabling Casefolding"
		ENABLE_CONF="${ENABLE_CONF} CONFIG_SDCARD_FS"
		DISABLE_CONF="${DISABLE_CONF} CONFIG_UNICODE"
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
	VERSION=$(${CLANG_LOC}/bin/clang --version | grep -wom 1 "[0-99][0-99].[0-99].[0-99]")
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

                # Zip up
                mv ${builddir}/main/${TARGET_IMAGE} $builddir/anykernel/
                cd ${builddir}/anykernel
                zip -r -q "INFINITY${kVersion}.zip" .
                rm ${builddir}/anykernel/${TARGET_IMAGE}
                mv ${builddir}/anykernel/INFINITY${kVersion}.zip ${builddir}/main/
		cp ${builddir}/main/INFINITY${kVersion}.zip /mnt/phone_share/

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

			# Zip up
			mv ${builddir}/casefolding/${TARGET_IMAGE} $builddir/anykernel/
			cd ${builddir}/anykernel
			zip -r -q "INFINITY-CASEFOLDING${kVersion}.zip" .
			rm ${builddir}/anykernel/${TARGET_IMAGE}
			mv ${builddir}/anykernel/INFINITY-CASEFOLDING${kVersion}.zip ${builddir}/casefolding/
			cp ${builddir}/casefolding/INFINITY-CASEFOLDING${kVersion}.zip /mnt/phone_share/

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
