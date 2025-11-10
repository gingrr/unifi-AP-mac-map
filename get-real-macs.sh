#!/usr/bin/env bash
# Collect UniFi AP 2.4GHz and 5GHz MACs via sshpass, parsing BusyBox ifconfig.
# Input : ips.txt (one IP per line) in same dir
# Output: wifi_macs.csv (ip,host,mac_24ghz,mac_5ghz_or_status)

set -u  

SSH_USER=""  # <-- SSH username
SSH_PASS=""  # <-- SSH password
SSH_PORT="22"
CONNECT_TIMEOUT="6"
NC_TIMEOUT="3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IPFILE="$SCRIPT_DIR/ips.txt"
OUT="$SCRIPT_DIR/wifi_macs.csv"

[ -f "$IPFILE" ] || { echo "Missing $IPFILE (one IP per line)"; exit 1; }

SSH_OPTS="-o ConnectTimeout=${CONNECT_TIMEOUT} \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password,keyboard-interactive \
  -o NumberOfPasswordPrompts=1 \
  -p ${SSH_PORT}"

port_22_state() {
  local ip="$1"
  if nc -G "$NC_TIMEOUT" -zv "$ip" "$SSH_PORT" >/dev/null 2>&1; then echo "OPEN"; return; fi
  if nc -G "$NC_TIMEOUT" -zv "$ip" "$SSH_PORT" 2>&1 | grep -qiE "timed out|Operation timed out"; then echo "TIMEOUT"; return; fi
  echo "CLOSED"
}

echo "ip,host,mac_24ghz,mac_5ghz_or_status" > "$OUT"

process_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "Skipping non-IP: $ip" >&2; return; }

  case "$(port_22_state "$ip")" in
    OPEN) : ;;
    TIMEOUT) printf "%s,%s,,TIMEOUT_22\n" "$ip" "$ip" >> "$OUT"; return ;;
    CLOSED)  printf "%s,%s,,CLOSED_22\n"  "$ip" "$ip" >> "$OUT"; return ;;
  esac

  # Non-interactive auth probe 
  if ! sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$ip" "echo ok" </dev/null >/dev/null 2>&1; then
    printf "%s,%s,,AUTH_FAILED\n" "$ip" "$ip" >> "$OUT"
    return
  fi

  # BusyBox sh + ifconfig parsing only
  local out
  out="$(sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$ip" 'sh -s' </dev/null <<'REMOTE'
PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"; export PATH

HOST="$( (hostname 2>/dev/null || echo unknown) | tr -d '\r' | tr -d ',' | tr -d '\n' )"

# helper: keep only first 6 octets; normalize to uppercase with colons
fmt6() { awk -F'[: -]' '{ if (NF>=6) printf "%02X:%02X:%02X:%02X:%02X:%02X\n","0x"$1,"0x"$2,"0x"$3,"0x"$4,"0x"$5,"0x"$6 }'; }

MAC24="$(ifconfig wifi0 2>/dev/null | awk '/HWaddr/ {print $NF}' | tr 'a-f' 'A-F' | tr '-' ':' | fmt6)"
MAC5="$( ifconfig wifi1 2>/dev/null | awk '/HWaddr/ {print $NF}' | tr 'a-f' 'A-F' | tr '-' ':' | fmt6)"

# Fallback to ath* heuristic if wifi0/wifi1 missing
if [ -z "$MAC24" ] || [ "$MAC24" = "00:00:00:00:00:00" ]; then
  MAC24="$(ifconfig 2>/dev/null | awk '
    /^ath[0-9]/ {iface=$1}
    /HWaddr/    {gsub("-",
":",$NF); m=toupper($NF); split(m,a,":"); if (length(m)>0) printf "%s:%s:%s:%s:%s:%s %s\n",a[1],a[2],a[3],a[4],a[5],a[6],iface}
  ' | awk '/:24:/ {print $1; exit}')"
fi
if [ -z "$MAC5" ] || [ "$MAC5" = "00:00:00:00:00:00" ]; then
  MAC5="$(ifconfig 2>/dev/null | awk '
    /^ath[0-9]/ {iface=$1}
    /HWaddr/    {gsub("-",
":",$NF); m=toupper($NF); split(m,a,":"); if (length(m)>0) printf "%s:%s:%s:%s:%s:%s %s\n",a[1],a[2],a[3],a[4],a[5],a[6],iface}
  ' | awk '/:25:/ {print $1; exit}')"
fi

# Emit
echo "HOST=$HOST"
echo "MAC24=$MAC24"
echo "MAC5=$MAC5"
REMOTE
)" || out=""

  # Parse returned lines
  local host mac24 mac5
  host="$(printf "%s\n" "$out" | awk -F= '/^HOST=/{print $2}' | tr -d '\r\n,')"
  mac24="$(printf "%s\n" "$out" | awk -F= '/^MAC24=/{print $2}' | tr -d '\r\n')"
  mac5="$( printf "%s\n" "$out" | awk -F= '/^MAC5=/{print $2}'  | tr -d '\r\n')"
  [ -z "$host" ] && host="$ip"
  [ -z "$mac24" ] && mac24="NOT_FOUND"
  [ -z "$mac5" ]  && mac5="NOT_FOUND"

  printf "%s,%s,%s,%s\n" "$ip" "$host" "$mac24" "$mac5" >> "$OUT"
}

# Read ips.txt 
exec 3<"$IPFILE"
while IFS= read -r ip <&3; do
  ip="$(echo "$ip" | tr -d '[:space:]')"
  [ -z "$ip" ] && continue
  process_ip "$ip"
done
exec 3<&-

echo "Wrote $(wc -l < "$OUT") lines to $OUT"