# UniFi-MacMap

**Extract true 2.4 GHz and 5 GHz radio MACs from UniFi APs — no controller required.**

---

## Overview

A lightweight Bash utility for auditing UniFi Access Points over SSH and extracting their true 2.4 GHz and 5 GHz radio MAC addresses — independent of the UniFi Controller, which only reports the Ethernet MAC and is notoriously inaccurate.  
Designed for field engineers and network administrators who need verified radio MACs directly from the AP firmware for accurate inventory, troubleshooting, and documentation.

---

## Features
- Connects to multiple UniFi APs via SSH using a simple `ips.txt` list  
- Extracts the **real** 2.4 GHz (`wifi0`) and 5 GHz (`wifi1`) MAC addresses  
- Cleans up padded 16-byte UNSPEC MAC formats (removes `-00-00-...`)  
- Handles authentication, timeouts, and unreachable hosts gracefully  
- Produces a clean CSV report (`wifi_macs.csv`)  
- Works independently of the UniFi Controller or network topology  

---

## Requirements

This script runs on macOS, Linux, or Windows (via WSL) with the following tools:

| Dependency | Purpose | Installed by default? |
|-------------|----------|-----------------------|
| `bash` | Shell interpreter | ✅ Yes |
| `ssh` | SSH client | ✅ Yes |
| `sshpass` | Non-interactive password authentication | ❌ No |
| `awk`, `grep`, `sed` | Text utilities | ✅ Yes |

---

## Installation

### macOS
```bash
brew install sshpass
