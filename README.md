# LinuxMCE Docker Setup Scripts

This repository contains scripts to set up Docker-based build environments for LinuxMCE.

## Available Scripts

### 1. linuxmce-builder-bootstrap.sh

Basic bootstrap script for setting up a LinuxMCE build environment on Debian.

### 2. linuxmce-docker-setup.sh

Advanced setup script that can run in both interactive and headless modes. It:

- Automatically searches for LinuxMCE repositories in your home directory
- Maps found repositories into the Docker container
- Provides options for MySQL data mapping
- Creates a fully configured Docker environment for LinuxMCE development

#### Usage

```bash
./linuxmce-docker-setup.sh [OPTIONS]
```

Options:
- `--headless`: Run in headless mode without user prompts
- `--project-dir DIR`: Set the project directory (default: $HOME/linuxmce-docker)
- `--ubuntu-version VER`: Set Ubuntu version for Docker image (default: 22.04)
- `--help`: Show help message

#### Running the Docker Environment

Once set up, you can:

1. Build the Docker image:
   ```bash
   ./run.sh --build
   ```

2. Start the Docker container:
   ```bash
   ./run.sh --start
   ```

3. Access a shell in the container:
   ```bash
   ./run.sh --shell
   ```

4. Start MySQL if needed:
   ```bash
   ./run.sh --mysql-start
   ```

5. Stop the container:
   ```bash
   ./run.sh --stop
   ```

## Requirements

- Docker
- Docker Compose
