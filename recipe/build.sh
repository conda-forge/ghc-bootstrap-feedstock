export CC="x86_64-conda_cos6-linux-gnu-cc"
export LD="x86_64-conda_cos6-linux-gnu-cc"
export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
perl -pi -e 's/("C compiler link flags", " "),/("C compiler link flags", " -L$PREFIX\/lib"),/g' settings
cat $PREFIX/lib/ghc-8.2.2/settings
make install
