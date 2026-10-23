#!/usr/bin/env bash
set -eu

unset build_alias
unset host_alias

# Create directories for binaries and logs
mkdir -p "${PREFIX}"/ghc-bootstrap "${SRC_DIR}"/_logs

case "${target_platform}" in
  linux-aarch64) conda_triplet="aarch64-conda-linux-gnu"; ghc_arch="aarch64" ;;
  *)             conda_triplet="x86_64-conda-linux-gnu";  ghc_arch="x86_64" ;;
esac

ghc_root="${PREFIX}/ghc-bootstrap"
ghc_libdir="${ghc_root}/lib/ghc-${PKG_VERSION}"
ghc_private="${ghc_libdir}/lib/private"
# Literal $topdir (as written in the settings file) for the unix layout:
# $topdir is lib/ghc-<ver>/lib, so four levels up is ${PREFIX}
settings_topdir='\$topdir/../../../..'
settings_private='\$topdir/private'
test_ghc_flags=""

fine_tune_linux_rpaths() {
  # Fine-tune RPATHs (mirrors the 9.8.4 recipe, adapted to the lib/ghc-<ver>/lib layout)
  local dir binary base_dir needed_libs lib select_path
  local need_sysroot_lib64 need_sysroot_usr_lib64 need_conda_lib need_prefix_lib need_haskell_lib need_private
  local rpath current_rpath
  local sysroot_lib64="${PREFIX}/${conda_triplet}/sysroot/lib64"
  local sysroot_usr_lib64="${PREFIX}/${conda_triplet}/sysroot/usr/lib64"
  local conda_lib="${PREFIX}/${conda_triplet}/lib"
  local haskell_dir="${ghc_libdir}/lib/${ghc_arch}-linux-ghc-${PKG_VERSION}"

  # Every $ORIGIN-relative entry is computed per file (the 9.12 layout is not the 9.8 one)
  for dir in "${ghc_root}/bin" "${ghc_libdir}/bin" "${ghc_libdir}/lib/bin"; do
    [[ -d "${dir}" ]] || continue

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

          if [[ -f "${sysroot_lib64}/${lib}" ]]; then
            need_sysroot_lib64=1
          elif [[ -f "${sysroot_usr_lib64}/${lib}" ]]; then
            need_sysroot_usr_lib64=1
          elif [[ -f "${conda_lib}/${lib}" ]]; then
            need_conda_lib=1
          elif [[ -f "${ghc_private}/${lib}" ]]; then
            need_private=1
          elif [[ -f "${haskell_dir}/${lib}" ]]; then
            need_haskell_lib=1
          elif [[ -f "${PREFIX}/lib/${lib}" ]]; then
            need_prefix_lib=1
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
        [[ $need_sysroot_lib64 == 1 ]]     && rpath="${rpath:+$rpath:}\$ORIGIN/$(realpath -m --relative-to="${base_dir}" "${sysroot_lib64}")"
        [[ $need_sysroot_usr_lib64 == 1 ]] && rpath="${rpath:+$rpath:}\$ORIGIN/$(realpath -m --relative-to="${base_dir}" "${sysroot_usr_lib64}")"
        [[ $need_conda_lib == 1 ]]         && rpath="${rpath:+$rpath:}\$ORIGIN/$(realpath -m --relative-to="${base_dir}" "${conda_lib}")"
        [[ $need_private == 1 ]]           && rpath="${rpath:+$rpath:}\$ORIGIN/$(realpath -m --relative-to="${base_dir}" "${ghc_private}")"
        [[ $need_haskell_lib == 1 ]]       && rpath="${rpath:+$rpath:}\$ORIGIN/$(realpath -m --relative-to="${base_dir}" "${haskell_dir}")"
        [[ $need_prefix_lib == 1 ]]        && rpath="${rpath:+$rpath:}\$ORIGIN/$(realpath -m --relative-to="${base_dir}" "${PREFIX}/lib")"

        current_rpath=$(patchelf --print-rpath "${binary}" 2>/dev/null || echo "")

        # Removing the RPATH damages ghc-pkg and hc-iserv-dyn-ghc
        patchelf --force-rpath --set-rpath "${rpath}${current_rpath:+:$current_rpath}" "${binary}"

        if [[ "${binary}" != *".so"* ]]; then
          # Anchor interpreter to the versioned loader
          echo -n ":"
          patchelf --set-interpreter "${ghc_private}/ld-2.17.so" "${binary}" && echo -n "*"
        fi
        echo -n "]"
      fi
    done
  done
}

