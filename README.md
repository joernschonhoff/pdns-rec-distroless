# pdns-rec-distroless

A distroless container image for the PowerDNS Recursor.

## Purpose & Warning

This is a **hobby / learning project**. It is **not intended for production use** — it lacks typical hardening, monitoring, and operational features you would expect from a production-grade recursor deployment. Use at your own risk.

This project is **not affiliated with, endorsed by, or associated with PowerDNS.com B.V.** in any form. "PowerDNS" is a trademark of PowerDNS.com B.V.; this image simply compiles and packages the official, publicly available PowerDNS Recursor source releases.

## Contents

- Minimal Docker build for the PowerDNS Recursor
  - `pdns_recursor` is compiled with DNS-over-TLS, dnstap, and NOD support enabled
  - PowerDNS Recursor tarballs are verified against official PGP signatures before building
  - Final runtime image is based on `gcr.io/distroless/base-debian13` — no shell, no package manager
- Runs as a non-root user (UID/GID 1000)
- Includes an embedded `dns-healthcheck` binary for container health checks
- `Debug.Dockerfile` variant available (Debian 13-slim with a shell) for interactive troubleshooting

## Quickstart

### Build

The project ships a `Makefile` that wraps the `docker buildx` invocations (reads the version from `VERSION`, sets labels, tags, etc.):

```bash
# Show all available targets
make help

# Build production image
make build-prod

# Build debug image
make build-debug

# Build both
make build
```

### Running

`make build-prod` tags the image as `registry.gitlab.com/joern_schonhoff/pdns-rec-distroless:<version>` (override with `CI_REGISTRY_IMAGE=<name> make build-prod` for a local-only tag).

```bash
docker run --rm -v /path/to/recursor.conf:/etc/pdns/recursor.conf:ro registry.gitlab.com/joern_schonhoff/pdns-rec-distroless:$(cat VERSION)
```

## Configuration

The PowerDNS Recursor reads its configuration from `/etc/pdns/recursor.conf` by default. Mount your own configuration file into the container as shown above.

## Version Management

The PowerDNS Recursor version is stored in the `VERSION` file. When a new version is released:

1. Update the `VERSION` file with the new version number
2. Build and test the image: `make build && make verify`
3. Commit the change

**Automated Updates:** The project is configured for Renovate bot, which will:
- Monitor https://downloads.powerdns.com/releases/ for new PowerDNS Recursor releases
- Automatically create PRs when new stable versions (e.g., `pdns-recursor-5.x.y.tar.xz`) are detected
- Extract the version number and update the `VERSION` file

## Health Checks

The production image includes an embedded DNS health check utility (`dns-healthcheck`), wired up via `HEALTHCHECK` in the Dockerfile.

**Docker Compose:**
```yaml
services:
  pdns-rec:
    # ... other config ...
    healthcheck:
      test: ["CMD", "/usr/bin/dns-healthcheck", "--check-udp", "--check-tcp"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 5s
```

**Kubernetes:**
```yaml
livenessProbe:
  tcpSocket:
    port: 53
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  tcpSocket:
    port: 53
  initialDelaySeconds: 5
  periodSeconds: 5
```

For the debug image (which uses full Debian and has no HEALTHCHECK wired up), health checks must be implemented at the orchestration level:

**Docker Compose (Debug):**
```yaml
services:
  pdns-rec:
    # ... other config ...
    healthcheck:
      test: ["CMD", "true"]  # Minimal check - container is running
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 30s
```

## License

GPL-2.0 (GNU General Public License v2)

This project bundles the PowerDNS Recursor, which is licensed under GPL-2.0. See the LICENSE file for the full text.
