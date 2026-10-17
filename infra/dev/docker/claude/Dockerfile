FROM spydemon/claude:1.0

# SSH client so that Claude can connect to the other dev containers.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint-ssh.sh
RUN chmod +x /usr/local/bin/entrypoint-ssh.sh

# Overriding ENTRYPOINT resets the CMD inherited from the base image, so both are restated.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint-ssh.sh"]
CMD ["sleep", "infinity"]
