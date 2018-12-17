FROM debian:buster-20180213
RUN apt-get -y update \
    && apt-get -y install --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    gawk \
    m4 \
    xz-utils
ENV ARCH x86_64
ENV SYS linux
ENV VENDOR talos
ENV SYSROOT /${VENDOR}
ENV TOOLCHAIN /toolchain
ENV TARGET ${ARCH}-${VENDOR}-${SYS}-gnu
ENV SRC /usr/local/src
ENV ROOTFS /rootfs
ENV PATH ${TOOLCHAIN}/bin:$PATH
RUN mkdir -p ${SYSROOT}${TOOLCHAIN}
RUN ln -s ${SYSROOT}${TOOLCHAIN} ${TOOLCHAIN}
RUN mkdir -p ${TOOLCHAIN}/lib
RUN ln -s lib ${TOOLCHAIN}/lib64
WORKDIR ${SRC}

ENV CURL "curl --retry 5 --retry-delay 0 --retry-max-time 45 -L"

# binutils pass 1

WORKDIR ${SRC}/binutils-pass-1/build
RUN ${CURL} https://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/binutils-pass-1/build/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --with-sysroot=${SYSROOT} \
    --with-lib-path=${TOOLCHAIN}/lib \
    --target=${TARGET} \
    --disable-nls \
    --disable-werror
RUN make -j $(($(nproc) / 2))
RUN make install

# gcc pass 1

WORKDIR ${SRC}/gcc-pass-1
RUN ${CURL} https://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz | tar --strip-components=1 -xJ \
    && mkdir mpfr && curl https://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz | tar -xJ --strip-components=1 -C mpfr \
    && mkdir gmp && curl https://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz | tar -xJ --strip-components=1 -C gmp \
    && mkdir mpc && curl https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz | tar -xz --strip-components=1 -C mpc
COPY ./hack/gcc-setup.sh /bin/
RUN chmod +x /bin/gcc-setup.sh
RUN gcc-setup.sh
WORKDIR ${SRC}/gcc-pass-1/build
RUN ../configure \
    --target=${TARGET} \
    --prefix=${TOOLCHAIN} \
    --with-glibc-version=2.26 \
    --with-sysroot=${SYSROOT} \
    --with-newlib \
    --without-headers \
    --with-local-prefix=${TOOLCHAIN} \
    --with-native-system-header-dir=${TOOLCHAIN}/include \
    --disable-nls \
    --disable-shared \
    --disable-multilib \
    --disable-decimal-float \
    --disable-threads \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libmpx \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --enable-languages=c,c++
RUN make -j $(($(nproc) / 2))
RUN make install-strip

# linux headers

