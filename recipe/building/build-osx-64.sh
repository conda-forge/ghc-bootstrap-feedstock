#!/usr/bin/env bash
set -eu

unset build_alias
unset host_alias

# Create directories for binaries and logs
_topdir="${GHC_INSTALLDIR}/lib/ghc-${PKG_VERSION}/lib"
settings_topdir="\\\$topdir/../../../.."

_privatedir="${_topdir}/private"
settings_private="\\\$topdir/private"
mkdir -p "${_privatedir}"

./configure --prefix="${GHC_INSTALLDIR}" >& "${SRC_DIR}"/_logs/configure.log

echo "Running make install ..."
make install >& "${SRC_DIR}"/_logs/make_install.log

settings_file=$(find "${_topdir}" -name settings)
perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##g' "${settings_file}"

# Add system libs
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-L${settings_private} -Wl,-rpath ${settings_private} -Wl,-L${settings_topdir}/lib -Wl,-rpath,${settings_topdir}/lib\"#g" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 -L${settings_private} -rpath ${settings_private} -L"${settings_topdir}"/lib -rpath ${settings_topdir}/lib\"#g" "${settings_file}"

# # Add FLAGS
# perl -i -pe "s#(C compiler flags\", \")([^\"]*)\"#\1\2 ${CFLAGS}\"#g" "${settings_file}"
# perl -i -pe "s#(C\+\+ compiler flags\", \")([^\"]*)\"#\1\2 ${CXXFLAGS}\"#g" "${settings_file}"
# perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 ${LDFLAGS}\"#g" "${settings_file}"

# We enforce prioritizing conda libs and create a stub for missing symbols in libiconv
${CC} -dynamiclib -o "${_topdir}"/private/libiconv_compat.dylib "${RECIPE_DIR}"/building/osx_iconv_compat.c \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -mmacosx-version-min=10.13 \
    -install_name "${_topdir}"/private/libiconv_compat.dylib
perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -liconv_compat"#g' "${settings_file}"
perl -i -pe 's#("ld link flags", ")([^"]*)"#\1\2 -liconv_compat"#g' "${settings_file}"

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
