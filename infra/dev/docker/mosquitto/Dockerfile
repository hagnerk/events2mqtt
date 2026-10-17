FROM eclipse-mosquitto:2

# SSH server so that Claude can log into this container as root.
RUN apk add --no-cache openssh-server \
    && sed -i 's/^root:!/root:*/' /etc/shadow \
    && mkdir -p /root/.ssh \
    && chmod 700 /root/.ssh

COPY entrypoint.sh /usr/local/bin/entrypoint-ssh.sh
RUN chmod +x /usr/local/bin/entrypoint-ssh.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint-ssh.sh"]
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
