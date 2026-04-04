FROM emscripten/emsdk:3.1.50

RUN apt-get update && apt-get install -y \
    bison \
    flex \
    autoconf \
    automake \
    libtool \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY build-ngspice.sh .
RUN chmod +x build-ngspice.sh

COPY src/ /build/src-js/

CMD ["sh", "-lc", "./${NGSPICE_BUILD_SCRIPT:-build-ngspice.sh}"]
