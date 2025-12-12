#!/bin/bash

# Capture Spin Variables
SPIN_ACTION=${SPIN_ACTION:-"install"}
SPIN_PHP_VERSION="${SPIN_PHP_VERSION:-8.5}"
SPIN_PHP_VARIATION="${SPIN_PHP_VARIATION:-fpm-nginx}"
SPIN_PHP_DOCKER_INSTALLER_IMAGE="${SPIN_PHP_DOCKER_INSTALLER_IMAGE:-serversideup/php:${SPIN_PHP_VERSION}-cli}"
SPIN_PHP_DOCKER_BASE_IMAGE="${SPIN_PHP_DOCKER_BASE_IMAGE:-serversideup/php:${SPIN_PHP_VERSION}-fpm-nginx-alpine}"

# Set project variables
spin_template_type="pro"
spin_database="sqlite"
javascript_package_manager="yarn"
php_dockerfile="Dockerfile.php"
project_dir=${SPIN_PROJECT_DIRECTORY:-"$(pwd)/template"}
template_src_dir=${SPIN_TEMPLATE_TEMPORARY_SRC_DIR:-"$(pwd)"}

# Initialize the service variables
horizon=""
queue=""
reverb=""
schedule=""
sqlite=""
mysql=""
mariadb=""
meilisearch=""
postgresql=""
redis=""
octane=""
use_github_actions=""

###############################################
# Functions
###############################################
add_php_extensions() {
    echo "${BLUE}Adding custom PHP extensions...${RESET}"
    local dockerfile="$project_dir/$php_dockerfile"
    
    # Check if Dockerfile exists
    if [ ! -f "$dockerfile" ]; then
        echo "Error: $dockerfile not found."
        return 1
    fi
    
    # Uncomment the USER root line
    line_in_file --action replace --file "$dockerfile" "# USER root" "USER root"
    
    # Add RUN command to install extensions
    local extensions_string="${php_extensions[*]}"
    line_in_file --action replace --file "$dockerfile" "# RUN install-php-extensions" "RUN install-php-extensions $extensions_string"
    
    echo "Custom PHP extensions added."
}

configure_javascript_package_manager() {
    if [ $javascript_package_manager != "yarn" ]; then
        line_in_file --action exact --file "$project_dir/docker-compose.dev.yml" "yarn run dev" "$javascript_package_manager run dev"
    fi
}

configure_sqlite() {
    local service_name="sqlite"
    local init_sqlite=true
    local laravel_default_sqlite_database_path="$project_dir/database/database.sqlite"
    local spin_sqlite_database_path="$project_dir/.infrastructure/volume_data/sqlite/database.sqlite"

    if [[ "$SPIN_ACTION" == "init" ]] && grep -q 'DB_CONNECTION=sqlite' "$SPIN_PROJECT_DIRECTORY/.env"; then
        echo "${BOLD}${RED}⚠️  WARNING ⚠️${RESET}"
        echo "👉 We detected SQLite being used on this project."
        echo "👉 We need to update the .env file to use the correct path."
        echo "${BOLD}${RED}🚨 This means you may need to manually move your data to the path for the database.${RESET}"
        echo ""
        read -n 1 -r -p "${BOLD}${YELLOW} Would you like us to automatically configure SQLite for you? [Y/n]${RESET} " response
        echo ""

        if [[ $response =~ ^([nN][oO]|[nN])$ ]]; then
            echo ""
            echo "${BOLD}${YELLOW}🚨 You will need to manually move your SQLite database to the correct path.${RESET}"
            echo "${BOLD}${YELLOW}🚨 The path is: ${RESET}${spin_sqlite_database_path}"
            echo ""
            init_sqlite=false
            add_user_todo_item "Move your SQLite database to \"${spin_sqlite_database_path}\"."
        fi
    fi

    if [ "$init_sqlite" == true ]; then
        # Create the SQLite database folder
        mkdir -p "$project_dir/.infrastructure/volume_data/sqlite"

        echo "$service_name: Updating the Laravel .env and .env.example files..."
        line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=sqlite"
        line_in_file --action after --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_DATABASE=/var/www/html/.infrastructure/volume_data/sqlite/database.sqlite"

        # Check if the default Laravel SQLite database exists and the Spin SQLite database doesn't
        if [[ -f "$laravel_default_sqlite_database_path" && ! -f "$spin_sqlite_database_path" ]]; then
            echo "${BLUE}Moving existing SQLite database to new location...${RESET}"
            mv "$laravel_default_sqlite_database_path" "$spin_sqlite_database_path"
            echo "SQLite database moved successfully."
        elif [[ ! -f "$laravel_default_sqlite_database_path" && ! -f "$spin_sqlite_database_path" && "$instal" ]]; then
            echo "No existing SQLite database found. Running migrations to create a new one..."
            # Run the migrations to create the SQLite database
            docker run --rm \
                -v "$project_dir:/var/www/html" \
                --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
                -e COMPOSER_CACHE_DIR=/dev/null \
                -e "SHOW_WELCOME_MESSAGE=false" \
                "$SPIN_PHP_DOCKER_INSTALLER_IMAGE" \
                php /var/www/html/artisan migrate --force
        else
            echo "SQLite database already exists in the correct location. Skipping migration."
        fi
    fi
}

