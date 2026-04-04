#!/bin/bash
set -euo pipefail

CODE_MODELS=(spice2poly digital analog xtradev xtraevt table tlines)
LIBRARY_RUNTIME_METHODS="['ccall','cwrap','addFunction','removeFunction','lengthBytesUTF8','stringToUTF8','UTF8ToString']"
LINK_INPUT_ROOT="src"

find_library_artifact() {
    local pattern="$1"
    find src -type f -name "$pattern" | head -n 1
}

write_metadata() {
        cat > /dist/manifest.json <<EOF
{
    "buildMode": "library",
    "artifactKind": "$1",
    "primaryArtifact": "$2",
    "notes": "$3"
}
EOF
}

resolve_link_input() {
    local token="$1"
    local dir
    local base
    local candidate

    case "$token" in
        *.la)
            dir="$(dirname "$token")"
            base="$(basename "$token" .la)"
            for candidate in \
                "$LINK_INPUT_ROOT/$dir/.libs/$base.a" \
                "$LINK_INPUT_ROOT/$dir/$base.a"; do
                if [ -f "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
            echo "Could not resolve libtool archive: $token" >&2
            return 1
            ;;
        *.lo)
            dir="$(dirname "$token")"
            base="$(basename "$token" .lo)"
            for candidate in \
                "$LINK_INPUT_ROOT/$dir/.libs/$base.o" \
                "$LINK_INPUT_ROOT/$dir/$base.o"; do
                if [ -f "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
            echo "Could not resolve libtool object: $token" >&2
            return 1
            ;;
        *)
            printf '%s\n' "$token"
            ;;
    esac
}

print_make_variable() {
    local variable_name="$1"
    local print_file

    print_file="$(mktemp)"
    cat > "$print_file" <<EOF
print-value:
	@printf '%s\\n' "\$($variable_name)"
EOF

    make -s -C src -f Makefile -f "$print_file" print-value
    rm -f "$print_file"
}

echo "=== Cloning ngspice ==="
git clone https://github.com/danchitnis/ngspice-sf-mirror
cd ngspice-sf-mirror

echo "=== Patching source files ==="
# Fix compiler warning flag for emscripten
sed -i 's/-Wno-unused-but-set-variable/-Wno-unused-const-variable/g' ./configure.ac

# Remove getrusage check (not available in WASM)
sed -i 's/AC_CHECK_FUNCS(\[time getrusage\])/AC_CHECK_FUNCS(\[time\])/g' ./configure.ac

# Do not treat unknown available memory (reported as 0 in WASM) as a hard error.
sed -i 's/if (memrequ > memavail) {/if (memavail > 0 \&\& memrequ > memavail) {/' ./src/frontend/outitf.c

# Remove cppduals code that causes issues with stdlib and modern compilers
sed -i '/\/\/\/ Duals are compound types\./,/struct is_compound<duals::dual<T>> : true_type {};/d' \
    ./src/include/cppduals/duals/dual

echo "=== Running autogen ==="
./autogen.sh

echo "=== Configuring library build ==="
mkdir -p release-lib
cd release-lib

export CFLAGS="-Wno-unused-command-line-argument -fPIC"
WASM_INITIAL_MEMORY="${WASM_INITIAL_MEMORY:-256MB}"
WASM_ALLOW_MEMORY_GROWTH="${WASM_ALLOW_MEMORY_GROWTH:-0}"
WASM_MAXIMUM_MEMORY="${WASM_MAXIMUM_MEMORY:-256MB}"

emconfigure ../configure \
    --disable-debug \
    --with-readline=no \
    --disable-openmp \
    --enable-xspice \
    --with-ngshared \
    --without-x

# Configure runs in Linux inside Docker, but the final runtime is WASM in a browser.
# Disable Linux /proc-based memory probing, which is not valid in the target environment.
sed -i 's/^#define HAVE__PROC_MEMINFO 1$/\/\* #undef HAVE__PROC_MEMINFO \*\//g' src/include/ngspice/config.h

