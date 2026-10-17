# Events2mqtt

## Developer setup

The development environment runs in Docker and is described in `infra/dev/docker-compose.yml`. It requires Docker Engine 25 or later with the Compose plugin, since the healthcheck relies on the `start_interval` option. Once Docker is available, we can start everything from the `infra/dev` directory:

```sh
cd infra/dev
docker compose up -d --build
```

Three containers are started on a shared network:

| Service | Role |
|---|---|
| `claude` | Claude Code, with the repository mounted on `/workspace` |
| `mosquitto` | The MQTT broker, published on port `1883` of the host |
| `go` | The Go toolchain, with the repository mounted on `/workspace` |

Claude does not have the Go toolchain or the broker in its own container: it reaches the two other containers over SSH as `root`, for example with `ssh root@go 'cd /workspace && go build ./...'`. Note that an SSH session on `go` starts in `/root`, since the `WORKDIR` of the image does not apply to it, hence the `cd`.

### The SSH key

The key pair Claude uses to log into the other containers is not versioned: it lives in `infra/dev/data/ssh`, which is excluded by `.gitignore` along with `infra/dev/data/claude` (Claude credentials, history and sessions). On a fresh clone, the `claude` container therefore generates it on first start, in its entrypoint, if `id_rsa` does not exist yet.

This creates an ordering constraint, because `mosquitto` and `go` mount `id_rsa.pub` to copy it into their `authorized_keys`. If they started before the key exists, Docker would create an empty directory in place of the missing file and their entrypoint would fail. To avoid this, both services declare a `depends_on` on `claude` with the `service_healthy` condition, and `claude` only reports healthy once `id_rsa.pub` is present. As a consequence, starting `mosquitto` or `go` alone also starts `claude`.

The public key is only copied when a container starts. If the key pair is deleted and regenerated, `mosquitto` and `go` keep authorizing the old one until they are recreated:

```sh
docker compose up -d --force-recreate mosquitto go
```

The SSH host keys of `mosquitto` and `go` are kept in the `mosquitto-ssh` and `go-ssh` volumes, so they survive a restart and Claude's `known_hosts` stays valid. If these volumes are removed, the containers get new host keys and the connection fails with `Host key verification failed`. In that case, the old entries have to be removed from inside the `claude` container before connecting again:

```sh
ssh-keygen -R mosquitto
ssh-keygen -R go
```
