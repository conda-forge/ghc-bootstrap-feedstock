#!/usr/bin/env bash
set -eu

unset build_alias
unset host_alias

# Create directories for binaries and logs
_topdir="${GHC_INSTALLDIR}/lib/ghc-${PKG_VERSION}"
settings_topdir="\\\$topdir/../../.."

# Correct sysroot redirection to system libc: strip absolute dir prefixes in the libc.so linker script
sysroot_libc_script="${BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot/usr/lib64/libc.so"
if [[ ! -f "${sysroot_libc_script}" ]]; then
  sysroot_libc_script="${BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot/usr/lib/libc.so"
fi
perl -i -pe 's#/(?:usr/)?lib(?:64)?/##g' "$sysroot_libc_script"

./configure --prefix="${GHC_INSTALLDIR}" >& "${SRC_DIR}"/_logs/configure.log

echo "Running make install ..."
make install >& "${SRC_DIR}"/_logs/make_install.log

settings_file=$(find "${_topdir}" -name settings)
perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##g' "${settings_file}"

# Add system libs
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-L${settings_topdir}/lib -Wl,-rpath,${settings_topdir}/lib -Wl,-rpath-link,${settings_topdir}/lib\"#g" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 -L"${settings_topdir}"/lib -rpath ${settings_topdir}/lib -rpath-link ${settings_topdir}/lib\"#g" "${settings_file}"

# Add sysroot
perl -i -pe "s#(C compiler flags\", \")([^\"]*)\"#\1\2 -I${settings_topdir}/aarch64-conda-linux-gnu/sysroot/usr/include\"#g" "${settings_file}"
perl -i -pe "s#(C\+\+ compiler flags\", \")([^\"]*)\"#\1\2 -I${settings_topdir}/aarch64-conda-linux-gnu/sysroot/usr/include\"#g" "${settings_file}"
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/lib64 -Wl,-L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/usr/lib64 -Wl,-L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/lib -Wl,-L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/usr/lib\"#g" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 -L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/lib64 -L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/usr/lib64 -L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/lib -L${settings_topdir}/aarch64-conda-linux-gnu/sysroot/usr/lib\"#g" "${settings_file}"

# # Add FLAGS
# perl -i -pe "s#(C compiler flags\", \")([^\"]*)\"#\1\2 ${CFLAGS}\"#g" "${settings_file}"
# perl -i -pe "s#(C\+\+ compiler flags\", \")([^\"]*)\"#\1\2 ${CXXFLAGS}\"#g" "${settings_file}"
# perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 ${LDFLAGS}\"#g" "${settings_file}"

# Remove no-pie
perl -i -pe "s#(compiler supports -no-pie\", \")[^\"]*\"#\1YES\"#g" "${settings_file}"

# Add conda lib RUNPATH for libtinfo consumers
echo "Adding conda lib RUNPATH for libtinfo consumers"
find "${GHC_INSTALLDIR}" -type f | while read -r f; do
  if file "$f" | grep -q ELF; then
    needed=$(patchelf --print-needed "$f" 2>/dev/null || true)
    if grep -q "libtinfo.so" <<< "$needed"; then
      rel=$(realpath --relative-to="$(dirname "$f")" "${PREFIX}/lib")
      current_rpath=$(patchelf --print-rpath "$f")
      new_rpath="\$ORIGIN/${rel}${current_rpath:+:$current_rpath}"
      patchelf --set-rpath "$new_rpath" "$f"
      echo -n "."
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

"${GHC_INSTALLDIR}"/bin/ghc -v -L"${BUILD_PREFIX}"/lib signal_test.hs >> "${ghc_test_log}" 2>&1 || {
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
