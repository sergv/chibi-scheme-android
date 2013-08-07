#!/bin/bash
#
# File: build_android.sh
#
# Created: Sunday,  4 August 2013
#

set -e

gcc_prefix="/home/sergey/projects/android/android-ndk-standalone/bin"
cc="ccache ${gcc_prefix}/arm-linux-androideabi-gcc"
clang_flags=""

# gcc_prefix="/home/sergey/projects/android/clang-ndk-standalone/"
# cc="${gcc_prefix}/bin/clang"
# clang_flags="-Wall -Wextra -Wno-unused-parameter -Wno-sign-compare -Wno-format -mstrict-align"

# dest_dir="/home/sergey/projects/scheme/chibi-scheme/android/"
dest_dir="/mnt/disk/projects/chibi-scheme/android"
lib_dest="${dest_dir}/assets"

enable_ndebug="yes"

if [ "${enable_ndebug}X" = "yesX" ]; then
    ndebug_flag="-DNDEBUG=1"
else
    ndebug_flag="-UNDEBUG"
fi

cflags="-marm -mthumb -mthumb-interwork -fpic -fomit-frame-pointer -ffunction-sections -funwind-tables -fstack-protector -no-canonical-prefixes -DANDROID=1 -O2 -g0 -fno-unsafe-math-optimizations -fno-tree-vectorize -march=armv6 -mfloat-abi=softfp ${ndebug_flag} -Wno-unused-parameter"

# cflags="-marm -mthumb -mthumb-interwork -fomit-frame-pointer -ffunction-sections -funwind-tables -fstack-protector -no-canonical-prefixes -DANDROID=1 -O2 -g3 -fno-unsafe-math-optimizations -fno-tree-vectorize -march=armv6 -mfloat-abi=softfp ${ndebug_flag} ${clang_flags}"

# --analyze
 # -fsanitize=address -fsanitize=thread -fsanitize=undefined


ldflags="-Wl,-soname,libchibi-scheme.so -no-canonical-prefixes -Wl,--no-undefined -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -llog"


echo "Clearing"
make clean
rm -f -r "${dest_dir}/assets/lib.zip" "${dest_dir}/jni/libchibi-scheme.so"

echo -e "\nBuilding host executable"
# creates chibi-scheme-static-host executable
host_cflags="-O2 -g0 -DNDEBUG"
make CC=ccache\ gcc CFLAGS="${host_cflags}" chibi-scheme-static-host -j 4

echo -e "\nClearing after host build"
make clean

echo -e "\nBuilding main library and extension libraries for android"

# SEXP_USE_NTP_GETTIME requires sys/timex.h which is not available on android
make CHIBI="./chibi-scheme-static-host" CC="${cc}" CFLAGS="${cflags}" LDFLAGS="${ldflags}" PLATFORM=Android SEXP_USE_NTP_GETTIME=0 PREFIX="" DESTDIR="${lib_dest}" XLIBS=-lm\ -llog all libchibi-scheme.so all-libs -j 1
# install

# make lib.zip distribution with modules
find lib \( -name '*.so' -o -name '*.sld' -o -name '*.scm' -o -type d \) -print | \
    zip --names-stdin "${lib_dest}/lib.zip"

cp libchibi-scheme.so "${dest_dir}/jni"

pushd android

if [ ! -f "jni/libchibi-scheme.so" ]; then
    echo "library jni/libchibi-scheme.so not found, but is neened to proceed" >&2
    exit 1
fi

ndebg=""
if [ "${enable_ndebug}X" = "yesX" ]; then
    ndebg="1"
else
    ndebg="0"
fi


# build android jni

for build_type in "BUILD_ARMV7=0"; do # "BUILD_ARMV7=1"; do
    ${NDK_HOME}/ndk-build APP_BUILD_SCRIPT=./jni/Application.mk $build_type NDEBUG="${ndebg}" "${@}"
done

cp "jni/libchibi-scheme.so" libs/armeabi/
# ~/projects/android/android-ndk-standalone/bin/arm-linux-androideabi-strip libs/armeabi/*.so

popd

exit 0

