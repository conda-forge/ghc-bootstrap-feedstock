#!/usr/bin/env bash
set -eu

unset build_alias
unset host_alias

# Create directories for binaries and logs
mkdir -p "${PREFIX}"/ghc-bootstrap "${SRC_DIR}"/_logs

# Install bootstrap GHC - Set conda platform moniker
if [[ ! -d bootstrap-ghc ]]; then
  bash configure \
    --prefix="${PREFIX}"/ghc-bootstrap \
    --enable-ghc-toolchain
  cp default.target.ghc-toolchain default.target
  make install
  perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings

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
  perl -i -pe 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#x86_64-unknown-mingw32#x86_64-w64-mingw32#g' "${PREFIX}"/ghc-bootstrap/lib/settings

  # Add Windows-specific compiler flags to settings
  perl -i -pe 's/("C compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-gcc.exe"/g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's/("C\+\+ compiler command", ")([^"]*)"/\1x86_64-w64-mingw32-g++.exe"/g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's/--rtlib=compiler-rt//g; s/-Qunused-arguments//g' "${PREFIX}"/ghc-bootstrap/lib/settings
  perl -i -pe 's#("windres command", ")[^"]*"#\1\$topdir/../bin/windres.bat"#g' "${PREFIX}"/ghc-bootstrap/lib/settings
  # perl -i -pe 's#-fstack-check##g' "${PREFIX}"/ghc-bootstrap/lib/settings

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
# for pkg in $(find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*.conf' -exec grep -l '^license:' {} \; | sort -u); do
for pkg in $(find "${PREFIX}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}" -name '*.conf' -print0 | xargs -0 -I {} grep -l '^license:' {} | sort -u); do
  echo "Processing package: ${pkg}"
  pkg_name=$(basename "${pkg}" .conf)
  pkg_name=${pkg_name%-*}
  license_file=$(find "${license_files_dir}/${pkg_name}" -name LICENSE | head -n 1)
  if [[ -f "${license_file}" ]]; then
    echo "Found license file for ${pkg_name}: ${license_file}"
    cp "${license_file}" "${SRC_DIR}"/license_files/"${pkg_name}"-LICENSE
  fi
done
