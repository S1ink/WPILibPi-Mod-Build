#!/bin/bash

SUB_STAGE_DIR=${PWD}

#
# Fixup absolute links to relative in /usr/lib and libs in /etc/alternatives
#
pushd "${ROOTFS_DIR}"
find ./usr/lib -lname '/*' | \
  while read l
  do
    echo ln -sf $(echo $(echo $l | sed 's|/[^/]*|/..|g')$(readlink $l) | sed 's/.....//') $l
  done | sh
find ./usr/include -lname '/*' | \
  while read l
  do
    echo ln -sf $(echo $(echo $l | sed 's|/[^/]*|/..|g')$(readlink $l) | sed 's/.....//') $l
  done | sh
find ./etc/alternatives -lname '/*.so.*' | \
  while read l
  do
    echo ln -sf $(echo $(echo $l | sed 's|/[^/]*|/..|g')$(readlink $l) | sed 's/.....//') $l
  done | sh
find ./etc/alternatives -lname '/*/arm-linux-gnueabihf/*' | \
  while read l
  do
    echo ln -sf $(echo $(echo $l | sed 's|/[^/]*|/..|g')$(readlink $l) | sed 's/.....//') $l
  done | sh
popd

#
# Add symbolic link for cblas.h to /usr/include (required by OpenCV)
#
ln -sf arm-linux-gnueabihf/cblas.h "${ROOTFS_DIR}/usr/include/cblas.h"

#
# Download sources
#
DOWNLOAD_DIR=${STAGE_WORK_DIR}/download
mkdir -p ${DOWNLOAD_DIR}
pushd ${DOWNLOAD_DIR}

# raspbian toolchain
wget -nc -nv \
    https://github.com/wpilibsuite/opensdk/releases/download/v2023-7/armhf-raspi-bullseye-2023-i686-linux-gnu-Toolchain-10.2.0.tgz
#    https://github.com/wpilibsuite/raspbian-toolchain/releases/download/v2.1.0/Raspbian10-Linux-i386-Toolchain-8.3.0.tar.gz

# opencv sources
wget -nc -nv \
    https://github.com/opencv/opencv/archive/4.6.0.tar.gz

# allwpilib
wget -nc -nv -O allwpilib.tar.gz \
    https://github.com/wpilibsuite/allwpilib/archive/v2023.1.1-beta-3.tar.gz
#    https://github.com/wpilibsuite/allwpilib/archive/6e23985ae612c396958dfebed3aa25d1f09ec538.tar.gz
#    https://github.com/wpilibsuite/allwpilib/archive/v2023.1.1-beta-4.tar.gz

# pynetworktables
wget -nc -nv -O pynetworktables.tar.gz \
    https://github.com/robotpy/pynetworktables/archive/2021.0.0.tar.gz

# robotpy-cscore
wget -nc -nv -O robotpy-cscore.tar.gz \
    https://github.com/robotpy/robotpy-cscore/archive/2022.0.3.tar.gz

# pybind11 submodule of robotpy-cscore
wget -nc -nv -O pybind11.tar.gz \
    https://github.com/robotpy/pybind11/archive/67b55bcf7887aad358a6bc91c73e07d1920e96bd.tar.gz

# pixy2
wget -nc -nv -O pixy2.tar.gz \
    https://github.com/charmedlabs/pixy2/archive/2adc6caba774a3056448d0feb0c6b89855a392f4.tar.gz

popd

#
# Extract and patch sources
#
EXTRACT_DIR=${ROOTFS_DIR}/usr/src
install -v -d ${EXTRACT_DIR}
pushd ${EXTRACT_DIR}

# opencv
tar xzf "${DOWNLOAD_DIR}/4.6.0.tar.gz"
pushd opencv-4.6.0
sed -i -e 's/javac sourcepath/javac target="1.8" source="1.8" sourcepath/' modules/java/jar/build.xml.in
# disable extraneous data warnings; these are common with USB cameras
sed -i -e '/JWRN_EXTRANEOUS_DATA/d' 3rdparty/libjpeg/jdmarker.c
sed -i -e '/JWRN_EXTRANEOUS_DATA/d' 3rdparty/libjpeg-turbo/src/jdmarker.c
patch -p0 < "${SUB_STAGE_DIR}/files/opencv.patch"
popd

