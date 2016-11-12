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

IMG_SIZE=1000

THIS_DIR=$(realpath)
IMG_ROOT=${THIS_DIR}/imgroot
IMG_DEVFS=${THIS_DIR}/imgroot/dev
IMG_FW_DIR=${IMG_ROOT}/boot/msdos
IMG_FSTAB=${IMG_ROOT}/etc/fstab
IMG_NAME=imgroot.img
IMG_MNTP=imgroot.md
IMG_NAME_MMCBOOT=mmcboot.img
IMG_MNTP_MMCBOOT=mmcboot.md

dd if=/dev/zero of=${IMG_NAME} bs=1M count=${IMG_SIZE}
dd if=/dev/zero of=${IMG_NAME_MMCBOOT} bs=1M count=24
MD_DEV=$(mdconfig -t vnode ${IMG_NAME})
MD_DEV_MMCBOOT=$(mdconfig -t vnode ${IMG_NAME_MMCBOOT})


if [ -d "${IMG_MNTP}" ]; then
    chflags -R noschg ${IMG_MNTP}
    rm -Rf ${IMG_MNTP}
fi

echo "MD_DEV: ${MD_DEV}"
echo "MD_DEV_MMCBOOT: ${MD_DEV_MMCBOOT}"

gpart create -s MBR ${MD_DEV}
gpart add -a 63 -s 24M -t '!12' ${MD_DEV}
gpart set -a active -i 1 ${MD_DEV}
gpart add -t freebsd ${MD_DEV}
gpart create -s BSD ${MD_DEV}s2
gpart add -t freebsd-ufs -a 64k ${MD_DEV}s2
newfs_msdos -L UBOOT -F 16 ${MD_DEV}s1
newfs ${MD_DEV}s2a

# Construct the MMC boot only image and filesystem
if [ -d "${IMG_MNTP_MMCBOOT}" ]; then
    rm -Rf ${IMG_MNTP_MMCBOOT}
fi

# Partition formatting is inspired from Crochet build scripts.
gpart create -s MBR ${MD_DEV_MMCBOOT}
gpart add -a 63 -t '!12' ${MD_DEV_MMCBOOT}
gpart set -a active -i 1 ${MD_DEV_MMCBOOT}
newfs_msdos -L UBOOTMMC -F 16 ${MD_DEV_MMCBOOT}s1
mkdir ${IMG_MNTP_MMCBOOT}
mount -t msdosfs /dev/${MD_DEV_MMCBOOT}s1 ${IMG_MNTP_MMCBOOT}

mkdir ${IMG_MNTP}
mount -o async /dev/${MD_DEV}s2a ${IMG_MNTP}
mkdir -p ${IMG_MNTP}/boot/msdos
mount -t msdosfs /dev/${MD_DEV}s1 ${IMG_MNTP}/boot/msdos

# This will throw an error because it can't preserve file permissions
# in the FAT partiton. Not sure how to work around this.
tar -cf - -C ${IMG_ROOT} . | tar -xvf - -C ${IMG_MNTP}

# This will throw an error from tar for the same reason as above.
tar -cf - -C ${IMG_ROOT}/boot/msdos . | tar -xvf - -C ${IMG_MNTP_MMCBOOT}
echo "loaderdev=usb 0" >> ${IMG_MNTP_MMCBOOT}/uenv.txt
sync

umount ${IMG_MNTP}/boot/msdos
umount ${IMG_MNTP}
umount ${IMG_MNTP_MMCBOOT}

# The journal size is inspired from Crochet build scripts.
tunefs -n enable /dev/${MD_DEV}s2a
tunefs -j enable -S 4194304 /dev/${MD_DEV}s2a
tunefs -N enable /dev/${MD_DEV}s2a
tunefs -L uroot /dev/${MD_DEV}s2a

mdconfig -d -u ${MD_DEV}
mdconfig -d -u ${MD_DEV_MMCBOOT}
mount

if [ -e "${IMG_NAME}.xz" ]; then
    rm ${IMG_NAME}.xz
fi

if [ -e "${IMG_NAME_MMCBOOT}.xz" ]; then
    rm ${IMG_NAME_MMCBOOT}.xz
fi

date
xz --threads=0 ${IMG_NAME}
xz --threads=0 ${IMG_NAME_MMCBOOT}
date


