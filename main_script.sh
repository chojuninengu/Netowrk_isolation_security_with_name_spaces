#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or use sudo."
  exit 1
fi

# Step 1: Clean up existing resources (if any)
echo "Cleaning up existing resources..."
docker stop TEAM_A TEAM_B 2>/dev/null
docker rm TEAM_A TEAM_B 2>/dev/null
docker network rm team_A_network team_B_network 2>/dev/null
sudo ip link delete br0 2>/dev/null
sudo ip link delete veth0 2>/dev/null
sudo ip link delete veth2 2>/dev/null
echo "Cleanup complete."

# Step 2: Create Docker networks and containers
echo "Creating Docker networks and containers..."
docker network create team_A_network 2>/dev/null || echo "Network team_A_network already exists."
docker network create team_B_network 2>/dev/null || echo "Network team_B_network already exists."
docker run -d --name TEAM_A --network team_A_network nginx 2>/dev/null || echo "Container TEAM_A already exists."
docker run -d --name TEAM_B --network team_B_network nginx 2>/dev/null || echo "Container TEAM_B already exists."
echo "Docker containers TEAM_A and TEAM_B created."

# Step 3: Disable iptables for bridged traffic
echo "Disabling iptables for bridged traffic..."
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
echo "net.bridge.bridge-nf-call-iptables set to 0."

# Step 4: Create a bridged network (br0)
echo "Creating bridged network (br0)..."
sudo ip link add br0 type bridge 2>/dev/null || echo "Bridge br0 already exists."
sudo ip addr add 192.168.1.1/24 dev br0 2>/dev/null || echo "IP address already assigned to br0."
sudo ip link set br0 up 2>/dev/null || echo "Bridge br0 is already up."
echo "Bridge br0 created and configured."
# Step 4: Create a bridged network (br0)
echo "Creating bridged network (br0)..."
sudo ip link add br0 type bridge 2>/dev/null || echo "Bridge br0 already exists."
sudo ip addr add 192.168.1.1/24 dev br0 2>/dev/null || echo "IP address already assigned to br0."
sudo ip link set br0 up 2>/dev/null || echo "Bridge br0 is already up."
echo "Bridge br0 created and configured."

# Step 5: Create veth pairs and attach to the bridge
echo "Creating veth pairs and attaching to the bridge..."
sudo ip link add veth0 type veth peer name veth1 2>/dev/null || echo "Veth pair veth0/veth1 already exists."
sudo ip link add veth2 type veth peer name veth3 2>/dev/null || echo "Veth pair veth2/veth3 already exists."
sudo ip link set veth0 master br0 2>/dev/null || echo "Veth0 is already attached to br0."
sudo ip link set veth2 master br0 2>/dev/null || echo "Veth2 is already attached to br0."
sudo ip link set veth0 up 2>/dev/null || echo "Veth0 is already up."
sudo ip link set veth2 up 2>/dev/null || echo "Veth2 is already up."
echo "Veth pairs created and attached to the bridge."

# Step 6: Attach veth pairs to containers
echo "Attaching veth pairs to containers..."
TEAM_A_PID=$(docker inspect -f '{{.State.Pid}}' TEAM_A 2>/dev/null)
TEAM_B_PID=$(docker inspect -f '{{.State.Pid}}' TEAM_B 2>/dev/null)

if [ -z "$TEAM_A_PID" ]; then
  echo "Error: Could not retrieve PID for TEAM_A. Is the container running?"
  exit 1
fi

if [ -z "$TEAM_B_PID" ]; then
  echo "Error: Could not retrieve PID for TEAM_B. Is the container running?"
  exit 1
fi

sudo ip link set veth1 netns $TEAM_A_PID 2>/dev/null || echo "Veth1 is already attached to TEAM_A."
sudo ip link set veth3 netns $TEAM_B_PID 2>/dev/null || echo "Veth3 is already attached to TEAM_B."
echo "Veth pairs attached to containers."

# Step 7: Configure IP addresses for containers
echo "Configuring IP addresses for containers..."
sudo nsenter -t $TEAM_A_PID -n ip addr add 192.168.1.2/24 dev veth1 2>/dev/null || echo "IP address already assigned to veth1."
sudo nsenter -t $TEAM_A_PID -n ip link set veth1 up 2>/dev/null || echo "Veth1 is already up."
sudo nsenter -t $TEAM_B_PID -n ip addr add 192.168.1.3/24 dev veth3 2>/dev/null || echo "IP address already assigned to veth3."
sudo nsenter -t $TEAM_B_PID -n ip link set veth3 up 2>/dev/null || echo "Veth3 is already up."
echo "IP addresses configured for containers."

# Step 8: Configure iptables for one-way communication
echo "Configuring iptables for one-way communication..."
# Allow TEAM_A to ping TEAM_B
sudo nsenter -t $TEAM_A_PID -n iptables -A OUTPUT -d 192.168.1.3 -p icmp --icmp-type echo-request -j ACCEPT
sudo nsenter -t $TEAM_B_PID -n iptables -A INPUT -s 192.168.1.2 -p icmp --icmp-type echo-request -j ACCEPT

# Block TEAM_B from pinging TEAM_A
sudo nsenter -t $TEAM_B_PID -n iptables -A OUTPUT -d 192.168.1.2 -p icmp --icmp-type echo-request -j DROP
sudo nsenter -t $TEAM_A_PID -n iptables -A INPUT -s 192.168.1.3 -p icmp --icmp-type echo-request -j DROP
echo "iptables rules configured."

# Step 9: Test connectivity
echo "Testing connectivity between containers..."
echo "Pinging TEAM_B (192.168.1.3) from TEAM_A..."
sudo nsenter -t $TEAM_A_PID -n ping -c 4 192.168.1.3
echo "Pinging TEAM_A (192.168.1.2) from TEAM_B..."
sudo nsenter -t $TEAM_B_PID -n ping -c 4 192.168.1.2
echo "to confirm connection from TEAM_A to TEAM_B use:sudo nsenter -t $TEAM_A_PID -n ping -c 4 192.168.1.3 "
echo "Setup complete!"
