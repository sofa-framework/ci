FROM centos:7

SHELL ["/bin/bash", "-c"]

# Install yum repositories
RUN yum install -y -q deltarpm 
RUN yum install -y -q epel-release
RUN yum update -y && yum upgrade -y && yum clean all

# Install tools
RUN yum install -y -q \
    git \
    wget \
    curl \
    update-alternatives

# Install build tools
RUN yum install -y -q \
	cmake3 \
    ninja-build \
    ccache
RUN yum install -y -q centos-release-scl \
    && yum update -y -q \
    && yum install -y -q devtoolset-6 \
    && yum install -y -q devtoolset-7 llvm-toolset-7
RUN mkdir -p /root/bin \
    && (echo '#!/bin/bash' && echo 'scl enable devtoolset-6 "gcc $*"') > /root/bin/gcc-6 \
    && (echo '#!/bin/bash' && echo 'scl enable devtoolset-6 "g++ $*"') > /root/bin/g++-6 \
    && (echo '#!/bin/bash' && echo 'scl enable devtoolset-7 "gcc $*"') > /root/bin/gcc-7 \
    && (echo '#!/bin/bash' && echo 'scl enable devtoolset-7 "g++ $*"') > /root/bin/g++-7 \
    && chmod a+x /root/bin/*
ENV PATH="/root/bin${PATH:+:${PATH}}"

# Install plugins deps
RUN yum install -y -q \
    python numpy scipy \
    libpng-devel libjpeg-devel libtiff-devel \
    zlib-devel \
    libglew \
    blas-devel \
    lapack-devel \
    freeglut-devel \
    suitesparse-devel \
    assimp-devel \
    bullet-devel \
    OCE-devel
ENV VM_HAS_ASSIMP="true"
ENV VM_HAS_BULLET="true"
ENV VM_HAS_OPENCASCADE="true"

# Install Qt
ARG QT_MAJOR=5
ARG QT_MINOR=12
ARG QT_PATCH=6
RUN mkdir -p /root/.local/share/Qt
ADD https://raw.githubusercontent.com/sofa-framework/ci/testing/setup/qtaccount.ini /root/.local/share/Qt/qtaccount.ini
ADD https://raw.githubusercontent.com/sofa-framework/ci/testing/setup/qtinstaller_controlscript_template_linux.qs /tmp/qtinstaller_controlscript_template_linux.qs
RUN cat /tmp/qtinstaller_controlscript_template_linux.qs | sed "s/_QTVERSION_/$QT_MAJOR$QT_MINOR$QT_PATCH/g" > /tmp/qtinstaller_controlscript.qs
ADD http://download.qt.io/official_releases/online_installers/qt-unified-linux-x64-online.run /tmp/qt-unified-linux-x64-online.run
RUN yum install -y -q libxkbcommon-x11
RUN chmod a+x /tmp/qt-unified-linux-x64-online.run \
    && /tmp/qt-unified-linux-x64-online.run --script /tmp/qtinstaller_controlscript.qs --platform minimal --verbose
ENV QTDIR="/opt/Qt/$QT_MAJOR.$QT_MINOR.$QT_PATCH/gcc_64"
ENV PATH="$QTDIR/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="$QTDIR/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Install Boost
RUN yum install -y -q boost169-devel
ENV BOOST_INCLUDEDIR="/usr/include/boost169"
ENV BOOST_LIBRARYDIR="/usr/lib64/boost169"
ENV LD_LIBRARY_PATH="${BOOST_LIBRARYDIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Set cmake3 the default CMake
RUN update-alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
    --slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
    --slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
    --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 \
    --family cmake

# Install CGAL
ADD https://github.com/CGAL/cgal/releases/download/releases/CGAL-4.14.3/CGAL-4.14.3.tar.xz /tmp
RUN yum install -y -q gmp-devel mpfr-devel
RUN tar -xJf /tmp/CGAL-4.14.3.tar.xz --directory /tmp \
    && cd /tmp/CGAL-4.14.3 \
    && mkdir build \
    && cd build \
    && source /opt/rh/devtoolset-7/enable || true \
	&& source /opt/rh/llvm-toolset-7/enable || true \
    && cmake -DCMAKE_BUILD_TYPE=Release -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE .. \
    && make install
ENV VM_HAS_CGAL="true"

# Install CUDA
RUN yum-config-manager --add-repo \
    http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel7.repo \
    && yum clean all
RUN yum install -y -q cuda-toolkit-10-2
RUN yum install -y -q nvidia-driver-cuda
RUN yum install -y -q nvidia-kmod
ENV PATH="/usr/local/cuda-10.2/bin:/usr/local/cuda-10.2/NsightCompute-2019.1${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="/usr/local/cuda-10.2/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV VM_HAS_CUDA="true"
ENV VM_CUDA_HOST_COMPILER="/root/bin/gcc-6"
ENV VM_CUDA_ARCH="sm_50"


# Init /builds directory
WORKDIR /builds

# Set env vars
ENV HOME="/root"

# Cleanup
RUN yum clean all \
    && rm -rf /tmp/*

# In-process env settings
COPY docker-entrypoint.sh /
RUN chmod a+x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Default command to run
CMD ["/bin/bash"]
