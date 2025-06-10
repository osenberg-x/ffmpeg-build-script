ARG CUDAVER=12.9.0
ARG UBUNTUVER=22.04

FROM nvidia/cuda:${CUDAVER}-devel-ubuntu${UBUNTUVER} AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,video

# Update package lists
RUN apt-get update
# Install required packages
RUN apt-get -y --no-install-recommends install build-essential curl ca-certificates libva-dev libva-drm2 cmake \
    python3 python-is-python3 ninja-build meson git curl
# Clean up package cache and temporary files
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* && find /var/log -type f -delete
# Update CA certificates
RUN update-ca-certificates


# Install NVIDIA CUDA samples to get deviceQuery
RUN mkdir -p /code && \
    git clone --depth 1 --filter=blob:none --sparse https://github.com/NVIDIA/cuda-samples.git /code/cuda-samples && \
    cd /code/cuda-samples && \
    git sparse-checkout set Samples/1_Utilities/deviceQuery Common

# Build deviceQuery in its original location where it can find dependencies
WORKDIR /code/cuda-samples/Samples/1_Utilities/deviceQuery
RUN mkdir build && cd build && \
    cmake .. && \
    make -j$(nproc) && \
    cp deviceQuery /usr/local/bin/ && \
    cd /code && \
    rm -rf cuda-samples

WORKDIR /app
COPY ./build-ffmpeg /app/build-ffmpeg

RUN CUDA_COMPUTE_CAPABILITY=$(deviceQuery | grep Capability | head -n 1 | awk 'END {print $NF}' | tr -d '.') SKIPINSTALL=yes /app/build-ffmpeg --build --enable-gpl-and-non-free && \
    rm -rf /app/packages/* /app/workspace/doc/* /app/workspace/lib/* /app/workspace/share/* /app/workspace/include/*

FROM ubuntu:${UBUNTUVER} AS release

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,video

# install va-driver
RUN apt-get update \
    && apt-get -y install libva-drm2 \
    && apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*

# Copy libnpp
COPY --from=build /usr/local/cuda-12.9/targets/x86_64-linux/lib/libnppc.so /lib/x86_64-linux-gnu/libnppc.so.12
COPY --from=build /usr/local/cuda-12.9/targets/x86_64-linux/lib/libnppig.so /lib/x86_64-linux-gnu/libnppig.so.12
COPY --from=build /usr/local/cuda-12.9/targets/x86_64-linux/lib/libnppicc.so /lib/x86_64-linux-gnu/libnppicc.so.12
COPY --from=build /usr/local/cuda-12.9/targets/x86_64-linux/lib/libnppidei.so /lib/x86_64-linux-gnu/libnppidei.so.12
COPY --from=build /usr/local/cuda-12.9/targets/x86_64-linux/lib/libnppif.so /lib/x86_64-linux-gnu/libnppif.so.12

# Copy ffmpeg
COPY --from=build /app/workspace/bin/ffmpeg /usr/bin/ffmpeg
COPY --from=build /app/workspace/bin/ffprobe /usr/bin/ffprobe
COPY --from=build /app/workspace/bin/ffplay /usr/bin/ffplay

# Check shared library
RUN ldd /usr/bin/ffmpeg
RUN ldd /usr/bin/ffprobe
RUN ldd /usr/bin/ffplay

CMD         ["--help"]
ENTRYPOINT  ["/usr/bin/ffmpeg"]
