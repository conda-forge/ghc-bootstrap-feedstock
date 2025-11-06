#!/usr/bin/env bash
set -eu

pushd bootstrap-ghc 2>/dev/null || exit 1
  tar cf - ./* | (cd "${GHC_INSTALLDIR}" || exit; tar xf -)
popd 2>/dev/null || exit 1

# Build CRT compatibility shim for legacy MSVCRT symbols
echo "Building CRT compatibility shim..."
x86_64-w64-mingw32-gcc.exe -c "${RECIPE_DIR}"/building/crt_compat.c -o "${GHC_INSTALLDIR}"/lib/crt_compat.o
x86_64-w64-mingw32-ar.exe rcs "${GHC_INSTALLDIR}"/lib/libcrt_compat.a "${GHC_INSTALLDIR}"/lib/crt_compat.o

settings_file=$(find "${GHC_INSTALLDIR}" -name settings)

# Reassign mingw references to conda Mingw
perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##' "${settings_file}"
perl -i -pe 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${settings_file}"
perl -i -pe 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${settings_file}"
perl -i -pe 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${settings_file}"

# Add Windows-specific compiler flags to settings
perl -i -pe 's/("C compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
perl -i -pe 's/("C\+\+ compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-g++.exe"/g' "${settings_file}"
perl -i -pe 's/(CPP command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
perl -i -pe 's/("C compiler link flags", ")([^"]*)"/\1-fuse-ld=bfd -Wl,--enable-auto-import -Wl,--image-base=0x400000 -Wl,--disable-dynamicbase -Wl,--disable-high-entropy-va -L\$topdir\/..\/lib -lcrt_compat"/g' "${settings_file}"

# Update GHC settings for Windows toolchain compatibility
perl -i -pe 's/("ar command", ")([^"]*)"/\1x86_64-w64-mingw32-ar.exe"/g' "${settings_file}"
perl -i -pe 's/("ar flags", ")([^"]*)"/\1qc"/g' "${settings_file}"
perl -i -pe 's/("ar supports -L", ")([^"]*)"/\1NO"/g' "${settings_file}"

# Configure ranlib
perl -i -pe 's/("ranlib command", ")([^"]*)"/\1x86_64-w64-mingw32-ranlib.exe"/g' "${settings_file}"
  
# Force use of GNU ld instead of lld to avoid relocation type 0xe errors
perl -i -pe 's/("Merge objects command", ")([^"]*)"/\1x86_64-w64-mingw32-ld.exe"/g' "${settings_file}"
perl -i -pe 's/("Merge objects flags", ")([^"]*)"/\1-r"/g' "${settings_file}"
perl -i -pe 's/("Merge objects supports response files", ")([^"]*)"/\1YES"/g' "${settings_file}"

# Remove clang compiler options
perl -i -pe 's/--rtlib=compiler-rt//g' "${settings_file}"
perl -i -pe 's/-Qunused-arguments//g' "${settings_file}"
perl -i -pe 's/--target=([^ ]*)//g' "${settings_file}"

# Wrap windres
perl -i -pe 's#("windres command", ")[^"]*"#\1\$topdir/../bin/windres.bat"#g' "${settings_file}"
cp "${RECIPE_DIR}"/building/windres.bat "${GHC_INSTALLDIR}"/bin/windres.bat

cat "${settings_file}"

# Reduce footprint
rm -rf "${GHC_INSTALLDIR}"/lib/lib
rm -rf "${GHC_INSTALLDIR}"/lib/doc/html
rm -rf "${GHC_INSTALLDIR}"/doc/html
rm -rf "${GHC_INSTALLDIR}"/mingw

mkdir -p "${GHC_INSTALLDIR}"/mingw/{include,lib,bin,share}
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/include/__unused__
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/lib/__unused__
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/bin/__unused__
echo "Fake mingw directory created at ${GHC_INSTALLDIR}/mingw" | cat >> "${GHC_INSTALLDIR}"/mingw/share/__unused__

cp "${RECIPE_DIR}/activate.bat" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.bat"
