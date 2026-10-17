#!/bin/sh
set -e

# Host keys are generated once and kept in the volume mounted on /etc/ssh.
ssh-keygen -A

# Claude's public key is mounted read-only, then copied with the right permissions.
install -m 600 /tmp/claude_id_rsa.pub /root/.ssh/authorized_keys

/usr/sbin/sshd -o PermitRootLogin=prohibit-password -o PasswordAuthentication=no

exec /docker-entrypoint.sh "$@"