initialize_git_repository() {
    local current_dir=""
    current_dir=$(pwd)

    cd "$project_dir" || exit
    echo "Initializing Git repository..."
    git init

    cd "$current_dir" || exit
}

install_node_dependencies() {
    if [[ ! -d "$project_dir" ]]; then
        echo "Error: Project directory '$project_dir' does not exist." >&2
        return 1
    fi

    if ! cd "$project_dir"; then
        echo "Error: Failed to change to project directory '$project_dir'." >&2
        return 1
    fi

    if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
        echo "${BLUE}Installing Node dependencies with ${javascript_package_manager}...${RESET}"
        if ! $COMPOSE_CMD run --no-deps --rm --remove-orphans node ${javascript_package_manager} install; then
            echo "${BOLD}${RED}Error: Failed to install node dependencies.${RESET}" >&2
            return 1
        fi
        echo "Node dependencies installed successfully."
    fi
}

process_selections() { 
    [[ $sqlite ]] && configure_sqlite
    [[ $javascript_package_manager ]] && configure_javascript_package_manager
    if [ "$spin_template_type" = "pro" ]; then
        sleep 0.5  # Small delay before processing service configurations
        [[ $schedule ]] && configure_schedule
        [[ $mysql ]] && configure_mysql
        [[ $mariadb ]] && configure_mariadb
        [[ $postgresql ]] && configure_postgresql
        [[ $redis ]] && configure_redis
        [[ $meilisearch ]] && configure_meilisearch
        [[ $horizon ]] && configure_horizon
        [[ $queue ]] && configure_queue
        [[ $reverb ]] && configure_reverb
        [[ $octane ]] && configure_octane
        [[ $use_github_actions ]] && configure_github_actions
    fi
    echo "Services configured."
}

select_database() {
    local selection_made=false
    while ! $selection_made; do
        clear
        echo "${BOLD}${YELLOW}What database engine(s) would you like to use?${RESET}"
        echo -e "${sqlite:+$BOLD$BLUE}1) SQLite${RESET}"
        if [ "$spin_template_type" = "pro" ]; then
            echo -e "${mysql:+$BOLD$BLUE}2) MySQL${RESET}"
            echo -e "${mariadb:+$BOLD$BLUE}3) MariaDB${RESET}"
            echo -e "${postgresql:+$BOLD$BLUE}4) PostgreSQL${RESET}"
            if [[ $horizon ]]; then
                echo -e "${BOLD}${BLUE}5) Redis (Required for Horizon)${RESET}"
            else
                echo -e "${redis:+$BOLD$BLUE}5) Redis${RESET}"
            fi
        else
            echo -e "${DIM}2) MySQL (Pro)${RESET}"
            echo -e "${DIM}3) MariaDB (Pro)${RESET}"
            echo -e "${DIM}4) PostgreSQL (Pro)${RESET}"
            echo -e "${DIM}5) Redis (Pro)${RESET}"
        fi
        show_spin_pro_notice
        echo "Press a number to select/deselect. Press ${BOLD}${BLUE}ENTER${RESET} to continue."

        read -s -n 1 key
        case $key in
            1) 
                if [[ $sqlite ]]; then
                    sqlite=""
                else
                    sqlite="1"
                fi
                ;;
            2) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $mysql ]] && mysql="" || mysql="1"
                fi
                ;;
            3) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $mariadb ]] && mariadb="" || mariadb="1"
                fi
                ;;
            4) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $postgresql ]] && postgresql="" || postgresql="1"
                fi
                ;;
            5) 
                if [ "$spin_template_type" = "pro" ]; then
                    if [[ ! $horizon ]]; then
                        [[ $redis ]] && redis="" || redis="1"
                    fi
                fi
                ;;
            '') 
                if [ "$spin_template_type" = "pro" ] && [[ $horizon && ! $redis ]]; then
                    echo -e "${RED}Redis is required for Horizon. Redis has been automatically selected.${RESET}"
                    redis="1"
                    read -n 1 -s -r -p "Press any key to continue..."
                else
                    selection_made=true
                fi
                ;;
        esac
    done
}

