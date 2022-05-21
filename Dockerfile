# Build latest gnubg from sources in latest Alpine Linux
#
# Created: Ingo Macherius <ingo@macherius.de>, 2022-02-20
#
# Copyright (C) 1998-2003 Gary Wong <gtw@gnu.org>
# Copyright (C) 2000-2022 the AUTHORS
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

FROM alpine:3.15 AS gnubg_builder

ARG GNUBG_INSTALL_DIRECTORY=/gnubg/install
ARG GNUBG_COMPILE_DIRECTORY=/gnubg
ARG GNUBG_PATCH_FILE=./patch/gnubg.patch

# Compiler and development libc
RUN set -ex && \
    apk add --no-cache gcc musl-dev
# Toolchain for Linux build
RUN set -ex && \
    apk add --no-cache cvs libtool automake autoconf make bison flex file texinfo patch
# Libs
RUN set -ex && \
    apk add --no-cache glib-dev 

# Download sources
RUN cvs -z7 -d:pserver:anonymous@cvs.savannah.gnu.org:/sources/gnubg co gnubg
COPY ${GNUBG_PATCH_FILE} .
RUN patch -s -p0 < gnubg.patch
WORKDIR ${GNUBG_COMPILE_DIRECTORY}
RUN chmod +x autogen.sh && ./autogen.sh

# The binary is meant for use in a FIBS gammonbot, we need only
# an absolute minimum of functionality. So let's exclude the fancy stuff.
# Also, we want to be fast bot, so ramp up compiler optimizations

#CFLAGS="--pipe -Ofast -march=native -mtune=native"
RUN \
CFLAGS="--pipe -Ofast" \
CC=gcc \
 ./configure \
 --prefix=${GNUBG_INSTALL_DIRECTORY} \
 --disable-gasserts \
 --without-gtk \
 --without-board3d \
 --without-sqlite \
 --disable-threads \
 --without-python \
 --without-libcurl
RUN make install && \
  rm -f ${GNUBG_INSTALL_DIRECTORY}/bin/bearoffdump \
        ${GNUBG_INSTALL_DIRECTORY}/bin/makehyper \
        ${GNUBG_INSTALL_DIRECTORY}/bin/makeweights \
        ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/gnubg.css \
        ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/boards.xml \
        ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/gnubg.gtkrc \
        ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/gnubg.sql \
        ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/textures.txt \
  && rm -rf ${GNUBG_INSTALL_DIRECTORY}/bin/makebearoff \
         ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/Shaders \
         ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/flags \
         ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/fonts \ 
         ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/scripts \
         ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/textures \
         ${GNUBG_INSTALL_DIRECTORY}/share/gnubg/sounds \
         ${GNUBG_INSTALL_DIRECTORY}/share/doc \
         ${GNUBG_INSTALL_DIRECTORY}/share/man \
  && strip ${GNUBG_INSTALL_DIRECTORY}/bin/gnubg

##################################

FROM alpine:3.15

ARG GNUBG_INSTALL_DIRECTORY=/gnubg/install
ARG GNUBG_COMPILE_DIRECTORY=/gnubg

ARG GBOT_INSTALL_DIRECTORY=/home/gammonbot
ARG GBOT_SOURCE_DIRECTORY=./gbot

# Copy over gnubg binary from builder and install dependencies

RUN mkdir --parents /${GNUBG_INSTALL_DIRECTORY}
# Libs for gnubg
RUN set -ex && \
    apk add --no-cache glib 
COPY --from=gnubg_builder /${GNUBG_INSTALL_DIRECTORY} /${GNUBG_INSTALL_DIRECTORY}

# Install GammonBot scripts and Perl

RUN mkdir --parents /${GNUBG_INSTALL_DIRECTORY}
# Perl
RUN set -ex && \
    apk add --no-cache perl perl-scalar-list-utils perl-time-hires perl-carp

# Python
#RUN set -ex && \
#     apk add --no-cache python3
# Install python/pip
ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache python3 && ln -sf python3 /usr/bin/python
RUN python3 -m ensurepip
RUN pip3 install --no-cache --upgrade pip setuptools
RUN apk add gcc g++ make libffi-dev openssl-dev git
RUN pip3 install pycryptodome
# Copy our scripts
WORKDIR ${GBOT_INSTALL_DIRECTORY}
COPY ${GBOT_SOURCE_DIRECTORY}/* ./

CMD ["/home/gammonbot/entrypoint.sh"]
