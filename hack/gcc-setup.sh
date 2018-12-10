#!/bin/bash

# TODO(andrewrynhard): /toolchain should be a parameter to this script.

for file in gcc/config/{linux,i386/linux{,64}}.h
do
  cp -uv $file{,.orig}
  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/toolchain&@g' \
      -e 's@/usr@/toolchain@g' $file.orig > $file
  echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/toolchain/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
  touch $file.orig
done

sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