select_features() {
    while true; do
        clear
        echo "${BOLD}${YELLOW}Select which Laravel features you'd like to use:${RESET}"
        if [ "$spin_template_type" = "pro" ]; then
            echo -e "${schedule:+$BOLD$BLUE}1) Task Scheduling${RESET}"
            echo -e "${horizon:+$BOLD$BLUE}2) Horizon${RESET}"
            echo -e "${queue:+$BOLD$BLUE}3) Queues (without Redis)${RESET}"
            echo -e "${reverb:+$BOLD$BLUE}4) Reverb${RESET}"
            echo -e "${meilisearch:+$BOLD$BLUE}5) Meilisearch${RESET}"
            
            # Octane - only available with FrankenPHP
            if [[ "$SPIN_PHP_VARIATION" == "frankenphp" ]]; then
                echo -e "${octane:+$BOLD$BLUE}6) Laravel Octane${RESET}"
            else
                echo -e "${DIM}6) Laravel Octane (Requires FrankenPHP)${RESET}"
            fi
        else
            echo -e "${DIM}1) Task Scheduling (Pro)${RESET}"
            echo -e "${DIM}2) Horizon (Pro)${RESET}"
            echo -e "${DIM}3) Queues (Pro)${RESET}"
            echo -e "${DIM}4) Reverb (Pro)${RESET}"
            echo -e "${DIM}5) Meilisearch (Pro)${RESET}"
            echo -e "${DIM}6) Laravel Octane (Pro)${RESET}"
        fi
        show_spin_pro_notice
        echo "Press a number to select/deselect."
        echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or skip."

        read -s -r -n 1 key
        case $key in
            1) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $schedule ]] && schedule="" || schedule="1"
                fi
                ;;
            2) 
                if [ "$spin_template_type" = "pro" ]; then
                    if [[ $horizon ]]; then
                        horizon=""
                        redis=""
                    else
                        horizon="1"
                        redis="1"
                    fi
                fi
                ;;
            3) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $queue ]] && queue="" || queue="1"
                fi
                ;;
            4) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $reverb ]] && reverb="" || reverb="1"
                fi
                ;;
            5) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $meilisearch ]] && meilisearch="" || meilisearch="1"
                fi
                ;;
            6) 
                if [ "$spin_template_type" = "pro" ]; then
                    if [[ "$SPIN_PHP_VARIATION" == "frankenphp" ]]; then
                        [[ $octane ]] && octane="" || octane="1"
                    else
                        # Show a helpful message if FrankenPHP is not selected
                        clear
                        echo "${BOLD}${RED}⚠️  FrankenPHP Required${RESET}"
                        echo ""
                        echo "Laravel Octane requires FrankenPHP to be selected as your web server."
                        echo "FrankenPHP was introduced in the first prompt of this setup."
                        echo ""
                        read -n 1 -s -r -p "${BOLD}${YELLOW}Press any key to continue...${RESET}"
                    fi
                fi
                ;;
            '') break ;;
        esac
    done
}

