# export CC="x86_64-conda_cos6-linux-gnu-cc"
# export LD="x86_64-conda_cos6-linux-gnu-ld"
# export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH:$BUILD_PREFIX/lib"
./configure --prefix=$PREFIX
make install
