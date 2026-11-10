# syntax=docker/dockerfile:1

# QGIS with its desktop, built from a composed version in opengisch/QGIS. A copy of slim/Dockerfile of qgis/qgis-docker,
# the image qgis/qgis-slim, at 9fe8e4c03fef211a29dbd68a0fc6ea06d84eca3a, with the desktop on top, and GEOS 3.15 built
# from source: QGIS comes from qgis_repository, is built with the desktop and without Wayland, and keeps its desktop
# files; the image has Mesa, the SVG icons of Qt, a font and the Python modules of the desktop plugins, and no offscreen
# platform. The workflow build pushes it to ghcr.io/opengisch/qgis-custom. Locally:
#   docker build --platform linux/amd64 --build-arg qgis_ref=qgis-custom/qgis-dmav -t qgis-custom .

ARG os=ubuntu
ARG release=resolute

FROM ${os}:${release} AS gdal

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates ccache cmake curl git ninja-build pkgconf swig \
      libarrow-acero-dev libarrow-dataset-dev libarrow-dev libparquet-dev \
      libcurl4-openssl-dev libdeflate-dev libexpat1-dev libgeos-dev libjpeg-dev libopenjp2-7-dev \
      libpng-dev libpq-dev libproj-dev libspatialite-dev libsqlite3-dev libssl-dev libwebp-dev libzstd-dev \
      python3-dev python3-numpy python3-pip python3-setuptools \
    && rm -rf /var/lib/apt/lists/*

ENV CCACHE_DIR=/root/.ccache

# GEOS, which Ubuntu resolute has at 3.14, as GDAL is below: over the GEOS of the packages, which SpatiaLite keeps in the
# image. Its C API, the one that QGIS, GDAL and SpatiaLite use, keeps its soname: ldconfig takes the newer library.
ARG geos_version=3.15.0
RUN --mount=type=cache,id=ccache,target=/root/.ccache \
    mkdir -p /src/geos && cd /src/geos \
    && curl -fsSL https://github.com/libgeos/geos/archive/refs/tags/${geos_version}.tar.gz | tar xz --strip-components=1 \
    && cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DBUILD_TESTING=OFF \
      -DBUILD_GEOSOP=OFF \
    && cmake --build build \
    && cmake --install build --strip \
    && DESTDIR=/install cmake --install build --strip \
    && rm -rf /src/geos

# GDAL is installed in the builder to compile QGIS against it, and in /install for the final image
ARG gdal_version=v3.13.3
RUN --mount=type=cache,id=ccache,target=/root/.ccache \
    mkdir -p /src/gdal && cd /src/gdal \
    && curl -fsSL https://github.com/OSGeo/gdal/archive/refs/tags/${gdal_version}.tar.gz | tar xz --strip-components=1 \
    && cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DBUILD_TESTING=OFF \
      -DBUILD_PYTHON_BINDINGS=ON \
      -DBUILD_JAVA_BINDINGS=OFF \
      -DBUILD_CSHARP_BINDINGS=OFF \
      -DGDAL_USE_EXTERNAL_LIBS=OFF \
      -DGDAL_USE_ARROW=ON \
      -DGDAL_USE_ARROWCOMPUTE=ON \
      -DGDAL_USE_ARROWDATASET=ON \
      -DGDAL_USE_PARQUET=ON \
      -DGDAL_USE_CURL=ON \
      -DGDAL_USE_DEFLATE=ON \
      -DGDAL_USE_EXPAT=ON \
      -DGDAL_USE_GEOS=ON \
      -DGDAL_USE_ICONV=ON \
      -DGDAL_USE_JPEG=ON \
      -DGDAL_USE_OPENJPEG=ON \
      -DGDAL_USE_OPENSSL=ON \
      -DGDAL_USE_PNG=ON \
      -DGDAL_USE_POSTGRESQL=ON \
      -DGDAL_USE_SPATIALITE=ON \
      -DGDAL_USE_SQLITE3=ON \
      -DGDAL_USE_WEBP=ON \
      -DGDAL_USE_ZLIB=ON \
      -DGDAL_USE_ZSTD=ON \
    && cmake --build build \
    && DEB_PYTHON_INSTALL_LAYOUT=deb_system cmake --install build --strip \
    && DEB_PYTHON_INSTALL_LAYOUT=deb_system DESTDIR=/install cmake --install build --strip \
    && rm -rf /src/gdal

FROM gdal AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      bison flex libprotobuf-dev libqca-qt6-dev libqscintilla2-qt6-dev libzip-dev protobuf-compiler \
      qt6-5compat-dev qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-l10n-tools \
      qt6-multimedia-dev qt6-positioning-dev qt6-svg-dev qt6-tools-dev qtkeychain-qt6-dev \
      pyqt6-dev pyqt6.qsci-dev python3-pyqt6 python3-pyqt6.qsci python3-pyqt6.qtmultimedia \
      python3-pyqt6.qtpositioning python3-pyqt6.sip python3-pyqtbuild sip-tools \
    && rm -rf /var/lib/apt/lists/*

# qgis_ref can be a branch, a tag or a commit
ARG qgis_repository=opengisch/QGIS
ARG qgis_ref=qgis-custom/qgis-dmav
RUN --mount=type=cache,id=ccache,target=/root/.ccache \
    mkdir -p /src/qgis && cd /src/qgis \
    && git init -q \
    && git fetch -q --depth 1 https://github.com/${qgis_repository}.git ${qgis_ref} \
    && git checkout -q FETCH_HEAD \
    && cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DUSE_CCACHE=ON \
      # silence the ABI notes of GCC on arm64, they exceed the log limit of BuildKit
      -DCXX_EXTRA_FLAGS=-Wno-psabi \
      -DENABLE_TESTS=OFF \
      -DWITH_DESKTOP=ON \
      -DWITH_SERVER=OFF \
      -DWITH_3D=OFF \
      -DWITH_QUICK=OFF \
      # the desktop runs on X11, Qt has no Wayland platform in the image
      -DWITH_WAYLAND=OFF \
      -DWITH_CUSTOM_WIDGETS=OFF \
      # the gui library is required by the processing plugin
      -DWITH_GUI=ON \
      -DWITH_ANALYSIS=ON \
      -DWITH_BINDINGS=ON \
      -DWITH_QGIS_PROCESS=ON \
      -DWITH_QTWEBENGINE=OFF \
      -DWITH_QTSERIALPORT=OFF \
      -DWITH_PDAL=OFF \
      -DWITH_DRACO=OFF \
      -DWITH_EXIV2=OFF \
      -DWITH_GSL=OFF \
      -DWITH_GRASS7=OFF \
      -DWITH_GRASS8=OFF \
      -DWITH_INTERNAL_SPATIALINDEX=ON \
      -DUSE_OPENCL=OFF \
    && cmake --build build \
    && DESTDIR=/install cmake --install build --strip \
    && rm -rf /src/qgis

# Drop what is only useful for development
RUN cd /install/usr \
    && rm -rf include lib/cmake lib/pkgconfig lib/*/cmake lib/*/pkgconfig \
    # Python modules are not stripped by the install
    && (find /install -type f -name '*.so*' | xargs strip --strip-unneeded 2>/dev/null || true) \
    # one du per level, as du does not count twice the same directory
    && for DIR in /install/usr /install/usr/lib /install/usr/share /install/usr/share/qgis /install/usr/share/qgis/python; do \
      du -sh ${DIR}/*; \
    done | sort -h | tail -30

# Qt Multimedia libraries are copied, not installed from their packages, to leave out the FFmpeg plugin and codecs
ADD --chmod=755 https://raw.githubusercontent.com/qgis/qgis-docker/9fe8e4c03fef211a29dbd68a0fc6ea06d84eca3a/slim/runtime-packages.sh /usr/local/bin/runtime-packages.sh
RUN mkdir /runtime \
    && runtime-packages.sh /install libqt6multimedia6 libqt6multimediawidgets6 libqt6spatialaudio6 python3-pyqt6.qtmultimedia \
      > /runtime/packages.txt \
    && cat /runtime/packages.txt

FROM ${os}:${release}
LABEL maintainer="OPENGIS.ch <info@opengis.ch>"

ARG DEBIAN_FRONTEND=noninteractive

# The last two lines are the desktop: a font, the Python modules of its plugins, and the SVG icons, a plugin of Qt that
# no library depends on
RUN --mount=type=bind,from=builder,source=/runtime,target=/runtime \
    apt-get update \
    && xargs -a /runtime/packages.txt apt-get install -y --no-install-recommends \
      ca-certificates libqca-qt6-plugins libqt6sql6-sqlite pyqt6-dev-tools python3 python3-numpy python3-pip \
      python3-psycopg python3-psycopg2 python3-pydantic python3-pyqt6 python3-pyqt6.qsci python3-pyqt6.qtpositioning \
      python3-yaml qt6-qpa-plugins tini xvfb \
      fonts-dejavu-core python3-jinja2 python3-lxml python3-matplotlib python3-owslib python3-plotly python3-pygments \
      qt6-svg-plugins \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install/ /
RUN ldconfig

ENV LANG=C.UTF-8
ENV QGIS_PREFIX_PATH=/usr
ENV PYTHONPATH=/usr/share/qgis/python:/usr/share/qgis/python/plugins
# pip installs into /usr/local, next to the Python packages of the system
ENV PIP_BREAK_SYSTEM_PACKAGES=1
# Qt Multimedia looks for PipeWire, which is not installed
ENV QT_LOGGING_RULES=qt.multimedia.symbolsresolver.warning=false

# qgis_process only loads the Python processing providers enabled in the user profile,
# the GDAL and QGIS providers are split from the processing plugin since QGIS 4.4
RUN for PLUGIN in gdalprovider qgisprovider; do \
      if [ -d /usr/share/qgis/python/plugins/${PLUGIN} ]; then QT_QPA_PLATFORM=offscreen qgis_process plugins enable ${PLUGIN} || exit 1; fi; \
    done

# an init process forwards the signals and reaps the zombie processes, xvfb-run hangs if it is the PID 1
ENTRYPOINT ["/usr/bin/tini", "--"]
