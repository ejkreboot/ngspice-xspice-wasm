# ngspice-xspice-wasm

A Docker-based build system for compiling [ngspice](http://ngspice.sourceforge.net/) with XSPICE extensions to WebAssembly (WASM) using Emscripten.

## Overview

This project provides a reproducible build environment for creating a WASM version of ngspice, a popular open-source SPICE circuit simulator. The build includes XSPICE code model support with dynamic loading capabilities, enabling the simulator to run in web browsers with support for more advanced models that use XSPICE (e.g., poly-controlled sources used in many opamp subcircuits).

## Features

- **Full ngspice compilation to WASM**: Core simulator compiled with Emscripten
- **XSPICE support**: Includes analog, digital, and mixed-signal code models
- **Dynamic code model loading**: Code models built as WASM side modules
- **Dockerized build**: Consistent, reproducible build environment
- **Automated patching**: Handles source modifications for WASM compatibility

## Prerequisites

- Docker installed on your system
- Sufficient disk space (~2-3 GB for Docker image and build artifacts)

## Building

1. **Clone or navigate to this repository**:
   ```bash
   git clone ngspice-xspice-wasm
   cd ngspice-xspice-wasm
   ```

2. **Build the Docker image**:
   ```bash
   docker build -t ngspice-wasm-builder .
   ```

3. **Run the build**:
   ```bash
   docker run --rm -v $(pwd)/output:/output ngspice-wasm-builder
   ```

The build artifacts will be placed in the `output` directory:
- `ngspice.js` - Main JavaScript loader
- `ngspice.wasm` - Main ngspice WASM module
- `*.cm` files - XSPICE code model side modules (e.g., `analog.cm`, `digital.cm`)

## Build Process

The build script performs the following steps:

1. Clones the ngspice source repository
2. Patches source files for WASM compatibility:
   - Fixes compiler warnings for Emscripten
   - Removes `getrusage` function (not available in WASM)
   - Removes problematic `cppduals` standard lib compound variable reassignment.
3. Configures ngspice with XSPICE enabled and X11/readline/debug disabled
4. Patches Makefiles to enable dynamic linking:
   - Main module built with `-sMAIN_MODULE=1`
   - Code models built as side modules with `-sSIDE_MODULE=1`
5. Builds the native `cmpp` preprocessor
6. Compiles ngspice and all code models
7. Collects output files

## Code Models

The following XSPICE code models are included:

- `spice2poly.cm` - SPICE2 polynomial models
- `digital.cm` - Digital logic models
- `analog.cm` - Analog behavioral models
- `xtradev.cm` - Extra device models
- `xtraevt.cm` - Extra event-driven models
- `table.cm` - Table-based models
- `tlines.cm` - Transmission line models

## Technical Details

- **Emscripten version**: 3.1.50
- **Build configuration**: Release build with debug disabled
- **WASM features**: Main module with dynamic linking support
- **No dependencies on**: OpenMP, readline, X11

## Usage

After building, integrate the WASM files into your web application:

```javascript
// Load the main ngspice module
const ngspice = await import('./output/ngspice.js');

// The code models (*.cm files) will be dynamically loaded
// when needed by the simulator
```

## Demo (browser playground)

A prebuilt playground lives in [demo/index.html](demo/index.html) with a worker wired to the WASM build. It stages the bundled code models and `spinit`, starts a fresh worker per run, and streams stdout/stderr live.

### Run locally

From the repo root:

1. Serve the `demo/` folder (any static server works):
   ```bash
   cd demo
   python -m http.server 8000
   ```
2. Open http://localhost:8000/
3. Edit the netlist in the left pane and click “Run simulation.” Output streams on the right; each run instantiates a clean worker and reloads the virtual filesystem.

### What’s included
- `ngspice.js` / `ngspice.wasm` (WASM build)
- `cm/*.cm` XSPICE code models staged into `/usr/local/lib/ngspice`
- `spinit` staged into `/usr/local/share/ngspice/scripts/spinit` and `/spinit`
- Worker: [demo/ngspice-worker.js](demo/ngspice-worker.js)

### Notes
- Serve over HTTP(S) to avoid CORS when fetching WASM and code models.
- Each run is single-shot; stopping mid-run = terminate the worker.
- The UI suppresses expected `/proc/meminfo` and keepRuntimeAlive warnings for cleaner logs.

## Credits

- [ngspice](http://ngspice.sourceforge.net/) - Original SPICE simulator
- [Emscripten](https://emscripten.org/) - LLVM-to-WebAssembly compiler
- Source repository: [danchitnis/ngspice-sf-mirror](https://github.com/danchitnis/ngspice-sf-mirror)

## License

MIT License

Copyright (c) 2026 Eric J. Kort

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.