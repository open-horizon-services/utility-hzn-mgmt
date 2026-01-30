#!/bin/bash

# Script to monitor Open Horizon nodes in real-time (like 'top' utility)
# Usage: ./monitor-nodes.sh [OPTIONS] [ENV_FILE]

# Strict error handling
set -euo pipefail

# Default configuration
REFRESH_INTERVAL=10
USER_ID=""
NO_COLOR=false
ONCE_MODE=false
JSON_ONLY=false
VERBOSE=false
ENV_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -u|--user)
            USER_ID="$2"
            shift 2
            ;;
        -n|--no-color)
            NO_COLOR=true
            shift
            ;;
        -1|--once)
            ONCE_MODE=true
            shift
            ;;
        -j|--json)
            JSON_ONLY=true
            ONCE_MODE=true  # JSON mode implies once
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            export VERBOSE
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [ENV_FILE]"
            echo ""
            echo "Monitor Open Horizon nodes in real-time (like 'top' utility)"
            echo ""
            echo "Options:"
            echo "  -i, --interval SECONDS   Refresh interval in seconds (default: 10)"
            echo "  -u, --user USER_ID       Monitor nodes for specific user (default: authenticated user)"
            echo "  -n, --no-color           Disable color output"
            echo "  -1, --once               Run once and exit (no continuous monitoring)"
            echo "  -j, --json               Output JSON format (implies --once)"
            echo "  -v, --verbose            Show detailed information"
            echo "  -h, --help               Show this help message"
            echo ""
            echo "Arguments:"
            echo "  ENV_FILE                 Optional: Path to .env file (e.g., mycreds.env)"
            echo "                           If not provided, will prompt for selection"
            echo ""
            echo "Examples:"
            echo "  $0                       # Monitor with defaults (10s refresh)"
            echo "  $0 -i 5                  # Refresh every 5 seconds"
            echo "  $0 -u myuser             # Monitor specific user's nodes"
            echo "  $0 --once                # Run once and exit"
            echo "  $0 --json mycreds.env    # JSON output for automation"
            echo ""
            echo "Interactive Controls:"
            echo "  q or Ctrl+C              Exit"
            echo "  r                        Force immediate refresh"
            echo ""
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Non-option argument is env file
            ENV_FILE="$1"
            shift
            ;;
    esac
done