# allwpilib
tar xzf "${DOWNLOAD_DIR}/allwpilib.tar.gz"
mv allwpilib-* allwpilib
pushd allwpilib
sed -i -e 's/add_subdirectory(fieldImages)//' CMakeLists.txt
sed -i -e 's/-Werror/-Werror -Wno-error=deprecated-declarations/' cmake/modules/CompileWarnings.cmake
popd

# pynetworktables
tar xzf "${DOWNLOAD_DIR}/pynetworktables.tar.gz"
mv pynetworktables-* pynetworktables
echo "__version__ = '2021.0.0'" > pynetworktables/_pynetworktables/_impl/version.py

# robotpy-cscore
tar xzf "${DOWNLOAD_DIR}/robotpy-cscore.tar.gz"
mv robotpy-cscore-* robotpy-cscore
echo "__version__ = '2022.0.2'" > robotpy-cscore/cscore/version.py
pushd robotpy-cscore
rm -rf pybind11
tar xzf "${DOWNLOAD_DIR}/pybind11.tar.gz"
mv pybind11-* pybind11
popd

# pixy2
tar xzf "${DOWNLOAD_DIR}/pixy2.tar.gz"
mv pixy2-* pixy2
rm -rf pixy2/releases
sed -i -e 's/^python/python3/;s/_pixy.so/_pixy.*.so/' pixy2/scripts/build_python_demos.sh
sed -i -e 's/print/#print/' pixy2/src/host/libpixyusb2_examples/python_demos/setup.py

popd

#
# Build
#

# get number of CPU cores
NCPU=`grep -c 'cpu[0-9]' /proc/stat`

# extract raspbian toolchain
pushd ${WORK_DIR}
tar xzf ${DOWNLOAD_DIR}/armhf-raspi-bullseye-*.tgz
export PATH=${WORK_DIR}/raspi-bullseye/bin:${PATH}
popd

export RPI_CROSS_PREFIX=arm-linux-gnueabihf     # armv6-bullseye-linux-gnueabihf for downloaded toolchain
export RPI_CROSS_VERSION=10
export RPI_CROSS_CXX=${RPI_CROSS_PREFIX}-g++-${RPI_CROSS_VERSION}
export RPI_CROSS_CC=${RPI_CROSS_PREFIX}-gcc-${RPI_CROSS_VERSION}

export PKG_CONFIG_DIR=
export PKG_CONFIG_LIBDIR=${ROOTFS_DIR}/usr/lib/arm-linux-gnueabihf/pkgconfig:${ROOTFS_DIR}/usr/lib/pkgconfig:${ROOTFS_DIR}/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=${ROOTFS_DIR}

pushd ${STAGE_WORK_DIR}
#
# Build OpenCV
#
build_opencv () {
    rm -rf $1
    mkdir -p $1
    pushd $1
    cmake "${EXTRACT_DIR}/opencv-4.6.0" \
	-DWITH_FFMPEG=OFF \
        -DBUILD_JPEG=ON \
        -DBUILD_TESTS=OFF \
        -DPython_ADDITIONAL_VERSIONS=3.9 \
        -DBUILD_JAVA=$3 \
        -DENABLE_CXX11=ON \
        -DBUILD_SHARED_LIBS=$3 \
        -DCMAKE_BUILD_TYPE=$2 \
        -DCMAKE_DEBUG_POSTFIX=d \
        -DCMAKE_TOOLCHAIN_FILE=${SUB_STAGE_DIR}/files/arm-pi-gnueabihf.toolchain.cmake \
        -DARM_LINUX_SYSROOT=${ROOTFS_DIR} \
        -DCMAKE_MAKE_PROGRAM=make \
        -DENABLE_NEON=ON \
        -DENABLE_VFPV3=ON \
        -DBUILD_opencv_python3=$3 \
        -DPYTHON3_INCLUDE_PATH=${ROOTFS_DIR}/usr/include/python3.9 \
        -DPYTHON3_NUMPY_INCLUDE_DIRS=${ROOTFS_DIR}/usr/include/python3.9/numpy \
        -DOPENCV_EXTRA_FLAGS_DEBUG=-Og \
	-DOPENCV_GENERATE_PKGCONFIG=ON \
        -DCMAKE_MODULE_PATH=${SUB_STAGE_DIR}/files \
        -DCMAKE_INSTALL_PREFIX=/usr/local/frc$4 \
        || exit 1
    make -j${NCPU} || exit 1
    make DESTDIR=${ROOTFS_DIR} install || exit 1
    popd
}

