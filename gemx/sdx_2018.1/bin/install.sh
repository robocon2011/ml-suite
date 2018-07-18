#!/bin/bash

# Deployment script for SDAccel compiled OpenCL programs

# This script will do the following:
# 1. Copy the necessary runtime files to the target directory specified with -d switch
# 2. Remove SDAccel's copy of libstdc++ and libOpenCL.so if the target system already
#    has the correct version of these files installed
# 3. Compile and install Linux kernel device drivers unless -k no or -f no switch is specifed
# 4. Install the firmware files like bitstreams and dsabins to the Linux firmware area
# 5. Generates a setup.sh environment script which may be used to setup correct environment
#    in order to run the compiled binaries.
#
# If run without root privileges, the script would not attempt to install firmware files
# or install the Linux kernel drivers


ROOT_DIR=`pwd`
DEST=
INSTALL_KERNEL_DRV="yes"
FORCE_INSTALL_KERNEL_DRV="no"

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

usage () {
    echo "Usage: $0 [-d <install_root>] [-k <yes|no>] [-f <yes|no>]"
    echo "       -d deployment directory"
    echo "       -k install kernel drivers"
    echo "       -f force-install kernel drivers"
    exit 1
}

update_check () {
    NEW=$1
    OLD=$2
    if [[ $OLD == ERROR* ]]; then
        # No previous version of xcldma found?
        return 0;
    elif [ -z "$OLD" ]; then
        # Zero sized version string implies $OLD is 2015.4 xcldma driver which does not
        # have version attribute. In this case always trust the newer driver.
        return 0
    elif [ -z "$NEW" ]; then
        # Zero sized version string implies $NEW is 2015.4 xcldma driver which does not
        # have version attribute. Skip $NEW since the currently installed version is more
        # recent.
        return 1
    fi
    n=`echo $NEW | awk '-F.' '{ print $1*100 + $2*10 + $3 }'`
    o=`echo $OLD | awk '-F.' '{ print $1*100 + $2*10 + $3 }'`
    if [ $n -gt $o ]; then
        return 0
    else
        return 1
    fi
}

path_exists_check () {
    EXE_NAME=$1
    if [[ ! $(which $EXE_NAME) ]]; then
      echo "WARN: Unable to find '${EXE_NAME}' using PATH environment variable. Please install or add to PATH."
    fi
}

exists_check () {
    FILE=$1
    MSG=$2
    if [[ ! -f $FILE ]]; then
      echo "WARN: Unable to find '${FILE}'. ${MSG}"
    fi
}

cleanup_old_driver () {
    DRIVER_NAME=$1
    MODULE_INFO=`modinfo $DRIVER_NAME 2>&1`
    if [ $? == 0 ]; then
       echo "Removing existing ${DRIVER_NAME}"
       ( rmmod ${DRIVER_NAME}.ko || true ) > /dev/null 2>&1 
       /bin/rm -f /lib/modules/$(/bin/uname -r)/extra/${DRIVER_NAME}.ko
    fi
}
cleanup_old_drivers () {
    cleanup_old_driver xcldma
    cleanup_old_driver xdma
    cleanup_old_driver xclmgmt
    cleanup_old_driver xocl
}

path_exists_check unzip
path_exists_check gcc
path_exists_check perl
path_exists_check lspci

KERNEL_DEVEL_MAKEFILE="/lib/modules/`uname -r`/build/Makefile"
exists_check $KERNEL_DEVEL_MAKEFILE "This suggests that the kernel-devel package has not been installed. Please install this package."


while [[ $# -gt 0 ]]
do
    switch="$1"
    case $switch in
        -d)
            DEST="$2"
            shift
            ;;
        -k)
            INSTALL_KERNEL_DRV="$2"
            shift
            ;;
        -f)
            FORCE_INSTALL_KERNEL_DRV="$2"
            shift
            ;;
        -h)
            usage
            ;;
        *)
            usage
            ;;
    esac
    shift
done

PLAT=`uname -m`
OWNER=`whoami`

if [ -n "$DEST" ]; then
    mkdir -p $DEST > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "ERROR: $OWNER does not have write priviledges for $DEST"
        exit 1
    fi
else
    DEST=$ROOT_DIR
fi