# Validate refresh interval
if ! [[ "$REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || [ "$REFRESH_INTERVAL" -lt 1 ]; then
    echo "Error: Refresh interval must be a positive integer"
    exit 1
fi

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Terminal control functions
hide_cursor() {
    if [ "$ONCE_MODE" = false ] && [ "$JSON_ONLY" = false ]; then
        tput civis 2>/dev/null || true
    fi
}

show_cursor() {
    if [ "$ONCE_MODE" = false ] && [ "$JSON_ONLY" = false ]; then
        tput cnorm 2>/dev/null || true
    fi
}

clear_screen() {
    if [ "$ONCE_MODE" = false ] && [ "$JSON_ONLY" = false ]; then
        clear
    fi
}

# Cleanup function
cleanup() {
    show_cursor
    exit 0
}

# Setup cleanup trap
trap cleanup EXIT INT TERM

# Handle .env file selection and load credentials
selected_file=""
select_env_file "$ENV_FILE" || exit 1
load_credentials "$selected_file" || exit 1

# If USER_ID not provided, extract it from HZN_EXCHANGE_USER_AUTH
if [ -z "$USER_ID" ]; then
    if [[ "$HZN_EXCHANGE_USER_AUTH" == *"/"* ]]; then
        USER_ID="${HZN_EXCHANGE_USER_AUTH#*/}"
        USER_ID="${USER_ID%%:*}"
    else
        USER_ID="${HZN_EXCHANGE_USER_AUTH%%:*}"
    fi
    
    if [ "$JSON_ONLY" = false ]; then
        print_info "No user ID specified, using authenticated user: $USER_ID"
        echo ""
    fi
fi

# Check if curl is installed
check_curl || exit 1

# Check if jq is installed (optional but recommended)
check_jq

# Parse authentication credentials
parse_auth

# Use the Exchange URL as-is
BASE_URL="${HZN_EXCHANGE_URL%/}"

# Construct the full owner identifier
if [[ "$USER_ID" == *"/"* ]]; then
    OWNER_ID="$USER_ID"
else
    OWNER_ID="${HZN_ORG_ID}/${USER_ID}"
fi

# Function to convert ISO 8601 timestamp to seconds since epoch
timestamp_to_seconds() {
    local timestamp="$1"
    # Remove the [UTC] suffix if present
    timestamp="${timestamp%\[UTC\]}"
    # Use date command to parse (works on both Linux and macOS)
    if date -d "$timestamp" +%s 2>/dev/null; then
        return 0
    elif date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%.*}" +%s 2>/dev/null; then
        return 0
    else
        echo "0"
    fi
}

# Function to format time difference as human-readable
format_time_ago() {
    local timestamp="$1"
    local now
    local then_ts
    now=$(date +%s)
    then_ts=$(timestamp_to_seconds "$timestamp")
    
    if [ "$then_ts" -eq 0 ]; then
        echo "unknown"
        return
    fi
    
    local diff=$((now - then_ts))
    
    if [ $diff -lt 0 ]; then
        echo "future"
    elif [ $diff -lt 60 ]; then
        echo "${diff}s ago"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# Function to get color code based on heartbeat age
get_heartbeat_color() {
    local timestamp="$1"
    local now
    local then_ts
    now=$(date +%s)
    then_ts=$(timestamp_to_seconds "$timestamp")
    
    if [ "$NO_COLOR" = true ] || [ "$then_ts" -eq 0 ]; then
        echo ""
        return
    fi
    
    local diff=$((now - then_ts))
    
    if [ $diff -lt 120 ]; then
        # < 2 minutes: Green (active)
        echo "$GREEN"
    elif [ $diff -lt 600 ]; then
        # 2-10 minutes: Yellow (stale)
        echo "$YELLOW"
    else
        # > 10 minutes: Red (inactive)
        echo "$RED"
    fi
}

# Function to fetch and display nodes
fetch_and_display_nodes() {
    # Make the API call
    local response
    response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" \
        "${BASE_URL}/orgs/${HZN_ORG_ID}/nodes?owner=${OWNER_ID}" 2>&1)
    
    # Extract HTTP status code and body
    local http_code
    local response_body
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')
    
    # Check HTTP status code
    if [ "$http_code" -ne 200 ]; then
        if [ "$JSON_ONLY" = false ]; then
            print_error "Failed to fetch nodes (HTTP $http_code)"
            echo ""
            echo "Response: $response_body"
        fi
        return 1
    fi
    
    # Validate JSON
    if ! echo "$response_body" | python3 -m json.tool &> /dev/null; then
        if [ "$JSON_ONLY" = false ]; then
            print_error "Invalid JSON response from API"
        fi
        return 1
    fi
    
    # JSON-only mode: output raw JSON and exit
    if [ "$JSON_ONLY" = true ]; then
        echo "$response_body"
        return 0
    fi
    
    # Parse nodes and extract data
    local node_data=()
    local node_names=()
    
    if [ "$JQ_AVAILABLE" = true ]; then
        while IFS= read -r node; do
            [ -n "$node" ] && node_names+=("$node")
        done < <(echo "$response_body" | jq -r '.nodes | keys[]' 2>/dev/null || echo "")
    else
        while IFS= read -r node; do
            [ -n "$node" ] && node_names+=("$node")
        done < <(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('nodes', {}).keys()))" 2>/dev/null || echo "")
    fi
    
    local total_nodes=${#node_names[@]}
    local active_nodes=0
    local stale_nodes=0
    local inactive_nodes=0
    
    # Extract node details and sort by heartbeat
    for node in "${node_names[@]}"; do
        local heartbeat
        local node_type
        local arch
        local pattern
        local name
        
        if [ "$JQ_AVAILABLE" = true ]; then
            heartbeat=$(echo "$response_body" | jq -r ".nodes[\"$node\"].lastHeartbeat // \"\"" 2>/dev/null)
            node_type=$(echo "$response_body" | jq -r ".nodes[\"$node\"].nodeType // \"device\"" 2>/dev/null)
            arch=$(echo "$response_body" | jq -r ".nodes[\"$node\"].arch // \"unknown\"" 2>/dev/null)
            pattern=$(echo "$response_body" | jq -r ".nodes[\"$node\"].pattern // \"\"" 2>/dev/null)
            name=$(echo "$response_body" | jq -r ".nodes[\"$node\"].name // \"\"" 2>/dev/null)
        else
            heartbeat=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('lastHeartbeat', ''))" 2>/dev/null)
            node_type=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('nodeType', 'device'))" 2>/dev/null)
            arch=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('arch', 'unknown'))" 2>/dev/null)
            pattern=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('pattern', ''))" 2>/dev/null)
            name=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('name', ''))" 2>/dev/null)
        fi
        
        # Calculate heartbeat age for sorting and categorization
        local now
        local then_ts
        now=$(date +%s)
        then_ts=$(timestamp_to_seconds "$heartbeat")
        local age=$((now - then_ts))
        
        # Categorize by age
        if [ $age -lt 120 ]; then
            ((active_nodes++))
        elif [ $age -lt 600 ]; then
            ((stale_nodes++))
        else
            ((inactive_nodes++))
        fi
        
        # Store node data with heartbeat timestamp for sorting
        node_data+=("${then_ts}|${name}|${node_type}|${arch}|${pattern}|${heartbeat}")
    done
    
    # Sort nodes by heartbeat (most recent first)
    local sorted_nodes=()
    while IFS= read -r line; do
        sorted_nodes+=("$line")
    done < <(printf '%s\n' "${node_data[@]}" | sort -t'|' -k1 -rn)
    
    # Display header
    clear_screen
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "Open Horizon Node Monitor - User: $USER_ID, Org: $HZN_ORG_ID"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "Refresh: ${REFRESH_INTERVAL}s | Total: $total_nodes | Active: $active_nodes | Stale: $stale_nodes | Inactive: $inactive_nodes"
    echo "Last Updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    if [ "$total_nodes" -eq 0 ]; then
        echo "No nodes found for user '$USER_ID'"
    else
        # Display table header
        printf "%-25s %-12s %-10s %-8s %-20s\n" \
            "NODE ID" "TYPE" "ARCH" "STATUS" "LAST HEARTBEAT"
        echo "───────────────────────────────────────────────────────────────────────────────"
        
        # Display nodes
        for node_line in "${sorted_nodes[@]}"; do
            IFS='|' read -r timestamp name node_type arch pattern heartbeat <<< "$node_line"
            
            local time_ago
            local color
            local status_color=""
            local status_text=""
            time_ago=$(format_time_ago "$heartbeat")
            color=$(get_heartbeat_color "$heartbeat")
            
            # Determine status based on age
            local now
            now=$(date +%s)
            local age=$((now - timestamp))
            
            if [ $age -lt 120 ]; then
                status_text="Active"
                status_color="$GREEN"
            elif [ $age -lt 600 ]; then
                status_text="Stale"
                status_color="$YELLOW"
            else
                status_text="Inactive"
                status_color="$RED"
            fi
            
            # Display row with color
            if [ "$NO_COLOR" = false ]; then
                printf "%-25s %-12s %-10s ${status_color}%-8s${NC} ${color}%-20s${NC}\n" \
                    "$name" "$node_type" "$arch" "$status_text" "$time_ago"
            else
                printf "%-25s %-12s %-10s %-8s %-20s\n" \
                    "$name" "$node_type" "$arch" "$status_text" "$time_ago"
            fi
        done
    fi
    
    echo ""
    if [ "$ONCE_MODE" = false ]; then
        echo "Press 'q' to quit, 'r' to refresh now"
    fi
    
    return 0
}

# Main monitoring loop
if [ "$ONCE_MODE" = true ]; then
    # Run once and exit
    fetch_and_display_nodes
else
    # Interactive monitoring mode
    hide_cursor
    
    # Initial display
    fetch_and_display_nodes
    
    # Monitoring loop
    while true; do
        # Wait for refresh interval or user input
        if read -r -t "$REFRESH_INTERVAL" -n 1 key 2>/dev/null; then
            case "$key" in
                q|Q)
                    break
                    ;;
                r|R)
                    fetch_and_display_nodes
                    ;;
            esac
        else
            # Timeout reached, refresh display
            fetch_and_display_nodes
        fi
    done
fi

# Cleanup is handled by trap
