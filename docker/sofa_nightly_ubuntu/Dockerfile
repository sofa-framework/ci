FROM ubuntu:18.04

SHELL ["/bin/bash", "-c"]

# ADD "https://www.sofa-framework.org/rand/" ForceNoCache

RUN useradd --no-log-init sofa --uid 1000 --home /home/sofa --create-home --shell /bin/bash
ENV HOME="/home/sofa"

RUN apt-get update && apt-get upgrade -y

# Install tools
RUN apt-get install -y \
    zip \
    unzip

# Install SOFA binaries
ARG BINARIES_BRANCH=v20.12
ARG BINARIES_CONFIG=standard
ENV SOFA_ROOT=/opt/sofa
RUN mkdir -p "$SOFA_ROOT" "/tmp/sofa/zip" "/tmp/sofa/binaries"
ADD https://ci.inria.fr/sofa-ci-dev/job/nightly-generate-binaries/CI_BRANCH=${BINARIES_BRANCH},CI_SCOPE=${BINARIES_CONFIG}/lastSuccessfulBuild/artifact/Linux/*zip*/Linux.zip \
    /tmp/sofa
RUN unzip /tmp/sofa/Linux.zip -d /tmp/sofa/zip \
    && unzip /tmp/sofa/zip/Linux/SOFA_*.zip -d /tmp/sofa/binaries
RUN mv /tmp/sofa/binaries/SOFA_*/* $SOFA_ROOT \
    && rm -rf /tmp/sofa \
    && chmod +x $SOFA_ROOT/bin/runSofa* \
    && chown -R sofa:sofa $SOFA_ROOT
ENV PATH="$SOFA_ROOT:$SOFA_ROOT/bin:$PATH"
RUN apt-get install -y libqt5webenginecore5
#RUN apt-get install -y \
#    libdbus-1-3 libfontconfig1 libfreetype6 \
#    libgl1-mesa-glx libglib2.0-0 libopengl0 \
#    libx11-xcb1 libxrender1

# Init WORKDIR
WORKDIR "$SOFA_ROOT"

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