build_opencv build/opencv-build-debug Debug ON "" || exit 1
build_opencv build/opencv-build Release ON "" || exit 1
build_opencv build/opencv-static Release OFF "-static" || exit 1

# fix up java install
cp -p ${ROOTFS_DIR}/usr/local/frc/share/java/opencv4/libopencv_java460*.so "${ROOTFS_DIR}/usr/local/frc/lib/"
mkdir -p "${ROOTFS_DIR}/usr/local/frc/java"
cp -p "${ROOTFS_DIR}/usr/local/frc/share/java/opencv4/opencv-460.jar" "${ROOTFS_DIR}/usr/local/frc/java/"

# the opencv build names the python .so with the build platform name
# instead of the target platform, so rename it
pushd "${ROOTFS_DIR}/usr/local/frc/lib/python3.9/site-packages/cv2/python-3.9"
mv cv2.cpython-39-*-gnu.so cv2.cpython-39-arm-linux-gnueabihf.so
mv cv2d.cpython-39-*-gnu.so cv2d.cpython-39-arm-linux-gnueabihf.so
popd

# link python package to dist-packages
ln -sf /usr/local/frc/lib/python3.9/site-packages/cv2 "${ROOTFS_DIR}/usr/local/lib/python3.9/dist-packages/cv2"

#
# Build wpiutil, cscore, ntcore, cameraserver
# always use the release version of opencv jar/jni
#
build_wpilib () {
    rm -rf $1
    mkdir -p $1
    pushd $1
    cmake "${EXTRACT_DIR}/allwpilib" \
        -DWITH_GUI=OFF \
        -DWITH_TESTS=OFF \
        -DWITH_SIMULATION_MODULES=OFF \
        -DCMAKE_BUILD_TYPE=$2 \
        -DCMAKE_TOOLCHAIN_FILE=${SUB_STAGE_DIR}/files/arm-pi-gnueabihf.toolchain.cmake \
        -DCMAKE_MODULE_PATH=${SUB_STAGE_DIR}/files \
        -DOPENCV_JAR_FILE=`ls ${ROOTFS_DIR}/usr/local/frc/java/opencv-460.jar` \
        -DOPENCV_JNI_FILE=`ls ${ROOTFS_DIR}/usr/local/frc/lib/libopencv_java460.so` \
        -DOpenCV_DIR=${ROOTFS_DIR}/usr/local/frc/share/opencv4 \
        -DTHREADS_PTHREAD_ARG=-pthread \
        -DCMAKE_INSTALL_PREFIX=/usr/local/frc \
        || exit 1
    make -j${NCPU} || exit 1
    popd
}

build_wpilib build/allwpilib-build-debug Debug || exit 1
build_wpilib build/allwpilib-build Release || exit 1

# static (for tools)
build_static_wpilib() {
    rm -rf $1
    mkdir -p $1
    pushd $1
    cmake "${EXTRACT_DIR}/allwpilib" \
        -DWITH_GUI=OFF \
        -DWITH_TESTS=OFF \
        -DWITH_SIMULATION_MODULES=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${SUB_STAGE_DIR}/files/arm-pi-gnueabihf.toolchain.cmake \
        -DCMAKE_MODULE_PATH=${SUB_STAGE_DIR}/files \
        -DOpenCV_DIR=${ROOTFS_DIR}/usr/local/frc/share/OpenCV \
        -DWITH_JAVA=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DTHREADS_PTHREAD_ARG=-pthread \
        -DCMAKE_INSTALL_PREFIX=/usr/local/frc-static \
        || exit 1
    make -j${NCPU} || exit 1
    popd
}
build_static_wpilib build/allwpilib-static || exit 1

