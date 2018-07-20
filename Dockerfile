from ubuntu:16.04

COPY . /root/dashc

RUN apt-get update && \
BUILD_DEP="libffi-dev git opam m4 pkg-config libssl-dev" && \
apt-get install -yq libssl1.0.0 libffi6 $BUILD_DEP && \
cd /root/dashc &&\
./configure && \
eval $(opam config env) && \
opam install -y async_ssl && \
./configure && \
make && \
cp /root/dashc/dashc.exe / && \
rm -rf /root && \
apt-get remove -yq $BUILD_DEP && \
apt-get clean && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/dashc.exe"]
