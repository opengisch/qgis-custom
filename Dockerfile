# syntax=docker/dockerfile:1

# QGIS with its desktop, built from a composed version in opengisch/QGIS, on the build dependencies that qgis/QGIS
# compiles master with, on Ubuntu 26.04. The workflow build pushes it to ghcr.io/opengisch/qgis-custom. Locally:
#   docker build --platform linux/amd64 --build-arg QGIS_REF=qgis-custom/qgis-dmav -t qgis-custom .
FROM scratch AS source

ARG QGIS_REPOSITORY=opengisch/QGIS
ARG QGIS_REF=qgis-custom/qgis-dmav
# With its .git, which gives QGIS its revision
ADD --keep-git-dir=true https://github.com/${QGIS_REPOSITORY}.git#${QGIS_REF} /QGIS

FROM qgis/qgis3-build-deps-ubuntu-qt6:master

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONPATH=/usr/share/qgis/python
ENV CCACHE_DIR=/ccache
ENV CCACHE_MAXSIZE=3G

# QGIS runs where it is built: the runtime dependencies of the packages of qgis.org that the build dependencies lack
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        fonts-dejavu-core \
        python3-jinja2 \
        python3-lxml \
        python3-matplotlib \
        python3-plotly \
        python3-pygments \
        qt6-svg-plugins \
    && rm -rf /var/lib/apt/lists/*

# The desktop application and its Python, without 3D, GRASS or PDAL. The source is mounted, not copied, to keep it out
# of the image. The cache of ccache outlives the builds.
RUN --mount=type=bind,from=source,source=/QGIS,target=/QGIS,rw \
    --mount=type=cache,target=/ccache \
    ccache --zero-stats \
    && cmake -S /QGIS -B /tmp/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DUSE_CCACHE=ON \
        -DENABLE_TESTS=OFF \
        -DENABLE_UNITY_BUILDS=ON \
        -DWITH_3D=OFF \
        -DWITH_GRASS7=OFF \
        -DWITH_GRASS8=OFF \
        -DWITH_PDAL=OFF \
        -DWITH_INTERNAL_SPATIALINDEX=ON \
    && cmake --build /tmp/build -j "$(nproc)" \
    && ccache --show-stats \
    && cmake --install /tmp/build \
    && rm -rf /tmp/build \
    && ldconfig
