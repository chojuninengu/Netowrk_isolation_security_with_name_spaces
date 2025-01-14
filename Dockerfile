# Use an official Ubuntu base image
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    docker.io \
    iptables \
    iproute2 \
    net-tools \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Copy the script into the container
COPY setup_network.sh /usr/local/bin/setup_network.sh

# Make the script executable
RUN chmod +x /usr/local/bin/setup_network.sh

# Set the script as the entrypoint
ENTRYPOINT ["/usr/local/bin/setup_network.sh"]
