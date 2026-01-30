#!/bin/bash
set -e

echo "=== Cloning ngspice ==="
git clone https://github.com/danchitnis/ngspice-sf-mirror
cd ngspice-sf-mirror

echo "=== Patching source files ==="
# Fix compiler warning flag for emscripten
sed -i 's/-Wno-unused-but-set-variable/-Wno-unused-const-variable/g' ./configure.ac

# Remove getrusage check (not available in WASM)
sed -i 's/AC_CHECK_FUNCS(\[time getrusage\])/AC_CHECK_FUNCS(\[time\])/g' ./configure.ac

# Remove cppduals code that causes issues with stdilb and modern compilers
sed -i '/\/\/\/ Duals are compound types\./,/struct is_compound<duals::dual<T>> : true_type {};/d' \
    ./src/include/cppduals/duals/dual

echo "=== Running autogen ==="
./autogen.sh

echo "=== Configuring ==="
mkdir -p release
cd release

export CFLAGS="-Wno-unused-command-line-argument -fPIC"

emconfigure ../configure \
    --disable-debug \
    --with-readline=no \
    --disable-openmp \
    --enable-xspice \
    --without-x

echo "=== Patching Makefiles for WASM dynamic linking ==="
# Main ngspice: enable dynamic loading of code models
sed -i 's/^ngspice_LDFLAGS = $/ngspice_LDFLAGS = -sMAIN_MODULE=1/' src/Makefile
sed -i 's|spicelib/devices/dev\.lo||g' src/Makefile

# Code models: build as WASM side modules
sed -i '/^CMDIRS = /a LDFLAGS = -sSIDE_MODULE=1 -Wl,--no-entry -Wl,--export=_malloc -Wl,--export=_free -Wl,--allow-undefined' src/xspice/icm/GNUmakefile

echo "=== Building cmpp natively ==="
cd src/xspice/cmpp
make clean
make CC=gcc CFLAGS="-O2" LDFLAGS=""
chmod +x cmpp
cd ../../..

echo "=== Building ngspice and code models ==="
emmake make -j$(nproc)

echo "=== Collecting output files ==="
mkdir -p /output

# Main ngspice WASM files
cp src/ngspice /output/ngspice.js
cp src/ngspice.wasm /output/

# Code models
for cm in spice2poly digital analog xtradev xtraevt table tlines; do
    if [ -f "src/xspice/icm/$cm/$cm.cm" ]; then
        cp "src/xspice/icm/$cm/$cm.cm" /output/
        echo "Copied $cm.cm"
    fi
done

echo "=== Build complete! ==="
echo "Output files in /output:"
ls -la /output/