select_github_actions() {
    while true; do
        clear
        echo "${BOLD}${YELLOW}Would you like to use GitHub Actions?${RESET}"
        if [ "$spin_template_type" = "pro" ]; then
            if [ "$use_github_actions" = "1" ]; then
                echo -e "${BOLD}${BLUE}1) Yes${RESET}"
                echo "2) No"
            else
                echo "1) Yes"
                echo -e "${BOLD}${BLUE}2) No${RESET}"
            fi
        else
            echo -e "${DIM}1) Yes (Pro)${RESET}"
            echo -e "${BOLD}${BLUE}2) No${RESET}"
            show_spin_pro_notice
        fi
        echo "Press a number to select/deselect."
        echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue."

        read -s -n 1 key
        case $key in
            1) 
                if [ "$spin_template_type" = "pro" ]; then
                    use_github_actions="1"
                fi
                ;;
            2) use_github_actions="" ;;
            '') break ;;
        esac
    done
}

select_javascript_package_manager() {
    if [ "$spin_template_type" = "pro" ]; then
        while true; do
            clear
            echo "${BOLD}${YELLOW}Choose your JavaScript package manager:${RESET}"
            if [ "$javascript_package_manager" = "yarn" ]; then
                echo -e "${BOLD}${BLUE}1) yarn${RESET}"
                echo "2) npm"
            else
                echo "1) yarn"
                echo -e "${BOLD}${BLUE}2) npm${RESET}"
            fi
            echo "Press a number to select."
            echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue."

            read -s -n 1 key
            case $key in
                1) javascript_package_manager="yarn" ;;
                2) javascript_package_manager="npm" ;;
                '') break ;;
            esac
        done
    else
        # For open-source, only yarn is available
        javascript_package_manager="yarn"
        clear
        echo "${BOLD}${YELLOW}Choose your JavaScript package manager:${RESET}"
        echo -e "${BOLD}${BLUE}1) yarn${RESET}"
        echo -e "${DIM}2) npm (Pro)${RESET}"
        show_spin_pro_notice
        echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or skip."

        read -s -n 1 key
        case $key in
            '') ;;
            *) select_javascript_package_manager ;;
        esac
    fi
}

