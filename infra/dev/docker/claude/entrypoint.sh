#!/bin/sh
set -e

# The SSH key pair lives in the volume mounted on /root/.ssh and is generated on first start.
# The other dev containers authorize its public key once this container is healthy.
chmod 700 /root/.ssh
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -N '' -C 'claude@event2mqtt-dev' -f /root/.ssh/id_rsa
fi

exec "$@"