WORKDIR ${SRC}/linux-headers
RUN ${CURL} https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.10.tar.xz | tar --strip-components=1 -xJ
RUN make mrproper
RUN make INSTALL_HDR_PATH=dest headers_install
RUN cp -rv dest/include/* ${TOOLCHAIN}/include
WORKDIR ${SRC}/glibc
RUN ${CURL} https://ftp.gnu.org/gnu/glibc/glibc-2.26.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/glibc/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --host=${TARGET} \
    --build=$(../scripts/config.guess) \
    --enable-kernel=4.9 \
    --with-headers=${TOOLCHAIN}/include \
    --enable-obsolete-nsl \
    libc_cv_forced_unwind=yes \
    libc_cv_c_cleanup=yes
RUN make -j $(($(nproc) / 2))
RUN make install
RUN echo 'int main(){}' > dummy.c
RUN ${TARGET}-gcc dummy.c
RUN readelf -l a.out | grep "${TOOLCHAIN}"
RUN rm -v dummy.c a.out

# libstdcpp

WORKDIR ${SRC}/libstdcpp
RUN ${CURL} https://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/libstdcpp/build
RUN ../libstdc++-v3/configure \
    --host=${TARGET} \
    --prefix=${TOOLCHAIN} \
    --disable-multilib \
    --disable-nls \
    --disable-libstdcxx-threads \
    --disable-libstdcxx-pch \
    --with-gxx-include-dir=${TOOLCHAIN}/${TARGET}/include/c++/7.3.0
RUN make -j $(($(nproc) / 2))
RUN make install

# binutils pass 2

WORKDIR ${SRC}/binutils-pass-2
RUN ${CURL} https://ftp.gnu.org/gnu/binutils/binutils-2.29.1.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/binutils-pass-2/build
RUN CC=${TARGET}-gcc \
    AR=${TARGET}-ar \
    RANLIB=${TARGET}-ranlib \
    ../configure \
    --prefix=${TOOLCHAIN} \
    --disable-nls \
    --disable-werror \
    --with-lib-path=${TOOLCHAIN}/lib \
    --with-sysroot=${SYSROOT}
RUN make -j $(($(nproc) / 2))
RUN make install
RUN make -C ld clean \
    && make -C ld LIB_PATH=/usr/lib:/lib \
    && cp -v ld/ld-new ${TOOLCHAIN}/bin

# gcc pass 2

WORKDIR ${SRC}/gcc-pass-2
RUN ${CURL} https://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz | tar --strip-components=1 -xJ \
    && mkdir mpfr && curl https://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz | tar -xJ --strip-components=1 -C mpfr \
    && mkdir gmp && curl https://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz | tar -xJ --strip-components=1 -C gmp \
    && mkdir mpc && curl https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz | tar -xz --strip-components=1 -C mpc
RUN cat gcc/limitx.h gcc/glimits.h gcc/limity.h > `dirname $(${TARGET}-gcc -print-libgcc-file-name)`/include-fixed/limits.h
COPY --chown=1000 ./hack/gcc-setup.sh /bin/
RUN chmod +x /bin/gcc-setup.sh \
    && gcc-setup.sh
WORKDIR ${SRC}/gcc-pass-2/build
RUN CC=${TARGET}-gcc \
    CXX=${TARGET}-g++ \
    AR=${TARGET}-ar \
    RANLIB=${TARGET}-ranlib \
    ../configure \
    --prefix=${TOOLCHAIN} \
    --with-local-prefix=${TOOLCHAIN} \
    --with-native-system-header-dir=${TOOLCHAIN}/include \
    --enable-languages=c,c++ \
    --disable-libstdcxx-pch \
    --disable-multilib \
    --disable-bootstrap \
    --disable-libgomp
RUN make -j $(($(nproc) / 2))
RUN make install-strip
RUN ln -sv gcc ${TOOLCHAIN}/bin/cc \
    && echo 'int main(){}' > dummy.c \
    && cc dummy.c \
    && readelf -l a.out | grep "${TOOLCHAIN}"

# tcl

WORKDIR ${SRC}/tcl
RUN ${CURL} https://sourceforge.net/projects/tcl/files/Tcl/8.6.7/tcl-core8.6.7-src.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/tcl/build
RUN ../unix/configure --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install
RUN chmod -v u+w ${TOOLCHAIN}/lib/libtcl8.6.so \
    && make install-private-headers \
    && ln -sv tclsh8.6 ${TOOLCHAIN}/bin/tclsh

# expect

WORKDIR ${SRC}/expect
RUN ${CURL} https://downloads.sourceforge.net/expect/expect5.45.3.tar.gz | tar --strip-components=1 -xz
RUN cp -v configure configure.orig \
    && sed 's:/usr/local/bin:/bin:' configure.orig > configure
WORKDIR ${SRC}/expect/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --with-tcl=${TOOLCHAIN}/lib \
    --with-tclinclude=${TOOLCHAIN}/include
RUN make -j $(($(nproc) / 2))
RUN make SCRIPTS="" install

# dejagnu

WORKDIR ${SRC}/dejagnu
RUN ${CURL} https://ftp.gnu.org/gnu/dejagnu/dejagnu-1.6.1.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/dejagnu/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make install

# check

WORKDIR ${SRC}/check
RUN ${CURL} https://github.com/libcheck/check/releases/download/0.12.0/check-0.12.0.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/check/build
RUN PKG_CONFIG= ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# ncurses

WORKDIR ${SRC}/ncurses
RUN ${CURL} https://ftp.gnu.org/gnu//ncurses/ncurses-6.0.tar.gz | tar --strip-components=1 -xz
RUN sed -i s/mawk// configure
WORKDIR ${SRC}/ncurses/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --with-shared \
    --without-debug \
    --without-ada \
    --enable-widec \
    --enable-overwrite
RUN make -j $(($(nproc) / 2))
RUN make install

# bash

WORKDIR ${SRC}/bash
RUN ${CURL} https://ftp.gnu.org/gnu/bash/bash-4.4.12.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/bash/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --without-bash-malloc
RUN make -j $(($(nproc) / 2))
RUN make install
RUN ln -sv bash ${TOOLCHAIN}/bin/sh

# bzip2

WORKDIR ${SRC}/bzip2
RUN ${CURL} https://fossies.org/linux/misc/bzip2-1.0.6.tar.gz | tar --strip-components=1 -xz
RUN sed -i 's@\(ln -s -f \)$(TOOLCHAIN)/bin/@\1@' Makefile
RUN make -j $(($(nproc) / 2)) -f Makefile-libbz2_so
RUN make -j $(($(nproc) / 2)) clean
RUN make -j $(($(nproc) / 2))
RUN make PREFIX=${TOOLCHAIN} install
RUN cp -v bzip2-shared ${TOOLCHAIN}/bin/bzip2 \
    && cp -av libbz2.so* ${TOOLCHAIN}/lib \
    && mkdir -p ${TOOLCHAIN}/usr/lib \
    && ln -sv ../../lib/libbz2.so.1.0 ${TOOLCHAIN}/lib/libbz2.so \
    && rm -v ${TOOLCHAIN}/bin/bunzip2 \
    && rm -v ${TOOLCHAIN}/bin/bzcat \
    && ln -sv bzip2 ${TOOLCHAIN}/bin/bunzip2 \
    && ln -sv bzip2 ${TOOLCHAIN}/bin/bzcat

# coreutils

WORKDIR ${SRC}/coreutils
RUN ${CURL} https://ftp.gnu.org/gnu/coreutils/coreutils-8.27.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/coreutils/build
RUN FORCE_UNSAFE_CONFIGURE=1 \
    ../configure \
    --prefix=${TOOLCHAIN} \
    --enable-install-program=hostname
RUN make -j $(($(nproc) / 2))
RUN make install

# diffutils

WORKDIR ${SRC}/diffutils
RUN ${CURL} https://ftp.gnu.org/gnu/diffutils/diffutils-3.6.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/diffutils/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# file

WORKDIR ${SRC}/file
RUN curl --retry 5 --retry-delay 0 --retry-max-time 45 -L ftp://ftp.astron.com/pub/file/file-5.32.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/file/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# findutils

WORKDIR ${SRC}/findutils
RUN ${CURL} https://ftp.gnu.org/gnu/findutils/findutils-4.6.0.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/findutils/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# gawk

WORKDIR ${SRC}/gawk
RUN ${CURL} https://ftp.gnu.org/gnu/gawk/gawk-4.2.0.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/gawk/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# gettext

WORKDIR ${SRC}/gettext
RUN ${CURL} https://ftp.gnu.org/gnu/gettext/gettext-0.19.8.1.tar.xz | tar --strip-components=1 -xJ
RUN cd gettext-tools \
    && EMACS="no" \
    ./configure \
    --prefix=${TOOLCHAIN} \
    --disable-shared
RUN cd gettext-tools \
    && make -C gnulib-lib \
    && make -C intl pluralx.c \
    && make -C src msgfmt \
    && make -C src msgmerge \
    && make -C src xgettext
RUN cd gettext-tools \
    && cp -v src/msgfmt src/msgmerge src/xgettext ${TOOLCHAIN}/bin

# grep

WORKDIR ${SRC}/grep
RUN ${CURL} https://ftp.gnu.org/gnu/grep/grep-3.1.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/grep/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# gzip

WORKDIR ${SRC}/gzip
RUN ${CURL} https://ftp.gnu.org/gnu/gzip/gzip-1.8.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/gzip/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# m4

WORKDIR ${SRC}/m4
RUN ${CURL} https://ftp.gnu.org/gnu/m4/m4-1.4.18.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/m4/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# lzip

WORKDIR ${SRC}/lzip
RUN ${CURL} https://download.savannah.gnu.org/releases/lzip/lzip-1.20.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/lzip/build
RUN ../configure --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# ed

WORKDIR ${SRC}/ed
RUN ${CURL} https://ftp.gnu.org/gnu/ed/ed-1.14.2.tar.lz | tar --strip-components=1 -x --lzip
WORKDIR ${SRC}/ed/build
RUN ../configure --prefix=${TOOLCHAIN} \
    --bindir=/bin
RUN make -j $(($(nproc) / 2))
RUN make install

# texinfo

WORKDIR ${SRC}/texinfo
RUN ${CURL} https://ftp.gnu.org/gnu/texinfo/texinfo-6.5.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/texinfo/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# bc

WORKDIR ${SRC}/bc
RUN ${CURL} https://ftp.gnu.org/gnu/bc/bc-1.07.1.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/bc/build
RUN ../configure --prefix=${TOOLCHAIN} \
    --with-readline \
    --mandir=${TOOLCHAIN}/share/man \
    --infodir=${TOOLCHAIN}/share/info
RUN make -j $(($(nproc) / 2))
RUN make install

# bison

WORKDIR ${SRC}/bison
RUN ${CURL} https://ftp.gnu.org/gnu/bison/bison-3.0.4.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/bison/build
RUN FORCE_UNSAFE_CONFIGURE=1 \
    ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# make

WORKDIR ${SRC}/make
RUN ${CURL} https://ftp.gnu.org/gnu/make/make-4.2.1.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/make/build
RUN ../configure  \
    --prefix=${TOOLCHAIN} \
    --without-guile
RUN make -j $(($(nproc) / 2))
RUN make install

# patch

WORKDIR ${SRC}/patch
RUN ${CURL} https://ftp.gnu.org/gnu/patch/patch-2.7.5.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/patch/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# perl

WORKDIR ${SRC}/perl
RUN ${CURL} https://www.cpan.org/src/5.0/perl-5.26.1.tar.xz | tar --strip-components=1 -xJ
RUN sh Configure \
    -des \
    -Dprefix=${TOOLCHAIN} \
    -Dvendorprefix=${TOOLCHAIN} \
    -Duseshrplib \
    -Dlibs="-lm -ldl" \
    -Dusedl \
    -Ddlsrc="dl_dlopen.xs"
RUN make -j $(($(nproc) / 2))
RUN make install

WORKDIR ${SRC}/sed
RUN ${CURL} https://ftp.gnu.org/gnu/sed/sed-4.4.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/sed/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# tar

WORKDIR ${SRC}/tar
RUN ${CURL} https://ftp.gnu.org/gnu/tar/tar-1.29.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/tar/build
RUN FORCE_UNSAFE_CONFIGURE=1 \
    ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# util-linux

WORKDIR ${SRC}/util-linux
RUN ${CURL} https://www.kernel.org/pub/linux/utils/util-linux/v2.31/util-linux-2.31.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/util-linux/build
RUN PKG_CONFIG="" \
    ../configure \
    --prefix=${TOOLCHAIN} \
    --without-python \
    --disable-makeinstall-chown \
    --without-systemdsystemunitdir \
    --without-ncurses
RUN make -j $(($(nproc) / 2))
RUN make install
RUN cp -R ../include ${TOOLCHAIN}/include/util-linux

# xz

WORKDIR ${SRC}/xz
RUN ${CURL} https://github.com/xz-mirror/xz/releases/download/v5.2.2/xz-5.2.2.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/xz/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# libffi

WORKDIR ${SRC}/libffi
RUN curl --retry 5 --retry-delay 0 --retry-max-time 45 ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz | tar --strip-components=1 -xz
RUN sed -e '/^includesdir/ s/$(libdir).*$/$(includedir)/' -i include/Makefile.in
RUN sed -e '/^includedir/ s/=.*$/=@includedir@/' -e 's/^Cflags: -I${includedir}/Cflags:/' -i libffi.pc.in
WORKDIR ${SRC}/libffi/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --disable-static
RUN make -j $(($(nproc) / 2))
RUN make install

# gmp

WORKDIR ${SRC}/gmp
RUN ${CURL} https://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/gmp/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --enable-cxx \
    --disable-static
RUN make -j $(($(nproc) / 2))
RUN make install

# mpfr

WORKDIR ${SRC}/mpfr
RUN ${CURL} https://ftp.gnu.org/gnu/mpfr/mpfr-3.1.6.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/mpfr/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --disable-static \
    --enable-thread-safe
RUN make -j $(($(nproc) / 2))
RUN make install

# mpc

WORKDIR ${SRC}/mpc
RUN ${CURL} https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/mpc/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --disable-static
RUN make -j $(($(nproc) / 2))
RUN make install

# expat

WORKDIR ${SRC}/expat
RUN ${CURL} https://github.com/libexpat/libexpat/releases/download/R_2_2_5/expat-2.2.5.tar.bz2 | tar --strip-components=1 -xj
WORKDIR ${SRC}/expat/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --disable-static
RUN make -j $(($(nproc) / 2))
RUN make install

# gdbm

WORKDIR ${SRC}/gdbm
RUN ${CURL} https://ftp.gnu.org/gnu/gdbm/gdbm-1.13.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/gdbm/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --disable-static \
    --enable-libgdbm-compat
RUN make -j $(($(nproc) / 2))
RUN make install

# zlib

WORKDIR ${SRC}/zlib
RUN ${CURL} https://zlib.net/zlib-1.2.11.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/zlib/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# python

WORKDIR ${SRC}/python
RUN ${CURL} https://www.python.org/ftp/python/3.6.3/Python-3.6.3.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/python/build
RUN echo ac_cv_file__dev_ptmx=no >config.site
RUN echo ac_cv_file__dev_ptc=no >>config.site
RUN apt-get update -y
RUN apt-get install -y python3
RUN ln -s /usr/bin/python3 /usr/bin/python
RUN rm -rf /usr/include
RUN CONFIG_SITE=config.site \
    ../configure \
    --prefix=${TOOLCHAIN} \
    --enable-shared \
    --host=${TARGET} \
    --build=${ARCH} \
    --target=${TARGET} \
    --disable-ipv6 \
    --with-tcltk-includes="-I${TOOLCHAIN}/include" \
    --with-tcltk-libs="-I${TOOLCHAIN}/lib" \
    --without-ensurepip
RUN sed -i 's/^#zlib/zlib/' Modules/Setup
RUN make -j $(($(nproc) / 2))
RUN make install

# openssl

WORKDIR ${SRC}/openssl
RUN ${CURL} https://www.openssl.org/source/openssl-1.1.0g.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/openssl/build
RUN ../config \
    --prefix=${TOOLCHAIN} \
    --openssldir=${TOOLCHAIN} \
    --libdir=lib \
    shared \
    zlib-dynamic
RUN make -j $(($(nproc) / 2))
RUN make install

# ca-certificates

RUN mkdir -p ${TOOLCHAIN}/etc/ssl/certs
RUN ${CURL} https://curl.haxx.se/ca/cacert.pem -o ${TOOLCHAIN}/etc/ssl/certs/ca-certificates

# curl

WORKDIR ${SRC}/curl
RUN ${CURL} https://curl.haxx.se/download/curl-7.56.1.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/curl/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --disable-static \
    --enable-threaded-resolver \
    --with-ca-bundle=${TOOLCHAIN}/etc/ssl/certs/ca-certificates
RUN make -j $(($(nproc) / 2))
RUN make install

# gperf

WORKDIR ${SRC}/gperf
RUN ${CURL} https://ftp.gnu.org/gnu/gperf/gperf-3.0.4.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/gperf/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# libcap

WORKDIR ${SRC}/libcap
RUN ${CURL} https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.25.tar.xz | tar --strip-components=1 -xJ
RUN sed -i '/install.*STALIBNAME/d' libcap/Makefile
RUN make -j $(($(nproc) / 2))
RUN make RAISE_SETFCAP=no lib=lib prefix=${TOOLCHAIN} install

# xml-parser

WORKDIR ${SRC}/xml-parser
RUN ${CURL} https://cpan.metacpan.org/authors/id/T/TO/TODDR/XML-Parser-2.44.tar.gz | tar --strip-components=1 -xz
RUN perl Makefile.PL EXPATINCPATH=${TOOLCHAIN}/include EXPATLIBPATH=${TOOLCHAIN}/lib
RUN make -j $(($(nproc) / 2))
RUN make install

# intltool

WORKDIR ${SRC}/intltool
RUN ${CURL} https://launchpad.net/intltool/trunk/0.51.0/+download/intltool-0.51.0.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/intltool/build
RUN ../configure --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# pkgconfig

WORKDIR ${SRC}/pkgconfig
RUN ${CURL} https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/pkgconfig/build
RUN ../configure --prefix=${TOOLCHAIN} \
    --with-internal-glib \
    --disable-host-too
RUN make -j $(($(nproc) / 2))
RUN make install

# elfutils

RUN ln -fs ${TOOLCHAIN}/bin/bash /bin/sh
WORKDIR ${SRC}/elfutils
RUN ${CURL} https://sourceware.org/ftp/elfutils/0.170/elfutils-0.170.tar.bz2 | tar --strip-components=1 -xj
WORKDIR ${SRC}/elfutils/build
RUN ../configure \
    --prefix=${TOOLCHAIN} \
    --without-bzlib
RUN make -j $(($(nproc) / 2))
RUN make install

# flex

WORKDIR ${SRC}/flex
RUN ${CURL} https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/flex/build
RUN sed -i "/math.h/a #include <malloc.h>" ../src/flexdef.h
RUN ../configure --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# kmod

RUN mkdir -p ${TOOLCHAIN}/usr/bin && ln -sv flex ${TOOLCHAIN}/usr/bin/lex
WORKDIR ${SRC}/kmod
RUN ${CURL} https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-25.tar.xz | tar --strip-components=1 -xJ
RUN ./configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# autoconf

RUN for target in depmod insmod modinfo modprobe rmmod; do ln -s ../bin/kmod ${TOOLCHAIN}/bin/${target}; done
WORKDIR ${SRC}/autoconf
RUN ${CURL} https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz | tar --strip-components=1 -xJ
WORKDIR ${SRC}/autoconf/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# git

WORKDIR ${SRC}/git
RUN ${CURL} https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.16.2.tar.xz | tar --strip-components=1 -xJ
RUN make configure
RUN ./configure \
    --prefix=${TOOLCHAIN}
RUN make -j $(($(nproc) / 2))
RUN make install

# cpio

WORKDIR ${SRC}/cpio
RUN ${CURL} https://ftp.gnu.org/gnu/cpio/cpio-2.12.tar.gz | tar --strip-components=1 -xz
WORKDIR ${SRC}/cpio/build
RUN ../configure \
    --prefix=${TOOLCHAIN}
RUN make
RUN make install

# golang

WORKDIR ${TOOLCHAIN}/usr/local
RUN ${CURL} https://dl.google.com/go/go1.11.2.linux-amd64.tar.gz | tar -xz

# cleanup

WORKDIR /
RUN rm -rf ${SRC}/*

# glibc

# PB: We start the glibc build from scratch in order to ensure a clean toolchain.

FROM scratch
COPY --from=0 /talos/toolchain /toolchain
RUN [ "/toolchain/bin/mkdir", "/bin" ]
RUN [ "/toolchain/bin/ln", "-s", "/toolchain/bin/bash", "/bin/sh" ]
RUN [ "/toolchain/bin/ln", "-s", "/toolchain/bin/bash", "/bin/bash" ]

ENV TOOLCHAIN /toolchain
ENV ROOTFS /rootfs
ENV PATH ${TOOLCHAIN}/bin
ENV SRC /usr/local/src

# fhs

# TODO(andrewrynhard): We should use a go library here to create the rootfs.
# We can then use the same library in the installation of Talos. This keeps
# things DRY.
WORKDIR ${ROOTFS}
COPY ./hack/fhs.sh ${TOOLCHAIN}/bin
RUN chmod +x ${TOOLCHAIN}/bin/fhs.sh
RUN fhs.sh ${ROOTFS}

# glibc

WORKDIR ${SRC}/glibc
RUN curl --retry 5 --retry-delay 0 --retry-max-time 45 https://ftp.gnu.org/gnu/glibc/glibc-2.26.tar.xz | tar --strip-components=1 -xJ
RUN ln -sfv ${TOOLCHAIN}/lib/gcc /usr/lib
# Required by makeinfo.
RUN ln -sv ${TOOLCHAIN}/bin/perl /usr/bin/perl
WORKDIR ${SRC}/glibc/build
RUN CC="gcc -isystem /usr/lib/gcc/x86_64-pc-linux-gnu/7.2.0/include -isystem /usr/include" \
    ../configure \
    --prefix=/usr \
    --disable-static \
    --disable-werror \
    --enable-kernel=4.9 \
    --enable-stack-protector=strong \
    libc_cv_slibdir=/lib
RUN make -j $(($(nproc) / 2))
# RUN make check || true
RUN sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
RUN make install DESTDIR=${ROOTFS}
# RUN mkdir ${ROOTFS}/usr/lib/locale
# RUN localedef -i en_US -f UTF-8 en_US.UTF-8
# RUN mkdir p ${ROOTFS}/etc/default
# RUN echo LC_ALL="en_US.UTF-8" >${ROOTFS}/etc/default/locale
RUN ln -sfv ${TOOLCHAIN}/lib/libgcc_s.so{,.1} /usr/lib
RUN mv -v ${TOOLCHAIN}/bin/{ld,ld-old}
RUN mv -v ${TOOLCHAIN}/$(uname -m)-pc-linux-gnu/bin/{ld,ld-old}
RUN mv -v ${TOOLCHAIN}/bin/{ld-new,ld}
RUN ln -sv ${TOOLCHAIN}/bin/ld ${TOOLCHAIN}/$(uname -m)-pc-linux-gnu/bin/ld
RUN gcc -dumpspecs | sed -e "s@${TOOLCHAIN}@@g" \
    -e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
    -e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' > \
    `dirname $(gcc --print-libgcc-file-name)`/specs
RUN echo 'int main(){}' > dummy.c
RUN cc dummy.c -v -Wl,--verbose &> dummy.log
RUN readelf -l a.out | grep ': /lib'
RUN grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log
RUN grep -B1 '^ /usr/include' dummy.log
RUN grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
RUN grep "/lib.*/libc.so.6 " dummy.log
RUN grep found dummy.log
RUN rm -v dummy.c a.out dummy.log
WORKDIR /
RUN rm -rf ${SRC}/*

# cleanup

RUN strip --strip-debug /toolchain/lib/* || true
RUN strip --strip-unneeded /toolchain/bin/* /toolchain/sbin/* || true
RUN rm -rf /toolchain/share/info /toolchain/share/man /toolchain/share/doc

# toolchain

FROM scratch
COPY --from=1 /toolchain /toolchain
COPY --from=1 /rootfs /rootfs
ENV TOOLCHAIN /toolchain
ENV ROOTFS /rootfs
ENV INITRAMFS /initramfs
ENV SRC /toolchain/usr/local/src
ENV GOROOT /toolchain/usr/local/go
ENV GOPATH /toolchain/go
ENV PATH /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:${TOOLCHAIN}/bin:$GOROOT/bin:$GOPATH/bin
RUN [ "/toolchain/bin/mkdir", "/bin" ]
RUN [ "/toolchain/bin/ln", "-s", "/toolchain/bin/bash", "/bin/sh" ]
RUN [ "/toolchain/bin/ln", "-s", "/toolchain/bin/bash", "/bin/bash" ]
RUN mkdir -p /tmp
RUN mkdir -p /usr
RUN ln -s /toolchain/lib /lib
RUN ln -s /toolchain/lib /usr/lib
RUN ln -s /lib /lib64
RUN ln -s /lib /usr/lib64
RUN mkdir ${SRC}
RUN mkdir ${TOOLCHAIN}/go
RUN curl --retry 5 --retry-delay 0 --retry-max-time 45 -L https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.10.tar.xz -o ${SRC}/linux.tar.xz
