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
use_github_actions=false

# Set project variables
project_dir=${SPIN_PROJECT_DIRECTORY:-"$(pwd)/template"}
template_src_dir=${SPIN_TEMPLATE_TEMPORARY_SRC_DIR:-"$(pwd)"}
user_id=${SPIN_USER_ID:-$(id -u)}
docker_compose_database_migration="false"

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
    if ! grep -q "import fs from 'fs';" "$file"; then
        sed_inplace "1s/^/import fs from 'fs';\n/" "$file"
    fi

    # Update or add server configuration using awk
    awk '
    BEGIN { server_added = 0 }
    /^import .* from/ { print; next }
    /^export default defineConfig\({/ {
        print
        print "    server: {"
        print "        host: '"'"'0.0.0.0'"'"',"
        print "        hmr: {"
        print "            host: '"'"'vite.dev.test'"'"',"
        print "            clientPort: 443,"
        print "        },"
        print "        https: {"
        print "            key: fs.readFileSync('"'"'/usr/src/app/.infrastructure/conf/traefik/dev/certificates/local-dev-key.pem'"'"'),"
        print "            cert: fs.readFileSync('"'"'/usr/src/app/.infrastructure/conf/traefik/dev/certificates/local-dev.pem'"'"'),"
        print "        },"
        print "    },"
        server_added = 1
        next
    }
    /^});/ && !server_added {
        print "    server: {"
        print "        host: '"'"'0.0.0.0'"'"',"
        print "        hmr: {"
        print "            host: '"'"'vite.dev.test'"'"',"
        print "            clientPort: 443,"
        print "        },"
        print "        https: {"
        print "            key: fs.readFileSync('"'"'/usr/src/app/.infrastructure/conf/traefik/dev/certificates/local-dev-key.pem'"'"'),"
        print "            cert: fs.readFileSync('"'"'/usr/src/app/.infrastructure/conf/traefik/dev/certificates/local-dev.pem'"'"'),"
        print "        },"
        print "    },"
    }
    { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

    echo "Vite configuration updated successfully."
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

display_github_actions_menu() {
    clear
    echo "${BOLD}${YELLOW}Would you like to use GitHub Actions?${RESET}"
    if [ "$use_github_actions" = true ]; then
        echo -e "${BOLD}${BLUE}1) Yes${RESET}"
        echo "2) No"
    else
        echo "1) Yes"
        echo -e "${BOLD}${BLUE}2) No${RESET}"
    fi
    echo "Press a number to select/deselect."
    echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue."
}

initialize_database_service() {
    stop_running_containers

    echo "${BOLD}${YELLOW}🔄 Initializing the database service...${RESET}"
    cd "$project_dir" || exit
    $COMPOSE_CMD up -d --remove-orphans --build

    trap '$COMPOSE_CMD down --volumes --remove-orphans > /dev/null 2>&1' EXIT
    echo "${BOLD}${YELLOW}🔄 Running migrations...${RESET}"
    $COMPOSE_CMD run --rm --remove-orphans --no-deps \
    -e "AUTORUN_ENABLED=true" \
    -e "AUTORUN_LARAVEL_CONFIG_CACHE=false" \
    -e "AUTORUN_LARAVEL_EVENT_CACHE=false" \
    -e "AUTORUN_LARAVEL_ROUTE_CACHE=false" \
    -e "AUTORUN_LARAVEL_VIEW_CACHE=false" \
    -e "SHOW_WELCOME_MESSAGE=false" \
    -e "S6_VERBOSITY=0" \
    php \
    true

    echo "✅ Migrations completed successfully!${RESET}"
}

install_node_dependencies() {
    local reinstall

    if [[ ! -d "$project_dir" ]]; then
        echo "Error: Project directory '$project_dir' does not exist." >&2
        return 1
    fi

    # if [[ -d "$project_dir/node_modules" ]]; then
    #     echo "Existing node_modules directory found."
    #     while true; do
    #         read -rp "Would you like to reinstall node dependencies with yarn? (y/n) " reinstall
    #         case $reinstall in
    #             [Yy]) 
    #                 echo "Reinstalling node dependencies with yarn..."
    #                 if ! rm -rf "$project_dir/node_modules"; then
    #                     echo "Error: Failed to remove existing node_modules directory." >&2
    #                     return 1
    #                 fi
    #                 break
    #                 ;;
    #             [Nn]) 
    #                 echo "Skipping reinstallation."
    #                 return 0
    #                 ;;
    #             *) 
    #                 echo "Please answer y or n."
    #                 ;;
    #         esac
    #     done
    # fi

    if ! cd "$project_dir"; then
        echo "Error: Failed to change to project directory '$project_dir'." >&2
        return 1
    fi

    echo "${BOLD}${YELLOW}🔄 Installing Node dependencies with yarn...${RESET}"
    if ! $COMPOSE_CMD run --no-deps --rm --remove-orphans node yarn install; then
        echo "${BOLD}${RED}Error: Failed to install node dependencies.${RESET}" >&2
        return 1
    fi

    echo "Node dependencies installed successfully."
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

    echo "${BLUE}Updating files for $service_name...${RESET}"

    find "$blocks_dir" -type f | while read -r block; do
        # Extract the relative path of the file within the blocks directory
        local rel_path=${block#"$blocks_dir/"}
        
        # Determine the destination file
        local destination="${project_dir}/${rel_path}"
        
        # Create the destination directory if it doesn't exist
        mkdir -p "$(dirname "$destination")"
        
        # Check if the file is a YAML file
        if [[ "$block" =~ \.(yml|yaml)$ ]]; then
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
            
            echo "$service_name: Updated ${rel_path}"
        else
            # For non-YAML files, simply copy the file
            cp "$block" "$destination"
            echo "$service_name: Copied ${rel_path}"
        fi
    done
}

process_selections() {
    echo "Preparing your project..."
    
    for selection in sqlite mysql mariadb postgresql redis horizon queues reverb schedule github_actions; do
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
            github_actions)
                [[ $use_github_actions ]] && setup_github_actions
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

setup_github_actions() {
    local service_name="github-actions"
    merge_blocks "$service_name"
}

setup_horizon() {
    local service_name="horizon"
    local current_dir=$(pwd)

    cd "$project_dir" || { echo "Failed to change to project directory"; return 1; }

    echo "$service_name: Installing Horizon dependencies..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" php composer --verbose --working-dir=/var/www/html/ require laravel/horizon

    cd "$current_dir" || { echo "Failed to return to original directory"; return 1; }

    merge_blocks "$service_name"
    
}

setup_mariadb() {
    docker_compose_database_migration="true"
    local service_name="mariadb"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=mysql"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_HOST" "DB_HOST=mariadb"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PORT" "DB_PORT=3306"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_USERNAME" "DB_USERNAME=root"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PASSWORD" "DB_PASSWORD=rootpassword"
}

setup_mysql() {
    docker_compose_database_migration="true"
    local service_name="mysql"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=mysql"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_HOST" "DB_HOST=mysql"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PORT" "DB_PORT=3306"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_USERNAME" "DB_USERNAME=root"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PASSWORD" "DB_PASSWORD=rootpassword"
}

setup_postgresql() {
    docker_compose_database_migration="true"
    local service_name="postgres"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=pgsql"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_HOST" "DB_HOST=postgres"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PORT" "DB_PORT=5432"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_USERNAME" "DB_USERNAME=postgres"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_PASSWORD" "DB_PASSWORD=postgrespassword"
}

setup_queues() {
    merge_blocks "queues"
}

setup_redis() {
    local service_name="redis"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "REDIS_HOST" "REDIS_HOST=redis"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "REDIS_PASSWORD" "REDIS_PASSWORD=redispassword"
}

setup_reverb() {
    local service_name="reverb"
    merge_blocks "$service_name"

    cd "$project_dir" || { echo "Failed to change to project directory"; return 1; }

    echo "$service_name: Installing and configuring Laravel Reverb..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" php php artisan install:broadcasting --without-node

    echo "$service_name: Installing Laravel Reverb node dependencies..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps node yarn add --dev laravel-echo pusher-js
    $COMPOSE_CMD run --rm --remove-orphans --no-deps node yarn run build

    echo "$service_name: Preparing env files for Reverb..."
    line_in_file --action replace --file ".env" "REVERB_HOST" "REVERB_HOST=\"reverb.dev.test\""
    line_in_file --action replace --file ".env" "REVERB_PORT" "REVERB_PORT=443"
    line_in_file --action replace --file ".env" "REVERB_SCHEME" "REVERB_SCHEME=https"

    # Update ENV example file only
    line_in_file --action replace --file ".env.example" "REVERB_APP_ID" "REVERB_APP_ID=999999"
    line_in_file --action replace --file ".env.example" "REVERB_APP_KEY" "REVERB_APP_KEY=changemeabcde1234567"
    line_in_file --action replace --file ".env.example" "REVERB_APP_SECRET" "REVERB_APP_SECRET=changeme123456789abcde"
    line_in_file --action replace --file ".env.example" "VITE_REVERB_APP_KEY" "VITE_REVERB_APP_KEY=\"\${REVERB_APP_KEY}\""
    line_in_file --action replace --file ".env.example" "VITE_REVERB_HOST" "VITE_REVERB_HOST=\"\${REVERB_HOST}\""
    line_in_file --action replace --file ".env.example" "VITE_REVERB_PORT" "VITE_REVERB_PORT=\"\${REVERB_PORT}\""
    line_in_file --action replace --file ".env.example" "VITE_REVERB_SCHEME" "VITE_REVERB_SCHEME=\"\${REVERB_SCHEME}\""

    cd "$current_dir" || { echo "Failed to return to original directory"; return 1; }
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
        line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=sqlite"
        line_in_file --action after --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_DATABASE=/var/www/html/.infrastructure/volume_data/sqlite/database.sqlite"

        # Run the migrations to create the SQLite database
        docker run --rm -v "$project_dir:/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" "$SPIN_PHP_DOCKER_IMAGE" php /var/www/html/artisan migrate --force
    fi
}

stop_running_containers() {
    local running_containers
    running_containers=$(docker ps -q)

    echo "Checking for running containers..."    
    if [[ -n "$running_containers" ]]; then
        clear
        echo "${BOLD}${YELLOW}The following containers are currently running:${RESET}"
        if ! docker ps --format "table {{.Names}}\t{{.Ports}}"; then
            echo "Error: Failed to list running containers."
            return 1
        fi
        
        local answer
        read -r -p $'\n'"${BOLD}${YELLOW}Do you want to stop all running containers? (y/n): ${RESET}" answer
        
        if [[ $answer =~ ^[Yy]$ ]]; then
            echo "Stopping all running containers..."
            if ! docker stop $running_containers; then
                echo "Error: Failed to stop some or all containers."
                return 1
            fi
        else
            echo "Exiting. Please stop the containers manually before proceeding."
            return 1
        fi
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

# GitHub Actions selection loop
while true; do
    display_github_actions_menu
    read -s -r -n 1 key
    case $key in
        1) use_github_actions=true ;;
        2) use_github_actions=false ;;
        '') break ;;
    esac
done

# Clean up the screen before moving forward
clear

process_selections
configure_vite
line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "APP_URL" "APP_URL=https://laravel.dev.test"
prompt_and_update_file \
    --title "🔐 Configure Let's Encrypt" \
    --details "Let's Encrypt requires an email address to send notifications about SSL renewals." \
    --prompt "Please enter your email" \
    --file "$project_dir/.infrastructure/conf/traefik/prod/traefik.yml" \
    --search-default "changeme@example.com" \
    --success-msg "Updated \".infrastructure/conf/traefik/prod/traefik.yml\" with your email."

# Install npm dependencies

install_node_dependencies

if [[ "$docker_compose_database_migration" == "true" ]]; then
    initialize_database_service
fi

# Export actions so it's available to the main Spin script
export SPIN_USER_TODOS