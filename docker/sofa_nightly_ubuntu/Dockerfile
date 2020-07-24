FROM ubuntu:18.04

SHELL ["/bin/bash", "-c"]

# ADD "https://www.sofa-framework.org/rand/" ForceNoCache

RUN apt-get update && apt-get upgrade -y

# Install tools
RUN apt-get install -y \
    zip \
    unzip

# Install SOFA binaries
ARG DOCKER_TAG
ADD https://ci.inria.fr/sofa-ci-dev/job/nightly-generate-binaries/CI_SCOPE=binaries_${DOCKER_TAG}/lastSuccessfulBuild/artifact/Linux/*zip*/Linux.zip /tmp
RUN unzip /tmp/Linux.zip -d /tmp && unzip /tmp/Linux/SOFA_*.zip -d /root
RUN mv /root/SOFA_* /root/SOFA
ENV SOFA_ROOT="/root/SOFA"
ENV PATH="/root/SOFA:$PATH"
RUN echo -e '#!/bin/bash \n $SOFA_ROOT/bin/runSofa $@' > /usr/bin/runSofa && chmod +x /usr/bin/runSofa

# Init WORKDIR
WORKDIR /root/SOFA

# Set env vars
ENV HOME="/root"

# Cleanup
RUN apt-get clean -y \
    && apt-get autoremove -y \
    && rm -rf /tmp/*

# In-process env settings
COPY docker-entrypoint.sh /
RUN chmod a+x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Define default command.
CMD ["/bin/bash"]


