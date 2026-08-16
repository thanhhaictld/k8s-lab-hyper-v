#!/bin/bash

HYPERV_NETWORK="192.168.50.0/24"
INTERFACE="eth0"

# Get current WSL -> Windows gateway dynamically
GATEWAY=$(ip route show default dev "$INTERFACE" | awk '/default/ {print $3; exit}')

if [ -z "$GATEWAY" ]; then
    echo "ERROR: Cannot determine WSL gateway on $INTERFACE"
    exit 1
fi

echo "WSL interface : $INTERFACE"
echo "WSL gateway   : $GATEWAY"
echo "Hyper-V subnet: $HYPERV_NETWORK"

# Replace existing route or create it
sudo ip route replace "$HYPERV_NETWORK" via "$GATEWAY" dev "$INTERFACE"

echo
echo "Route configured:"
ip route show "$HYPERV_NETWORK"