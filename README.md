# # 🚀 Network Bridge Script Documentation 
Overview
This script creates an isolated network environment using Docker containers with a custom bridge configuration, implementing one-way ICMP (ping) communication between two containers.
Technical Components
# 1. Root Permission Check
```sh
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or use sudo."
  exit 1
fi
```
Verifies root privileges required for network operations.
# 2. Resource Cleanup
```sh
docker stop TEAM_A TEAM_B
docker rm TEAM_A TEAM_B
docker network rm team_A_network team_B_network
sudo ip link delete br0
sudo ip link delete veth0
sudo ip link delete veth2
```
Stops and removes existing containers
Cleans up Docker networks
Removes existing bridge and veth interfaces

# 3. Docker Network Setup
```sh
docker network create team_A_network
docker network create team_B_network
docker run -d --name TEAM_A --network team_A_network nginx
docker run -d --name TEAM_B --network team_B_network nginx
```
Creates isolated Docker networks
Deploys nginx containers in respective networks

# 4. Bridge Configuration
```sh
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
sudo ip link add br0 type bridge
sudo ip addr add 192.168.1.1/24 dev br0
sudo ip link set br0 up
```
Disables iptables for bridged traffic
Creates bridge interface br0
Assigns IP address 192.168.1.1/24
Activates the bridge

# 5. Virtual Ethernet (veth) Pairs
```sh
sudo ip link add veth0 type veth peer name veth1
sudo ip link add veth2 type veth peer name veth3
sudo ip link set veth0 master br0
sudo ip link set veth2 master br0
Creates and configures two veth pairs:
```
```sh
veth0-veth1 for TEAM_A
veth2-veth3 for TEAM_B
Attaches to bridge br0
```
# 6. Container Network Configuration
```sh
TEAM_A_PID=$(docker inspect -f '{{.State.Pid}}' TEAM_A)
TEAM_B_PID=$(docker inspect -f '{{.State.Pid}}' TEAM_B)

sudo ip link set veth1 netns $TEAM_A_PID
sudo ip link set veth3 netns $TEAM_B_PID
```
Retrieves container PIDs
Moves veth interfaces into container network namespaces

# 7. IP Configuration
```sh
sudo nsenter -t $TEAM_A_PID -n ip addr add 192.168.1.2/24 dev veth1
sudo nsenter -t $TEAM_B_PID -n ip addr add 192.168.1.3/24 dev veth3
```
Assigns IP addresses:

TEAM_A: 192.168.1.2/24
TEAM_B: 192.168.1.3/24

# 8. IPTables Rules
```sh
# Allow TEAM_A → TEAM_B
sudo nsenter -t $TEAM_A_PID -n iptables -A OUTPUT -d 192.168.1.3 -p icmp --icmp-type echo-request -j ACCEPT
sudo nsenter -t $TEAM_B_PID -n iptables -A INPUT -s 192.168.1.2 -p icmp --icmp-type echo-request -j ACCEPT

# Block TEAM_B → TEAM_A
sudo nsenter -t $TEAM_B_PID -n iptables -A OUTPUT -d 192.168.1.2 -p icmp --icmp-type echo-request -j DROP
sudo nsenter -t $TEAM_A_PID -n iptables -A INPUT -s 192.168.1.3 -p icmp --icmp-type echo-request -j DROP
```
Implements one-way ICMP communication:

Allows ping from TEAM_A to TEAM_B
Blocks ping from TEAM_B to TEAM_A

# Network Topology
```
CopyTEAM_A (192.168.1.2) ←→ br0 (192.168.1.1) ←→ TEAM_B (192.168.1.3)
     ↓                                            ↑
Can ping                                     Cannot ping
```
Usage
```sh
# Make script executable
chmod +x script.sh
```
```sh
# Run with sudo
sudo ./script.sh
```
```sh
# Test connectivity
sudo nsenter -t $TEAM_A_PID -n ping -c 4 192.168.1.3  # Should work
sudo nsenter -t $TEAM_B_PID -n ping -c 4 192.168.1.2  # Should fail
```