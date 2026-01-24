#!/bin/bash

# Quiet flag check
[[ "$*" == *"-q"* ]] && QUIET=1 || QUIET=0

# 1. Get L3 Cache and normalize to MB
L3_RAW=$(lscpu | grep "L3 cache" | head -n 1 | awk '{print $3$4}')
L3_MB=$(echo "$L3_RAW" | sed 's/[^0-9]//g')
[[ "$L3_RAW" == *K* ]] && L3_MB=$((L3_MB / 1024))

# 2. Get CPU Sockets (NUMA nodes)
SOCKETS=$(lscpu | grep "Socket(s):" | awk '{print $2}')
[[ -z "$SOCKETS" ]] && SOCKETS=1

# 3. Calculate Threads and Pages
THREADS=$((L3_MB / 2))
GB_PAGES=$((3 * SOCKETS))
TWO_MB_COUNT=$((128 + THREADS + 10))

# 4. Check for 1GB support
if grep -q "pdpe1gb" /proc/cpuinfo; then
    NEW_GRUB="quiet splash hugepagesz=1G hugepages=$GB_PAGES hugepagesz=2M hugepages=$TWO_MB_COUNT default_hugepagesz=2M msr.allow_writes=on"
else
    # Fallback: All 2MB pages (1168 baseline per socket + threads)
    TOTAL_2M=$(((1168 * SOCKETS) + THREADS + 10))
    NEW_GRUB="quiet splash default_hugepagesz=2M hugepages=$TOTAL_2M msr.allow_writes=on"
fi

# 5. Output
if [ $QUIET -eq 1 ]; then
    echo "$NEW_GRUB"
else
    echo "--- Hardware Detected ---"
    echo "L3 Cache: ${L3_MB}MB | Sockets: $SOCKETS | Threads: $THREADS"
    echo "-------------------------"
    echo "Proposed GRUB Line:"
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_GRUB\""
fi