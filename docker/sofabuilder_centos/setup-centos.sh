#!/bin/bash

############################ 
# Script based on CentOS 7 #
############################

# Install yum repositories
# yum install -y -q 'yum-command(config-manager)'
# yum config-manager --set-enabled PowerTools
yum install -y -q deltarpm 
yum install -y -q epel-release
yum install -y -q subscription-manager 
subscription-manager repos \
    --enable rhel-7-server-optional-rpms \
    --enable rhel-server-rhscl-7-rpms \
    --enable rhel-7-server-devtools-rpms
yum update -y && yum upgrade -y && yum clean all

# Install tools
yum install -y -q \
    git \
    wget \
    curl \
    update-alternatives

# Install build tools
yum install -y -q \
	cmake3 \
    ninja-build \
    ccache
yum install -y -q centos-release-scl && yum update -y -q
yum install -y -q devtoolset-6
yum install -y -q devtoolset-7 llvm-toolset-6.0
mkdir -p /root/bin
(echo '#!/bin/bash' && echo 'scl enable devtoolset-6 "gcc $*"') > /root/bin/gcc-6
(echo '#!/bin/bash' && echo 'scl enable devtoolset-6 "g++ $*"') > /root/bin/g++-6
(echo '#!/bin/bash' && echo 'scl enable devtoolset-7 "gcc $*"') > /root/bin/gcc-7
(echo '#!/bin/bash' && echo 'scl enable devtoolset-7 "g++ $*"') > /root/bin/g++-7
chmod a+x /root/bin/*
# Default to GCC-7 and Clang-6
(echo '' && echo 'source scl_source enable devtoolset-7 llvm-toolset-6.0' && echo '' ) >> /root/.bashrc

# Install plugins deps
yum install -y -q \
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

# Install Qt
yum install -y -q qt5-qtbase

# Install Boost
yum install -y -q boost169-devel

# Set cmake3 the default CMake
alternatives \
    --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
    --slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
    --slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
    --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 \
    --family cmake

# Install CGAL
# ADD http://springdale.princeton.edu/data/springdale/7/x86_64/os/Computational/CGAL-4.11.1-1.sdl7.x86_64.rpm /tmp
# ADD http://springdale.princeton.edu/data/springdale/7/x86_64/os/Computational/CGAL-devel-4.11.1-1.sdl7.x86_64.rpm /tmp
# yum install -y -q gmp-devel mpfr-devel
# rpm -Uvh /tmp/CGAL-*rpm \
# 	&& yum install -y -q CGAL
# Due to dependencies on Boost and Qt, we have to build CGAL
curl https://github.com/CGAL/cgal/releases/download/releases/CGAL-4.14.3/CGAL-4.14.3.tar.xz --output /tmp/CGAL-4.14.3.tar.xz
yum install -y -q gmp-devel mpfr-devel
tar -xJf /tmp/CGAL-4.14.3.tar.xz --directory /tmp
cd /tmp/CGAL-4.14.3 && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
    -DWITH_CGAL_Core=TRUE -DWITH_CGAL_ImageIO=TRUE -DWITH_CGAL_Qt5=TRUE \
    -DBOOST_INCLUDEDIR=/usr/include/boost169 -DBOOST_LIBRARYDIR=/usr/lib64/boost169 \
    ..
make install

# Install CUDA
# yum install -y -q kernel-devel-$(uname -r) kernel-headers-$(uname -r)
# yum install -y -q subscription-manager \
# 	&& subscription-manager remove --all || true \
# 	&& subscription-manager unregister || true \
# 	&& subscription-manager clean || true \
# 	&& subscription-manager register || true \
# 	&& subscription-manager refresh || true \
# 	&& subscription-manager repos --enable=rhel-7-workstation-optional-rpms
yum-config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel7.repo
yum install -y -q cuda-toolkit-10-2 nvidia-driver-cuda nvidia-kmod
#    && yum install -y -q nvidia-driver-latest-dkms cuda \
#    && yum install -y -q cuda-drivers \

# Cleanup
yum clean all
rm -rf /tmp/*
