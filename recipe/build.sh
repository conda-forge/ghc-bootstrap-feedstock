#!/usr/bin/env bash
set -eu

unset build_alias
unset host_alias

# Create directories for binaries and logs
mkdir -p "${PREFIX}"/ghc-bootstrap "${SRC_DIR}"/_logs

# Install bootstrap GHC - Set conda platform moniker (we only download non-unix in separate directory)
if [[ ! -d bootstrap-ghc ]]; then
  if [[ "${target_platform}" == "linux-"* ]]; then
    bash configure \
      --prefix="${PREFIX}"/ghc-bootstrap \
      --build="${BUILD}" \
      --host="${HOST}" \
      --enable-ghc-toolchain
  else
    bash configure \
      --prefix="${PREFIX}"/ghc-bootstrap \
      --enable-ghc-toolchain
  fi

  if [[ -f default.target.ghc-toolchain ]]; then
    cp default.target.ghc-toolchain default.target
  fi
  make install

  settings_file="${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings
  perl -i -pe 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${settings_file}"
  perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -L\$topdir/../../../../lib"#g' "${settings_file}"

  if [[ "${target_platform}" == "osx-"* ]]; then
    perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -Wl,-rpath,@loader_path/../lib"#g' "${settings_file}"
  fi

  ## RPATH to conda's lib last
  perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -Wl,-rpath,\$topdir/../../../../lib"#g' "${settings_file}"

  if [[ "${target_platform}" == "linux-"* ]]; then
    # We enforce prioritizing the sysroot for full sysroot complianc
    find ${PREFIX}/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -type f -executable | while read -r binary; do
      if file "$binary" | grep -q "ELF"; then
        echo "Patching binary: $binary"
        current_rpath=$(patchelf --print-rpath "$binary" 2>/dev/null || echo "")
        sysroot_lib64="\$ORIGIN/../../../../x86_64-conda-linux-gnu/sysroot/lib64"
        sysroot_usr_lib64="\$ORIGIN/../../../../x86_64-conda-linux-gnu/sysroot/usr/lib64"
        conda_lib="\$ORIGIN/../../../../lib"
        if [[ -n "$current_rpath" ]]; then
          new_rpath="${sysroot_lib64}:${sysroot_usr_lib64}:${conda_lib}:${current_rpath}"
        else
          new_rpath="${sysroot_lib64}:${sysroot_usr_lib64}:${conda_lib}"
        fi
        patchelf --set-rpath "$new_rpath" "$binary" 2>/dev/null && echo "Updated rpath for $binary"
      fi
    done

  fi

  # Verify sysroot compatibility
  printf 'import System.Posix.Signals\nmain = installHandler sigTERM Default Nothing >> putStrLn "Signal test"\n' > signal_test.hs
  ${PREFIX}/ghc-bootstrap/bin/ghc -v signal_test.hs && ./signal_test

  # Reduce footprint
  rm -rf "${PREFIX}"/ghc-bootstrap/share/doc/ghc-"${PKG_VERSION}"/html
  find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*_p.a' -delete
  find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*.p_o' -delete
else
  pushd bootstrap-ghc 2>/dev/null || exit 1
    tar cf - ./* | (cd "${PREFIX}/ghc-bootstrap" || exit; tar xf -)
  popd 2>/dev/null || exit 1

  perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${PREFIX}"/ghc-bootstrap/lib/settings

  # Add Windows-specific compiler flags to settings
  perl -i -pe 's/("C compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's/("C\+\+ compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-g++.exe"/g' "${PREFIX}"/ghc-bootstrap/lib/settings

  # Remove clang compiler options
  perl -i -pe 's/--rtlib=compiler-rt//g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's/-Qunused-arguments//g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's/--target=([^ ]*)//g' "${PREFIX}"/ghc-bootstrap/lib/settings

  cat "${PREFIX}"/ghc-bootstrap/lib/settings

  # Wrap windres
  perl -i -pe 's#("windres command", ")[^"]*"#\1\$topdir/../bin/windres.bat"#g' "${PREFIX}"/ghc-bootstrap/lib/settings
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
license_files_dir=$(find "${PREFIX}"/ghc-bootstrap/"${share}"/doc -name "${arch}-${os}-ghc-${PKG_VERSION}-*" -type d | head -n 1)

echo "License files directory: ${license_files_dir}"
for pkg in $(find "${PREFIX}"/ghc-bootstrap/lib -name '*.conf' -print0 | env -i PATH="$PATH" xargs -0 grep -l '^license:' | sort -u); do
  echo "Processing package: ${pkg}"
  pkg_name=$(basename "${pkg}" .conf)
  pkg_name=${pkg_name%-*}
  license_file=$(find "${license_files_dir}/${pkg_name}" -name LICENSE | head -n 1)
  if [[ -f "${license_file}" ]]; then
    echo "Found license file for ${pkg_name}: ${license_file}"
    cp "${license_file}" "${SRC_DIR}"/license_files/"${pkg_name}"-LICENSE
  fi
done
