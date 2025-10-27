# Build using Debian packages for Mosquitto headers
# Using bookworm since golang:trixie isn't available yet
FROM golang:1.23-bookworm AS go_auth_builder

ENV CGO_CFLAGS="-I/usr/include -fPIC"
ENV CGO_LDFLAGS="-shared"
ENV CGO_ENABLED=1

# Install mosquitto-dev for headers and gcc for building
RUN apt-get update && apt-get install -y \
    mosquitto-dev \
    libmosquitto-dev \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy source and build
COPY ./ ./
RUN set -ex; \
    go build -buildmode=c-archive go-auth.go; \
    go build -buildmode=c-shared -o go-auth.so; \
    go build pw-gen/pw.go

# Use Debian bookworm as final image
FROM debian:bookworm-slim

RUN set -ex; \
    apt-get update; \
    apt-get install -y mosquitto tini && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/mosquitto /var/log/mosquitto
RUN set -ex; \
    groupadd mosquitto || true; \
    useradd -s /sbin/nologin mosquitto -g mosquitto -d /var/lib/mosquitto || true; \
    chown -R mosquitto:mosquitto /var/log/mosquitto/; \
    chown -R mosquitto:mosquitto /var/lib/mosquitto/

# Copy the auth plugin and password generator
COPY --from=go_auth_builder /app/go-auth.so /mosquitto/go-auth.so
COPY --from=go_auth_builder /app/pw /mosquitto/pw

# Create necessary directories
RUN mkdir -p /mosquitto/auth /mosquitto/conf.d && \
    chown -R mosquitto:mosquitto /mosquitto

EXPOSE 1883 1884

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/sbin/mosquitto", "-c", "/etc/mosquitto/mosquitto.conf"]