# Create ICD entry for SDAccel if missing
if [ ! -e /etc/OpenCL/vendors/xilinx.icd ]; then
    if [ $OWNER != "root" ]; then
        echo "WARN: root priviledges required, skipping creating of ICD registry"
    else
        echo "INFO: Creating ICD entry for Xilinx Platform"
        mkdir -p /etc/OpenCL/vendors
        echo "libxilinxopencl.so" > /etc/OpenCL/vendors/xilinx.icd
	chmod -R 755 /etc/OpenCL
    fi
fi

SYS_LIBDIR=/usr/lib/x86_64-linux-gnu
if [ $PLAT == ppc64le ]; then
    SYS_LIBDIR=/usr/lib/powerpc64le-linux-gnu
fi

# Check if an ICD is already installed then remove our copy of ICD
if [ -e $SYS_LIBDIR/libOpenCL.so ] ||
       [ -e /usr/lib64/libOpenCL.so ]; then
    rm -f runtime/lib/$PLAT/libOpenCL.so*
fi

# Install the firmware into Linux firmware directory
if [ $OWNER != "root" ]; then
    echo "WARN: root priviledges required, skipping installation of firmware files"
else
    echo "INFO: Installing firmware for FPGA devices"
    install -d /lib/firmware/xilinx
    install -m 644 firmware/* /lib/firmware/xilinx
fi

# Check if native C++ library supports C++ features we need
FOUND1=1
if [ -e $SYS_LIBDIR/libstdc++.so.6 ]; then
    nm -D $SYS_LIBDIR/libstdc++.so.6 | grep GLIBCXX_3.4.22 > /dev/null 2>&1
    FOUND1=$?
fi

FOUND2=1
if [ -e /usr/lib64/libstdc++.so.6 ]; then
    nm -D /usr/lib64/libstdc++.so.6 | grep GLIBCXX_3.4.22 > /dev/null 2>&1
    FOUND2=$?
fi

if [ $FOUND1 -eq 0 ] ||
       [ $FOUND2 -eq 0 ]; then
    rm -rf runtime/lib/$PLAT/libstdc++.so.6
fi

# Install runtime if a different destination folder is desired
if [ $ROOT_DIR != $DEST ]; then
    echo "INFO: Installing runtime libraries in $DEST"
    install -d $DEST/runtime/lib/$PLAT
    install runtime/lib/$PLAT/* $DEST/runtime/lib/$PLAT
fi

# Identify the preferred device
XCL_PLATFORM=`ls runtime/platforms | head -n 1`

# Compile and install Linux kernel drivers
mkdir -p /tmp/$$

index=0
err=0
for DEV in runtime/platforms/*; do
    cd $ROOT_DIR
    XCL_PLAT=`basename $DEV`;
    if [ $ROOT_DIR != $DEST ]; then
        echo "INFO: Device $XCL_PLAT"
        install -d $DEST/$DEV/driver
        install $DEV/driver/*.so $DEST/$DEV/driver
    fi
    if [ $INSTALL_KERNEL_DRV != "yes" ] && [ $FORCE_INSTALL_KERNEL_DRV != "yes" ]; then
        continue;
    fi
    
    KERNEL_DEVEL_MAKEFILE="/lib/modules/`uname -r`/build/Makefile"
    MSG="This suggests that the kernel-devel package has not been installed. Please install this package."
    if [[ ! -f $KERNEL_DEVEL_MAKEFILE ]]; then
      echo "ERR: Unable to find '${KERNEL_DEVEL_MAKEFILE}'. ${MSG}"
      exit 1
    fi
    
    #Clean up the old drivers. 
    cleanup_old_drivers
    TEMP=/tmp/$$/$index
    rm -rf $TEMP
    mkdir -p $TEMP
    KERNEL_DRV_ZIPS=`ls $DEV/driver/*.zip | head -n 3`
    for KERNEL_DRV_ZIP in $KERNEL_DRV_ZIPS; do 
        if [[ $KERNEL_DRV_ZIP == *"hal.zip" ]]; then
          echo "Found hal zip..ignoring"
          continue
        fi
        cp $KERNEL_DRV_ZIP $TEMP
        cd $TEMP
        echo $TEMP
        KERNEL_DRV_ZIP=`basename $KERNEL_DRV_ZIP`
        unzip $KERNEL_DRV_ZIP
        cd driver
        
        for DIR in *; do
            MAKEFILE_DIR=`find $DIR -name Makefile 2>/dev/null`
            if [ -z "$MAKEFILE_DIR" ]; then
                echo "no makefile found in $DIR"
                continue
            fi
            cd `dirname $MAKEFILE_DIR`
            echo "INFO: building kernel mode driver"
            make
            MODULE=`ls *.ko | head -n 1`
            if [ $OWNER != "root" ]; then
                echo "WARN: root priviledges required, skipping installation of kernel module $MODULE"
            else
                NEW_MODULE_VER=`modinfo -F version $MODULE 2>&1`
                MODULE=`basename $MODULE .ko`
                OLD_MODULE_VER=`modinfo -F version $MODULE 2>&1`
                if [ $? == 0 ]; then
                  update_check "$NEW_MODULE_VER" "$OLD_MODULE_VER"
                  UPDATE=$?
                else
                  UPDATE=0
                fi
                if [ $UPDATE -eq 0 ] || [ $FORCE_INSTALL_KERNEL_DRV == "yes" ]; then
                    echo "INFO: Installing new kernel mode driver $MODULE version $NEW_MODULE_VER"
                    make install
                    if [ -z "$NEW_MODULE_VER" ]; then
                        # "$NEW_MODULE_VER" is 2015.4 driver where the Makefile does not load the
                        # currently built kernel module. We need to manually load the driver.
                        ( rmmod $MODULE || true ) > /dev/null 2>&1
                        modprobe $MODULE
                    fi
                else
                    echo "INFO: More recent kernel mode driver $MODULE version $OLD_MODULE_VER already installed"
                    echo "INFO: Skipping install of newly built kernel mode driver"
                    ( rmmod $MODULE || true ) > /dev/null 2>&1
                    modprobe $MODULE
                fi
                
                if [ $? != 0 ]; then
                    echo "Error occured while installing $MODULE "
                    err=1
                fi
            fi
        done
        rm -rf $TEMP/driver
        cd $ROOT_DIR
    done
    index=$((index + 1))
done

rm -rf /tmp/$$
cd $ROOT_DIR

echo "Generating SDAccel runtime environment setup script, setup.sh for bash"
#-- setup.sh
echo "export XILINX_OPENCL=$DEST" > setup.sh
echo "export LD_LIBRARY_PATH=\$XILINX_OPENCL/runtime/lib/$PLAT:\$LD_LIBRARY_PATH" >> setup.sh
echo "export PATH=\$XILINX_OPENCL/runtime/bin:\$PATH" >> setup.sh
#echo "export XCL_PLATFORM=$XCL_PLATFORM" >> setup.sh
echo "unset XILINX_SDACCEL" >> setup.sh
echo "unset XILINX_SDX" >> setup.sh
echo "unset XCL_EMULATION_MODE" >> setup.sh

#-- setup.csh

echo "Generating SDAccel runtime environment setup script, setup.csh for (t)csh"
echo "setenv XILINX_OPENCL $DEST" > setup.csh
echo "if ( ! \$?LD_LIBRARY_PATH ) then" >> setup.csh
echo "    setenv LD_LIBRARY_PATH \$XILINX_OPENCL/runtime/lib/$PLAT" >> setup.csh
echo "else" >> setup.csh
echo "    setenv LD_LIBRARY_PATH \$XILINX_OPENCL/runtime/lib/$PLAT:\$LD_LIBRARY_PATH" >> setup.csh
echo "endif" >> setup.csh

echo "if ( ! \$?PATH ) then" >> setup.csh
echo "    setenv PATH \$XILINX_OPENCL/runtime/bin" >> setup.csh
echo "else" >> setup.csh
echo "    setenv PATH \$XILINX_OPENCL/runtime/bin:\$PATH" >> setup.csh
echo "endif" >> setup.csh

#echo "setenv XCL_PLATFORM $XCL_PLATFORM" >> setup.csh
echo "unsetenv XILINX_SDACCEL" >> setup.csh
echo "unsetenv XILINX_SDX" >> setup.csh
echo "unsetenv XCL_EMULATION_MODE" >> setup.csh
exit $err


