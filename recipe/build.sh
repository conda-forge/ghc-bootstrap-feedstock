#!/usr/bin/env bash
set -eu

update_settings() {
  if [[ "${target_platform}" == "osx-"* ]]; then
    settings_file="${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings
    iconv_aliases="-Wl,-alias,_libiconv,_iconv"
    iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_open,_iconv_open"
    iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_close,_iconv_close"

    # On occasion, the build_prefix was hardcoded
    perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${settings_file}"
    
    # Add PREFIX conda libs
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
    perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"

    # We seem to need the Apple ar/ranlib
    perl -i -pe "s#(ar command\", \").*\"#\1/usr/bin/ar\"#" "${settings_file}"
    perl -i -pe "s#(ranlib command\", \").*\"#\1/usr/bin/ranlib\"#" "${settings_file}"

  elif [[ "${target_platform}" == "linux-"* ]]; then
    settings_file="${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings

    # On occasion, the build_prefix was hardcoded
    perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${settings_file}"

    # Fixing the sysroot
    compiling="--sysroot=\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot"
    compiling="${compiling} -isystem=\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot/usr/include -D_GNU_SOURCE"

    clang_linking="--sysroot=\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot"
    clang_linking="${clang_linking} -Wl,-L\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot/lib64"
    clang_linking="${clang_linking} -Wl,-L\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot/usr/lib64"
    clang_linking="${clang_linking} -Wl,-L\\\$topdir/../../../../x86_64-conda-linux-gnu/lib"
    clang_linking="${clang_linking} -Wl,-L\\\$topdir/../../../../lib"

    ld_linking="--sysroot=\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot"
    ld_linking="${ld_linking} -L\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot/lib64"
    ld_linking="${ld_linking} -L\\\$topdir/../../../../x86_64-conda-linux-gnu/sysroot/usr/lib64"
    ld_linking="${ld_linking} -L\\\$topdir/../../../../x86_64-conda-linux-gnu/lib"
    ld_linking="${ld_linking} -L\\\$topdir/../../../../lib"

    perl -i -pe "s#(C compiler flags\", \")#\1 ${compiling} #" "${settings_file}"
    perl -i -pe "s#(C\+\+ compiler flags\", \")#\1 ${compiling} #" "${settings_file}"
    perl -i -pe "s#(Haskell CPP flags\", \")#\1 ${compiling} #" "${settings_file}"
    perl -i -pe "s#(link flags\", \")#\1 ${clang_linking} #" "${settings_file}"
    perl -i -pe "s#(ld flags\", \")#\1 ${ld_linking} #" "${settings_file}"

  else
    settings_file="${PREFIX}"/ghc-bootstrap/lib/settings

    # Reassign mingw references to conda-forge Mingw
    perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##' "${settings_file}"
    perl -i -pe 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${settings_file}"
    perl -i -pe 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${settings_file}"
    perl -i -pe 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${settings_file}"

    # Add Windows-specific compiler flags to settings
    perl -i -pe 's/("C compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
    perl -i -pe 's/("C\+\+ compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-g++.exe"/g' "${settings_file}"
    perl -i -pe 's/(CPP command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
    perl -i -pe 's/("C compiler link flags", ")([^"]*)"/\1-fuse-ld=bfd -Wl,--enable-auto-import"/g' "${settings_file}"

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
  fi
}

unset build_alias
unset host_alias

# Create directories for binaries and logs
_installdir="${PREFIX}/ghc-bootstrap"
_topdir="${_installdir}/lib/ghc-${PKG_VERSION}"
_conda_root_topdir="\\\$topdir/../../.."
_private_topdir="\\\$topdir/private"

mkdir -p "${_topdir}"/private "${SRC_DIR}"/_logs
debug_log="${SRC_DIR}"/_logs/settings_debug.log

