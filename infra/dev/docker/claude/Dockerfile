FROM spydemon/claude:1.0

# SSH client so that Claude can connect to the other dev containers.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Gitleaks, required by the pre-commit hook to block commits containing secrets.
# The archive is checked against the checksum published with the release.
ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256_X64=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG GITLEAKS_SHA256_ARM64=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
ARG TARGETARCH
RUN set -e; \
    case "$TARGETARCH" in \
        amd64) arch=x64; sha256="$GITLEAKS_SHA256_X64" ;; \
        arm64) arch=arm64; sha256="$GITLEAKS_SHA256_ARM64" ;; \
        *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    archive="gitleaks_${GITLEAKS_VERSION}_linux_${arch}.tar.gz"; \
    curl -fsSL -o "/tmp/$archive" "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/$archive"; \
    echo "$sha256  /tmp/$archive" | sha256sum -c -; \
    tar -xzf "/tmp/$archive" -C /usr/local/bin gitleaks; \
    rm "/tmp/$archive"; \
    gitleaks version

COPY entrypoint.sh /usr/local/bin/entrypoint-ssh.sh
RUN chmod +x /usr/local/bin/entrypoint-ssh.sh

# Overriding ENTRYPOINT resets the CMD inherited from the base image, so both are restated.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint-ssh.sh"]
CMD ["sleep", "infinity"]
