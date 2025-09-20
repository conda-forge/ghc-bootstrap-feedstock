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

fine_tune_linux_rpaths() {
  # Fine-tune RPATHs
  for dir in \
    "${PREFIX}"/ghc-bootstrap/bin \
    "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/bin \
    ; do

    if [[ "${dir}" == "${PREFIX}"/ghc-bootstrap/bin ]]; then
      rpath_str="../.."
    elif [[ "${dir}" == "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/bin ]]; then
      rpath_str="../../../.."
    else
      rpath_str="../../../../.."
    fi

    find "${dir}" -maxdepth 1 -type f \( -executable -o -name "*.so" \) | while read -r binary; do
      if (file "${binary}" | grep -q "ELF") >& /dev/null; then
        echo -n "["
        echo -n "$(basename "${binary}")"

        base_dir="$(dirname "${binary}")"

        needed_libs=$(readelf -d "${binary}" | grep "NEEDED" | grep -o '\[.*\]' | tr -d '[]')

        need_sysroot_lib64=0
        need_sysroot_usr_lib64=0
        need_conda_lib=0
        need_prefix_lib=0
        need_haskell_lib=0
        need_private=0
        while IFS= read -r lib; do
          [[ -z "${lib}" ]] && continue

          if select_path="x86_64-conda-linux-gnu/sysroot/lib64" \
            && [[ -f "${PREFIX}/${select_path}/${lib}" ]]; then
              (cd "${base_dir}" && ls "${rpath_str}/${select_path}/${lib}" | grep -q "${lib}") && need_sysroot_lib64=1
          elif select_path="x86_64-conda-linux-gnu/sysroot/usr/lib64" \
            && [[ -f "${PREFIX}/${select_path}/${lib}" ]]; then
              (cd "${base_dir}" && ls "${rpath_str}/${select_path}/${lib}" | grep -q "${lib}") &&  need_sysroot_usr_lib64=1
          elif select_path="x86_64-conda-linux-gnu/lib" \
            && [[ -f "${PREFIX}/${select_path}/${lib}" ]]; then
              (cd "${base_dir}" && ls "${rpath_str}/${select_path}/${lib}" | grep -q "${lib}") && need_conda_lib=1
          elif select_path="ghc-bootstrap/lib/private" \
            && [[ -f "${PREFIX}/${select_path}/${lib}" ]]; then
               (cd "${base_dir}" && ls "${rpath_str}/${select_path}/${lib}" | grep -q "${lib}") && need_private=1
          elif select_path="ghc-bootstrap/lib/ghc-${PKG_VERSION}/lib/x86_64-linux-ghc-${PKG_VERSION}" \
            && [[ -f "${PREFIX}/${select_path}/${lib}" ]]; then
              (cd "${base_dir}" && ls "${rpath_str}/${select_path}/${lib}" | grep -q "${lib}") && need_haskell_lib=1
          elif select_path="lib" \
            && [[ -f "${PREFIX}/${select_path}/${lib}" ]]; then
              (cd "${base_dir}" && ls "${rpath_str}/${select_path}/${lib}" | grep -q "${lib}") && need_prefix_lib=1
          fi

          if [[ ${need_private} == 0 ]] && [[ ${need_haskell_lib} == 0 ]] && [[ ${need_prefix_lib} == 0 ]] && [[ ${need_conda_lib} == 0 ]] && [[ ${need_sysroot_usr_lib64} == 0 ]] && [[ ${need_sysroot_lib64} == 0 ]]; then
            echo -n "DBG: NEEDED lib ${lib} - NOT FOUND"
            exit 1
          fi
        done <<< "$needed_libs"

        if (ldd "${binary}" | grep -q "libgcc_s.so.1" 2>/dev/null) && ! (readelf -d "${binary}" | grep -q "libgcc_s.so.1" 2>/dev/null); then
          need_conda_lib=1
        fi

        rpath=""
        [[ $need_sysroot_lib64 == 1 ]]     && rpath="${rpath:+$rpath:}\$ORIGIN/$rpath_str/x86_64-conda-linux-gnu/sysroot/lib64"
        [[ $need_sysroot_usr_lib64 == 1 ]] && rpath="${rpath:+$rpath:}\$ORIGIN/$rpath_str/x86_64-conda-linux-gnu/sysroot/usr/lib64"
        [[ $need_conda_lib == 1 ]]         && rpath="${rpath:+$rpath:}\$ORIGIN/$rpath_str/x86_64-conda-linux-gnu/lib"
        [[ $need_private == 1 ]]           && rpath="${rpath:+$rpath:}\$ORIGIN/$rpath_str/ghc-bootstrap/lib/private"
        [[ $need_haskell_lib == 1 ]]       && rpath="${rpath:+$rpath:}\$ORIGIN/$rpath_str/ghc-bootstrap/lib/ghc-${PKG_VERSION}/lib/x86_64-linux-ghc-${PKG_VERSION}"
        [[ $need_prefix_lib == 1 ]]        && rpath="${rpath:+$rpath:}\$ORIGIN/$rpath_str/lib"

        current_rpath=$(patchelf --print-rpath "${binary}" 2>/dev/null || echo "")

        # Removing the RPATH damages ghc-pkg and hc-iserv-dyn-ghc
        patchelf --force-rpath --set-rpath "${rpath}${current_rpath:+:$current_rpath}" "${binary}"

        if [[ "${binary}" != *".so"* ]]; then
          # Anchor interpreter to the versionned loader
          echo -n ":"
          patchelf --set-interpreter "${PREFIX}/ghc-bootstrap/lib/private/ld-2.17.so" "${binary}" && echo -n "*"
        fi
        echo -n "]"
      fi
    done
  done
}

unset build_alias
unset host_alias

# Create directories for binaries and logs
mkdir -p "${PREFIX}"/ghc-bootstrap "${SRC_DIR}"/_logs

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
    bash configure \
      --prefix="${PREFIX}"/ghc-bootstrap \
      --build="${BUILD}" \
      --host="${HOST}" \
      --enable-ghc-toolchain >& "${SRC_DIR}"/_logs/configure.log
  else
    bash configure \
      --prefix="${PREFIX}"/ghc-bootstrap \
      --enable-ghc-toolchain >& "${SRC_DIR}"/_logs/configure.log
  fi

  if [[ -f default.target.ghc-toolchain ]]; then
    cp default.target.ghc-toolchain default.target
  fi
  echo "Running make install with sysroot environment..."
  make install >& "${SRC_DIR}"/_logs/make_install.log

  # Update the installed settings file (find custom libraries, set sysroot, ...)
  update_settings

  if [[ "${target_platform}" == "linux-"* ]]; then
    # --- Mock PREFIX-installed sysroot for fine-tuning of RPATHs
    mkdir -p "${PREFIX}"/x86_64-conda-linux-gnu/{sysroot,lib}
    cp -r "${BUILD_PREFIX}"/x86_64-conda-linux-gnu/sysroot "${PREFIX}"/x86_64-conda-linux-gnu
    cp -r "${BUILD_PREFIX}"/x86_64-conda-linux-gnu/lib/libgcc_s* "${PREFIX}"/x86_64-conda-linux-gnu/lib

    # Copy ncurses 5 shared libraries to private location
    echo "Bundling ncurses 5 libraries privately"
    mkdir -p "${PREFIX}"/ghc-bootstrap/lib/private
    cp "${BUILD_PREFIX}"/lib/libncurses.so.5* "${PREFIX}"/ghc-bootstrap/lib/private/ 2>/dev/null || true
    cp "${BUILD_PREFIX}"/lib/libtinfo.so.5* "${PREFIX}"/ghc-bootstrap/lib/private/ 2>/dev/null || true
    cp "${BUILD_PREFIX}"/lib/libtinfow.so.5* "${PREFIX}"/ghc-bootstrap/lib/private/ 2>/dev/null || true

    # We seem to have an issue with using a loader different than 2.17 for ghc-pkg
    cp "${BUILD_PREFIX}"/x86_64-conda-linux-gnu/sysroot/lib64/ld-2.17.so* "${PREFIX}"/ghc-bootstrap/lib/private/ 2>/dev/null || true
    
    # Fine tune RPATHs
    fine_tune_linux_rpaths

    # Verify sysroot compatibility
    echo "Verify sysroot compatibility"
    "${PREFIX}"/ghc-bootstrap/bin/ghc-pkg recache
    printf 'import System.Posix.Signals\nmain = installHandler sigTERM Default Nothing >> putStrLn "Signal test"\n' > signal_test.hs
    "${PREFIX}"/ghc-bootstrap/bin/ghc signal_test.hs 2>/dev/null || exit 1
    if [[ -f ./signal_test ]] && ./signal_test; then
      echo "Signal test passed"
    else
      echo "Signal test failed with exit code $?"
      exit 1
    fi

    rm -rf "${PREFIX}"/x86_64-conda-linux-gnu
  fi
  
  # Reduce footprint
  rm -rf "${PREFIX}"/ghc-bootstrap/share/doc/ghc-"${PKG_VERSION}"/html
  find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*_p.a' -delete
  find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*.p_o' -delete
else
  pushd bootstrap-ghc 2>/dev/null || exit 1
    tar cf - ./* | (cd "${PREFIX}/ghc-bootstrap" || exit; tar xf -)
  popd 2>/dev/null || exit 1

  # Update the installed settings file (find custom libraries, set sysroot, ...)
  update_settings

  # Wrap windres
  perl -i -pe 's#("windres command", ")[^"]*"#\1\$topdir/../bin/windres.bat"#g' "${settings_file}"
  cp "${RECIPE_DIR}"/windres.bat "${PREFIX}"/ghc-bootstrap/bin/windres.bat

  # Reduce footprint
  rm -rf "${PREFIX}"/ghc-bootstrap/lib/lib
  rm -rf "${PREFIX}"/ghc-bootstrap/lib/doc/html
  rm -rf "${PREFIX}"/ghc-bootstrap/doc/html
  rm -rf "${PREFIX}"/ghc-bootstrap/mingw

  mkdir -p "${PREFIX}"/ghc-bootstrap/mingw/{include,lib,bin,share}
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/include/__unused__
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/lib/__unused__
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/bin/__unused__
  echo "Fake mingw directory created at ${PREFIX}/ghc-bootstrap/mingw" | cat >> "${PREFIX}"/ghc-bootstrap/mingw/share/__unused__
fi

# Clean up package cache
rm -f "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"

# Add package licenses
if [[ "${PKG_VERSION}" != "9.6.7" ]]; then
  mkdir -p "${SRC_DIR}"/license_files
  arch="-${target_platform#*-}"
  arch="${arch//-64/-x86_64}"
  arch="${arch#*-}"
  arch="${arch//arm64/aarch64}"
  os=${target_platform%%-*}
  os="${os//win/windows}"
  if [[ "${target_platform}" == "linux-"* ]] || [[ "${target_platform}" == "osx-"* ]]; then
    share="share"
  else
    share="lib"
  fi
  license_files_dir=$(find "${PREFIX}"/ghc-bootstrap/"${share}"/doc -name "${arch}-${os}-ghc-${PKG_VERSION}*" -type d | head -n 1)

  echo "License files directory: ${license_files_dir}"
  for pkg in $(find "${PREFIX}"/ghc-bootstrap/lib -name '*.conf' -print0 | env -i PATH="$PATH" xargs -0 grep -l '^license:' | sort -u); do
    pkg_name=$(basename "${pkg}" .conf)
    pkg_name=${pkg_name%-*}
    license_file=$(find "${license_files_dir}/${pkg_name}" -name LICENSE | head -n 1)
    if [[ -f "${license_file}" ]]; then
      echo -n "."
      cp "${license_file}" "${SRC_DIR}"/license_files/"${pkg_name}"-LICENSE
    fi
  done
  echo " done"
fi
