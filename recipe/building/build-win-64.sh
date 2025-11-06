#!/usr/bin/env bash
set -eu

_topdir="${GHC_INSTALLDIR}/lib"
settings_topdir="\\\$topdir/../.."
settings_mingw="\\\$topdir/../mingw"

_privatedir="${_topdir}/private"

mkdir -p "${_privatedir}"

pushd bootstrap-ghc 2>/dev/null || exit 1
  tar cf - ./* | (cd "${GHC_INSTALLDIR}" || exit; tar xf -)
popd 2>/dev/null || exit 1

# Build CRT compatibility shim for legacy MSVCRT symbols
x86_64-w64-mingw32-gcc.exe -c -D_CRT_SECURE_NO_WARNINGS -O2 "${RECIPE_DIR}"/building/crt_compat.c -o "${_privatedir}"/crt_compat.o
x86_64-w64-mingw32-ar.exe rcs "${_privatedir}"/libcrt_compat.a "${_privatedir}"/crt_compat.o
rm "${_privatedir}"/crt_compat.o

settings_file=$(find "${GHC_INSTALLDIR}" -name settings)

# Reassign mingw references to conda Mingw
perl -i -pe "s#${settings_mingw}/bin/(llvm-)?##" "${settings_file}"
perl -i -pe "s#-I${settings_mingw}/include#-I${settings_topdir}/Library/include#g" "${settings_file}"
perl -i -pe "s#-L${settings_mingw}/lib#-L${settings_topdir}/Library/lib#g" "${settings_file}"
perl -i -pe "s#-L${settings_mingw}/x86_64-w64-mingw32/lib#-L${settings_topdir}/Library/bin -L${settings_topdir}/Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,${settings_topdir}/Library/x86_64-w64-mingw32/sysroot/usr/lib#g" "${settings_file}"

# Add Windows-specific compiler flags to settings
perl -i -pe 's/(C compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
perl -i -pe 's/(C\+\+ compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-g++.exe"/g' "${settings_file}"
perl -i -pe 's/(CPP command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
perl -i -pe 's/(C compiler link flags", ")([^"]*)"/\1-fuse-ld=bfd -Wl,--enable-auto-import -Wl,--image-base=0x400000 -Wl,--disable-dynamicbase -Wl,--disable-high-entropy-va -Wl,--whole-archive,\$topdir\/private\/libcrt_compat.a,--no-whole-archive"/g' "${settings_file}"

# Also add to ld flags for direct linker invocation
perl -i -pe 's/(ld flags", ")([^"]*)"/\1 -L\$topdir\/private --whole-archive \$topdir\/private\/libcrt_compat.a --no-whole-archive \2"/g' "${settings_file}"

# # Add conda CFLAGS/CXXFLAGS/LDFLAGS (use Perl ENV to avoid backslash escaping issues)
# perl -i -pe 's/(C compiler flags", ")([^"]*)"/\1\2 $ENV{CFLAGS}"/g' "${settings_file}"
# perl -i -pe 's/(C\+\+ compiler flags", ")([^"]*)"/\1\2 $ENV{CXXFLAGS}"/g' "${settings_file}"
# perl -i -pe 's/(ld flags", ")([^"]*)"/\1\2 $ENV{LDFLAGS}"/g' "${settings_file}"

# Update GHC settings for Windows toolchain compatibility
perl -i -pe 's/(ar command", ")([^"]*)"/\1x86_64-w64-mingw32-ar.exe"/g' "${settings_file}"
perl -i -pe 's/(ar flags", ")([^"]*)"/\1qc"/g' "${settings_file}"
perl -i -pe 's/(ar supports -L", ")([^"]*)"/\1NO"/g' "${settings_file}"

# Configure ranlib
perl -i -pe 's/(ranlib command", ")([^"]*)"/\1x86_64-w64-mingw32-ranlib.exe"/g' "${settings_file}"
  
# Force use of GNU ld instead of lld to avoid relocation type 0xe errors
perl -i -pe 's/(Merge objects command", ")([^"]*)"/\1x86_64-w64-mingw32-ld.exe"/g' "${settings_file}"
perl -i -pe 's/(Merge objects flags", ")([^"]*)"/\1-r"/g' "${settings_file}"
perl -i -pe 's/(Merge objects supports response files", ")([^"]*)"/\1YES"/g' "${settings_file}"

# Remove clang compiler options
perl -i -pe 's/--rtlib=compiler-rt//g' "${settings_file}"
perl -i -pe 's/-Qunused-arguments//g' "${settings_file}"
perl -i -pe 's/--target=([^ ]*)//g' "${settings_file}"

# Wrap windres
perl -i -pe 's#("windres command", ")[^"]*"#\1\$topdir/../bin/windres.bat"#g' "${settings_file}"
cp "${RECIPE_DIR}"/building/windres.bat "${GHC_INSTALLDIR}"/bin/windres.bat

# Reduce footprint
rm -rf "${GHC_INSTALLDIR}"/lib/lib
rm -rf "${GHC_INSTALLDIR}"/lib/doc/html
rm -rf "${GHC_INSTALLDIR}"/docs/html
rm -rf "${GHC_INSTALLDIR}"/mingw

mkdir -p "${GHC_INSTALLDIR}"/mingw/{include,lib,bin,share}
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/include/__unused__
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/lib/__unused__
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/bin/__unused__
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/share/__unused__

cp "${RECIPE_DIR}/activate.bat" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.bat"
