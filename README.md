# UniFi-MacMap

**Extract true 2.4 GHz and 5 GHz radio MACs from UniFi APs — no controller required.**

## Overview
UniFi-MacMap is a lightweight Bash utility that audits UniFi Access Points over SSH and extracts their true 2.4 GHz and 5 GHz radio MAC addresses — independent of the UniFi Controller (which only reports the Ethernet MAC and is often inaccurate). It’s built for field engineers and network administrators who need verified radio MACs directly from the AP firmware for accurate inventory, documentation, and troubleshooting.

## Features
- Connects to multiple UniFi APs via SSH using `ips.txt`
- Retrieves real `wifi0` (2.4 GHz) and `wifi1` (5 GHz) MACs
- Cleans padded 16-byte UNSPEC MAC formats (removes the “-00-00-…” tail)
- Handles authentication, timeouts, and unreachable hosts gracefully
- Exports results to `wifi_macs.csv`
- Works independently of the UniFi Controller

## Requirements
Runs on macOS, Linux, or Windows (WSL) with:

- bash (shell interpreter)
- ssh (SSH client)
- sshpass (non-interactive SSH auth)
- awk, grep, sed, nc (standard text/network tools)

## Installation

### macOS
    brew install sshpass

### Debian / Ubuntu / Raspberry Pi OS
    sudo apt update
    sudo apt install sshpass

### Windows (via WSL)
1) Install Windows Subsystem for Linux (WSL): https://learn.microsoft.com/en-us/windows/wsl/install  
2) Open WSL (Ubuntu recommended)  
3) Install dependencies inside WSL:
    
        sudo apt update
        sudo apt install bash openssh-client sshpass netcat

## Setup

1) Clone the repository:
    
        git clone https://github.com/yourname/unifi-macmap.git
        cd unifi-macmap

2) Create or edit `ips.txt` (one IP per line). Lines starting with `#` and blank lines are ignored; duplicates are fine.

    Example `ips.txt`:
    
        # UniFi APs – Building A
        10.0.0.106
        10.0.3.181
        10.0.1.125

        # Building B
        10.0.3.20
        10.0.1.88
        10.0.1.200

3) Make the script executable:
    
        chmod +x get-real-macs.sh

4) Run the script (provide the SSH password via env var):
    
        PASS='your_ssh_password_here' bash ./get-real-macs.sh

The script will:
- SSH into each AP listed in `ips.txt`
- Extract 2.4 GHz and 5 GHz radio MACs from `ifconfig`
- Clean/normalize MACs (trim padded zeros; colon format)
- Append results to `wifi_macs.csv` in the repo directory

## Example Output

File: `wifi_macs.csv`
    
    ip,host,mac_2.4ghz,mac_5ghz
    10.0.0.186,ArtRoomAP,74:83:C2:24:81:D5,74:83:C2:25:81:D5
    10.0.1.200,1stGradeAP,74:83:C2:24:7B:C0,74:83:C2:25:7B:C0

If a host is unreachable or authentication fails, you’ll see a status row like:

    10.0.1.99,unknown,UNREACHABLE,UNREACHABLE

## Troubleshooting

- `UNREACHABLE` → Wrong VLAN / firewall / routing; test manual SSH from your machine:
      
      ssh C5xWnwtwo@10.0.0.106

- `AUTH_FAILED` → Wrong username or password; verify AP SSH credentials (Controller → Settings → System → Device SSH Access)
- `CLOSED_22` → Port 22 filtered/closed; check switch/firewall rules
- Empty output → `ips.txt` has no valid IPv4 lines; ensure one IP per line

## Quick Start (3 commands)
    
    git clone https://github.com/yourname/unifi-macmap.git
    cd unifi-macmap
    PASS='your_ssh_password_here' bash ./get-real-macs.sh

## License
MIT License  
Copyright © 2025 Andrew Gianikas

> “Because sometimes you just want the truth — straight from the radio.”