# manually install, since cmake install is a bit weirdly set up
# built libs and headers
sh -c 'cd build/allwpilib-build/lib && tar cf - lib*' | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/lib && tar xf -"
sh -c 'cd build/allwpilib-build-debug/lib && tar cf - lib*' | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/lib && tar xf -"
sh -c 'cd build/allwpilib-static/lib && tar cf - lib*' | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc-static/lib && tar xf -"
sh -c 'cd build/allwpilib-build/hal/gen && tar cf - .' | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"

# built jars
sh -c 'cd build/allwpilib-build/jar && tar cf - *.jar' | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/java && tar xf -"

# headers
#apriltag
sh -c "cd ${EXTRACT_DIR}/allwpilib/apriltag/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#cameraserver
sh -c "cd ${EXTRACT_DIR}/allwpilib/cameraserver/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#cscore
sh -c "cd ${EXTRACT_DIR}/allwpilib/cscore/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#hal
sh -c "cd ${EXTRACT_DIR}/allwpilib/hal/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#ntcore + generated
sh -c "cd ${EXTRACT_DIR}/allwpilib/ntcore/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd build/allwpilib-build/ntcore/generated/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#wpilibc
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpilibc/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#wpimath + drake, eigen, gcem
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpimath/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpimath/src/main/native/thirdparty/eigen/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpimath/src/main/native/thirdparty/drake/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpimath/src/main/native/thirdparty/gcem/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#wpinet + uv, tcpsockets
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpinet/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpinet/src/main/native/thirdparty/libuv/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpinet/src/main/native/thirdparty/tcpsockets/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
#wpiutil + fmt, ghc, json, llvm, memory, mpack, sigslot
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/thirdparty/fmtlib/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/thirdparty/ghc/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/thirdparty/json/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/thirdparty/llvm/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/thirdparty/memory/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/thirdparty/mpack/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"
sh -c "cd ${EXTRACT_DIR}/allwpilib/wpiutil/src/main/native/thirdparty/sigslot/include && tar cf - ." | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/include && tar xf -"

# executables (use static build to ensure they don't break)
sh -c 'cd build/allwpilib-static/bin && tar cf - cscore_* netconsoleTee*' | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/frc/bin && tar xf -"

