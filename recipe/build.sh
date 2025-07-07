#!/usr/bin/env bash
set -eu

# Create directories for binaries and logs
mkdir -p "${PREFIX}"/ghc-bootstrap "${SRC_DIR}"/_logs

"${RECIPE_DIR}"/building/build-"${target_platform}.sh"

mkdir -p "${PREFIX}"/bin
ln -s ${PREFIX}/ghc-bootstrap/bin/ghc "${PREFIX}"/bin/ghc-bootstrap

# Add package licenses
arch="-${target_platform#*-}"
arch="${arch//-64/-x86_64}"
arch="${arch#*-}"
arch="${arch//arm64/aarch64}"
cp "${PREFIX}/ghc-bootstrap/share/doc/${arch}-${target_platform%%-*}-ghc-${PKG_VERSION}/ghc-${PKG_VERSION}/LICENSE" "${SRC_DIR}/LICENSE"
