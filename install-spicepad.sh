#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="all"
SOURCE_DIR=""
TARGET_DIR=""

install_artifacts() {
    local mode="$1"
    local source_dir="$2"
    local target_dir="$3"
    local main_js
    local main_wasm
    local cm_files

    if [ ! -d "${source_dir}" ]; then
        echo "Missing output directory: ${source_dir}" >&2
        return 1
    fi

    if [ "${mode}" = "library" ]; then
        main_js="${source_dir}/ngspice-lib.js"
        main_wasm="${source_dir}/ngspice-lib.wasm"
    else
        main_js="${source_dir}/ngspice.js"
        main_wasm="${source_dir}/ngspice.wasm"
    fi

    for required_file in "${main_js}" "${main_wasm}"; do
        if [ ! -f "${required_file}" ]; then
            echo "Missing build artifact: ${required_file}" >&2
            return 1
        fi
    done

    shopt -s nullglob
    cm_files=("${source_dir}"/*.cm)
    shopt -u nullglob

    if [ ${#cm_files[@]} -eq 0 ]; then
        echo "No code model files found in ${source_dir}" >&2
        return 1
    fi

    mkdir -p "${target_dir}"

    cp "${main_js}" "${target_dir}/"
    cp "${main_wasm}" "${target_dir}/"
    cp "${cm_files[@]}" "${target_dir}/"

    if [ "${mode}" = "library" ] && [ -f "${source_dir}/spinit" ]; then
        cp "${source_dir}/spinit" "${target_dir}/"
    fi

    echo "Installed ${mode} ngspice artifacts to ${target_dir}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

if [ -z "${TARGET_DIR}" ]; then
    TARGET_DIR="${SCRIPT_DIR}/../spicepad/public"
fi

case "${MODE}" in
    app)
        if [ -z "${SOURCE_DIR}" ]; then
            SOURCE_DIR="${SCRIPT_DIR}/output"
        fi
        install_artifacts "app" "${SOURCE_DIR}" "${TARGET_DIR}"
        ;;
    library)
        if [ -z "${SOURCE_DIR}" ]; then
            SOURCE_DIR="${SCRIPT_DIR}/output-lib"
        fi
        install_artifacts "library" "${SOURCE_DIR}" "${TARGET_DIR}"
        ;;
    all)
        install_artifacts "app" "${SCRIPT_DIR}/output" "${TARGET_DIR}"

        if [ -d "${SCRIPT_DIR}/output-lib" ]; then
            if install_artifacts "library" "${SCRIPT_DIR}/output-lib" "${TARGET_DIR}/lib"; then
                :
            else
                echo "Skipping library artifact install because output-lib is incomplete." >&2
            fi
        fi
        ;;
    *)
        echo "Unsupported mode: ${MODE}" >&2
        exit 1
        ;;
esac