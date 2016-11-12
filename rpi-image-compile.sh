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

set -e
set -x

echo "Current Environment"
echo "Path: `pwd`"
NCPU=$(sysctl -n hw.ncpu)
env

# When running by hand, do it like this:
#
#   xtarget=rpi sudo -E ./rpi-image-compile.sh
# or
#   xtarget=rpi2 sudo -E ./rpi-image-compile.sh
#
# But, this script is really meant to be used with Jenkins. Define a Matrix
# build with a "User-defined Axis" with a name of "xtarget" and values of
# "rpi rpi2".

xtarget=${xtarget:-rpi2}

echo "xtarget: $xtarget"

if [ -d "bld" ]; then
    chflags -R noschg bld
    rm -Rf bld
fi

if [ -d "source/release/dist" ]; then
    chflags -R noschg source/release/dist
    rm -Rf source/release/dist
fi

export BASEDIR=$(pwd)
export MAKEOBJDIRPREFIX=`pwd`/bld
export TARGET=arm
export TARGET_ARCH=armv6
export UBLDR_LOADADDR=0x2000000
echo "Number of CPUs $NCPU"

# Assume RPI2, but built rpi if specified
export KERNCONF=RPI2
if [ "${xtarget}" = "rpi" ]; then
    export KERNCONF=RPI-B
fi

make -C source -j$NCPU buildworld
make -C source -j$NCPU buildkernel
make -C source/release base.txz
make -C source/release kernel.txz
mv source/release/*.txz .
env