# pkgconfig files
install -v -d "${ROOTFS_DIR}/usr/local/frc/lib/pkgconfig"
install -m 644 ${SUB_STAGE_DIR}/files/pkgconfig/* "${ROOTFS_DIR}/usr/local/frc/lib/pkgconfig"
install -v -d "${ROOTFS_DIR}/usr/local/frc-static/lib/pkgconfig"
for f in ${SUB_STAGE_DIR}/files/pkgconfig/*.pc; do
  install -m 644 $f "${ROOTFS_DIR}/usr/local/frc-static/lib/pkgconfig"
  sed -i -e 's,/usr/local/frc,/usr/local/frc-static,' "${ROOTFS_DIR}/usr/local/frc-static/lib/pkgconfig/`basename $f`"
done

# clean up frc-static
rm -rf "${ROOTFS_DIR}/usr/local/frc-static/bin"
rm -rf "${ROOTFS_DIR}/usr/local/frc-static/include"
ln -sf ../frc/include "${ROOTFS_DIR}/usr/local/frc-static/include"
rm -rf "${ROOTFS_DIR}/usr/local/frc-static/python"

# fix up frc-static opencv pkgconfig Libs.private
sed -i -e 's, -L/pi-gen[^ ]*,,g' "${ROOTFS_DIR}/usr/local/frc-static/lib/pkgconfig/opencv4.pc"

# echo "************************"
# pushd "${ROOTFS_DIR}/usr/local"
# ls -l -R
# popd
# echo "************************"

popd

#
# Install pynetworktables
#

#sh -c "cd ${EXTRACT_DIR}/pynetworktables && tar cf - networktables ntcore" | sh -c "cd ${ROOTFS_DIR}/usr/local/lib/python3.9/dist-packages/ && tar xf -"
on_chroot << EOF
pip3 install setuptools
pushd /usr/src/pynetworktables
python3 setup.py build
python3 setup.py install
python3 setup.py clean
popd
EOF

#
# Build robotpy-cscore
# this build is pretty cpu-intensive, so we don't want to build it in a chroot,
# and setup.py doesn't support cross-builds, so build it manually
#
# NOTE: robotpy-cscore now supports an upgraded build system -- this should be used instead of manual build --> *and update to newest*
#
pushd ${EXTRACT_DIR}/robotpy-cscore

# install Python sources
sh -c 'tar cf - cscore' | \
    sh -c "cd ${ROOTFS_DIR}/usr/local/lib/python3.9/dist-packages && tar xf -"

# install blank _init_cscore.py
touch "${ROOTFS_DIR}/usr/local/lib/python3.9/dist-packages/cscore/_init_cscore.py"

# [temporary fix] try to upgrade wpi::span to std::span for 2023/c++-20 compatibility
pushd src
sed -i -- 's/wpi::span/std::span/g' *
popd

# build module
${RPI_CROSS_CXX} \
    --sysroot=${ROOTFS_DIR} \
    -g -O -Wall -fvisibility=hidden -shared -fPIC -std=c++20 \
    -o "${ROOTFS_DIR}/usr/local/lib/python3.9/dist-packages/_cscore.cpython-39-arm-linux-gnueabihf.so" \
    -Ipybind11/include \
    `env PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR}:${ROOTFS_DIR}/usr/local/frc/lib/pkgconfig pkg-config --cflags python3 cscore wpiutil` \
    src/_cscore.cpp \
    src/ndarray_converter.cpp \
    `env PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR}:${ROOTFS_DIR}/usr/local/frc/lib/pkgconfig pkg-config --libs cscore wpiutil` \
    || exit 1

popd

#
# Build pixy2
#
on_chroot << EOF
pushd /usr/src/pixy2/scripts
./build_libpixyusb2.sh
./build_python_demos.sh
popd
EOF

install -m 644 "${EXTRACT_DIR}/pixy2/build/libpixyusb2/libpixy2.a" "${ROOTFS_DIR}/usr/local/frc/lib/"
install -m 644 "${EXTRACT_DIR}/pixy2/build/python_demos/pixy.py" "${ROOTFS_DIR}/usr/local/lib/python3.9/dist-packages/"
install -m 755 ${EXTRACT_DIR}/pixy2/build/python_demos/_pixy.*.so "${ROOTFS_DIR}/usr/local/lib/python3.9/dist-packages/"
rm -rf "${EXTRACT_DIR}/pixy2/build"

#
# Finish up
#

# Split debug info

split_debug () {
    ${RPI_CROSS_PREFIX}-objcopy --only-keep-debug $1 $1.debug
    ${RPI_CROSS_PREFIX}-strip -g $1
    ${RPI_CROSS_PREFIX}-objcopy --add-gnu-debuglink=$1.debug $1
}

split_debug_so () {
    pushd $1
    for lib in *.so
    do
        split_debug $lib
    done
    popd
}

split_debug_exe () {
    pushd $1
    for exe in *
    do
        split_debug $exe
    done
    popd
}

split_debug_exe "${ROOTFS_DIR}/usr/local/frc/bin"
split_debug_so "${ROOTFS_DIR}/usr/local/frc/lib"

# Add /usr/local/frc/lib to ldconfig

install -m 644 files/ld.so.conf.d/*.conf "${ROOTFS_DIR}/etc/ld.so.conf.d/"

# Add /usr/local/frc/lib/pkgconfig to pkg-config

install -m 644 files/profile.d/*.sh "${ROOTFS_DIR}/etc/profile.d/"

# Add udev rules

install -m 644 files/rules.d/*.rules "${ROOTFS_DIR}/etc/udev/rules.d/"

on_chroot << EOF
ldconfig
EOF
