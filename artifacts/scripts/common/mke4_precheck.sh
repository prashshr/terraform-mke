#!/usr/bin/env bash
################################################################################
# MKE 4.2.0 Network Connectivity Check
# Default: Test connectivity only. Optional: Start listeners with --with-listeners
################################################################################

if [ -z "$BASH_VERSION" ]; then
  echo "Error: This script requires bash. Run with: bash $0 $*" >&2
  exit 1
fi

set -u
set -o pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Colored output functions
log_ok() { echo -e "${GREEN}[✓]${NC} $*"; }
log_fail() { echo -e "${RED}[✗]${NC} $*"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }

# Parse arguments
usage() {
  cat << EOF
Usage: $0 <nodes_file> <ssh_user> <ssh_key> [--with-listeners]

Arguments:
  nodes_file        File with list of node IPs/hostnames (one per line)
  ssh_user          SSH username for connecting to nodes
  ssh_key           Path to SSH private key file

Options:
  --with-listeners  Start temporary socat listeners for port testing
  --help            Show this help message
  
Examples:
  # Test existing services only (default)
  $0 list_hosts.txt ec2-user /path/to/key.pem

  # Test with temporary listeners
  $0 list_hosts.txt ec2-user /path/to/key.pem --with-listeners

  # Show help
  $0 --help

Notes:
  - Default mode tests only existing services (SSH, etc.)
  - With --with-listeners flag, socat is installed and listeners started
  - Listeners are automatically cleaned up on exit
  - Requires SSH access to all nodes with passwordless sudo

EOF
  exit 0
}

# Check for help flag in ANY position
for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    usage
  fi
done