echo "=== Patching Makefiles for WASM library linking ==="
# Code models: build as WASM side modules.
sed -i '/^CMDIRS = /a LDFLAGS = -sSIDE_MODULE=1 -Wl,--no-entry -Wl,--export=_malloc -Wl,--export=_free -Wl,--allow-undefined' src/xspice/icm/GNUmakefile

echo "=== Building cmpp natively ==="
cd src/xspice/cmpp
make clean
make CC=gcc CFLAGS="-O2" LDFLAGS=""
chmod +x cmpp
cd ../../..

echo "=== Building ngspice library and code models ==="
emmake make -j$(nproc)

echo "=== Re-linking browser library module ==="
object_list="$(print_make_variable 'libngspice_la_OBJECTS')"
libadd_list="$(print_make_variable 'libngspice_la_LIBADD')"

if [ -z "${object_list}" ] || [ -z "${libadd_list}" ]; then
    echo "Could not determine libngspice link inputs from src/Makefile" >&2
    exit 1
fi

read -r -a object_tokens <<< "${object_list}"
read -r -a libadd_tokens <<< "${libadd_list}"

link_inputs=()

for token in "${object_tokens[@]}"; do
    [ -n "$token" ] || continue
    link_inputs+=("$(resolve_link_input "$token")")
done

for token in "${libadd_tokens[@]}"; do
    [ -n "$token" ] || continue
    link_inputs+=("$(resolve_link_input "$token")")
done

link_command=(
    emcc
    "${link_inputs[@]}"
    -o src/ngspice-lib.js
    --no-entry
    -sMAIN_MODULE=1
    -sALLOW_TABLE_GROWTH=1
    -sINITIAL_MEMORY="${WASM_INITIAL_MEMORY}"
    -sINVOKE_RUN=0
    -sNO_EXIT_RUNTIME=1
    "-sEXPORTED_RUNTIME_METHODS=${LIBRARY_RUNTIME_METHODS}"
)

if [ "${WASM_ALLOW_MEMORY_GROWTH}" = "1" ]; then
    link_command+=(-sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY="${WASM_MAXIMUM_MEMORY}")
else
    link_command+=(-sALLOW_MEMORY_GROWTH=0)
fi

"${link_command[@]}"

echo "=== Collecting library output files ==="
mkdir -p /dist

loader_path="$(find_library_artifact 'ngspice-lib.js')"
wasm_path="$(find_library_artifact 'ngspice-lib.wasm')"

if [ -z "${loader_path}" ]; then
    loader_path="$(find_library_artifact 'libngspice*.js')"
fi

if [ -z "${wasm_path}" ]; then
    wasm_path="$(find_library_artifact 'libngspice*.wasm')"
fi

if [ -n "${loader_path}" ] && [ -n "${wasm_path}" ]; then
    cp "${loader_path}" /dist/ngspice-lib.js
    cp "${wasm_path}" /dist/ngspice-lib.wasm
    write_metadata \
        "main-module" \
        "ngspice-lib.js" \
        "Shared-library build produced a JavaScript loader and WebAssembly main module."
else
    echo "Could not locate libngspice*.js and libngspice*.wasm after the manual Emscripten relink step." >&2
    find src -maxdepth 3 -type f | sort >&2
    exit 1
fi

if [ -f /build/src-js/spinit ]; then
    cp /build/src-js/spinit /dist/spinit
    echo "Using custom spinit from src/"
elif [ -f "src/spinit" ]; then
    cp src/spinit /dist/spinit
    echo "Using build-generated spinit"
fi

for cm in "${CODE_MODELS[@]}"; do
    if [ -f "src/xspice/icm/$cm/$cm.cm" ]; then
        cp "src/xspice/icm/$cm/$cm.cm" /dist/
        echo "Copied $cm.cm"
    fi
done

echo "=== Copying client and worker scripts ==="
if [ -f /build/src-js/ngspice-client.js ]; then
    cp /build/src-js/ngspice-client.js /dist/
    echo "Copied ngspice-client.js"
fi
if [ -f /build/src-js/ngspice-worker.js ]; then
    cp /build/src-js/ngspice-worker.js /dist/
    echo "Copied ngspice-worker.js"
fi

echo "=== Library build complete! ==="
echo "Output files in /dist:"
ls -la /dist/