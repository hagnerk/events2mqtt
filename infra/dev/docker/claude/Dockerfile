FROM spydemon/claude:1.0

# SSH client so that Claude can connect to the other dev containers.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*
