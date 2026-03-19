FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites
RUN apt-get update && \
    apt-get install -y \
    wget curl gnupg2 ca-certificates lsb-release apt-transport-https \
    postgresql-client sudo && \
    apt-get clean

# Add Foreman repository
RUN wget https://apt.theforeman.org/pubkey.gpg -O /etc/apt/trusted.gpg.d/foreman.asc && \
    echo "deb http://apt.theforeman.org/ bookworm 3.9" > /etc/apt/sources.list.d/foreman.list && \
    apt-get update

# Install Foreman packages
RUN apt-get install -y \
    foreman \
    foreman-postgresql \
    foreman-cli \
    ruby-foreman-ansible \
    && apt-get clean

# Create required directories
RUN mkdir -p /usr/share/foreman/tmp/pids && \
    mkdir -p /var/log/foreman && \
    chown -R foreman:foreman /usr/share/foreman /var/log/foreman

# Copy configuration files
COPY foreman-settings.yaml /etc/foreman/settings.yaml
COPY database.yml /etc/foreman/database.yml

# Expose ports
EXPOSE 3000 8443

# Startup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /usr/share/foreman

ENTRYPOINT ["/entrypoint.sh"]