# Then check required arguments
if [[ $# -lt 3 ]]; then
  log_fail "Missing required arguments"
  echo ""
  usage
fi

nodes_file="$1"
ssh_user="$2"
ssh_key="$3"
use_listeners=0

if [[ ${4:-} == "--with-listeners" ]]; then
  use_listeners=1
fi

# Validate inputs
if [[ ! -f "$nodes_file" ]]; then
  log_fail "Nodes file not found: $nodes_file"
  exit 1
fi

if [[ ! -f "$ssh_key" ]]; then
  log_fail "SSH key not found: $ssh_key"
  exit 1
fi

# SSH connection options (used throughout)
SSH_OPTS=(-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$ssh_key" -l "$ssh_user")

tcp_ports=(22 443 2380 6443 9443 10250 33000 33001)
declare -a nodes=()
declare -A socat_available=()
cleanup_in_progress=0

mkdir -p mke4_port_check_output

cleanup() {
  [[ $cleanup_in_progress -eq 1 ]] && return
  cleanup_in_progress=1
  
  if [[ $use_listeners -eq 1 ]]; then
    echo ""
    log_info "CLEANUP: Killing socat listeners..."
    
    local max_retries=2
    local attempt=0
    local cleanup_ok=0
    
    while [[ $attempt -lt $max_retries && $cleanup_ok -eq 0 ]]; do
      ((attempt++))
      
      # Kill socat on all nodes in parallel
      local pids=()
      for node in "${nodes[@]}"; do
        ssh "${SSH_OPTS[@]}" "$node" "
          # Kill all socat processes by name
          pkill -9 socat 2>/dev/null || true
          # Belt-and-suspenders: kill any process still bound to our ports
          for port in ${tcp_ports[*]}; do
            pids_to_kill=\$(ss -tlnp \"sport = :\$port\" 2>/dev/null | grep -o 'pid=[0-9]*' | sed 's/pid=//' 2>/dev/null || true)
            for pid in \$pids_to_kill; do
              kill -9 \$pid 2>/dev/null || true
            done
          done
        " 2>/dev/null &
        pids+=($!)
      done
      
      # Wait for all kills to complete
      for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
      done
      
      # Verify cleanup — two methods: process check + port check
      sleep 1
      cleanup_ok=1
      for node in "${nodes[@]}"; do
        # Method 1: check for any remaining socat processes
        socat_check=$(ssh "${SSH_OPTS[@]}" "$node" \
          "pgrep socat 2>/dev/null | wc -l" 2>/dev/null) || socat_check="0"
        
        if [[ "$socat_check" != "0" && "$socat_check" != "" ]]; then
          log_warn "Node $node: $socat_check socat processes remain (attempt $attempt/$max_retries)"
          cleanup_ok=0
        fi
        
        # Method 2: check that our ports are free
        for port in "${tcp_ports[@]}"; do
          port_in_use=$(ssh "${SSH_OPTS[@]}" "$node" \
            "ss -tlnp \"sport = :$port\" 2>/dev/null | grep -c socat" 2>/dev/null) || port_in_use="0"
          if [[ "$port_in_use" != "0" ]]; then
            log_warn "Node $node: port $port still has socat bound (attempt $attempt/$max_retries)"
            cleanup_ok=0
          fi
        done
      done
      
      if [[ $cleanup_ok -eq 0 && $attempt -lt $max_retries ]]; then
        log_info "Retrying cleanup..."
        sleep 1
      fi
    done
    
    if [[ $cleanup_ok -eq 1 ]]; then
      log_ok "All listeners cleaned up — ports are free"
    else
      log_warn "WARNING: Some socat processes may still be running"
      log_warn "Manually verify: ssh <node> 'pgrep -a socat && ss -tlnp | grep socat'"
      log_warn "Manual kill:    ssh <node> 'pkill -9 socat'"
    fi
  fi
}

trap cleanup EXIT INT TERM HUP

log_info "Parsing $nodes_file..."
while read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  host=$(echo "$line" | awk '{print $1}')
  [[ -n "$host" ]] && nodes+=("$host")
done < "$nodes_file"

log_ok "Found ${#nodes[@]} nodes: ${nodes[*]}"
echo ""

# Test SSH
log_info "Testing SSH connectivity..."
for node in "${nodes[@]}"; do
  if timeout 5 ssh "${SSH_OPTS[@]}" "$node" "echo OK" >/dev/null 2>&1; then
    log_ok "$node"
  else
    log_fail "$node FAILED"
  fi
done
echo ""

# Handle listener startup if flag is set
if [[ $use_listeners -eq 1 ]]; then
  # ============================================================
  # Check socat availability
  # ============================================================
  log_info "Checking for socat (listener tool)..."
  missing_count=0

  for node in "${nodes[@]}"; do
    if ssh "${SSH_OPTS[@]}" "$node" "command -v socat >/dev/null 2>&1" >/dev/null 2>&1; then
      log_ok "$node has socat"
      socat_available["$node"]="yes"
    else
      log_warn "$node missing socat"
      socat_available["$node"]="no"
      ((missing_count++))
    fi
  done
  echo ""

  # Prompt to install socat if missing
  if [[ $missing_count -gt 0 ]]; then
    log_info "socat is required for listener-based port testing"
    log_info "Detected missing socat on $missing_count node(s)"
    echo ""
    
    read -p "Install socat on missing nodes? (y/n): " install_choice
    
    if [[ "$install_choice" =~ ^[yY]$ ]]; then
      log_info "Installing socat on nodes..."
      
      for node in "${nodes[@]}"; do
        if [[ "${socat_available["$node"]}" == "no" ]]; then
          log_info "Installing on $node..."
          
          # Detect OS and install
          os_type=$(ssh "${SSH_OPTS[@]}" "$node" \
            "cat /etc/os-release 2>/dev/null | grep '^ID=' | cut -d= -f2 | tr -d '\"'" 2>/dev/null) || os_type="unknown"
          
          case "$os_type" in
            rhel|centos|fedora|rocky|alma)
              install_cmd="sudo yum install -y socat"
              ;;
            ubuntu|debian)
              install_cmd="sudo apt-get update && sudo apt-get install -y socat"
              ;;
            alpine)
              install_cmd="apk add socat"
              ;;
            *)
              log_warn "Unknown OS type: $os_type on $node"
              continue
              ;;
          esac
          
          echo "  OS: $os_type"
          
          if ssh "${SSH_OPTS[@]}" "$node" "$install_cmd" >/dev/null 2>&1; then
            log_ok "socat installed"
            socat_available["$node"]="yes"
          else
            log_fail "Installation failed"
            socat_available["$node"]="no"
          fi
        fi
      done
      echo ""
    else
      log_info "Skipping socat installation - proceeding without listeners"
      use_listeners=0
    fi
  fi

  # Check if we have socat on all nodes
  if [[ $use_listeners -eq 1 ]]; then
    all_have_socat=1
    for node in "${nodes[@]}"; do
      if [[ "${socat_available["$node"]}" != "yes" ]]; then
        all_have_socat=0
        break
      fi
    done

    if [[ $all_have_socat -eq 0 ]]; then
      log_warn "Socat not available on all nodes - skipping listener startup"
      use_listeners=0
    fi
  fi

  # Start listeners if socat is available on all nodes
  if [[ $use_listeners -eq 1 ]]; then
    # Pre-flight cleanup: kill any leftover socat from previous runs
    log_info "Pre-flight: Cleaning up any existing socat processes..."
    for node in "${nodes[@]}"; do
      ssh "${SSH_OPTS[@]}" "$node" "pkill -9 socat 2>/dev/null || true" 2>/dev/null || true
    done
    sleep 1
    log_ok "Pre-flight cleanup done"
    
    log_info "Starting socat listeners on ports..."
    
    for node in "${nodes[@]}"; do
      for port in "${tcp_ports[@]}"; do
        ssh "${SSH_OPTS[@]}" "$node" \
          "nohup socat TCP-LISTEN:$port,reuseaddr,fork /dev/null >/dev/null 2>&1 &" 2>/dev/null || true
      done
    done
    
    # Wait longer for all listeners to bind
    log_info "Waiting 3 seconds for listeners to bind..."
    sleep 3
    
    # Verify listeners are running
    log_info "Verifying listeners..."
    total_listeners=0
    for node in "${nodes[@]}"; do
      # Count socat processes (robust method)
      socat_count=$(ssh "${SSH_OPTS[@]}" "$node" \
        "pgrep socat 2>/dev/null | wc -l" 2>/dev/null) || socat_count="0"
      
      # Also try to verify by testing localhost connection
      listening_ports=0
      for port in "${tcp_ports[@]}"; do
        if ssh "${SSH_OPTS[@]}" "$node" \
           "timeout 1 bash -c 'echo >/dev/tcp/127.0.0.1/$port' 2>/dev/null" >/dev/null 2>&1; then
          ((listening_ports++))
        fi
      done
      
      if [[ "$socat_count" -gt 0 ]]; then
        log_ok "$node: $socat_count socat processes, $listening_ports ports responding"
        ((total_listeners+=socat_count))
      else
        log_warn "$node: No socat processes found"
      fi
    done
    
    if [[ $total_listeners -gt 0 ]]; then
      log_ok "Listeners started successfully"
    else
      log_warn "No listeners detected - may be already in use or socat failed"
    fi
    echo ""
  fi
