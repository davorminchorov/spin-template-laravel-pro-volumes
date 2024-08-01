#!/bin/bash

# Set dependency versions
yq_version="4.44.2"

# Initialize the service variables
horizon=""
queues=""
reverb=""
scheduler=""
sqlite=""
mysql=""
mariadb=""
postgresql=""
redis=""

# Set project variables
project_dir=${SPIN_PROJECT_DIRECTORY:-"$(pwd)/template"}
template_src_dir=${SPIN_TEMPLATE_TEMPORARY_SRC_DIR:-"$(pwd)"}
user_id=${SPIN_USER_ID:-$(id -u)}

###############################################
# Functions
###############################################

display_database_menu() {
    clear
    echo "${BOLD}${YELLOW}What database engine(s) would you like to use?${RESET}"
    echo -e "${sqlite:+$BOLD$BLUE}1) SQLite${RESET}"
    echo -e "${mysql:+$BOLD$BLUE}2) MySQL${RESET}"
    echo -e "${mariadb:+$BOLD$BLUE}3) MariaDB${RESET}"
    echo -e "${postgresql:+$BOLD$BLUE}4) PostgreSQL${RESET}"
    if [[ $horizon ]]; then
        echo -e "${BOLD}${BLUE}5) Redis (Required for Horizon)${RESET}"
    else
        echo -e "${redis:+$BOLD$BLUE}5) Redis${RESET}"
    fi
    echo "Press a number to select/deselect. Press ENTER to continue."
}

display_feature_menu() {
    clear
    echo "${BOLD}${YELLOW}Select which Laravel features you'd like to use:${RESET}"
    echo -e "${horizon:+$BOLD$BLUE}1) Horizon${RESET}"
    echo -e "${queues:+$BOLD$BLUE}2) Queues (without Redis)${RESET}"
    echo -e "${reverb:+$BOLD$BLUE}3) Reverb${RESET}"
    echo -e "${scheduler:+$BOLD$BLUE}4) Task Scheduler${RESET}"
    echo "Press a number to select/deselect."
    echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or skip."
}

merge_blocks() {
    local service_name=$1
    local blocks_dir="$template_src_dir/blocks/$service_name"
    local yq_container_name="spin_yq_$(date +%s)"

    # Clean up the container when the script exits
    trap "docker rm -f $yq_container_name > /dev/null 2>&1" EXIT

    if [[ ! -d $blocks_dir ]]; then
        echo "${BOLD}${RED}The blocks directory for \"$service_name\" does not exist. Exiting...${RESET}"
        echo "Could not find the blocks directory at:"
        echo "$blocks_dir"
        exit 1
    fi

    echo "${BLUE}Updating Docker Compose files for $service_name...${RESET}"

    find "$blocks_dir" -type f \( -name "*.yml" -o -name "*.yaml" \) | while read -r block; do
        # Extract the filename without path and extension
        local filename=$(basename "$block")
        filename="${filename%.*}"
        
        # Determine the destination file
        local destination="${project_dir}/${filename}.yml"
        
        # If the destination file doesn't exist, create it
        if [[ ! -f "$destination" ]]; then
            echo "{}" > "$destination"
        fi
        
        # Get relative paths for Docker volume mounts
        local rel_block=${block#"$template_src_dir/"}
        local rel_destination=${destination#$project_dir/}
        
        # Merge the block into the destination file, appending values
        docker run --name "$yq_container_name" \
            --user $user_id \
            -v "${template_src_dir}:/src_dir" \
            -v "${project_dir}:/dest_dir" \
            "mikefarah/yq:$yq_version" eval-all \
            'select(fileIndex == 0) * select(fileIndex == 1)' \
            "/dest_dir/$rel_destination" "/src_dir/$rel_block" \
            -i
        
        echo "$service_name: Updated ${filename}.yml..."
    done
}

process_selections() {
    echo "Processing your selections..."
    
    for selection in sqlite mysql mariadb postgresql redis horizon queues reverb scheduler; do
        case "$selection" in
            sqlite)
                [[ $sqlite ]] && setup_sqlite
                ;;
            mysql)
                [[ $mysql ]] && setup_mysql
                ;;
            mariadb)
                [[ $mariadb ]] && setup_mariadb
                ;;
            postgresql)
                [[ $postgresql ]] && setup_postgresql
                ;;
            redis)
                [[ $redis ]] && setup_redis
                ;;
            horizon)
                [[ $horizon ]] && setup_horizon
                ;;
            queues)
                [[ $queues ]] && setup_queues
                ;;
            reverb)
                [[ $reverb ]] && setup_reverb
                ;;
            scheduler)
                [[ $scheduler ]] && setup_scheduler
                ;;
        esac
    done
    
    echo "Service set up complete!"
}

set_colors() {
    if [[ -t 1 ]]; then
        RAINBOW="
            $(printf '\033[38;5;196m')
            $(printf '\033[38;5;202m')
            $(printf '\033[38;5;226m')
            $(printf '\033[38;5;082m')
            "
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        YELLOW=$(printf '\033[33m')
        BLUE=$(printf '\033[34m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[m')
    else
        RAINBOW=""
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        BOLD=""
        RESET=""
    fi
}

setup_horizon() {
    merge_blocks "horizon"
}

setup_mariadb() {
    merge_blocks "mariadb"
}

setup_mysql() {
    merge_blocks "mysql"
}

setup_postgresql() {
    merge_blocks "postgresql"
}

setup_queues() {
    merge_blocks "queues"
}

setup_redis() {
    merge_blocks "redis"
}

setup_reverb() {
    merge_blocks "reverb"
}

setup_scheduler() {
    merge_blocks "scheduler"
}

setup_sqlite() {
    merge_blocks "sqlite"
}

###############################################
# Main
###############################################

set_colors

# Feature selection loop
while true; do
    display_feature_menu
    read -s -n 1 key
    case $key in
        1) 
            if [[ $horizon ]]; then
                horizon=""
                redis=""
            else
                horizon="1"
                redis="1"
            fi
            ;;
        2) [[ $queues ]] && queues="" || queues="1" ;;
        3) [[ $reverb ]] && reverb="" || reverb="1" ;;
        4) [[ $scheduler ]] && scheduler="" || scheduler="1" ;;
        '') break ;;
    esac
done

# Database selection loop
while true; do
    display_database_menu
    read -s -n 1 key
    case $key in
        1) [[ $sqlite ]] && sqlite="" || sqlite="1" ;;
        2) [[ $mysql ]] && mysql="" || mysql="1" ;;
        3) [[ $mariadb ]] && mariadb="" || mariadb="1" ;;
        4) [[ $postgresql ]] && postgresql="" || postgresql="1" ;;
        5) 
            if [[ ! $horizon ]]; then
                [[ $redis ]] && redis="" || redis="1"
            fi
            ;;
        '') 
            if [[ $horizon && ! $redis ]]; then
                echo -e "${RED}Redis is required for Horizon. Redis has been automatically selected.${RESET}"
                redis="1"
                read -n 1 -s -r -p "Press any key to continue..."
            else
                break
            fi
            ;;
    esac
done

# Clean up the screen before moving forward
clear

process_selections