#!/bin/bash

# Variables
LOG_DIR="/tmp/"
TARGET_MCR_VERSION="23.0.13"
LOG_FILE="$LOG_DIR/mcr_node_upgrade_$(date +%Y%m%d-%H_%M_%S).log"
REPO_FILE="/etc/yum.repos.d/docker-ee.repo"
SSH_USER="testuser"
SLEEP_DURATION=1
STABLE_REPO="docker-ee-stable-23.0"
DRY_RUN=false  # Default is not a dry-run
NODE_ROLE=""   # Node role to be set from --node-role flag

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Function to check if it's a dry run
run_command() {
    local CMD=$1
    local NODE=$2
    if [ "$DRY_RUN" = true ]; then
        log_message "Dry-run: Would run on $NODE: $CMD"
    else
        ssh $SSH_USER@$NODE "$CMD" 2>&1 | tee -a $LOG_FILE
    fi
}

# Function to enable the repo
enable_repo() {
    local NODE=$1
    log_message "Enabling the $STABLE_REPO repo on $NODE..."
    run_command "dzdo sed -i '/\[$STABLE_REPO\]/,/enabled=/s/enabled=[01]/enabled=1/' $REPO_FILE" $NODE
    log_message "Checking the repo after enabling on $NODE..."
    run_command "dzdo tail -8 $REPO_FILE" $NODE
}

# Function to disable the repo
disable_repo() {
    local NODE=$1
    log_message "Disabling the $STABLE_REPO repo on $NODE..."
    run_command "dzdo sed -i '/\[$STABLE_REPO\]/,/enabled=/s/enabled=[01]/enabled=0/' $REPO_FILE" $NODE
    log_message "Checking the repo after disabling on $NODE..."
    run_command "dzdo tail -8 $REPO_FILE" $NODE
}

# Function to fetch nodes based on role and Docker version
get_nodes() {
    local ROLE_FILTER=$1
    docker node ls --filter "role=$ROLE_FILTER" --format "{{.ID}}" | while read node_id; do
        version=$(docker node inspect $node_id --format '{{.Description.Engine.EngineVersion}}')
        if [ "$version" = "23.0.10" ]; then
            docker node inspect --format '{{.Description.Hostname}}' $node_id
        fi
    done
}

# Function to run the upgrade process
run_upgrade() {
    local NODES=$1

    for NODE in $NODES; do
        echo "------------------------------------- $NODE Activity Started -----------------------------------" | tee -a $LOG_FILE

        log_message "Starting upgrade on node: $NODE"
        
        # Enable the repo
        enable_repo $NODE

        # Check the upgrade process
        log_message "Checking the upgrade process on $NODE with '--assumeno'..."
        run_command "dzdo yum upgrade docker-ee-$TARGET_MCR_VERSION docker-ee-cli-$TARGET_MCR_VERSION containerd.io --assumeno" $NODE

        # Perform the actual upgrade
        log_message "Performing the actual upgrade on $NODE..."
        run_command "dzdo yum upgrade docker-ee-$TARGET_MCR_VERSION docker-ee-cli-$TARGET_MCR_VERSION containerd.io -y" $NODE

        # Disable the repo
        disable_repo $NODE

        # Restart Docker
        log_message "Restarting Docker on the node: $NODE"
        run_command "dzdo systemctl restart docker" $NODE
        sleep 5
        run_command "dzdo systemctl status docker" $NODE
        run_command "dzdo docker ps -a" $NODE

        log_message "Waiting for $SLEEP_DURATION seconds before proceeding to the next node..."
        sleep $SLEEP_DURATION

        echo "------------------------------------- $NODE Activity Ended -----------------------------------" | tee -a $LOG_FILE
    done
}

# Display help
display_help() {
    echo "Usage: $0 --node-role <worker|manager|all> [--dry-run] [--help]"
    echo
    echo "   --node-role  Mandatory. Specify node role to upgrade. Options: worker, manager, all"
    echo "   --dry-run    Optional. Run the script in dry-run mode (show what would be done)."
    echo "   --help       Optional. Show this help message."
}

# Parse arguments
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do
    case $1 in
        --dry-run )
            DRY_RUN=true
            ;;
        --node-role )
            shift
            NODE_ROLE=$1
            ;;
        --help )
            display_help
            exit 0
            ;;
    esac
    shift
done

# Check if --node-role is provided
if [ -z "$NODE_ROLE" ]; then
    echo "Error: --node-role is mandatory."
    display_help
    exit 1
fi

# Main Logic
log_message "Fetching list of nodes based on the role: $NODE_ROLE"

if [ "$NODE_ROLE" = "all" ]; then
    NODES=$(docker node ls --format "{{.Hostname}}")
else
    NODES=$(get_nodes $NODE_ROLE)
fi

log_message "Nodes found: $NODES"

# Execute upgrade if nodes are found
if [ -n "$NODES" ]; then
    run_upgrade "$NODES"
else
    log_message "No nodes found with the specified role and Docker version."
fi

