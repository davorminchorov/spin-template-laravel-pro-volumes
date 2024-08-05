#!/bin/bash

# Capture Spin Variables
SPIN_ACTION=${SPIN_ACTION:-"install"}
SPIN_PHP_DOCKER_IMAGE="${SPIN_PHP_DOCKER_IMAGE:-serversideup/php:8.3-cli}"

# Set dependency versions
yq_version="4.44.2"

# Initialize the service variables
horizon=""
queues=""
reverb=""
schedule=""
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

configure_vite() {
    local file="${project_dir}/vite.config.js"

    echo "Vite: Configuring Vite..."

    # Check if the file exists
    if [ ! -f "$file" ]; then
        echo "${RED}Error: $file does not exist.${RESET}"
        return 1
    fi

    # Add import statement if not present
    sed_inplace '/^import laravel/a\
const host = '\''vite.dev.test'\'';
' "$file"

    # Update or add server configuration
    awk '
    BEGIN { found=0; content="    server: {\n      host,\n      hmr: { \n          host,\n          clientPort: 443\n      },\n    },"; }
    /export default defineConfig\({/,/^\});/ {
        if ($0 ~ /server:/) {
            found=1
            print content
            next
        }
    }
    /^\});/ && !found {
        print content
    }
    { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

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
    echo -e "${schedule:+$BOLD$BLUE}4) Task Scheduling${RESET}"
    echo "Press a number to select/deselect."
    echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or skip."
}

merge_blocks() {
    local service_name=$1
    local blocks_dir="$template_src_dir/blocks/$service_name"

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
        docker run --rm \
            --user "$user_id" \
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
    echo "Preparing your project..."
    
    for selection in sqlite mysql mariadb postgresql redis horizon queues reverb schedule; do
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
            schedule)
                [[ $schedule ]] && setup_schedule
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
    local service_name="mariadb"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=mysql"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_HOST" "DB_HOST=mariadb"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PORT" "DB_PORT=3306"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_USERNAME" "DB_USERNAME=root"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PASSWORD" "DB_PASSWORD=rootpassword"
}

setup_mysql() {
    local service_name="mysql"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=mysql"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_HOST" "DB_HOST=mysql"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PORT" "DB_PORT=3306"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_USERNAME" "DB_USERNAME=root"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PASSWORD" "DB_PASSWORD=rootpassword"
}

setup_postgresql() {
    local service_name="postgres"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=pgsql"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_HOST" "DB_HOST=postgres"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PORT" "DB_PORT=5432"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_USERNAME" "DB_USERNAME=postgres"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PASSWORD" "DB_PASSWORD=postgrespassword"
}

setup_queues() {
    merge_blocks "queues"
}

setup_redis() {
    local service_name="redis"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "REDIS_HOST" "REDIS_HOST=redis"
    line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "REDIS_PASSWORD" "REDIS_PASSWORD=redispassword"
}

setup_reverb() {
    merge_blocks "reverb"
}

setup_schedule() {
    merge_blocks "schedule"
}

setup_sqlite() {
    local service_name="sqlite"
    local existing_sqlite_detected=false
    local init_sqlite=true

    merge_blocks "$service_name"

    # Determine SQLite is being used
    if grep -q 'DB_CONNECTION=sqlite' "$SPIN_PROJECT_DIRECTORY/.env"; then
        existing_sqlite_detected=true
    fi

    if [[ "$SPIN_ACTION" == "init" && "$existing_sqlite_detected" == true ]]; then
        echo "${BOLD}${YELLOW}[spin-template-laravel] 👉 We detected SQLite being used on this project.${RESET}"
        echo "${BOLD}${YELLOW}[spin-template-laravel] 👉 We need to update the .env file to use the correct path.${RESET}"
        echo "${BOLD}${YELLOW}[spin-template-laravel] 🚨 This means you may need to manually move your data to the path for the database.${RESET}"
        echo ""
        read -n 1 -r -p "${BOLD}${YELLOW}[spin-template-laravel] 🤔 Would you like us to automatically configure SQLite for you? [Y/n]${RESET} " response

        if [[ $response =~ ^([nN][oO]|[nN])$ ]]; then
            echo ""
            echo "${BOLD}${YELLOW}[spin-template-laravel] 🚨 You will need to manually move your SQLite database to the correct path.${RESET}"
            echo "${BOLD}${YELLOW}[spin-template-laravel] 🚨 The path is: ${RESET}/.infrastructure/volume_data/sqlite/database.sqlite"
            echo ""
            init_sqlite=false
        fi
    fi

    if [ "$init_sqlite" == true ]; then
        # Create the SQLite database folder
        mkdir -p "$project_dir/.infrastructure/volume_data/sqlite"

        echo "$service_name: Updating the Laravel .env and .env.example files..."
        line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=sqlite"
        line_in_file --after --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_DATABASE=/var/www/html/.infrastructure/volume_data/sqlite/database.sqlite"

        # Run the migrations to create the SQLite database
        docker run --rm -v "$project_dir:/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" "$SPIN_PHP_DOCKER_IMAGE" php /var/www/html/artisan migrate --force
    fi
}

###############################################
# Main
###############################################

set_colors

# Feature selection loop
while true; do
    display_feature_menu
    read -s -r -n 1 key
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
        4) [[ $schedule ]] && schedule="" || schedule="1" ;;
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
# configure_vite
line_in_file --replace --file "$project_dir/.env" --file "$project_dir/.env.example" "APP_URL" "APP_URL=https://laravel.dev.test"
prompt_and_update_file \
    --title "Configure Let's Encrypt" \
    --details "Let's Encrypt requires an email address to send notifications about SSL renewals." \
    --prompt "Please enter your email" \
    --file "$project_dir/.infrastructure/conf/traefik/prod/traefik.yml" \
    --search-default "changeme@example.com" \
    --success-msg "Updated \".infrastructure/conf/traefik/prod/traefik.yml\" with your email."