# Install bootstrap GHC - Set conda platform moniker (we only download non-unix in separate directory)
if [[ ! -d bootstrap-ghc ]]; then
  # Correct the libc.so script to avoid trying to load /lib64/libc.so.6
  if [[ "${target_platform}" == "linux-"* ]]; then
    sysroot_libc_script="${BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot/usr/lib64/libc.so"
    perl -i -pe "s|/lib64/libc.so.6|libc.so.6|g" "$sysroot_libc_script"
    perl -i -pe "s|/usr/lib64/libc_nonshared.a|libc_nonshared.a|g" "$sysroot_libc_script"
    perl -i -pe "s|/lib64/ld-linux-x86-64.so.2|ld-2.17.so|g" "$sysroot_libc_script"
  fi

  echo "Configuring ..."

  if [[ "${target_platform}" == "linux-"* ]]; then
    # This is needed by make install to use ncurses 5
    export LD_PRELOAD=${BUILD_PREFIX}/lib/libtinfo.so
    ./configure \
      --prefix="${_installdir}" \
      --build="${BUILD}" \
      --host="${HOST}" \
      >& "${SRC_DIR}"/_logs/configure.log
  else
    ./configure --prefix="${_installdir}" >& "${SRC_DIR}"/_logs/configure.log
  fi

  echo "Running make install ..."
  make install >& "${SRC_DIR}"/_logs/make_install.log

  settings_file=$(find "${_topdir}" -name settings)
  perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##g' "${settings_file}"

  # Add system libs
  perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-L${_private_topdir} -Wl,-rpath ${_private_topdir} -Wl,-L${_conda_root_topdir}/lib -Wl,-rpath,${_conda_root_topdir}/lib -Wl,-rpath-link,${_conda_root_topdir}/lib\"#g" "${settings_file}"
  perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 -L${_private_topdir} -rpath ${_private_topdir} -L"${_conda_root_topdir}"/lib -rpath ${_conda_root_topdir}/lib -rpath-link ${_conda_root_topdir}/lib\"#g" "${settings_file}"
  
  # We enforce prioritizing conda libs and create a stub for missing symbols in libiconv
  if [[ "${target_platform}" == "osx-"* ]]; then
    ${CC} -dynamiclib -o "${_topdir}"/private/libiconv_compat.dylib "${RECIPE_DIR}"/osx_iconv_compat.c \
        -L"${PREFIX}/lib" -liconv \
        -Wl,-rpath,"${PREFIX}/lib" \
        -mmacosx-version-min=10.13 \
        -install_name "${_topdir}"/private/libiconv_compat.dylib
    perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -liconv_compat"#g' "${settings_file}"
    perl -i -pe 's#("ld link flags", ")([^"]*)"#\1\2 -liconv_compat"#g' "${settings_file}"

    # # We seem to need the Apple ar/ranlib
    # perl -i -pe "s#(ar command\", \").*\"#\1/usr/bin/ar\"#" "${settings_file}"
    # perl -i -pe "s#(ranlib command\", \").*\"#\1/usr/bin/ranlib\"#" "${settings_file}"

  fi

  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -i -pe "s#(compiler flags\", \")([^\"]*)\"#\1\2 -fno-PIE -I${_conda_root_topdir}/x86_64-conda-linux-gnu/sysroot/usr/include\"#g" "${settings_file}"
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-no-pie -Wl,-L${_conda_root_topdir}/x86_64-conda-linux-gnu/sysroot/lib64 -Wl,-L${_conda_root_topdir}/x86_64-conda-linux-gnu/sysroot/usr/lib64\"#g" "${settings_file}"
    perl -i -pe "s#(ld flags\", \")([^\"]*)\"#\1\2 -no-pie -L${_conda_root_topdir}/x86_64-conda-linux-gnu/sysroot/lib64 -L${_conda_root_topdir}/x86_64-conda-linux-gnu/sysroot/usr/lib64\"#g" "${settings_file}"

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
  fi
  
  # Verify sysroot compatibility
  echo "Verify sysroot compatibility"
  printf 'import System.Posix.Signals\nmain = installHandler sigTERM Default Nothing >> putStrLn "Signal test"\n' > signal_test.hs

  ghc_test_log="${SRC_DIR}"/_logs/ghc_signal_test.log

  # Add BUILD_PREFIX/lib to LD_LIBRARY_PATH for build-time test
  # This helps the linker find libgmp during the build-time verification
  export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${LD_LIBRARY_PATH:-}"

  "${_installdir}"/bin/ghc -v -L"${BUILD_PREFIX}"/lib -optc-fno-PIE -optl-no-pie signal_test.hs >> "${ghc_test_log}" 2>&1 || {
    cat "${ghc_test_log}"
    exit 1
  }

  if ./signal_test; then
    echo "Signal test passed"
  else
    echo "Signal test failed with exit code $?"
    exit 1
  fi
  
  # Reduce footprint
  rm -rf "${_installdir}"/share/doc/ghc-"${PKG_VERSION}"/html
  find "${_topdir}" -name '*_p.a' -delete
  find "${_topdir}" -name '*.p_o' -delete
else
  pushd bootstrap-ghc 2>/dev/null || exit 1
    tar cf - ./* | (cd "${_installdir}" || exit; tar xf -)
  popd 2>/dev/null || exit 1

  settings_file=$(find "${_topdir}" -name settings)
  
  # Reassign mingw references to conda Mingw
  perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##' "${settings_file}"
  perl -i -pe 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${settings_file}"
  perl -i -pe 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${settings_file}"
  perl -i -pe 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${settings_file}"

  # Add Windows-specific compiler flags to settings
  perl -i -pe 's/("C compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
  perl -i -pe 's/("C\+\+ compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-g++.exe"/g' "${settings_file}"
  perl -i -pe 's/(CPP command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${settings_file}"
  perl -i -pe 's/("C compiler link flags", ")([^"]*)"/\1-fuse-ld=bfd -Wl,--enable-auto-import"/g' "${settings_file}"

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
  cp "${RECIPE_DIR}"/windres.bat "${_installdir}"/bin/windres.bat

  cat "${settings_file}"

  # Reduce footprint
  rm -rf "${_installdir}"/lib/lib
  rm -rf "${_installdir}"/lib/doc/html
  rm -rf "${_installdir}"/doc/html
  rm -rf "${_installdir}"/mingw

  mkdir -p "${_installdir}"/mingw/{include,lib,bin,share}
  echo "Fake mingw directory created at ${_installdir}/mingw" | cat >> "${_installdir}"/mingw/include/__unused__
  echo "Fake mingw directory created at ${_installdir}/mingw" | cat >> "${_installdir}"/mingw/lib/__unused__
  echo "Fake mingw directory created at ${_installdir}/mingw" | cat >> "${_installdir}"/mingw/bin/__unused__
  echo "Fake mingw directory created at ${_installdir}/mingw" | cat >> "${_installdir}"/mingw/share/__unused__
fi

# Clean up package cache
rm -f "${_topdir}"/lib/package.conf.d/package.cache
rm -f "${_topdir}"/lib/package.conf.d/package.cache.lock

mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"
