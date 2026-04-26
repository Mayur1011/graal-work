# FROM ubuntu:22.04
#
# ENV DEBIAN_FRONTEND=noninteractive
#
# RUN apt update && apt install -y \
#     git \
#     build-essential \
#     python3 \
#     python3-pip \
#     unzip \
#     zip \
#     wget \
#     curl \
#     cmake \
#     libxtst6 \
#     libxrender1 \
#     libxext6 \
#     libasound2 \
#     libfreetype6 \
#     fontconfig \
#     ca-certificates \
#     && apt clean
#
# ARG UID=1000
# ARG GID=1000
#
# RUN groupadd -g $GID dev && \
#     useradd -m -u $UID -g $GID dev
#
# # USER dev
#
# WORKDIR /home/dev
#
# WORKDIR /graal-dev
#
# # Set the mx path
# ENV PATH="/graal-dev/mx:${PATH}"

FROM ubuntu:noble
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    git \
    vim \
    tmux \
    build-essential \
    python3 \
    python3-pip \
    wget \
    curl \
    cmake \
    ca-certificates \
    && apt clean

ARG UID=1000
ARG GID=1000

RUN if ! getent group $GID >/dev/null; then \
        groupadd -g $GID dev; \
    fi && \
    if ! id -u $UID >/dev/null 2>&1; then \
        useradd -m -u $UID -g $GID -s /bin/bash dev; \
    else \
        usermod -l dev $(getent passwd $UID | cut -d: -f1); \
    fi

# install mx as root
RUN git clone https://github.com/graalvm/mx.git /opt/mx
RUN chown -R $UID:$GID /opt/mx

USER dev

WORKDIR /graal-dev

# use this setup if not mouting the whole local directory
# RUN git clone https://github.com/graalvm/mx.git
# ENV PATH="/graal-dev/mx:${PATH}"

ENV PATH="/opt/mx:${PATH}"