select_php_extensions() {
    clear
    echo "${BOLD}${YELLOW}What PHP extensions would you like to include?${RESET}"
    echo ""
    echo "${BLUE}Default extensions:${RESET}"
    echo "ctype, curl, dom, fileinfo, filter, hash, mbstring, mysqli,"
    echo "opcache, openssl, pcntl, pcre, pdo_mysql, pdo_pgsql, redis,"
    echo "session, tokenizer, xml, zip"
    echo ""
    echo "${BLUE}See available extensions:${RESET}"
    echo "https://serversideup.net/docker-php/available-extensions"
    echo ""
    echo "Enter additional extensions as a comma-separated list (no spaces).${RESET}"
    echo "Example: gd,imagick,intl"
    echo ""
    echo "${BOLD}${YELLOW}Enter comma separated extensions below or press ${BOLD}${BLUE}ENTER${RESET} ${BOLD}${YELLOW}to use default extensions.${RESET}"
    read -r extensions_input

    # Remove spaces and split into array
    IFS=',' read -r -a php_extensions <<< "${extensions_input// /}"

    # Print selected extensions for confirmation
    while true; do
        if [ ${#php_extensions[@]} -gt 0 ]; then
            clear
            echo "${BOLD}${YELLOW}These extensions names must be supported in the PHP version you selected.${RESET}"
            echo "Learn more here: https://serversideup.net/docker-php/available-extensions"
            echo ""
            echo "${BLUE}PHP Version:${RESET} $SPIN_PHP_VERSION"
            echo "${BLUE}Extensions:${RESET}"
            for extension in "${php_extensions[@]}"; do
                echo "- $extension"
            done
            echo ""
            echo "${BOLD}${YELLOW}Are these selections correct?${RESET}"
            echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or ${BOLD}${BLUE}any other key${RESET} to go back and change selections."
            read -n 1 -s -r key
            echo

            if [[ $key == "" ]]; then
                echo "${GREEN}Continuing with selected extensions...${RESET}"
                break
            else
                echo "${YELLOW}Returning to extension selection...${RESET}"
                select_php_extensions
                return
            fi
        else
            break
        fi
    done
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
        DIM=$(printf '\033[2m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[m')
    else
        RAINBOW=""
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        DIM=""
        BOLD=""
        RESET=""
    fi
}

show_spin_pro_notice() {
    if [ "$spin_template_type" != "pro" ]; then
        echo
        echo "${BOLD}${GREEN}Unlock Pro features at 👉 https://getspin.pro${RESET}"
        echo
    fi
}

###############################################
# Pro - Functions
###############################################
configure_github_actions() {
    local service_name="github-actions"
    merge_blocks "$service_name"
}

configure_horizon() {
    local service_name="horizon"
    local current_dir=""

    current_dir=$(pwd)

    cd "$project_dir" || { echo "Failed to change to project directory"; return 1; }

    if [[ "$SPIN_ACTION" == "new" ]]; then
        echo "$service_name: Installing Horizon dependencies..."
        $COMPOSE_CMD run --rm --remove-orphans --no-deps -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" php composer --verbose --working-dir=/var/www/html/ require laravel/horizon
        $COMPOSE_CMD run --rm --remove-orphans --no-deps -e "SHOW_WELCOME_MESSAGE=false" php php artisan horizon:install
    fi

    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "QUEUE_CONNECTION" "QUEUE_CONNECTION=redis"

    cd "$current_dir" || { echo "Failed to return to original directory"; return 1; }

    merge_blocks "$service_name"
    
}

configure_mailpit() {
    echo "Configuring Mailpit..."
    
    local files=("$project_dir/.env" "$project_dir/.env.example")
    
    for file in "${files[@]}"; do
        if line_in_file --action search --file "$file" "MAIL_DRIVER"; then
            line_in_file --action replace --file "$file" "MAIL_DRIVER" "MAIL_DRIVER=smtp"
        fi
        
        if line_in_file --action search --file "$file" "MAIL_MAILER"; then
            line_in_file --action replace --file "$file" "MAIL_MAILER" "MAIL_MAILER=smtp"
        fi
        
        line_in_file --action replace --file "$file" "MAIL_HOST" "MAIL_HOST=mailpit"
        line_in_file --action replace --file "$file" "MAIL_PORT" "MAIL_PORT=1025"
        line_in_file --action replace --file "$file" "MAIL_USERNAME" "MAIL_USERNAME="
        line_in_file --action replace --file "$file" "MAIL_PASSWORD" "MAIL_PASSWORD="
        line_in_file --action replace --file "$file" "MAIL_ENCRYPTION" "MAIL_ENCRYPTION="
    done
}

configure_mariadb() {
    local service_name="mariadb"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=mariadb"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_HOST" "DB_HOST=mariadb"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_PORT" "DB_PORT=3306"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_USERNAME" "DB_USERNAME=root"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_PASSWORD" "DB_PASSWORD=rootpassword"
}

configure_meilisearch() {
    local service_name="meilisearch"
    merge_blocks "$service_name"
    set_docker_database_dependencies "$service_name"

    cd "$project_dir" || { echo "Failed to change to project directory"; return 1; }

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "SCOUT_DRIVER" "SCOUT_DRIVER=meilisearch"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "MEILISEARCH_HOST" "MEILISEARCH_HOST=http://meilisearch:7700"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "MEILISEARCH_KEY" "MEILISEARCH_KEY=developmentkey1234567890"

    echo "$service_name: Installing and configuring Meilisearch..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" php composer --verbose --working-dir=/var/www/html/ require laravel/scout meilisearch/meilisearch-php http-interop/http-factory-guzzle

    echo "$service_name: Publishing Meilisearch configuration..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" php artisan vendor:publish --provider="Laravel\Scout\ScoutServiceProvider"

    cd "$current_dir" || { echo "Failed to return to original directory"; return 1; }
}

configure_mysql() {
    local service_name="mysql"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=mysql"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_HOST" "DB_HOST=mysql"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_PORT" "DB_PORT=3306"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_USERNAME" "DB_USERNAME=root"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_PASSWORD" "DB_PASSWORD=rootpassword"
}

configure_postgresql() {
    local service_name="postgres"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=pgsql"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_HOST" "DB_HOST=postgres"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_PORT" "DB_PORT=5432"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_DATABASE" "DB_DATABASE=laravel"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_USERNAME" "DB_USERNAME=postgres"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "# DB_PASSWORD" "DB_PASSWORD=postgrespassword"
}

configure_queue() {
    local service_name="queue"
    merge_blocks "$service_name"
    set_docker_database_dependencies "$service_name"

}

configure_redis() {
    local service_name="redis"

    merge_blocks "$service_name"

    echo "$service_name: Updating the Laravel .env and .env.example files..."
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "REDIS_HOST" "REDIS_HOST=redis"
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "REDIS_PASSWORD" "REDIS_PASSWORD=redispassword"
}

configure_reverb() {
    local service_name="reverb"
    local current_dir=""

    current_dir=$(pwd)
    merge_blocks "$service_name"

    set_docker_database_dependencies "$service_name"

    cd "$project_dir" || { echo "Failed to change to project directory"; return 1; }

    echo "$service_name: Installing and configuring Laravel Reverb..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" php php artisan install:broadcasting --reverb --no-interaction --without-node

    echo "$service_name: Installing Laravel Reverb node dependencies..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps node ${javascript_package_manager} add --dev laravel-echo pusher-js
    $COMPOSE_CMD run --rm --remove-orphans --no-deps node ${javascript_package_manager} run build

    echo "$service_name: Preparing env files for Reverb..."
    line_in_file --action replace --file ".env" "REVERB_HOST" "REVERB_HOST=\"reverb.dev.test\""
    line_in_file --action replace --file ".env" "REVERB_PORT" "REVERB_PORT=443"
    line_in_file --action replace --file ".env" "REVERB_SCHEME" "REVERB_SCHEME=https"

    # Update ENV example file only
    line_in_file --action replace --file ".env.example" "REVERB_APP_ID" "REVERB_APP_ID=999999"
    line_in_file --action replace --file ".env.example" "REVERB_APP_KEY" "REVERB_APP_KEY=changemeabcde1234567"
    line_in_file --action replace --file ".env.example" "REVERB_APP_SECRET" "REVERB_APP_SECRET=changeme123456789abcde"
    line_in_file --action replace --file ".env.example" "REVERB_HOST" "REVERB_HOST=\"reverb.dev.test\""
    line_in_file --action replace --file ".env.example" "REVERB_PORT" "REVERB_PORT=443"
    line_in_file --action replace --file ".env.example" "REVERB_SCHEME" "REVERB_SCHEME=https"
    line_in_file --action replace --file ".env.example" "VITE_REVERB_APP_KEY" "VITE_REVERB_APP_KEY=\"\${REVERB_APP_KEY}\""
    line_in_file --action replace --file ".env.example" "VITE_REVERB_HOST" "VITE_REVERB_HOST=\"\${REVERB_HOST}\""
    line_in_file --action replace --file ".env.example" "VITE_REVERB_PORT" "VITE_REVERB_PORT=\"\${REVERB_PORT}\""
    line_in_file --action replace --file ".env.example" "VITE_REVERB_SCHEME" "VITE_REVERB_SCHEME=\"\${REVERB_SCHEME}\""

    cd "$current_dir" || { echo "Failed to return to original directory"; return 1; }
}

configure_octane() {
    local service_name="octane"
    local current_dir=""

    current_dir=$(pwd)

    merge_blocks "$service_name"

    cd "$project_dir" || { echo "Failed to change to project directory"; return 1; }

    echo "$service_name: Installing and configuring Laravel Octane with FrankenPHP..."
    $COMPOSE_CMD run --rm --remove-orphans --no-deps -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" php composer require laravel/octane

    echo "$service_name: Configuring Traefik for Laravel Octane..."
    line_in_file --action exact \
        --file "${project_dir}/docker-compose.dev.yml" \
        --file "${project_dir}/docker-compose.prod.yml" \
        "laravel-web.loadbalancer.server.scheme=https" \
        "laravel-web.loadbalancer.server.scheme=http"

    line_in_file --action exact \
        --file "${project_dir}/docker-compose.dev.yml" \
        --file "${project_dir}/docker-compose.prod.yml" \
        "laravel-web.loadbalancer.server.port=8443" \
        "laravel-web.loadbalancer.server.port=8080"

    line_in_file --action exact \
        --file "${project_dir}/docker-compose.prod.yml" \
        "laravel-web.loadbalancer.healthcheck.scheme=https" \
        "laravel-web.loadbalancer.healthcheck.scheme=http"

    echo "$service_name: Laravel Octane configuration completed."

    cd "$current_dir" || { echo "Failed to return to original directory"; return 1; }
}

configure_schedule() {
    local service_name="schedule"
    merge_blocks "$service_name"
    set_docker_database_dependencies "$service_name"
}

configure_vite() {
    local file="${project_dir}/vite.config.js"

    echo "${BLUE}Updating Vite configuration...${RESET}"

    # Check if the file exists
    if [ ! -f "$file" ]; then
        echo "❌ ${BOLD}${RED}Error: $file does not exist.${RESET}"
        return 1
    fi

    # Add import statement if not present
    if ! grep -q "import fs from 'fs';" "$file"; then
        sed_inplace "1s/^/import fs from 'fs';\n/" "$file"
    fi

    # Update or add server configuration using awk
    awk '
    BEGIN { server_added = 0; in_server_block = 0 }
    /^import .* from/ { print; next }
    /^export default defineConfig\({/ {
        print
        if (!server_added) {
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
            print "        origin: '"'"'*'"'"',"
            print "        cors: {"
            print "            origin: '"'"'*'"'"',"
            print "            methods: ['"'"'GET'"'"', '"'"'POST'"'"', '"'"'OPTIONS'"'"'],"
            print "        },"
            print "    },"
            server_added = 1
        }
        next
    }
    /^    server: {/ { in_server_block = 1; server_added = 1; next }
    /^    },/ && in_server_block { in_server_block = 0; next }
    !in_server_block { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

    echo "vite: vite.config.js updated successfully."
}

docker_yq() {
    local yq_version="4.44.2"
    docker run --rm \
        --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
        -v "${project_dir}:/workdir" \
        -v "${template_src_dir}:/src" \
        "mikefarah/yq:$yq_version" \
        "$@"
}

initialize_database_service() {
    stop_running_containers

    echo "${BOLD}${BLUE}🔄 Initializing the database service...${RESET}"
    cd "$project_dir" || exit
    $COMPOSE_CMD up -d --remove-orphans --build

    trap '$COMPOSE_CMD down --volumes --remove-orphans > /dev/null 2>&1' EXIT
    echo "${BOLD}${BLUE}🔄 Running migrations...${RESET}"
    $COMPOSE_CMD run --rm --remove-orphans --no-deps \
    -e "AUTORUN_ENABLED=true" \
    -e "AUTORUN_LARAVEL_CONFIG_CACHE=false" \
    -e "AUTORUN_LARAVEL_EVENT_CACHE=false" \
    -e "AUTORUN_LARAVEL_ROUTE_CACHE=false" \
    -e "AUTORUN_LARAVEL_VIEW_CACHE=false" \
    -e "AUTORUN_LARAVEL_MIGRATION_TIMEOUT=90" \
    -e "SHOW_WELCOME_MESSAGE=false" \
    -e "S6_VERBOSITY=0" \
    php \
    true

    echo "✅ Migrations completed successfully!${RESET}"
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
            local rel_block="${block#"${template_src_dir}/"}"
            local rel_destination="${destination#"${project_dir}/"}"
            
            # Merge the block into the destination file, appending values
            docker_yq eval-all \
                'select(fileIndex == 0) * select(fileIndex == 1)' \
                "/workdir/$rel_destination" "/src/$rel_block" \
                -i
            
            echo "$service_name: Updated ${rel_path}"
        else
            # For non-YAML files, simply copy the file
            cp "$block" "$destination"
            echo "$service_name: Copied ${rel_path}"
        fi
    done
}

set_docker_database_dependencies() {
    local service_name=$1    
    # Determine which database is selected
    if [ "$mysql" = "1" ]; then
        spin_database="mysql"
    elif [ "$mariadb" = "1" ]; then
        spin_database="mariadb"
    elif [ "$postgresql" = "1" ]; then
        spin_database="postgres"
    else
        spin_database="sqlite"
    fi

    if [ "$spin_database" = "sqlite" ]; then
        # Remove the database dependency for SQLite
        echo "$service_name: Removing the database dependency for SQLite"
        docker_yq eval \
            'del(.services.'"$service_name"'.depends_on.spin-database)' \
            -i /workdir/docker-compose.dev.yml
    else
        # Remove default references to SQLite
        echo "$service_name: Remove default references to SQLite"
        line_in_file --action delete --file "$project_dir/docker-compose.prod.yml" "database_sqlite"

        # Update the docker-compose.yml file to include the correct database
        echo "$service_name: Setting the database dependency to $spin_database"
        docker_yq eval \
            '.services.'"$service_name"'.depends_on."'"$spin_database"'".condition = "service_healthy" | del(.services.'"$service_name"'.depends_on.spin-database)' \
            -i /workdir/docker-compose.dev.yml
    fi
}

stop_running_containers() {
    echo "Checking for running containers..."    
    
    # Get current running containers
    local running_containers
    running_containers=$(docker ps -q)
    
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
            # Stop each container individually and ignore errors for non-existent containers
            for container in $running_containers; do
                docker stop "$container" 2>/dev/null || true
            done
            return 0
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
select_php_extensions
select_features
select_javascript_package_manager
select_database
select_github_actions

# Clean up the screen before moving forward
clear

# Set PHP Version of Project
line_in_file --action replace --file "$project_dir/$php_dockerfile" "FROM serversideup" "FROM ${SPIN_PHP_DOCKER_BASE_IMAGE} AS base"

# Add PHP Extensions if available
if [ ${#php_extensions[@]} -gt 0 ]; then
    add_php_extensions
fi

# Install Composer dependencies
if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
    docker pull "$SPIN_PHP_DOCKER_INSTALLER_IMAGE"

    if [[ "$SPIN_ACTION" == "init" ]]; then
        echo "Re-installing composer dependencies..."
        docker compose run --rm --no-deps --build \
            -e COMPOSER_CACHE_DIR=/dev/null \
            -e "SHOW_WELCOME_MESSAGE=false" \
            php \
            composer install

        echo "Installing Spin..."
        docker compose run --rm --build --no-deps --remove-orphans \
            -e COMPOSER_CACHE_DIR=/dev/null \
            -e "SHOW_WELCOME_MESSAGE=false" \
                php \
                composer require serversideup/spin --dev
    else
        echo "Installing Spin..."
        docker run --rm \
            -v "$project_dir:/var/www/html" \
            --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
            -e COMPOSER_CACHE_DIR=/dev/null \
            -e "SHOW_WELCOME_MESSAGE=false" \
            "$SPIN_PHP_DOCKER_INSTALLER_IMAGE" \
            composer require serversideup/spin --dev
    fi
fi

# Process the user selections
process_selections

if [ "$spin_template_type" == "pro" ]; then
    # Configure Vite
    if [ -f "$project_dir/vite.config.js" ]; then
        configure_vite
    fi

    # Configure APP_URL
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "APP_URL" "APP_URL=https://laravel.dev.test"

    configure_mailpit
fi

# Configure Server Contact
line_in_file --action exact --ignore-missing --file "$project_dir/.infrastructure/conf/traefik/prod/traefik.yml" "changeme@example.com" "$SERVER_CONTACT"
line_in_file --action exact --ignore-missing --file "$project_dir/.spin.yml" "changeme@example.com" "$SERVER_CONTACT"

if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
    install_node_dependencies
    if [[ "$spin_template_type" == "pro" ]]; then
        initialize_database_service
    fi
fi

if [[ ! -d "$project_dir/.git" ]]; then
    initialize_git_repository
fi

# Export actions so it's available to the main Spin script
export SPIN_USER_TODOS