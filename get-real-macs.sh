#!/usr/bin/env bash
# Collect UniFi AP 5GHz MACs by SSID, using iwconfig on each AP.
# Input : ips.csv (lines like "10.0.0.186,MainOfficeAP" with optional header) in same dir
# Output: wifi_macs.csv (ip,host_or_friendly,mac_5ghz_or_status)

set -u  # no unbound vars

SSH_USER=""         # <-- SSH username (e.g. C5xWnwtwo)
SSH_PASS=""         # <-- SSH password
SSH_PORT="22"
CONNECT_TIMEOUT="6"
NC_TIMEOUT="3"

# SSID whose 5GHz BSSID you want (change this for the SSID Vocera cares about)
SSID_FILTER=""   # e.g. "XYZ_SCHOOL", "XYZ_SCHOOL_Guests", "XYZ_SCHOOL_Students", etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IPFILE="$SCRIPT_DIR/ips.csv"
OUT="$SCRIPT_DIR/wifi_macs.csv"

[ -f "$IPFILE" ] || { echo "Missing $IPFILE (one IP per line, ip[,friendly_name])"; exit 1; }

SSH_OPTS="-o ConnectTimeout=${CONNECT_TIMEOUT} \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password,keyboard-interactive \
  -o NumberOfPasswordPrompts=1 \
  -p ${SSH_PORT}"

port_22_state() {
  local ip="$1"
  if nc -G "$NC_TIMEOUT" -zv "$ip" "$SSH_PORT" >/dev/null 2>&1; then
    echo "OPEN"
    return
  fi
  if nc -G "$NC_TIMEOUT" -zv "$ip" "$SSH_PORT" 2>&1 | grep -qiE "timed out|Operation timed out"; then
    echo "TIMEOUT"
    return
  fi
  echo "CLOSED"
}

echo "ip,host_or_friendly,mac_5ghz_or_status" > "$OUT"

process_ip() {
  local ip="$1"
  local friendly="$2"

  # Basic IPv4 sanity check
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "Skipping non-IP: $ip" >&2; return; }

  local label state out host body mac5

  # Decide label (host/friendly column) up front
  if [ -n "$friendly" ]; then
    label="$friendly"
  else
    label="$ip"
  fi

  state="$(port_22_state "$ip")"
  case "$state" in
    OPEN) : ;;
    TIMEOUT)
      printf "%s,%s,%s\n" "$ip" "$label" "TIMEOUT_22" >> "$OUT"
      return
      ;;
    CLOSED)
      printf "%s,%s,%s\n" "$ip" "$label" "CLOSED_22" >> "$OUT"
      return
      ;;
  esac

  # Quick auth probe
  if ! sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$ip" "echo ok" </dev/null >/dev/null 2>&1; then
    printf "%s,%s,%s\n" "$ip" "$label" "AUTH_FAILED" >> "$OUT"
    return
  fi

  # Get hostname + iwconfig in one shot
  out="$(sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$ip" 'hostname; echo "-----"; iwconfig' </dev/null 2>/dev/null)" || out=""

  if [ -z "$out" ]; then
    printf "%s,%s,%s\n" "$ip" "$label" "NO_OUTPUT" >> "$OUT"
    return
  fi

  # First line = hostname
  host="$(printf '%s\n' "$out" | head -n1 | tr -d '\r' | tr -d ',')"
  # Everything after the separator is iwconfig body
  body="$(printf '%s\n' "$out" | sed '1d' | sed '1{/^-----$/d;}')"

  # Parse iwconfig output locally:
  # - Track current ESSID
  # - When we see a line with Frequency + Access Point and ESSID matches SSID_FILTER and freq is 5.x GHz, grab that BSSID.
  mac5="$(
    printf '%s\n' "$body" | awk -v ssid="$SSID_FILTER" '
      {
        line=$0
      }
      /ESSID:/ {
        essid=line
        sub(/.*ESSID:"/, "", essid)
        sub(/".*$/, "", essid)
        next
      }
      /Frequency:.*GHz/ && /Access Point:/ {
        if (essid != ssid) next
        freq=line
        sub(/.*Frequency:/, "", freq)
        sub(/GHz.*$/, "", freq)
        gsub(/^[ \t]+|[ \t]+$/, "", freq)
        if (freq !~ /^5\./) next

        tmp=line
        sub(/.*Access Point:[ \t]*/, "", tmp)
        # tmp now starts with MAC, possibly followed by spaces / extra text
        split(tmp, a, /[ \t]/)
        bssid=a[1]
        if (bssid == "") next
        # normalize to upper case
        bssid=toupper(bssid)
        gsub(/-/, ":", bssid)
        print bssid
        exit
      }
    '
  )"

  # Prefer friendly name > hostname > IP
  if [ -n "$friendly" ]; then
    label="$friendly"
  elif [ -n "$host" ]; then
    label="$host"
  else
    label="$ip"
  fi

  if [ -z "$mac5" ]; then
    mac5="NOT_FOUND"
  fi

  printf "%s,%s,%s\n" "$ip" "$label" "$mac5" >> "$OUT"
}

# Read ips.csv with "ip[,friendly]" format
# Example:
# ip,friendlyName
# 10.0.0.186,MainOfficeAP
# 10.0.1.200,1stGradeAP
exec 3<"$IPFILE"
while IFS= read -r line <&3; do
  # Trim CR
  line="$(echo "$line" | tr -d '\r')"
  # Skip blank or comment lines
  [ -z "$line" ] && continue
  case "$line" in
    \#*) continue ;;
  esac

  # Skip header row if present (starts with "ip," or equals "ip")
  case "$line" in
    ip,*|ip) continue ;;
  esac

  ip=""
  friendly=""

  if printf "%s" "$line" | grep -q ','; then
    ip="$(printf "%s" "$line" | cut -d',' -f1 | tr -d '[:space:]')"
    friendly="$(printf "%s" "$line" | cut -d',' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  else
    ip="$(echo "$line" | tr -d '[:space:]')"
  fi

  [ -z "$ip" ] && continue
  process_ip "$ip" "$friendly"
done
exec 3<&-

echo "Wrote $(wc -l < "$OUT") lines to $OUT"
