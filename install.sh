#!/bin/env bash
set -e # Exit on error

###############################################
# Prepare enviornment
###############################################

# Make sure the image is up to date before running
php_docker_image="serversideup/php:8.3-cli"
docker pull $php_docker_image

# Save anything passed to the script as an array
framework_args=("$@")

###############################################
# Configure "SPIN_PROJECT_DIRECTORY" variable
# This variable MUST be the ABSOLUTE path
###############################################

# Determine the project directory based on the SPIN_ACTION
if [ "$SPIN_ACTION" == "new" ]; then
  # Use the first framework argument or default to "laravel"
  laravel_project_directory=${framework_args[0]:-laravel}
  # Set the absolute path to the project directory
  SPIN_PROJECT_DIRECTORY="$(pwd)/$laravel_project_directory"

elif [ "$SPIN_ACTION" == "init" ]; then
  # Use the current working directory for the project directory
  SPIN_PROJECT_DIRECTORY="$(pwd)"
fi

# Export the project directory
export SPIN_PROJECT_DIRECTORY

###############################################
# Functions
###############################################

# Default function to run for new projects
new(){
  # Use the current working directory for our install command
  docker run --rm -v "$(pwd):/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" $php_docker_image composer --no-cache create-project laravel/laravel "${framework_args[@]}"

  init
}

# Required function name "init", used in "spin init" command
init(){
  # Install the spin package
  docker run --rm -v "$SPIN_PROJECT_DIRECTORY:/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" $php_docker_image composer --verbose --working-dir=/var/www/html/ require serversideup/spin:dev-75-spin-deploy-allow-deployments-without-cicd --dev
}

###############################################
# Main: Where we call the functions
###############################################

# When spin calls this script, it already sets a variable
# called $SPIN_ACTION (that will have a value of "new" or "init)

# Check to see if SPIN_ACTION function exists
if type "$SPIN_ACTION" &>/dev/null; then
  # Call the function
  $SPIN_ACTION
else
  # If the function does not exist, throw an error
  echo "The function '$SPIN_ACTION' does not exist."
  exit 1
fi