else
  log_warn "Listener startup disabled (default mode)"
  log_info "Testing only existing port accessibility"
  echo ""
fi

# ============================================================
# PHASE 1: Jumphost → Nodes
# ============================================================
log_info "========== PHASE 1: Jumphost → Nodes =========="
pass_ph1=0
fail_ph1=0

for node in "${nodes[@]}"; do
  for port in "${tcp_ports[@]}"; do
    if timeout 1 bash -c "echo >/dev/tcp/$node/$port" 2>/dev/null; then
      log_ok "jumphost → $node:$port"
      ((pass_ph1++))
    else
      log_fail "jumphost → $node:$port"
      ((fail_ph1++))
    fi
  done
done
echo ""

# ============================================================
# PHASE 2: Node → Node
# ============================================================
log_info "========== PHASE 2: Node → Node =========="
pass_ph2=0
fail_ph2=0

for src in "${nodes[@]}"; do
  for dst in "${nodes[@]}"; do
    [[ "$src" == "$dst" ]] && continue
    
    for port in "${tcp_ports[@]}"; do
      if ssh "${SSH_OPTS[@]}" "$src" \
         "timeout 1 bash -c 'echo >/dev/tcp/$dst/$port' 2>/dev/null" >/dev/null 2>&1; then
        log_ok "$src → $dst:$port"
        ((pass_ph2++))
      else
        log_fail "$src → $dst:$port"
        ((fail_ph2++))
      fi
    done
  done
done
echo ""

# ============================================================
# Summary
# ============================================================
total_pass=$((pass_ph1 + pass_ph2))
total_fail=$((fail_ph1 + fail_ph2))

echo "=================================="
log_info "SUMMARY"
echo "=================================="
echo ""

if [[ $use_listeners -eq 1 ]]; then
  log_ok "Listener-based testing (socat enabled)"
else
  log_warn "Service-based testing (listeners disabled)"
  log_info "Only existing services tested"
fi

echo ""
echo "Jumphost → Nodes: $pass_ph1 OPEN, $fail_ph1 CLOSED"
echo "Node → Node:      $pass_ph2 OPEN, $fail_ph2 CLOSED"
echo ""
echo "Total: $total_pass OPEN, $total_fail CLOSED"
echo "=================================="

[[ $total_fail -gt 0 ]] && exit 1
exit 0
