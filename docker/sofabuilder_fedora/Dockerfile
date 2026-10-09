FROM fedora:41

SHELL ["/bin/bash", "-c"]

ADD "https://www.sofa-framework.org/rand/" ForceNoCache


# Install dnf repositories
# RUN dnf install -y -q deltarpm
# RUN dnf install -y -q epel-release
# RUN dnf install -y -q centos-release-scl
# RUN dnf install -y -q centos-release-scl-rh
# RUN dnf install -y -q http://repo.okay.com.mx/centos/7/x86_64/release/okay-release-1-5.el7.noarch.rpm
# RUN dnf install -y -q https://packages.endpoint.com/rhel/7/os/x86_64/endpoint-repo-1.9-1.x86_64.rpm
RUN dnf install -y -q http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
RUN dnf update -y && dnf upgrade -y && dnf clean all

# Install system tools
RUN dnf install -y -q \
    dnf-utils \
    git \
    gh \
    wget \
    curl \
    ca-certificates \
    vim

# Install build tools
RUN dnf install -y -q \
    ninja-build \
    clang \
    ccache \
    libXdamage

# Install core deps
RUN dnf install -y -q \
    glew-devel \
    freeglut-devel \
    zlib-devel \
    eigen3-devel

# Install plugin deps
RUN dnf install -y -q \
    python3.12-devel \
    python3-pip \
    python3.13 \
    python3.13-devel \
    python3.14 \
    python3.14-devel \
    libpng-devel libjpeg-turbo-devel libtiff-devel \
    blas-devel \
    lapack-devel \
    suitesparse-devel \
    ffmpeg-devel \
    assimp-devel \
    opencascade-devel \
    libXrandr-devel \
    tinyxml2-devel \
    xorg-x11-server-devel\
    gtk3-devel


# Install pip, numpy, scipy, pybind11
ARG PYBIND11_VERSION=3.0.1
RUN python3.12 -m ensurepip
RUN python3.12 -m pip install numpy scipy matplotlib pybind11==$PYBIND11_VERSION mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages
RUN python3.13 -m ensurepip
RUN python3.13 -m pip install numpy scipy matplotlib pybind11==$PYBIND11_VERSION mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages
RUN python3.14 -m ensurepip
RUN python3.14 -m pip install numpy scipy matplotlib pybind11==$PYBIND11_VERSION mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages
ENV PYTHONPATH=""
ENV VM_HAS_ASSIMP="true"
ENV VM_HAS_OPENCASCADE="false"

###################################

# Install CMake
ARG CMAKE_VERSION=3.28.3
ADD https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-Linux-x86_64.sh /tmp/cmake.sh
RUN chmod a+x /tmp/cmake.sh
RUN /tmp/cmake.sh --skip-license --prefix=/usr/local

# Install Boost
RUN dnf install -y -q boost-devel
ENV BOOST_INCLUDEDIR="/usr/include"
ENV BOOST_LIBRARYDIR="/usr/lib64/boost"
ENV LD_LIBRARY_PATH="${BOOST_LIBRARYDIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"


###################################

# Disable core dumps
RUN printf '\n# Disable core dumps\n* soft core 0\n* hard core 0\n' >> /etc/security/limits.conf

# Init /builds directory
WORKDIR /builds

# Set env vars
ENV PYTHONIOENCODING="UTF-8"
ENV PYTHONUSERBASE="/tmp/pythonuserbase"
RUN mkdir -p "$PYTHONUSERBASE" && chmod -R 777 "$PYTHONUSERBASE"
ENV VM_PYTHON3_EXECUTABLE="/usr/bin/python3.12"
ENV VM_PYBIND11_CONFIG_EXECUTABLE="/usr/bin/python3.12 -m pybind11"
RUN git config --system user.name 'SOFA Bot' || git config --global user.name 'SOFA Bot'
RUN git config --system user.email '<>' || git config --global user.email '<>'

# TMP: fix Boost+CMake issue with a symlink
RUN ln -s /usr/include /include || true

# Cleanup
RUN dnf clean all \
    && rm -rf /tmp/*

# In-process env settings
COPY docker-entrypoint.sh /
RUN chmod a+x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Default command to run
CMD ["/bin/bash"]
