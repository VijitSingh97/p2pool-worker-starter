**XMRig-AutoDeploy 🚀**

A high-performance deployment script for XMRig on Ubuntu/Debian. This isn't just a basic installer; it's a **hardware-aware optimizer** that tunes your Linux kernel for maximum Monero mining efficiency.

### ✨ Features

*   **L3 Cache Optimization:** Automatically calculates mining threads based on the standard L3/2MB rule.
    
*   **Kernel Tuning:** Configures **GRUB** with 1GB and 2MB HugePages based on physical CPU socket count.
    
*   **Zen-Specific MSR:** Includes Ryzen prefetcher toggles (0xc0011022:0x510000) for Zen 2/3 architectures. 
    
*   **Persistent Mounts:** Sets up **hugetlbfs** mounts and lifts **memlock** limits automatically. 
    
*   **Systemd Integration:** Deploys XMRig as a background service with **cpupower** performance profiles. 
    

### 🛠 Prerequisites

*   **OS:** Ubuntu 22.04+ or Debian 12.
    
*   **Tools:** jq, gettext-base, and cmake. 
    
*   **Hardware:** A CPU with a healthy L3 cache (the script will calculate the rest).
    

### 🚀 Quick Start

**1\. Clone and Configure:**

``` Bash
    git clone https://github.com/VijitSingh97/p2pool-worker-starter.git
    cd p2pool-worker-starter
```

Edit **configuration.json** with your P2Pool node details.

**2\. Run the Deployer:**

```Bash
    chmod +x deploy.sh
    chmod +x util/proposed-grub.sh 
    sudo ./deploy.sh   
```

**3\. Reboot:** Kernel-level changes for HugePages require a fresh boot to allocate contiguous memory blocks.

```Bash
    sudo reboot   
```

**Maintenance & Logging**

*   **Logs:** Located at ~/worker/xmrig.log.
    
*   **Auto-Cleanup:** The script installs a logrotate policy in /etc/logrotate.d/xmrig.
    
*   **Retention:** It keeps 7 days of compressed logs and triggers rotation once the file exceeds 50MB. This ensures your server never runs out of space due to long-term mining logs.

### 📊 Optimization Logic

The script analyzes your hardware using **lscpu** to satisfy the requirements of the **RandomX** algorithm:

*   **1GB Pages:** Reserves 3 pages per CPU socket to keep the 2080MB dataset in the fastest memory tier.
    
*   **2MB Pages:** Allocates 128 pages for the RandomX Cache + 1 page per thread for scratchpads.
    
*   **MSR Tweaks:** Applies the zen2 preset and manual register writes to disable performance-sapping prefetchers. 
    

### 🔍 Verification & Troubleshooting

**Verify HugePage Allocation:**

```Bash
    grep Huge /proc/meminfo 
```

_Expected: HugePages\_Total should match your calculated count._

**Verify MSR Status:** Check your xmrig.log in the worker directory. You should see: msr register values for "zen2" preset has been set successfully

**Note on Secure Boot:** If MSR writes fail, you may need to disable **Secure Boot** in your BIOS, as it often blocks the kernel from modifying CPU registers.

### 📝 License

MIT