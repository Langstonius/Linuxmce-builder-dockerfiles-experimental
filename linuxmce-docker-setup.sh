#!/bin/bash
#
# LinuxMCE Docker Setup Script
# License GPL v3
#
# Purpose: Set up a Docker-based build environment for LinuxMCE with repository mapping
# Can run headless or with user input

set -e

# Default config values
UBUNTU_VERSION="22.04"
PROJECT_NAME="linuxmce"

# Print colored messages
print_info() {
    echo -e "\e[1;34m[INFO] $1\e[0m"
}

print_success() {
    echo -e "\e[1;32m[SUCCESS] $1\e[0m"
}

print_error() {
    echo -e "\e[1;31m[ERROR] $1\e[0m"
}

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    print_error "Please do not run this script as root or with sudo."
    print_info "The script will prompt for sudo password when needed."
    exit 1
fi

# Parse command line arguments
function print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --headless           Run in headless mode without user prompts"
    echo "  --project-dir DIR    Set the project directory (default: $HOME/linuxmce-docker)"
    echo "  --ubuntu-version VER Set Ubuntu version for Docker image (default: $UBUNTU_VERSION)"
    echo "  --help               Show this help message"
    exit 1
}

# Parse command line options
HEADLESS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --headless)
            HEADLESS=true
            shift
            ;;
        --project-dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        --ubuntu-version)
            UBUNTU_VERSION="$2"
            shift 2
            ;;
        --help)
            print_usage
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            ;;
    esac
done

# Project directory setup
PROJECT_DIR=${PROJECT_DIR:-$HOME/linuxmce-docker}
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR
print_info "Project directory: $PROJECT_DIR"

# Variables for repository mapping
REPO_MAPPINGS=""
MYSQL_MAPPING=""

if $HEADLESS; then
    print_info "Running in headless mode"
fi

# Function to find repositories
find_repositories() {
    print_info "Searching for LinuxMCE repositories in $HOME..."
    
    # Arrays to store found repositories
    declare -a FOUND_REPOS=()
    
    # Common repository names to search for
    REPO_NAMES=("LinuxMCE" "Ubuntu_Helpers_NoHardcode")
    
    # Search for each repository
    for REPO_NAME in "${REPO_NAMES[@]}"; do
        FOUND_PATHS=$(find $HOME -type d -name "$REPO_NAME" -o -name "$REPO_NAME.git" 2>/dev/null)
        
        # Add each found path to our array
        while IFS= read -r path; do
            if [ -n "$path" ]; then
                if [ -d "$path/.git" ] || [ "${path##*.}" == "git" ]; then
                    FOUND_REPOS+=("$path")
                    print_info "Found repository: $path"
                fi
            fi
        done <<< "$FOUND_PATHS"
    done
    
    # Return the found repositories
    echo "${FOUND_REPOS[@]}"
}