# Install bootstrap GHC - Set conda platform moniker (we only download non-unix in separate directory)
if [[ ! -d bootstrap-ghc ]]; then
  if [[ "${target_platform}" == "linux-"* ]]; then
    mkdir -p "${ghc_private}"

    # Correct sysroot redirection to system libc: strip absolute dir prefixes in the libc.so linker script
    sysroot_libc_script="${BUILD_PREFIX}/${conda_triplet}/sysroot/usr/lib64/libc.so"
    if [[ ! -f "${sysroot_libc_script}" ]]; then
      sysroot_libc_script="${BUILD_PREFIX}/${conda_triplet}/sysroot/usr/lib/libc.so"
    fi
    if [[ "${ghc_arch}" == "x86_64" ]]; then
      perl -i -pe "s|/lib64/libc.so.6|libc.so.6|g" "${sysroot_libc_script}"
      perl -i -pe "s|/usr/lib64/libc_nonshared.a|libc_nonshared.a|g" "${sysroot_libc_script}"
      perl -i -pe "s|/lib64/ld-linux-x86-64.so.2|ld-2.17.so|g" "${sysroot_libc_script}"
      # This is needed by make install to use ncurses 5
      export LD_PRELOAD="${BUILD_PREFIX}/lib/libtinfo.so"
    else
      perl -i -pe 's#/(?:usr/)?lib(?:64)?/##g' "${sysroot_libc_script}"
    fi
  fi

  echo "Configuring ..."
  if [[ "${target_platform}" == "linux-"* ]]; then
    bash configure \
      --prefix="${ghc_root}" \
      --build="${BUILD}" \
      --host="${HOST}" \
      --enable-ghc-toolchain >& "${SRC_DIR}"/_logs/configure.log
  else
    bash configure \
      --prefix="${ghc_root}" \
      --enable-ghc-toolchain >& "${SRC_DIR}"/_logs/configure.log
  fi

  if [[ -f default.target.ghc-toolchain ]]; then
    cp default.target.ghc-toolchain default.target
  fi
  echo "Running make install ..."
  make install >& "${SRC_DIR}"/_logs/make_install.log
  unset LD_PRELOAD

  if [[ "${target_platform}" == "linux-aarch64" ]]; then
    # Make the deb10 bindist usable against the glibc 2.17 sysroot
    echo "Patching glibc 2.27/2.28 symbol references"
    ${CC} -shared -fPIC -O2 -Wl,-soname,libghc_glibc_compat.so -o "${ghc_private}"/libghc_glibc_compat.so "${RECIPE_DIR}"/glibc_compat.c

    # Static archives: fcntl64 and fcntl share the same ABI on aarch64
    find "${ghc_root}" -type f -name 'libHSbase-*.a' | while read -r f; do
      "${OBJCOPY:-${HOST}-objcopy}" --redefine-sym fcntl64=fcntl "$f"
    done

    # Shared objects and executables: drop the symbol version requirement
    find "${ghc_root}" -type f | while read -r f; do
      if file "$f" | grep -q ELF; then
        dynsyms=$(readelf --dyn-syms -W "$f" 2>/dev/null || true)
        needs_compat=0
        for sym in fcntl64 statx memfd_create logf powf expf; do
          if grep -Eq "${sym}@GLIBC_2\.(2[0-9]|1[89])" <<< "$dynsyms"; then
            patchelf --clear-symbol-version "${sym}" "$f"
            case "${sym}" in
              fcntl64|statx|memfd_create) needs_compat=1 ;;
            esac
          fi
        done
        if [[ "${needs_compat}" == "1" ]]; then
          patchelf --add-needed libghc_glibc_compat.so "$f"
          rel=$(realpath --relative-to="$(dirname "$f")" "${ghc_private}")
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
          readelf --dyn-syms -W "$f" 2>/dev/null | grep -E 'GLIBC_2\.(1[89]|2[0-9]|3[0-9])' || true
          glibc_check_failed=1
        fi
      fi
    done < <(find "${ghc_root}" -type f)
    while read -r f; do
      if readelf -s -W "$f" 2>/dev/null | grep -q 'UND fcntl64'; then
        echo "ERROR: $f still has an undefined fcntl64 symbol"
        glibc_check_failed=1
      fi
    done < <(find "${ghc_root}" -type f -name 'libHSbase-*.a')
    if [[ "${glibc_check_failed}" != "0" ]]; then
      exit 1
    fi
    echo "glibc 2.17 compatibility check passed"
  fi

  settings_file="${ghc_libdir}"/lib/settings
  perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${settings_file}"
  # Add system libs
  perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib"#g' "${settings_file}"

  if [[ "${target_platform}" == "linux-"* ]]; then
    # Remove no-pie
    perl -i -pe "s#(compiler supports -no-pie\", \")[^\"]*\"#\1YES\"#g" "${settings_file}"
  fi

  if [[ "${target_platform}" == "linux-64" ]]; then
    # Fixing the sysroot (mirrors the 9.8.4 recipe)
    sysroot_rel="${settings_topdir}/x86_64-conda-linux-gnu/sysroot"
    compiling="--sysroot=${sysroot_rel} -isystem=${sysroot_rel}/usr/include -D_GNU_SOURCE"

    clang_linking="--sysroot=${sysroot_rel}"
    clang_linking="${clang_linking} -Wl,-L${sysroot_rel}/lib64"
    clang_linking="${clang_linking} -Wl,-L${sysroot_rel}/usr/lib64"
    clang_linking="${clang_linking} -Wl,-L${settings_topdir}/x86_64-conda-linux-gnu/lib"
    clang_linking="${clang_linking} -Wl,-L${settings_topdir}/lib"

    ld_linking="--sysroot=${sysroot_rel}"
    ld_linking="${ld_linking} -L${sysroot_rel}/lib64"
    ld_linking="${ld_linking} -L${sysroot_rel}/usr/lib64"
    ld_linking="${ld_linking} -L${settings_topdir}/x86_64-conda-linux-gnu/lib"
    ld_linking="${ld_linking} -L${settings_topdir}/lib"

    perl -i -pe "s#(C compiler flags\", \")#\1 ${compiling} #" "${settings_file}"
    perl -i -pe "s#(C\+\+ compiler flags\", \")#\1 ${compiling} #" "${settings_file}"
    perl -i -pe "s#(Haskell CPP flags\", \")#\1 ${compiling} #" "${settings_file}"
    perl -i -pe "s#(link flags\", \")#\1 ${clang_linking} #" "${settings_file}"
    perl -i -pe "s#(ld flags\", \")#\1 ${ld_linking} #" "${settings_file}"
  fi

  if [[ "${target_platform}" == "linux-aarch64" ]]; then
    # Private dir and sysroot paths: comma form only, nothing goes in "ld flags"
    perl -i -pe "s#(C compiler flags\", \")([^\"]*)\"#\1\2 -I${settings_topdir}/${conda_triplet}/sysroot/usr/include\"#g" "${settings_file}"
    perl -i -pe "s#(C\+\+ compiler flags\", \")([^\"]*)\"#\1\2 -I${settings_topdir}/${conda_triplet}/sysroot/usr/include\"#g" "${settings_file}"
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-rpath-link,${settings_topdir}/lib -Wl,-L${settings_private} -Wl,-rpath,${settings_private} -Wl,-rpath-link,${settings_private} -L${settings_private} -lghc_glibc_compat\"#g" "${settings_file}"
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)\"#\1\2 -Wl,-L${settings_topdir}/${conda_triplet}/sysroot/lib64 -Wl,-L${settings_topdir}/${conda_triplet}/sysroot/usr/lib64 -Wl,-L${settings_topdir}/${conda_triplet}/sysroot/lib -Wl,-L${settings_topdir}/${conda_triplet}/sysroot/usr/lib\"#g" "${settings_file}"
  fi

  if [[ "${target_platform}" == "osx-"* ]]; then
    perl -i -pe 's#("C compiler flags", ")([^"]*)"#\1\2 -mmacosx-version-min=11.0"#g' "${settings_file}"
    # conda libiconv exports _libiconv* names: alias them to _iconv* (mirrors main)
    iconv_aliases="-Wl,-alias,_libiconv,_iconv -Wl,-alias,_libiconv_open,_iconv_open -Wl,-alias,_libiconv_close,_iconv_close"
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -mmacosx-version-min=11.0 -L${settings_topdir}/lib -Wl,-rpath,${settings_topdir}/lib ${iconv_aliases} -liconv#" "${settings_file}"
    perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L${settings_topdir}/lib ${iconv_aliases} -liconv#" "${settings_file}"
    # Use the Apple ar/ranlib
    perl -i -pe 's#(ar command", ").*"#\1/usr/bin/ar"#' "${settings_file}"
    perl -i -pe 's#(ranlib command", ").*"#\1/usr/bin/ranlib"#' "${settings_file}"
  fi

  # We enforce prioritizing the sysroot for self-consistently finding the libraries
  if [[ "${target_platform}" == "linux-64" ]]; then
    echo "Bundling ncurses 5 libraries privately"
    # cp -L: dereference symlinks so real files land in the private dir
    for n in ncurses tinfo tinfow; do
      src=$(ls "${BUILD_PREFIX}"/lib/lib${n}.so.5* 2>/dev/null | head -n 1 || true)
      if [[ -z "${src}" ]]; then
        echo "ERROR: lib${n}.so.5 not found in ${BUILD_PREFIX}/lib"
        ls "${BUILD_PREFIX}"/lib | grep -E 'ncurses|tinfo' || true
        exit 1
      fi
      cp -L "${src}" "${ghc_private}/lib${n}.so.5"
    done

    # Loader 2.17 matching the sysroot libc (ghc-pkg breaks with any other loader)
    cp -L "${BUILD_PREFIX}/${conda_triplet}"/sysroot/lib64/ld-2.17.so "${ghc_private}/ld-2.17.so"

    # Mock PREFIX-installed sysroot for fine-tuning of RPATHs
    mkdir -p "${PREFIX}/${conda_triplet}"/{sysroot,lib}
    cp -r "${BUILD_PREFIX}/${conda_triplet}"/sysroot "${PREFIX}/${conda_triplet}"
    # clang toolchain: libgcc_s comes from conda's libgcc in BUILD_PREFIX/lib, not the gcc triplet dir
    if ls "${BUILD_PREFIX}"/lib/libgcc_s.so* >/dev/null 2>&1; then
      cp -L "${BUILD_PREFIX}"/lib/libgcc_s.so* "${PREFIX}"/x86_64-conda-linux-gnu/lib/
    elif ls "${BUILD_PREFIX}"/x86_64-conda-linux-gnu/lib/libgcc_s* >/dev/null 2>&1; then
      cp -L "${BUILD_PREFIX}"/x86_64-conda-linux-gnu/lib/libgcc_s* "${PREFIX}"/x86_64-conda-linux-gnu/lib/
    else
      echo "WARNING: libgcc_s not found in BUILD_PREFIX; skipping mock copy"
    fi

    fine_tune_linux_rpaths
    echo " done"

    "${ghc_root}"/bin/ghc-pkg recache
  fi

  if [[ "${target_platform}" == "linux-aarch64" ]]; then
    # Add conda lib RUNPATH for libtinfo consumers
    echo "Adding conda lib RUNPATH for libtinfo consumers"
    find "${ghc_root}" -type f | while read -r f; do
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

    # Help the build-time verification find libgmp
    export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
    test_ghc_flags="-L${BUILD_PREFIX}/lib"
  fi

  # Verify sysroot compatibility
  printf 'import System.Posix.Signals\nmain = installHandler sigTERM Default Nothing >> putStrLn "Signal test"\n' > signal_test.hs
  if [[ "${target_platform}" == "linux-aarch64" ]]; then
    # We need to map the PREFIX environment sysroot
    mkdir -p "${PREFIX}/${conda_triplet}" && ln -s "${BUILD_PREFIX}/${conda_triplet}"/sysroot "${PREFIX}/${conda_triplet}"/sysroot
  fi
  ghc_test_log="${SRC_DIR}"/_logs/ghc_signal_test.log
  "${ghc_root}"/bin/ghc -v ${test_ghc_flags} signal_test.hs >> "${ghc_test_log}" 2>&1 || {
    cat "${ghc_test_log}"
    exit 1
  }
  if ./signal_test; then
    echo "Signal test passed"
  else
    echo "Signal test failed with exit code $?"
    exit 1
  fi
  if [[ "${target_platform}" == "linux-"* ]]; then
    rm -rf "${PREFIX:?}/${conda_triplet}"
  fi

  # Reduce footprint
  rm -rf "${ghc_root}"/share/doc/ghc-"${PKG_VERSION}"/html
  find "${ghc_libdir}" -name '*_p.a' -delete
  find "${ghc_libdir}" -name '*.p_o' -delete
else
  pushd bootstrap-ghc 2>/dev/null || exit 1
    tar cf - ./* | (cd "${PREFIX}/ghc-bootstrap" || exit; tar xf -)
  popd 2>/dev/null || exit 1

  settings_file="${PREFIX}"/ghc-bootstrap/lib/settings

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

  cat "${settings_file}"

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
