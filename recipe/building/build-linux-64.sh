#!/usr/bin/env bash
set -eu

unset build_alias
unset host_alias

# Create directories for binaries and logs
_topdir="${GHC_INSTALLDIR}/lib/ghc-${PKG_VERSION}"
settings_topdir="\\\$topdir/../../.."

_privatedir="${_topdir}/private"
settings_private="\\\$topdir/private"

mkdir -p "${_privatedir}"

# Correct sysroot redirection to system libc
sysroot_libc_script="${BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot/usr/lib64/libc.so"
perl -i -pe "s|/lib64/libc.so.6|libc.so.6|g" "$sysroot_libc_script"
perl -i -pe "s|/usr/lib64/libc_nonshared.a|libc_nonshared.a|g" "$sysroot_libc_script"
perl -i -pe "s|/lib64/ld-linux-x86-64.so.2|ld-2.17.so|g" "$sysroot_libc_script"

# This is needed by make install to use ncurses 5
export LD_PRELOAD=${BUILD_PREFIX}/lib/libtinfo.so
./configure \
  --prefix="${GHC_INSTALLDIR}" \
  --build="${BUILD}" \
  --host="${HOST}" \
  >& "${SRC_DIR}"/_logs/configure.log

echo "Running make install ..."
make install >& "${SRC_DIR}"/_logs/make_install.log

settings_file=$(find "${_topdir}" -name settings)
perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##g' "${settings_file}"

# Add system libs
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-L${settings_private} -Wl,-rpath ${settings_private} -Wl,-L${settings_topdir}/lib -Wl,-rpath,${settings_topdir}/lib -Wl,-rpath-link,${settings_topdir}/lib\"#g" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 -L${settings_private} -rpath ${settings_private} -L"${settings_topdir}"/lib -rpath ${settings_topdir}/lib -rpath-link ${settings_topdir}/lib\"#g" "${settings_file}"

perl -i -pe "s#(compiler flags\", \")([^\"]*)\"#\1\2 -fno-PIE -I${settings_topdir}/x86_64-conda-linux-gnu/sysroot/usr/include\"#g" "${settings_file}"
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-no-pie -Wl,-L${settings_topdir}/x86_64-conda-linux-gnu/sysroot/lib64 -Wl,-L${settings_topdir}/x86_64-conda-linux-gnu/sysroot/usr/lib64\"#g" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 -no-pie -L${settings_topdir}/x86_64-conda-linux-gnu/sysroot/lib64 -L${settings_topdir}/x86_64-conda-linux-gnu/sysroot/usr/lib64\"#g" "${settings_file}"

echo "Bundling ncurses 5 libraries privately"
# Copy ncurses 5 shared libraries to private location
cp "${BUILD_PREFIX}/lib/libncurses.so.5"* "${_topdir}"/private/ 2>/dev/null || true
cp "${BUILD_PREFIX}/lib/libtinfo.so.5"* "${_topdir}"/private/ 2>/dev/null || true
cp "${BUILD_PREFIX}/lib/libtinfow.so.5"* "${_topdir}"/private/ 2>/dev/null || true

# Update rpath for GHC binaries to use private libraries first
find "${_topdir}"/bin -name "ghc*" -type f -executable | while read -r binary; do
  if file "$binary" | grep -q "ELF"; then
    if ldd "$binary" 2>/dev/null | grep -q "libncurses\|libtinfo"; then
      echo "Updating rpath for $binary to use private ncurses"
      current_rpath=$(patchelf --print-rpath "$binary" 2>/dev/null || echo "")
      private_lib="\$ORIGIN/../private"

      new_rpath="${private_lib}${current_rpath:+:$current_rpath}"
      patchelf --set-rpath "$new_rpath" "$binary" 2>/dev/null && echo -n "."
    fi
  fi
done
echo " done"

# Verify sysroot compatibility
echo "Verify sysroot compatibility"
printf 'import System.Posix.Signals\nmain = installHandler sigTERM Default Nothing >> putStrLn "Signal test"\n' > signal_test.hs

ghc_test_log="${SRC_DIR}"/_logs/ghc_signal_test.log

# Add BUILD_PREFIX/lib to LD_LIBRARY_PATH for build-time test
# This helps the linker find libgmp during the build-time verification
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${LD_LIBRARY_PATH:-}"

"${GHC_INSTALLDIR}"/bin/ghc -v -L"${BUILD_PREFIX}"/lib -optc-fno-PIE -optl-no-pie signal_test.hs >> "${ghc_test_log}" 2>&1 || {
  cat "${ghc_test_log}"
  exit 1
}

if ./signal_test; then
  echo "Signal test passed"
else
  echo "Signal test failed with exit code $?"
  exit 1
fi

cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"
