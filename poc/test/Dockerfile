FROM debian:12

# Install required packages
RUN apt-get update && \
    apt-get install -y \
    openssh-server \
    python3 \
    python3-pip \
    sudo \
    vim \
    curl \
    iproute2 \
    procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    echo 'root:testpass' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Expose SSH port
EXPOSE 22

# Start SSH
CMD ["/usr/sbin/sshd", "-D"]