# Function to setup repository mappings
setup_repo_mappings() {
    local repos=("$@")
    local mappings=""
    
    if [ ${#repos[@]} -eq 0 ]; then
        print_info "No repositories found in $HOME directory."
        return
    fi
    
    for repo in "${repos[@]}"; do
        if [ -n "$repo" ]; then
            if $HEADLESS; then
                # In headless mode, map all found repositories automatically
                repo_name=$(basename "$repo")
                mappings="$mappings      - $repo:/usr/local/lmce-build/source/$repo_name:rw\n"
                print_info "Mapping: $repo -> /usr/local/lmce-build/source/$repo_name"
            else
                # In interactive mode, ask for confirmation
                read -p "Map repository $repo to Docker? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    read -p "Enter target path in Docker container (default: /usr/local/lmce-build/source/$(basename "$repo")): " target_path
                    target_path=${target_path:-/usr/local/lmce-build/source/$(basename "$repo")}
                    mappings="$mappings      - $repo:$target_path:rw\n"
                    print_info "Added mapping: $repo -> $target_path"
                fi
            fi
        fi
    done
    
    # Return the mappings
    echo -e "$mappings"
}

# Function to setup MySQL mapping
setup_mysql_mapping() {
    local mysql_mapping=""
    
    if $HEADLESS; then
        # In headless mode, don't map MySQL unless specified by environment variable
        if [ -n "$MYSQL_DIR" ] && [ -d "$MYSQL_DIR" ]; then
            mysql_mapping="      - $MYSQL_DIR:/var/lib/mysql:rw\n"
            print_info "Mapping MySQL: $MYSQL_DIR -> /var/lib/mysql"
        fi
    else
        # In interactive mode, ask if MySQL mapping is needed
        read -p "Do you have MySQL data that needs to be mapped to Docker? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            read -p "Enter path to MySQL data directory: " mysql_dir
            if [ -d "$mysql_dir" ]; then
                mysql_mapping="      - $mysql_dir:/var/lib/mysql:rw\n"
                print_info "Added MySQL mapping: $mysql_dir -> /var/lib/mysql"
            else
                print_error "Directory $mysql_dir does not exist. MySQL mapping not added."
            fi
        fi
    fi
    
    # Return the MySQL mapping
    echo -e "$mysql_mapping"
}

# Main logic
if $HEADLESS; then
    # Headless mode - use environment variables or defaults
    if [ -z "$REPOS" ]; then
        # If REPOS env var isn't set, try to find repositories
        found_repos=($(find_repositories))
        REPO_MAPPINGS=$(setup_repo_mappings "${found_repos[@]}")
    else
        # Use provided REPOS env var (comma-separated list)
        IFS=',' read -ra repo_list <<< "$REPOS"
        REPO_MAPPINGS=$(setup_repo_mappings "${repo_list[@]}")
    fi
    
    # Setup MySQL mapping if env var is set
    if [ -n "$MYSQL_DIR" ]; then
        MYSQL_MAPPING=$(setup_mysql_mapping)
    fi
else
    # Interactive mode
    print_info "Welcome to the LinuxMCE Docker Setup Script"
    print_info "This script will set up a Docker environment for LinuxMCE development."
    
    # Find and map repositories
    found_repos=($(find_repositories))
    REPO_MAPPINGS=$(setup_repo_mappings "${found_repos[@]}")
    
    # Setup MySQL mapping
    MYSQL_MAPPING=$(setup_mysql_mapping)
    
    # Ask for any additional repositories
    read -p "Would you like to map any additional repositories? (y/n): " add_more
    if [[ "$add_more" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter repository path (or 'done' to finish): " repo_path
            if [ "$repo_path" == "done" ]; then
                break
            fi
            
            if [ -d "$repo_path" ]; then
                read -p "Enter target path in Docker container: " target_path
                REPO_MAPPINGS="$REPO_MAPPINGS      - $repo_path:$target_path:rw\n"
                print_info "Added mapping: $repo_path -> $target_path"
            else
                print_error "Directory $repo_path does not exist."
            fi
        done
    fi
fi

# Create Dockerfile
print_info "Creating Dockerfile..."
cat > $PROJECT_DIR/Dockerfile << EOF
FROM ubuntu:${UBUNTU_VERSION}

LABEL maintainer="LinuxMCE Community"
LABEL description="LinuxMCE Build Environment"
LABEL version="1.0"

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set locale
RUN apt-get update && apt-get install -y locales && \\
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL C

# Install necessary packages
RUN apt-get update && apt-get -y dist-upgrade && \\
    apt-get install -y \\
    wget \\
    build-essential \\
    debhelper \\
    linux-headers-generic \\
    language-pack-en-base \\
    aptitude \\
    openssh-client \\
    mysql-server \\
    git \\
    autotools-dev \\
    libgtk2.0-dev \\
    libvte-dev \\
    dupload \\
    joe \\
    g++ \\
    ccache \\
    lsb-release \\
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/*

# Configure MySQL
RUN mkdir -p /etc/mysql/conf.d/
COPY mysql/builder.cnf /etc/mysql/conf.d/
RUN mkdir -p /var/run/mysqld && \\
    chown mysql:mysql /var/run/mysqld

# Set up working directory
WORKDIR /root

# Define volume for build outputs
VOLUME ["/usr/local/lmce-build/output"]

# Set up build directories
RUN mkdir -p /usr/local/lmce-build/source
WORKDIR /usr/local/lmce-build

# Define entrypoint for running builds
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Default command if no arguments are provided
CMD ["shell"]
EOF

# Create MySQL configuration
print_info "Creating MySQL configuration..."
mkdir -p $PROJECT_DIR/mysql
cat > $PROJECT_DIR/mysql/builder.cnf << 'EOF'
[mysqld]
skip-networking
innodb_flush_log_at_trx_commit = 2
EOF

# Create entrypoint script
print_info "Creating entrypoint script..."
cat > $PROJECT_DIR/entrypoint.sh << 'EOF'
#!/bin/bash
#
# Entrypoint script for LinuxMCE Docker build environment
#

set -e

# If shell is specified, start a shell
if [ "$1" = "shell" ]; then
    exec /bin/bash
fi

# If mysql-start is specified, start MySQL
if [ "$1" = "mysql-start" ]; then
    if [ -d "/var/lib/mysql" ]; then
        service mysql start
        echo "MySQL service started"
    else
        echo "MySQL data directory not found"
    fi
    exit 0
fi

# If custom command is provided, execute it
exec "$@"
EOF
chmod +x $PROJECT_DIR/entrypoint.sh

# Create docker-compose.yml with dynamic mappings
print_info "Creating docker-compose.yml with mappings..."
cat > $PROJECT_DIR/docker-compose.yml << EOF
version: '3.8'

services:
  ${PROJECT_NAME}:
    build:
      context: .
      dockerfile: Dockerfile
    image: ${PROJECT_NAME}:latest
    container_name: ${PROJECT_NAME}
    volumes:
      # Mount output directory to host for accessing build artifacts
      - ./output:/usr/local/lmce-build/output:rw
      # Custom repository mappings
$(echo -e "$REPO_MAPPINGS")
      # MySQL mapping (if configured)
$(echo -e "$MYSQL_MAPPING")
    environment:
      - BUILD_TYPE=release
      - UBUNTU_VERSION=${UBUNTU_VERSION}
    command: shell
EOF

# Create run script
print_info "Creating run script..."
cat > $PROJECT_DIR/run.sh << EOF
#!/bin/bash
#
# LinuxMCE Docker Run Script
#

set -e

# Container name from setup
CONTAINER_NAME="${PROJECT_NAME}"

# Print colored messages
print_info() {
    echo -e "\e[1;34m[INFO] \$1\e[0m"
}

print_success() {
    echo -e "\e[1;32m[SUCCESS] \$1\e[0m"
}

print_error() {
    echo -e "\e[1;31m[ERROR] \$1\e[0m"
}

# Print help message
if [ "\$1" == "--help" ] || [ "\$1" == "-h" ]; then
    echo "LinuxMCE Docker Run Script"
    echo "Usage: \$0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build         Build the Docker image"
    echo "  --start         Start the Docker container"
    echo "  --stop          Stop the Docker container"
    echo "  --shell         Open a shell in the running container"
    echo "  --mysql-start   Start the MySQL service in the container"
    echo "  --exec CMD      Execute a command in the running container"
    echo "  --help          Show this help message"
    echo ""
    exit 0
fi

# Handle command line options
case "\$1" in
    --build)
        print_info "Building Docker image..."
        docker compose build
        ;;
    --start)
        print_info "Starting Docker container..."
        docker compose up -d
        ;;
    --stop)
        print_info "Stopping Docker container..."
        docker compose down
        ;;
    --shell)
        print_info "Opening shell in Docker container..."
        docker compose exec ${CONTAINER_NAME} /bin/bash
        ;;
    --mysql-start)
        print_info "Starting MySQL service in the container..."
        docker compose exec ${CONTAINER_NAME} mysql-start
        ;;
    --exec)
        shift
        print_info "Executing command in Docker container: \$@"
        docker compose exec ${CONTAINER_NAME} \$@
        ;;
    *)
        # Default is to show help
        echo "LinuxMCE Docker Run Script"
        echo "Usage: \$0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --build         Build the Docker image"
        echo "  --start         Start the Docker container"
        echo "  --stop          Stop the Docker container"
        echo "  --shell         Open a shell in the running container"
        echo "  --mysql-start   Start the MySQL service in the container"
        echo "  --exec CMD      Execute a command in the running container"
        echo "  --help          Show this help message"
        echo ""
        ;;
esac
EOF
chmod +x $PROJECT_DIR/run.sh

# Create README.md
print_info "Creating README.md..."
cat > $PROJECT_DIR/README.md << EOF
# LinuxMCE Docker Build Environment

This is a Docker-based build environment for LinuxMCE with repository and MySQL mapping.

## Prerequisites

- Docker
- Docker Compose

## Usage

1. Build the Docker image:
   \`\`\`bash
   ./run.sh --build
   \`\`\`

2. Start the Docker container:
   \`\`\`bash
   ./run.sh --start
   \`\`\`

3. Open a shell in the running container:
   \`\`\`bash
   ./run.sh --shell
   \`\`\`

4. Start MySQL in the container (if needed):
   \`\`\`bash
   ./run.sh --mysql-start
   \`\`\`

5. Execute a command in the running container:
   \`\`\`bash
   ./run.sh --exec <command>
   \`\`\`

6. Stop the Docker container:
   \`\`\`bash
   ./run.sh --stop
   \`\`\`

## Setup Script Options

The setup script supports the following options:

\`\`\`bash
./linuxmce-docker-setup.sh [OPTIONS]
\`\`\`

Options:
- \`--headless\`: Run in headless mode without user prompts
- \`--project-dir DIR\`: Set the project directory (default: \$HOME/linuxmce-docker)
- \`--ubuntu-version VER\`: Set Ubuntu version for Docker image (default: ${UBUNTU_VERSION})
- \`--help\`: Show help message

## Environment Variables

In headless mode, you can use the following environment variables:
- \`REPOS\`: Comma-separated list of repository paths to map
- \`MYSQL_DIR\`: Path to MySQL data directory

Example:
\`\`\`bash
REPOS="\$HOME/LinuxMCE,\$HOME/linuxmce-core" MYSQL_DIR="/var/lib/mysql" ./linuxmce-docker-setup.sh --headless
\`\`\`

## Project Structure

\`\`\`
${PROJECT_DIR}/
├── run.sh                 # Main run script
├── Dockerfile             # Docker image definition
├── docker-compose.yml     # Docker Compose configuration with mappings
├── entrypoint.sh          # Container entrypoint script
├── mysql/                 # MySQL configuration
│   └── builder.cnf
└── output/                # Build artifacts output directory
\`\`\`
EOF

# Create output directory
mkdir -p $PROJECT_DIR/output

# Final steps
print_success "Setup complete! Your LinuxMCE Docker environment is ready."
print_info "Project directory: $PROJECT_DIR"
print_info ""
print_info "To build the Docker image:"
print_info "  cd $PROJECT_DIR"
print_info "  ./run.sh --build"
print_info ""
print_info "To start the Docker container:"
print_info "  ./run.sh --start"
print_info ""
print_info "To open a shell in the running container:"
print_info "  ./run.sh --shell"
print_info ""
print_info "For more information, see the README.md file in the project directory."