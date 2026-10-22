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

# Correct sysroot redirection to system libc: strip absolute dir prefixes in the libc.so linker script
sysroot_libc_script="${BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot/usr/lib64/libc.so"
if [[ ! -f "${sysroot_libc_script}" ]]; then
  sysroot_libc_script="${BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot/usr/lib/libc.so"
fi
perl -i -pe 's#/(?:usr/)?lib(?:64)?/##g' "$sysroot_libc_script"

./configure --prefix="${GHC_INSTALLDIR}" >& "${SRC_DIR}"/_logs/configure.log

echo "Running make install ..."
make install >& "${SRC_DIR}"/_logs/make_install.log

# Make the deb10 bindist usable against the glibc 2.17 sysroot
echo "Patching glibc 2.27/2.28 symbol references"
${CC} -shared -fPIC -O2 -Wl,-soname,libghc_glibc_compat.so -o "${_privatedir}"/libghc_glibc_compat.so "${RECIPE_DIR}"/building/glibc_compat.c

# Static archives: fcntl64 and fcntl share the same ABI on aarch64
find "${GHC_INSTALLDIR}" -type f -name 'libHSbase-*.a' | while read -r f; do
  "${OBJCOPY:-${HOST}-objcopy}" --redefine-sym fcntl64=fcntl "$f"
done

# Shared objects and executables: drop the symbol version requirement
find "${GHC_INSTALLDIR}" -type f | while read -r f; do
  if file "$f" | grep -q ELF; then
    dynsyms=$(readelf --dyn-syms -W "$f" 2>/dev/null || true)
    needs_compat=0
    for sym in fcntl64 logf powf expf; do
      if grep -q "${sym}@GLIBC_2\.2[78]" <<< "$dynsyms"; then
        patchelf --clear-symbol-version "${sym}" "$f"
        if [[ "${sym}" == "fcntl64" ]]; then
          needs_compat=1
        fi
      fi
    done
    if [[ "${needs_compat}" == "1" ]]; then
      patchelf --add-needed libghc_glibc_compat.so "$f"
      rel=$(realpath --relative-to="$(dirname "$f")" "${_privatedir}")
      current_rpath=$(patchelf --print-rpath "$f")
      new_rpath="\$ORIGIN/${rel}${current_rpath:+:$current_rpath}"
      patchelf --set-rpath "$new_rpath" "$f"
    fi
  fi
done

# Verification gate: nothing newer than glibc 2.17 may remain
glibc_check_failed=0
while read -r f; do
  if file "$f" | grep -q ELF; then
    if readelf --dyn-syms -W "$f" 2>/dev/null | grep -Eq 'GLIBC_2\.(1[89]|2[0-9]|3[0-9])'; then
      echo "ERROR: $f still references glibc newer than 2.17"
      glibc_check_failed=1
    fi
  fi
done < <(find "${GHC_INSTALLDIR}" -type f)
while read -r f; do
  if readelf -s -W "$f" 2>/dev/null | grep -q 'UND fcntl64'; then
    echo "ERROR: $f still has an undefined fcntl64 symbol"
    glibc_check_failed=1
  fi
done < <(find "${GHC_INSTALLDIR}" -type f -name 'libHSbase-*.a')
if [[ "${glibc_check_failed}" != "0" ]]; then
  exit 1
fi
echo "glibc 2.17 compatibility check passed"

settings_file=$(find "${_topdir}" -name settings)
perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##g' "${settings_file}"

# Add system libs
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-L${settings_topdir}/lib -Wl,-rpath,${settings_topdir}/lib -Wl,-rpath-link,${settings_topdir}/lib -Wl,-L${settings_private} -Wl,-rpath,${settings_private} -Wl,-rpath-link,${settings_private}\"#g" "${settings_file}"
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
