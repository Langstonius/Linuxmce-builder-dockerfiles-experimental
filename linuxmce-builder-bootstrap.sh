#!/bin/bash
#
# LinuxMCE Docker Bootstrap Script for Debian
# Based on work by Marie O. Schmidt
# License GPL v3
#
# Purpose: Completely set up a Docker-based build environment for LinuxMCE on Debian
#

set -e

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

# Check for Debian
if [ ! -f /etc/debian_version ]; then
    print_error "This script is designed for Debian systems only."
    exit 1
fi

print_info "Starting LinuxMCE build environment setup..."

# Create project directory
PROJECT_DIR=${PROJECT_DIR:-$HOME/linuxmce-builder}
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR
print_info "Project directory: $PROJECT_DIR"

# Install Docker from official sources
print_info "Installing Docker from official sources..."

sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker packages
print_info "Installing Docker packages..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
sudo usermod -aG docker $USER
print_info "Added $USER to the docker group. You may need to log out and back in for this to take effect."

# Set up project structure
print_info "Setting up project structure..."

# Create required directories
mkdir -p $PROJECT_DIR/{output,configs,source,mysql}

# Create Dockerfile
print_info "Creating Dockerfile..."
cat > $PROJECT_DIR/Dockerfile << 'EOF'
FROM ubuntu:22.04

LABEL maintainer="Your Name <your.email@example.com>"
LABEL description="LinuxMCE Build Environment"
LABEL version="1.0"

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set locale
RUN apt-get update && apt-get install -y locales && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL C

# Install necessary packages
RUN apt-get update && apt-get -y dist-upgrade && \
    apt-get install -y \
    wget \
    build-essential \
    debhelper \
    linux-headers-generic \
    language-pack-en-base \
    aptitude \
    openssh-client \
    mysql-server \
    git \
    autotools-dev \
    libgtk2.0-dev \
    libvte-dev \
    dupload \
    joe \
    g++ \
    ccache \
    lsb-release \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure MySQL
RUN mkdir -p /etc/mysql/conf.d/
COPY mysql/builder.cnf /etc/mysql/conf.d/
RUN mkdir -p /var/run/mysqld && \
    chown mysql:mysql /var/run/mysqld

# Set up working directory
WORKDIR /root

# Define volume for build outputs
VOLUME ["/usr/local/lmce-build/output"]

#setup sparse checkout
RUN mkdir -p /root/buildscripts
WORKDIR /root/buildscripts
RUN git init
RUN git remote add origin https://github.com/Langstonius/LinuxMCE.git
RUN git config core.sparseCheckout true
RUN echo "src/Ubuntu_Helpers_NoHardcode" >> .git/info/sparse-checkout
RUN git pull origin master

# Set up build configuration
COPY configs/builder.custom.conf /root/buildscripts/conf-files/jammy-amd64/

# Install build helpers
WORKDIR /root/buildscripts
RUN chmod +x install.sh
RUN ./install.sh

# Set up build environment
WORKDIR /usr/local/lmce-build

# Define entrypoint for running builds
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Default command if no arguments are provided
CMD ["build"]
EOF

# Create MySQL configuration
print_info "Creating MySQL configuration..."
cat > $PROJECT_DIR/mysql/builder.cnf << 'EOF'
[mysqld]
skip-networking
innodb_flush_log_at_trx_commit = 2
EOF

# Create builder configuration
print_info "Creating builder configuration..."
cat > $PROJECT_DIR/configs/builder.custom.conf << 'EOF'
# Build configuration for LinuxMCE
# Generated on $(date)

# DVD build options
do_not_build_sl_dvd="yes"
do_not_build_dl_dvd="yes"

# Win32 options
win32_create_fake="yes"

# Database options
sqlcvs_host="schema.linuxmce.org"
EOF

# Create entrypoint script
print_info "Creating entrypoint script..."
cat > $PROJECT_DIR/entrypoint.sh << 'EOF'
#!/bin/bash
#
# Entrypoint script for LinuxMCE Docker build environment
# copyright 2025 (Based on work by Marie O. Schmidt)
# licence GPL v3
#

set -e

# Start MySQL service
service mysql start

# Default command is to run a build
if [ "$1" = "build" ]; then
    echo "Starting LinuxMCE build process..."
    cd /usr/local/lmce-build
    ./prepare.sh
    ./build.sh
    echo "Build completed!"
    exit 0
fi

# If prepare-only is specified, just run the prepare script
if [ "$1" = "prepare-only" ]; then
    cd /usr/local/lmce-build
    ./prepare.sh
    echo "Preparation completed!"
    exit 0
fi

# If build-only is specified, just run the build script
if [ "$1" = "build-only" ]; then
    cd /usr/local/lmce-build
    ./build.sh
    echo "Build completed!"
    exit 0
fi

# If shell is specified, start a shell
if [ "$1" = "shell" ]; then
    exec /bin/bash
fi

# If custom command is provided, execute it
exec "$@"
EOF
chmod +x $PROJECT_DIR/entrypoint.sh

# Create docker-compose.yml
print_info "Creating docker-compose.yml..."
cat > $PROJECT_DIR/docker-compose.yml << 'EOF'
version: '3.8'

