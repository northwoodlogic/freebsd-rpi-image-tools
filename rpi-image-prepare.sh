#!/bin/sh
#
# BSD 2-Clause License
#
# Copyright (c) 2016, Dave Rush
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -x

# The overlay archive is optional. If it exists it will be extracted to
# ${IMG_ROOT} after all other archive have been extracted. The archives are
# built using the standard archive building mechanism in the tree.

BASE=base.txz
KERN=kernel.txz
FW=firmware.txz
OVERLAY=overlay.txz

THIS_DIR=$(realpath)
IMG_ROOT=${THIS_DIR}/imgroot
IMG_DEVFS=${THIS_DIR}/imgroot/dev
IMG_FW_DIR=${IMG_ROOT}/boot/msdos
IMG_FSTAB=${IMG_ROOT}/etc/fstab
IMG_LOADER_CONF=${IMG_ROOT}/boot/loader.conf

QEMU_STATIC=/usr/local/bin/qemu-arm-static

umountdevfs () {
    mount | grep "${IMG_DEVFS}" > /dev/null 2>&1
    if [ $? = 0 ]; then
        umount ${IMG_DEVFS}
    fi
}

for arc in ${BASE} ${KERN} ${FW}; do
    if ! [ -e "${arc}" ]; then
        echo "Missing archive: ${arc}"
        exit 1
    fi
done

# Devfs probably won't be mounted. May need to check for proc or fdescfs
umountdevfs
trap umountdevfs EXIT

set -e
if [ -d "${IMG_ROOT}" ]; then
    echo "Going to remove ${IMG_ROOT}"
    chflags -R noschg ${IMG_ROOT}
    rm -Rf ${IMG_ROOT}
fi

mkdir ${IMG_ROOT}
tar -xvf ${BASE} -C ${IMG_ROOT}
tar -xvf ${KERN} -C ${IMG_ROOT}

mkdir ${IMG_FW_DIR}
# The firmware archive has a leading "firmware" directory component. The
# firmware files need to be placed directly in the msdos directory.
tar -xvf ${FW} --strip-components 1 -C ${IMG_FW_DIR}
# "ubldr", "ubldr.bin", "rpi.dtb" needs to be copied to the FW dir too.
cp ${IMG_ROOT}/boot/ubldr       ${IMG_FW_DIR}
cp ${IMG_ROOT}/boot/ubldr.bin   ${IMG_FW_DIR}

# TODO: Make this a configurable parameter to copy just RPI1 or RPI2 dtb.
cp ${IMG_ROOT}/boot/dtb/rpi.dtb ${IMG_FW_DIR}
cp ${IMG_ROOT}/boot/dtb/rpi2.dtb ${IMG_FW_DIR}

if [ -e "${OVERLAY}" ]; then
    echo "Extracting overlay archive: ${OVERLAY}"
    tar -xvf ${OVERLAY} -C ${IMG_ROOT}
fi

mkdir -p "${IMG_ROOT}/usr/local/bin"
cp $QEMU_STATIC ${IMG_ROOT}/usr/local/bin
mount -t devfs none ${IMG_ROOT}/dev
cp /etc/resolv.conf ${IMG_ROOT}/etc/

if [ -e "rpi-image.packages" ] ; then
    # This allows the rpi-image tools to run out of source checkout
    # directory or be installed system wide.
    if [ -e "rpi-image-install-packages.sh" ] ; then
        install -m 755 rpi-image-install-packages.sh ${IMG_ROOT}/
    else
        install -m 755 /usr/local/bin/rpi-image-install-packages.sh ${IMG_ROOT}/
    fi
    cp rpi-image.packages ${IMG_ROOT}/
    chroot ${IMG_ROOT} ./rpi-image-install-packages.sh

    rm ${IMG_ROOT}/rpi-image-install-packages.sh
    rm ${IMG_ROOT}/rpi-image.packages
    rm ${IMG_ROOT}/var/cache/pkg/*.txz
fi

if [ -d "root" ] ; then
    # The config script will need to set any special permissions on these
    # files. They are specifically not copied in archive mode to prevent
    # files being owned by normal users on the host build system. They will be
    # owned by root.
    cp -RPv root/ ${IMG_ROOT}
fi

# Run user supplied config.sh script here!
if [ -e "rpi-config.sh" ] ; then
    cp rpi-config.sh ${IMG_ROOT}
    chmod a+x ${IMG_ROOT}/rpi-config.sh
    chroot ${IMG_ROOT} ./rpi-config.sh
    rm ${IMG_ROOT}/rpi-config.sh
fi

umount ${IMG_ROOT}/dev
rm ${IMG_ROOT}/etc/resolv.conf
rm ${IMG_ROOT}/usr/local/bin/qemu-arm-static
# This is kind of a wart. Installing packages from in the chroot requires
# name resolution and will need to use the config from the host system.
# The image may want to configure itself with different settings.
# Therefore, the config script should write out any custom resolv.conf to
# a file called "etc/resolv.conf.img" and it will get fixed up later.
if [ -e "${IMG_ROOT}/etc/resolv.conf.img" ] ; then
    mv ${IMG_ROOT}/etc/resolv.conf.img ${IMG_ROOT}/etc/resolv.conf
fi

# If there isn't an fstab in the image directory then create one. The image
# may do more `creative` things like setting the vfs.root.mountfrom loader
# config variable and mount root from a USB or iSCSI share. This is just a
# bare bones fallback option.
if ! [ -e "${IMG_FSTAB}" ] ; then
    echo "Creating Image fstab: ${IMG_FSTAB}"
    cat > ${IMG_FSTAB} <<EOT
/dev/msdosfs/UBOOT /boot/msdos msdosfs rw,noatime   0 0
/dev/ufs/uroot /           ufs     rw,noatime       1 1
tmpfs          /tmp        tmpfs   rw,size=64m      0 0
tmpfs          /var/tmp    tmpfs   rw,size=32m      0 0
tmpfs          /var/log    tmpfs   rw,size=32m      0 0
EOT
fi

# If the image config script didn't set a root device then set up a default
# one.
if ! [ -e "${IMG_LOADER_CONF}" ] ; then
    echo -n "" > ${IMG_LOADER_CONF}
fi

WRITE_VFSROOT_CONF="no"
grep "vfs.root.mountfrom" < ${IMG_LOADER_CONF} || WRITE_VFSROOT_CONF=$(echo "yes")

if [ "$WRITE_VFSROOT_CONF" = "yes" ] ; then
cat >> ${IMG_LOADER_CONF} <<EOT
vfs.root.mountfrom="ufs:/dev/ufs/uroot"
EOT
fi

set +e
