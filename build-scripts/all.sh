#!/bin/bach

set -e

export FLANGDIR=/opt/R/flang-23

if [ -e /Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk ]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk
    export MACOSX_DEPLOYMENT_TARGET=14.0
fi
if [ -e /Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk ]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk
    export MACOSX_DEPLOYMENT_TARGET=13.0
fi
if [ -z "$SDKROOT" ]; then
    if [ -e /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk ]; then
	echo ''
	echo "WARNING: neither 13.3 nor 14.0 SDKs are present, falling back to default!"
	echo "         MACOSX_DEPLOYMENT_TARGET will NOT be set, so the target may be unsuitably high!"
	echo ''
	export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
    else
	echo "ERROR: SDKROOT is not set and CLI SDK is not present, aborting!" >&2
	exit 1
    fi
fi

if [ ! -e ~/Library/Python ]; then
    echo "No python library found, installing ninja"
    pip3 install --user ninja
fi
if [ ! -e /Applications/CMake.app/Contents/bin/cmake ]; then
    echo ERROR: Please put CMake.app into Applications >&2
    exit 1
fi

export PATH="$FLANGDIR/bin:$PATH:/Applications/CMake.app/Contents/bin:`ls -d ~/Library/Python/*/bin`"

ninja --version

## there are two ways to use this script:
## a) from a level above llvm (that's how we build it)
## b) from build-scripts inside the sources (untested!)
if [ -e ../clang/CMakeLists.txt ]; then
    ## symlink teh soruce top directory tollvm
    ln -s .. llvm
fi
if [ ! -e llvm ]; then
    echo WARNING: llvm not found, looking for sources ...
    src=`ls -d llvm-project-*.src/clang | tail -n1`
    if [ -z "$src" ]; then
	echo ERROR: cannot find llvm sources - download and unpack them to llvm-project-x.y.z.src
	exit 1
    fi
    ln -s "$src" llvm
fi

if [ ! -e $FLANGDIR ]; then
    echo $FLANGDIR not present, creating ...
    mkdir -p $FLANGDIR || ( sudo mkdir -p $FLANGDIR && sudo chown $USER $FLANGDIR )
fi

cd llvm

rm -rf build
mkdir build
cd build
../../run-llvm ../llvm
cmake --build . && cmake --install .
cd ..

install_name_tool -id $FLANGDIR/lib/libunwind.1.dylib $FLANGDIR/lib/libunwind.1.0.dylib
install_name_tool -id $FLANGDIR/lib/libomp.5.dylib $FLANGDIR/lib/libomp.dylib
ln -sfn libomp.dylib $FLANGDIR/lib/libomp.5.dylib
install_name_tool -id $FLANGDIR/lib/libc++.1.dylib $FLANGDIR/lib/libc++.1.0.dylib
install_name_tool -id $FLANGDIR/lib/libc++abi.1.dylib $FLANGDIR/lib/libc++abi.1.0.dylib
install_name_tool -change @rpath/libunwind.1.dylib $FLANGDIR/lib/libunwind.1.dylib $FLANGDIR/lib/libc++.1.dylib
install_name_tool -change @rpath/libunwind.1.dylib $FLANGDIR/lib/libunwind.1.dylib $FLANGDIR/lib/libc++abi.1.dylib

for i in libc++.1.dylib libc++abi.1.dylib libclang-cpp.23.1.dylib libLLVM.23.1.dylib libMLIR.23.1.dylib libunwind.1.dylib; do
    install_name_tool -id $FLANGDIR/lib/$i $FLANGDIR/lib/$i
    for j in libc++.1.dylib libc++abi.1.dylib libclang-cpp.23.1.dylib libLLVM.23.1.dylib libMLIR.23.1.dylib libunwind.1.dylib; do
	install_name_tool -change @rpath/$j $FLANGDIR/lib/$j $FLANGDIR/lib/$i
    done
done

## build flang
rm -rf fbuild
mkdir fbuild
cd fbuild
sh ../../run-f ../flang
cmake --build . && cmake --install .
cd ..

## build flang run-time
rm -rf fbuild-rt
mkdir fbuild-rt
cd fbuild-rt
sh ../../run-f ../runtimes
cmake --build . && cmake --install .
cd ..

## move away the full installation
## we want to install just flang w/o anything else
mv $FLANGDIR ${FLANGDIR}-orig

# to install flang w/o LLVM need this:
mkdir -p $FLANGDIR/lib/cmake/llvm
cp ${FLANGDIR}-orig/lib/cmake/llvm/LLVMInstallSymlink.cmake $FLANGDIR/lib/cmake/llvm/LLVMInstallSymlink.cmake

cd fbuild
cmake --install .
cd ../fbuild-rt
cmake --install .
cd ..

## after installation we don't need it anymore
rm -rf $FLANGDIR/lib/cmake

## the following are needed from LLVM
for i in libc++.1.dylib libc++abi.1.dylib libclang-cpp.23.1.dylib libLLVM.23.1.dylib libMLIR.23.1.dylib libunwind.1.dylib; do
    cp ${FLANGDIR}-orig/lib/$i $FLANGDIR/lib/$i
done

## make static runtime the default, but keep the dynamic one just in case
mv $FLANGDIR/lib/clang/23/lib/darwin/libflang_rt.runtime.dylib $FLANGDIR/lib/clang/23/lib/darwin/libflang_rt.runtime.0.dylib
install_name_tool -id $FLANGDIR/lib/clang/23/lib/darwin/libflang_rt.runtime.0.dylib $FLANGDIR/lib/clang/23/lib/darwin/libflang_rt.runtime.0.dylib

## set the SDK symlink
ln -sfn "$SDKROOT" $FLANGDIR/SDK

## -- build the driver-driver which sets SDKROOT and filters out -arch <arch> flags

## determine the target name
target=$($FLANGDIR/bin/flang-23 -v 2>&1 | sed -nE 's/^Target: *[^-]+-//p')
if [ -z "$target" ]; then
    target=apple-darwin`uname -r`
    echo WARNING: cannot determine the target name, using $target
fi

clang -DBUILD='"'$target'"' -DPREFIX='"'$FLANGDIR'"' -DEXENAME='"flang-23"' flang.c -o flang -Wall -O3 -arch x86_64 -arch arm64

mv $FLANGDIR/bin/flang-23 $FLANGDIR/bin/aarch64-${target}-flang-23
cp flang $FLANGDIR/bin/flang-23

echo Done
