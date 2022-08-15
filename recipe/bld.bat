export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH:$BUILD_PREFIX/lib"
./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
make install
