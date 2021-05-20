FROM centos:7

SHELL ["/bin/bash", "-c"]

ADD "https://www.sofa-framework.org/rand/" ForceNoCache

# Install yum repositories
RUN yum install -y -q deltarpm
RUN yum install -y -q epel-release
RUN yum install -y -q centos-release-scl
RUN yum install -y -q centos-release-scl-rh
RUN yum install -y -q http://repo.okay.com.mx/centos/7/x86_64/release/okay-release-1-1.noarch.rpm
RUN yum update -y && yum upgrade -y && yum clean all

# Install tools
RUN yum install -y -q \
    git \
    wget \
    curl \
    vim \
    update-alternatives

# Install build tools
RUN yum install -y -q \
    cmake3 \
    ninja-build \
    devtoolset-7 \
    llvm-toolset-7 \
    ccache
RUN ln -sf /usr/bin/ninja-build /usr/bin/ninja || true

# Install core deps
RUN yum install -y -q \
    glew-devel \
    freeglut-devel \
    zlib-devel \
    eigen3-devel

###################################

# Install plugin deps
RUN yum install -y -q \
    python27-python-devel python27-python-pip \
    rh-python38-python-devel rh-python38-python-pip \
    libpng-devel libjpeg-devel libtiff-devel \
    blas-devel \
    lapack-devel \
    suitesparse-devel \
    ffmpeg-devel \
    assimp-devel \
    bullet-extras-devel \
    OCE-devel \
    libXrandr-devel
RUN source /opt/rh/python27/enable \
    && python2.7 -m pip install --upgrade "pip == 20.3.4" \
    && python2.7 -m pip install "numpy == 1.16.6" "scipy == 1.2.3" "matplotlib == 2.2.5"
RUN source /opt/rh/rh-python38/enable \
    && python3.8 -m pip install --upgrade pip \
    && python3.8 -m pip install numpy scipy pygame
ENV PYTHONPATH=""
ENV VM_HAS_ASSIMP="true"
# BulletColisionDetection is broken
ENV VM_HAS_BULLET="disabled"
ENV VM_HAS_OPENCASCADE="true"

# Install Qt
ARG QT_MAJOR=5
ARG QT_MINOR=12
ARG QT_PATCH=6
ARG QT_INSTALLDIR="/opt/Qt"
RUN mkdir -p /root/.local/share/Qt
ADD https://raw.githubusercontent.com/sofa-framework/ci/master/setup/qt/qtaccount.ini /root/.local/share/Qt/qtaccount.ini
ADD https://raw.githubusercontent.com/sofa-framework/ci/master/setup/qt/qtinstaller_controlscript_template.qs /tmp/qtinstaller_controlscript_template.qs
RUN cat /tmp/qtinstaller_controlscript_template.qs \
    | sed 's:_QTVERSION_:'"$QT_MAJOR$QT_MINOR$QT_PATCH"':g' \
    | sed 's:_QTINSTALLDIR_:'"$QT_INSTALLDIR"':g' \
    | sed 's:_QTCOMPILER_:gcc_64:g' \
    > /tmp/qtinstaller_controlscript.qs
ADD http://download.qt.io/official_releases/online_installers/qt-unified-linux-x64-online.run /tmp/qt-unified-linux-x64-online.run
RUN yum install -y -q libxkbcommon-x11 libwayland-cursor
RUN chmod a+x /tmp/qt-unified-linux-x64-online.run \
    && /tmp/qt-unified-linux-x64-online.run --script /tmp/qtinstaller_controlscript.qs --platform minimal --verbose
ENV QTDIR="$QT_INSTALLDIR/$QT_MAJOR.$QT_MINOR.$QT_PATCH/gcc_64"
ENV PATH="$QTDIR/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="$QTDIR/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Install Boost
ARG BOOST_MAJOR=1
ARG BOOST_MINOR=69
RUN yum install -y -q boost${BOOST_MAJOR}${BOOST_MINOR}-devel
RUN ln -s -f "boost${BOOST_MAJOR}${BOOST_MINOR}/boost" "/usr/include/boost" || true
RUN ln -s -f "boost${BOOST_MAJOR}${BOOST_MINOR}" "/usr/lib64/boost" || true
ENV BOOST_INCLUDEDIR="/usr/include"
ENV BOOST_LIBRARYDIR="/usr/lib64/boost"
ENV LD_LIBRARY_PATH="${BOOST_LIBRARYDIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Set cmake3 the default CMake
RUN update-alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
    --slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
    --slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
    --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 \
    --family cmake

# Install CGAL
# Due to dependencies on Boost and Qt, we have to build CGAL
ARG CGAL_MAJOR=4
ARG CGAL_MINOR=14
ARG CGAL_PATCH=3
ADD https://github.com/CGAL/cgal/releases/download/releases/CGAL-$CGAL_MAJOR.$CGAL_MINOR.$CGAL_PATCH/CGAL-$CGAL_MAJOR.$CGAL_MINOR.$CGAL_PATCH.tar.xz /tmp/CGAL.tar.xz
RUN yum install -y -q gmp-devel mpfr-devel
RUN tar -xJf /tmp/CGAL.tar.xz --directory /tmp \
    && cd /tmp/CGAL-$CGAL_MAJOR.$CGAL_MINOR.$CGAL_PATCH \
    && mkdir build \
    && cd build \
    && source /opt/rh/devtoolset-7/enable || true \
    && source /opt/rh/llvm-toolset-7/enable || true \
    && cmake -DCMAKE_BUILD_TYPE=Release -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE .. \
    && make install
ENV VM_HAS_CGAL="true"
ENV VM_CGAL_PATH="/usr/local/lib64/cmake/CGAL"

# Install CUDA
ARG CUDA_MAJOR=10
ARG CUDA_MINOR=2
RUN yum-config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel7.repo \
    && yum clean expire-cache
RUN yum install -y -q cuda-$CUDA_MAJOR-$CUDA_MINOR
ENV PATH="/usr/local/cuda-$CUDA_MAJOR.$CUDA_MINOR/bin:/usr/local/cuda-$CUDA_MAJOR.$CUDA_MINOR/NsightCompute-2019.1${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="/usr/local/cuda-$CUDA_MAJOR.$CUDA_MINOR/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV VM_CUDA_HOST_COMPILER="/usr/bin/gcc"
ENV VM_CUDA_ARCH="sm_50"
ENV VM_HAS_CUDA="true"

# Install pybind11 (needed by SofaPython3)
ARG PYBIND_MAJOR=2
ARG PYBIND_MINOR=4
RUN git clone -b v$PYBIND_MAJOR.$PYBIND_MINOR --depth 1 https://github.com/pybind/pybind11.git /tmp/pybind11/src \
    && mkdir /tmp/pybind11/build && cd /tmp/pybind11/build \
    && source /opt/rh/rh-python38/enable || true \
    && cmake -DCMAKE_BUILD_TYPE=Release -DPYTHON_EXECUTABLE="$(which python3.8)" -DPYBIND11_TEST=OFF ../src \
    && make && make install

###################################

# Disable core dumps
RUN printf '\n# Disable core dumps\n* soft core 0\n* hard core 0\n' >> /etc/security/limits.conf

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
