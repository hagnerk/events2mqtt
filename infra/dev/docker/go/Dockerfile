FROM golang:1.27

# SSH server so that Claude can run go commands in this container.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /root/.ssh \
    && chmod 700 /root/.ssh

# SSH sessions do not inherit the Docker environment: expose Go to them.
RUN echo "PATH=$PATH" >> /etc/environment \
    && echo "GOPATH=$GOPATH" >> /etc/environment

COPY entrypoint.sh /usr/local/bin/entrypoint-ssh.sh
RUN chmod +x /usr/local/bin/entrypoint-ssh.sh

WORKDIR /workspace

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint-ssh.sh"]
