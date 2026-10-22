# Global build args — defined before any FROM so they are available in all stages
ARG DEBIAN_BASE_IMAGE=debian:13-slim@sha256:b6e2a152f22a40ff69d92cb397223c906017e1391a73c952b588e51af8883bf8
ARG DISTROLESS_IMAGE=gcr.io/distroless/base-debian13@sha256:f2df8702d4dcc45ce76df6cbc14ad1975fcf88a04bd0e8947b6194264f9ab75e
ARG DNS_HEALTHCHECK_IMAGE=registry.gitlab.com/joern_schonhoff/dns-healthcheck:v0.1.6@sha256:7c0e312b18f9c00a0a21e69b8dccb7fb91a1aa118fd1ec253375733d5e345da5

# Pull distroless into named stages so they can be referenced in COPY --from
# (ARG substitution is not supported in COPY --from, only in FROM)
FROM ${DISTROLESS_IMAGE} AS distroless
FROM ${DNS_HEALTHCHECK_IMAGE} AS dns-healthcheck

# Stage 1: Compile pdns-recursor
FROM ${DEBIAN_BASE_IMAGE} AS builder
ARG PDNS_RECURSOR_VERSION
RUN test -n "${PDNS_RECURSOR_VERSION}" || { echo "PDNS_RECURSOR_VERSION build-arg is required"; exit 1; }

# Install build dependencies
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
        ca-certificates \
        clang-19 \
        curl \
        g++ \
        gcc \
        gnupg \
        libboost-context-dev \
        libboost-dev \
        libboost-filesystem-dev \
        libboost-serialization-dev \
        libboost-system-dev \
        libboost-test-dev \
        libboost-thread-dev \
		libcap2-bin \
        libcurl4-openssl-dev \
        libfstrm-dev \
        libluajit-*-dev \
        libsodium-dev \
        libssl-dev \
        lua5.4 \
        luajit \
        make \
        pkg-config \
        python3 \
        xz-utils \
	&& apt-get clean

# Official PowerDNS signing keys — keyblock from https://doc.powerdns.com/powerdns-keyblock.asc
COPY powerdns-keyblock.asc /tmp/powerdns-keyblock.asc

WORKDIR /src

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && for link in /root/.cargo/bin/*; do ln -s "$link" /usr/local/bin/; done

# Verify tarball against detached PGP signature before extracting
RUN gpg --import /tmp/powerdns-keyblock.asc \
    && curl -sSL https://downloads.powerdns.com/releases/pdns-recursor-${PDNS_RECURSOR_VERSION}.tar.xz -o pdns-recursor-${PDNS_RECURSOR_VERSION}.tar.xz \
    && curl -sSL https://downloads.powerdns.com/releases/pdns-recursor-${PDNS_RECURSOR_VERSION}.tar.xz.asc -o pdns-recursor-${PDNS_RECURSOR_VERSION}.tar.xz.asc \
    && gpg --verify pdns-recursor-${PDNS_RECURSOR_VERSION}.tar.xz.asc pdns-recursor-${PDNS_RECURSOR_VERSION}.tar.xz \
    && tar xf pdns-recursor-${PDNS_RECURSOR_VERSION}.tar.xz --strip-components=1

RUN ./configure \
        --disable-systemd \
        --enable-dns-over-tls \
        --enable-dnstap \
        --enable-nod \
        --enable-unit-tests \
        --infodir=/usr/share/info \
        --libdir=/usr/lib/pdns \
        --localstatedir=/var \
        --mandir=/usr/share/man \
        --prefix=/usr \
        --sysconfdir=/etc/pdns \
        --with-libcrypto=/usr \
        --with-libsodium \
        --with-libssl \
        --with-lua=luajit \
    && make -j2 \
    && DESTDIR=/build make install \
    && strip /build/usr/bin/* /build/usr/sbin/*

RUN setcap 'cap_net_bind_service=+ep'  /build/usr/sbin/pdns_recursor

# Prepare runtime tree
RUN mkdir -p /runtime \
	&& cp -a /build/* /runtime/

# Collect shared libraries via ldd; rewrite /lib/ -> /usr/lib/ because
# distroless has /lib as a symlink to usr/lib on Debian 13
RUN find /build -type f -executable -exec sh -c \
	'for f; do ldd "$f" 2>/dev/null | awk "/=>/ {print \$3}" ; done' sh {} + \
	| sort -u | grep -E "^/" \
	| while read src; do \
	    dest=$(echo "$src" | sed 's|^/lib/|/usr/lib/|'); \
	    mkdir -p "/runtime$(dirname $dest)"; \
	    cp -L "$src" "/runtime$dest"; \
	  done

## Preserve distroless base entries (root, nobody, nonroot) then append pdns
RUN mkdir -p /runtime/etc
COPY --from=distroless /etc/passwd /runtime/etc/passwd
COPY --from=distroless /etc/group /runtime/etc/group
RUN echo "pdns:x:1000:1000:PowerDNS user:/var/lib/pdns:/sbin/nologin" >> /runtime/etc/passwd \
    && echo "pdns:x:1000:" >> /runtime/etc/group

# Strip debug symbols from collected shared libraries to reduce image size
RUN find /runtime -type f \( -name "*.so" -o -name "*.so.*" \) \
    -exec strip --strip-unneeded {} + 2>/dev/null || true

# Ensure runtime dirs exist and are owned by pdns
RUN mkdir -p \
        /runtime/etc/pdns \
        /runtime/var/run/pdns-recursor \
        /runtime/var/log/pdns-recursor \
        /runtime/var/lib/pdns-recursor \
    && chown -R 1000:1000 \
        /runtime/etc/pdns \
        /runtime/var/run/pdns-recursor \
        /runtime/var/log/pdns-recursor \
        /runtime/var/lib/pdns-recursor \
    && chmod 0755 /runtime/etc/pdns

# Cleanup /runtime of unnecessary files
RUN rm -rf \
		/runtime/usr/share/doc \
		/runtime/usr/share/man

FROM ${DISTROLESS_IMAGE} AS runtime

ARG PDNS_RECURSOR_VERSION

# SPDX identifier required by the OCI image-spec for org.opencontainers.image.licenses
LABEL \
	org.opencontainers.image.authors="Joern Schonhoff <joerns92@live.com>" \
    org.opencontainers.image.description="PowerDNS Recursor ${PDNS_RECURSOR_VERSION} based on Distroless Debian 13" \
    org.opencontainers.image.licenses="GPL-2.0-only" \
    org.opencontainers.image.source="https://gitlab.com/joern_schonhoff/pdns-rec-distroless" \
    org.opencontainers.image.title="pdns-rec-distroless" \
    org.opencontainers.image.url="https://gitlab.com/joern_schonhoff/pdns-rec-distroless" \
    org.opencontainers.image.version="${PDNS_RECURSOR_VERSION}"
	# org.opencontainers.image.created="FILLED BY BUILD SYSTEM"
	# org.opencontainers.image.revision="FILLED BY BUILD SYSTEM"

# Copy runtime fs from builder
COPY --from=builder /runtime/ /
COPY --from=dns-healthcheck /dns-healthcheck /usr/bin/dns-healthcheck

ENV TERM=dumb

# Expose DNS ports
EXPOSE 53/tcp 53/udp

# Run as pdns user created in /etc/passwd (UID 1000)
USER 1000:1000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=5s \
    CMD ["/usr/bin/dns-healthcheck", "--check-udp", "--check-tcp"]

ENTRYPOINT ["/usr/sbin/pdns_recursor"]
CMD [ "--disable-syslog", "--daemon=no" ]
