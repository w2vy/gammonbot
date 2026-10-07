# Build latest gnubg from sources in latest Alpine Linux
#
# Created: Ingo Macherius <ingo@macherius.de>, 2022-02-20
#
# Copyright (C) 1998-2003 Gary Wong <gtw@gnu.org>
# Copyright (C) 2000-2026 the AUTHORS
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.

######################################################
# Build gnubg from source in a separate builder image
######################################################

FROM alpine:3 AS builder_gnubg

ARG GNUBG_INSTALL_DIRECTORY=/gnubg/install/

# Set up compiler, toolchain and development libs
RUN set -ex && apk add --no-cache \
    gcc musl-dev glib-dev \
    git libtool automake autoconf make bison flex file texinfo patch dos2unix

# Build from latest sources after applying robustness patch.
# The binary is meant for use in a FIBS gammonbot only, we only roll in
# an bare minimum of functionality.
# We want to be fast bot, so ramp up compiler optimizations and enable SIMD=AVX.
WORKDIR /
RUN git clone https://https.git.savannah.gnu.org/git/gnubg.git
WORKDIR /gnubg
COPY ./patch/gnubg.patch .
RUN dos2unix gnubg.patch drawboard.c configure.ac \
    && patch --strip=1 --input=gnubg.patch \
    && chmod +x autogen.sh \
    && ./autogen.sh \
    && CFLAGS="--pipe -Ofast" \
        CC=gcc \
        ./configure \
        --prefix=${GNUBG_INSTALL_DIRECTORY} \
        --disable-gasserts \
        --without-gtk \
        --without-board3d \
        --without-sqlite \
        --disable-threads \
        --without-python \
        --without-libcurl \
        --disable-cputest \
        --enable-simd=avx \
    && make -j install

 # Remove files not needed to keep docker image size small
WORKDIR ${GNUBG_INSTALL_DIRECTORY}
RUN rm -rf \
    bin/bearoffdump \
    bin/makehyper \
    bin/makeweights \
    share/gnubg/gnubg.css \
    share/gnubg/boards.xml \
    share/gnubg/gnubg.gtkrc \
    share/gnubg/gnubg.sql \
    share/gnubg/textures.txt \
    bin/makebearoff \
    share/gnubg/Shaders \
    share/gnubg/flags \
    share/gnubg/fonts \ 
    share/gnubg/scripts \
    share/gnubg/textures \
    share/gnubg/sounds \
    share/doc \
    share/man \
    && strip bin/gnubg

##################################################
# Runtime image with gnubg and GammonBot scripts
##################################################

FROM alpine:3

ARG GNUBG_INSTALL_DIRECTORY=/gnubg/install/
ARG GBOT_INSTALL_DIRECTORY=/home/gammonbot/

# Install dependencies for gnubg and GammonBot scripts
RUN set -ex && \
    apk add --no-cache \
        glib \
        perl perl-scalar-list-utils perl-time-hires perl-carp

COPY --from=builder_gnubg ${GNUBG_INSTALL_DIRECTORY} ${GNUBG_INSTALL_DIRECTORY}
COPY ./gbot/* ${GBOT_INSTALL_DIRECTORY}

CMD ["/home/gammonbot/entrypoint.sh"]
