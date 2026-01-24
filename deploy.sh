#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# 1. SETUP ENVIRONMENT
SCRIPT_DIR=$(dirname "$(realpath "$0")")
CONFIG_JSON="$SCRIPT_DIR/configuration.json"

if [ ! -f "$CONFIG_JSON" ]; then
    echo "Error: configuration.json not found in $SCRIPT_DIR"
    exit 1
fi

# Extract Variables
RAW_HOME=$(jq -r .HOME_DIR "$CONFIG_JSON")
if [ "$RAW_HOME" == "DYNAMIC_HOME" ]; then
    HOME_DIR=$HOME
else
    HOME_DIR=$RAW_HOME
fi
DONATION=$(jq -r .DONATION "$CONFIG_JSON")
WORKER_CONFIG_FILE=$(jq -r .WORKER_CONFIG_FILE "$CONFIG_JSON")
P2POOL_NODE_HOSTNAME=$(jq -r .P2POOL_NODE_HOSTNAME "$CONFIG_JSON")
P2POOL_NODE_PORT=$(jq -r .P2POOL_NODE_PORT "$CONFIG_JSON")
TEMPLATE_CONFIG="$SCRIPT_DIR/$WORKER_CONFIG_FILE"

# 2. PREPARE DIRECTORIES
WORKER_ROOT="$HOME_DIR/worker"
mkdir -p "$WORKER_ROOT"
cd "$WORKER_ROOT"

GIT_DIR="xmrig"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -d "$GIT_DIR" ]; then
    echo "Backing up existing worker..."
    mv "$GIT_DIR" "${GIT_DIR}-${TIMESTAMP}"
fi

# 3. DEPENDENCIES
echo "Installing dependencies (this may take a minute)..."
sudo apt update -qq
sudo apt install -y -qq git build-essential cmake libuv1-dev libssl-dev libhwloc-dev avahi-daemon cpupower gettext-base jq &> /dev/null

# Ensure MSR module is loaded and will load on boot
sudo modprobe msr
echo "msr" | sudo tee -a /etc/modules > /dev/null || true

# 4. BUILD XMRIG
echo "Cloning and patching XMRig..."
git clone --quiet https://github.com/xmrig/xmrig.git
sed -i "s/DonateLevel = 1;/DonateLevel = $DONATION;/g" xmrig/src/donate.h

echo "Compiling (using $(nproc) cores)..."
mkdir -p xmrig/build && cd xmrig/build
cmake .. -DWITH_HWLOC=ON &> /dev/null
make -j$(nproc) &> /dev/null

# 5. CONFIGURATION
echo "Applying JSON configurations..."
# We define the full path for the log file here
LOG_FILE_PATH="$WORKER_ROOT/xmrig.log"

jq --arg url "$P2POOL_NODE_HOSTNAME.local:$P2POOL_NODE_PORT" \
   --arg user "$(hostname)" \
   --arg log "$LOG_FILE_PATH" \
   '.pools[0].url = $url | .pools[0].user = $user | ."log-file" = $log' "$TEMPLATE_CONFIG" > config.json

echo "Setting up log rotation to prevent disk bloat..."

# Create the logrotate config file
sudo tee /etc/logrotate.d/xmrig > /dev/null <<EOF
$LOG_FILE_PATH {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    minsize 50M
    create 0644 $(whoami) $(whoami)
}
EOF

# 6. SYSTEMD SERVICE
echo "Installing/Updating Systemd Service..."
export BUILD_DIR="$WORKER_ROOT/xmrig/build"
export CPUPOWER_PATH=$(which cpupower || echo "/usr/bin/cpupower")

# Overwrite the existing file
envsubst '$BUILD_DIR $CPUPOWER_PATH' < "$SCRIPT_DIR/systemd/xmrig.service.template" | sudo tee /etc/systemd/system/xmrig.service > /dev/null

# Refresh systemd's memory
sudo systemctl daemon-reload

# Enable it for boot (if not already)
sudo systemctl enable xmrig.service

# RESTART (not just start) to apply changes immediately
echo "Restarting service to apply updates..."
sudo systemctl restart xmrig.service

# 7. KERNEL & GRUB OPTIMIZATION
echo "Optimizing GRUB for HugePages..."
if [ -f "$SCRIPT_DIR/util/proposed-grub.sh" ]; then
    NEW_PARAMS=$("$SCRIPT_DIR/util/proposed-grub.sh" -q)
    sudo cp /etc/default/grub /etc/default/grub.bak
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" /etc/default/grub
    sudo update-grub
else
    echo "Warning: proposed-grub.sh not found, skipping GRUB update."
fi

# 8. PERMANENT MOUNTS & LIMITS
echo "Setting up HugePage mounts and limits..."
sudo mkdir -p /dev/hugepages1G

# Atomic check and append for fstab
FSTAB_LINES="hugetlbfs /dev/hugepages hugetlbfs defaults 0 0
hugetlbfs_1g /dev/hugepages1G hugetlbfs pagesize=1G 0 0"

echo "$FSTAB_LINES" | while read -r line; do
    grep -qF "$line" /etc/fstab || echo "$line" | sudo tee -a /etc/fstab > /dev/null
done

sudo mount -a || echo "Warning: Some mounts failed, check dmesg."

# Atomic check and append for limits
LIMITS="* soft memlock unlimited
* hard memlock unlimited"

echo "$LIMITS" | while read -r line; do
    grep -qF "$line" /etc/security/limits.conf || echo "$line" | sudo tee -a /etc/security/limits.conf > /dev/null
done

echo "--------------------------------------------------------"
echo "SUCCESS: Worker setup complete."
echo "CRITICAL: You MUST reboot for HugePages to take effect."
echo "--------------------------------------------------------"