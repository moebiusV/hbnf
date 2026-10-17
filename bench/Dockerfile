# The comparison environment: the existing Ada toolchain image plus the tools
# hbnf is measured against.  Built alongside it (tag hbnf-bench); the toolchain
# image is not touched.  Build args come from pins.txt (see run.sh).
FROM ada-toolchain:edge-full
ARG ANTLR_URL
ARG ANTLR_SHA
ARG PEG_URL
ARG PEG_SHA
ARG TS_VERSION
RUN apk add --no-cache bison flex nodejs openjdk21-jdk make
# byacc and bison both provide `yacc`, so apk will not install the two: unpack
# byacc's package into its own directory and call it byacc.
RUN cd /tmp && apk fetch -q byacc && mkdir -p /opt/byacc \
 && tar xzf byacc-*.apk -C /opt/byacc 2>/dev/null; \
    ln -s /opt/byacc/usr/bin/yacc /usr/local/bin/byacc && byacc -V
RUN wget -q "$ANTLR_URL" -O /opt/antlr.jar \
 && echo "$ANTLR_SHA  /opt/antlr.jar" | sha256sum -c -
RUN wget -q "$PEG_URL" -O /tmp/peg.tgz \
 && echo "$PEG_SHA  /tmp/peg.tgz" | sha256sum -c - \
 && tar xzf /tmp/peg.tgz -C /tmp && make -C /tmp/peg-* >/dev/null \
 && install /tmp/peg-*/peg /tmp/peg-*/leg /usr/local/bin
# tree-sitter-cli builds its JavaScript engine's bindings with bindgen.
RUN apk add --no-cache clang-dev
ENV LIBCLANG_PATH=/usr/lib
RUN cargo install tree-sitter-cli --version "=$TS_VERSION" --locked \
 && mkdir -p /opt/tree-sitter \
 && cp -r /root/.cargo/registry/src/*/tree-sitter-$TS_VERSION/src /opt/tree-sitter/src \
 && cp -r /root/.cargo/registry/src/*/tree-sitter-$TS_VERSION/include /opt/tree-sitter/include \
 && cp /root/.cargo/bin/tree-sitter /usr/local/bin/
