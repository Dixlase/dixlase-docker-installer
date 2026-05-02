<?php

/**
 * Comment dictionary for setup.sh — English (identity).
 */

return [
    '# Dixlase setup script' => '# Dixlase setup script',
    '# Purpose: Clone the core from GitHub and build the Docker environment.' => '# Purpose: Clone the core from GitHub and build the Docker environment.',
    '# Usage:' => '# Usage:',
    '#   ./setup.sh                  # Production mode (pre-built assets)' => '#   ./setup.sh                  # Production mode (pre-built assets)',
    '#   ./setup.sh --dev            # Development mode (Vite hot-reload)' => '#   ./setup.sh --dev            # Development mode (Vite hot-reload)',
    '#   ./setup.sh <branch>         # Clone the specified branch (default: main)' => '#   ./setup.sh <branch>         # Clone the specified branch (default: main)',
    '#   ./setup.sh --dev <branch>   # Development mode + specified branch' => '#   ./setup.sh --dev <branch>   # Development mode + specified branch',
    '# Repository URLs can be overridden via environment variables. Default is public HTTPS.' => '# Repository URLs can be overridden via environment variables. Default is public HTTPS.',
    '# Parse arguments: --dev flag and branch name' => '# Parse arguments: --dev flag and branch name',
    '# 1. Clone the core from GitHub' => '# 1. Clone the core from GitHub',
    '# 1.5. Fetch submodules (themes etc.)' => '# 1.5. Fetch submodules (themes etc.)',
    '# Clone directly instead of using a submodule (handles commits the core may not reach)' => '# Clone directly instead of using a submodule (handles commits the core may not reach)',
    '# 2. Set up .env' => '# 2. Set up .env',
    '# Root .env (used by Docker Compose to interpolate ports / DB credentials)' => '# Root .env (used by Docker Compose to interpolate ports / DB credentials)',
    '# Laravel .env (used by the application)' => '# Laravel .env (used by the application)',
    '# 3. Generate SSL certificate' => '# 3. Generate SSL certificate',
    '# 4. Build and start Docker containers' => '# 4. Build and start Docker containers',
    '# Wait for containers to start' => '# Wait for containers to start',
    '# 5. Set up Laravel' => '# 5. Set up Laravel',
    '# Reinstall because vendor/node_modules are missing on the host due to the volume mount' => '# Reinstall because vendor/node_modules are missing on the host due to the volume mount',
    '# Generate APP_KEY' => '# Generate APP_KEY',
    '# Create the storage symlink' => '# Create the storage symlink',
    '# Clear caches (skipped if DB does not exist yet)' => '# Clear caches (skipped if DB does not exist yet)',
    '# 6. Build assets (production mode only)' => '# 6. Build assets (production mode only)',
    '# Remove the hot file so the built assets are used' => '# Remove the hot file so the built assets are used',
    '# Done' => '# Done',
    '# Read the actual ports from .env and display them' => '# Read the actual ports from .env and display them',
    '# Omit the port from the URL when it is the standard 443/80' => '# Omit the port from the URL when it is the standard 443/80',
];
