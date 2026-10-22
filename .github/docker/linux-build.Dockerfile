# Build against the oldest supported Linux userspace (glibc 2.31).
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git build-essential binutils \
    && rm -rf /var/lib/apt/lists/*
RUN curl -LsSf https://astral.sh/uv/install.sh -o /tmp/install-uv.sh \
    && UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh /tmp/install-uv.sh \
    && rm /tmp/install-uv.sh \
    && uv venv --python 3.13 /opt/build-python
ENV PATH="/opt/build-python/bin:${PATH}"
WORKDIR /workspace
