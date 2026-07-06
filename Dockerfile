# Build stage: assemble the sub-Knots from source instead of downloading a
# signed release. Recipe = Knots 29.3 release + garbageman + Kyle's RDTS PRs,
# merged in order. These merge cleanly (verified), so the resulting tree equals
# the assemble-knots.pl output.
FROM debian:bookworm-slim AS builder
ARG VERSION
ARG PATH_VERSION
ARG TARGETPLATFORM
WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates cmake build-essential pkgconf python3 \
        libevent-dev libboost-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Sub-Knots recipe (edit these lines to build a different variant)
ENV KNOTS_BASE=v29.3.knots20260508
ENV GM_REPO=https://github.com/chrisguida/bitcoin.git
ENV GM_BRANCH=garbageman-29.3
ENV KNOTS_PRS="319 320 323 324"

RUN git clone https://github.com/bitcoinknots/bitcoin.git . \
 && git -c advice.detachedHead=false checkout "${KNOTS_BASE}" \
 && git config user.email build@local && git config user.name build \
 && git fetch --no-tags "${GM_REPO}" "${GM_BRANCH}" && git merge --no-edit FETCH_HEAD \
 && for pr in ${KNOTS_PRS}; do \
      git fetch --no-tags https://github.com/bitcoinknots/bitcoin.git "pull/$pr/head" \
      && git merge --no-edit FETCH_HEAD ; \
    done

RUN cmake -B build -D RDTS_CONSENT=IMPLICIT -D BUILD_GUI=OFF -D BUILD_TESTS=OFF \
        -D BUILD_BENCH=OFF -D BUILD_FUZZ_BINARY=OFF \
 && cmake --build build -j"$(nproc)" --target bitcoind bitcoin-cli \
 && strip build/bin/bitcoind build/bin/bitcoin-cli \
 && mkdir -p /build/bin && cp build/bin/bitcoind build/bin/bitcoin-cli /build/bin/

# Final image
FROM debian:bookworm-slim
ENV BITCOIN_DATA=/root/.bitcoin
ENV BITCOIN_PREFIX=/opt/bitcoin
ENV PATH=${BITCOIN_PREFIX}/bin:$PATH
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl e2fsprogs jq \
        libevent-core-2.1-7 libevent-extra-2.1-7 libevent-pthreads-2.1-7 libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/bin/bitcoind ${BITCOIN_PREFIX}/bin/
COPY --from=builder /build/bin/bitcoin-cli ${BITCOIN_PREFIX}/bin/
ARG ARCH
EXPOSE 8332 8333