services:
  linuxmce-builder:
    build:
      context: .
      dockerfile: Dockerfile
    image: linuxmce-builder:latest
    container_name: linuxmce-builder
    volumes:
      # Mount output directory to host for accessing build artifacts
      - ./output:/usr/local/lmce-build/output
      # Optional: Mount source code if you want to make changes without rebuilding the image
      - ./source:/usr/local/lmce-build/source:ro
      # Optional: Mount custom configuration
      - ./configs:/usr/local/lmce-build/configs:ro
      # Required to save or inject key
     # - ${PWD}/lmce-build:/etc/lmce-build
    environment:
      # Example environment variables that can be used to configure the build
      - BUILD_TYPE=release
      - SKIP_DVD_BUILD=yes
      - WIN32_CREATE_FAKE=yes
      - SQLCVS_HOST=schema.linuxmce.org
    # Default command will run the full build
    command: build
    # Set resource limits
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
EOF

# Create build script
print_info "Creating build script..."
cat > $PROJECT_DIR/build.sh << 'EOF'
#!/bin/bash
#
# LinuxMCE Build Script
# Based on work by Marie O. Schmidt
# License GPL v3
#

set -e

# Configuration variables (can be overridden by environment variables)
UBUNTU_VERSION=${UBUNTU_VERSION:-22.04}
BUILD_TYPE=${BUILD_TYPE:-release}
SKIP_DVD_BUILD=${SKIP_DVD_BUILD:-yes}
WIN32_CREATE_FAKE=${WIN32_CREATE_FAKE:-yes}
SQLCVS_HOST=${SQLCVS_HOST:-schema.linuxmce.org}

# Print help message
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "LinuxMCE Build Script"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build         Build the Docker image and run the full build (default)"
    echo "  --prepare-only  Run only the preparation steps"
    echo "  --build-only    Run only the build steps (after preparation)"
    echo "  --shell         Open a shell in the build environment"
    echo "  --help          Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  UBUNTU_VERSION    Ubuntu version to use (default: 22.04)"
    echo "  BUILD_TYPE        Build type (release or debug, default: release)"
    echo "  SKIP_DVD_BUILD    Skip DVD build (yes or no, default: yes)"
    echo "  WIN32_CREATE_FAKE Create fake Win32 binaries (yes or no, default: yes)"
    echo "  SQLCVS_HOST       SQL CVS host (default: schema.linuxmce.org)"
    echo ""
    exit 0
fi

# Handle command line options
case "$1" in
    --build)
        CMD="up"
        ;;
    --prepare-only)
        CMD="run --rm linuxmce-builder prepare-only"
        ;;
    --build-only)
        CMD="run --rm linuxmce-builder build-only"
        ;;
    --shell)
        CMD="run --rm linuxmce-builder shell"
        ;;
    *)
        # Default is to build
        CMD="up"
        ;;
esac

# Build the Docker image and run the specified command
docker compose $CMD
EOF
chmod +x $PROJECT_DIR/build.sh

# Create README.md
print_info "Creating README.md..."
cat > $PROJECT_DIR/README.md << 'EOF'
# LinuxMCE Docker Build Environment

This is a modern Docker-based build environment for LinuxMCE, replacing the traditional chroot-based approach.

## Prerequisites

- Docker
- Docker Compose

## Usage

1. Build the Docker image and start a full build:
   ```bash
   ./build.sh --build
   ```

2. Run only the preparation steps:
   ```bash
   ./build.sh --prepare-only
   ```

3. Run only the build steps (after preparation):
   ```bash
   ./build.sh --build-only
   ```

4. Open a shell in the build environment:
   ```bash
   ./build.sh --shell
   ```

## Customization

You can customize the build by:

1. Modifying the `Dockerfile`
2. Editing configuration files in the `configs/` directory
3. Setting environment variables before running the build script

## Build Artifacts

All build artifacts will be available in the `./output` directory.

## Project Structure

```
linuxmce-builder/
├── build.sh               # Main build script
├── Dockerfile             # Docker image definition
├── docker-compose.yml     # Docker Compose configuration
├── entrypoint.sh          # Container entrypoint script
├── configs/               # Build configuration files
│   └── builder.custom.conf
├── mysql/                 # MySQL configuration
│   └── builder.cnf
├── output/                # Build artifacts output directory
└── source/                # Optional source code mount
```
EOF

# Build the Docker image
print_info "Building Docker image (this may take some time)..."
cd $PROJECT_DIR
docker compose build

print_success "Setup complete! Your LinuxMCE build environment is ready."
print_info "Project directory: $PROJECT_DIR"
print_info ""
print_info "To start a full build:"
print_info "  cd $PROJECT_DIR"
print_info "  ./build.sh --build"
print_info ""
print_info "To run only the preparation steps:"
print_info "  ./build.sh --prepare-only"
print_info ""
print_info "To run only the build steps (after preparation):"
print_info "  ./build.sh --build-only"
print_info ""
print_info "To open a shell in the build environment:"
print_info "  ./build.sh --shell"
print_info ""
print_info "For more information, see the README.md file in the project directory."
print_info ""
print_info "Note: You may need to log out and back in for Docker permissions to take effect."
