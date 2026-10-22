# Dockerfile - Dixlase
FROM php:8.3-fpm

# Install system packages
# --allow-releaseinfo-change only tolerates a changed suite name (Debian moves
# these when a release ages), and package signatures are still verified: no
# --allow-unauthenticated here, since nothing in the list needs it and it would
# accept a tampered mirror.
RUN apt-get update --allow-releaseinfo-change && apt-get install -y \
    build-essential \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    locales \
    zip \
    jpegoptim optipng pngquant gifsicle \
    vim \
    unzip \
    git \
    curl \
    ca-certificates \
    gnupg \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libcurl4-openssl-dev \
    pkg-config \
    libssl-dev \
    libicu-dev \
    openssh-client \
    rsync \
    default-mysql-client

# Install Node.js 24 (NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs

# Install PHP extensions
RUN docker-php-ext-install pdo_mysql mbstring zip exif pcntl bcmath intl

# Configure GD library
RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install gd

# Install Redis PHP extension (PECL); enables Laravel cache / session / queue
# drivers that target Redis. Required by the Dixlase install wizard's Redis
# requirement check (extension_loaded('redis')).
#
# Pinned, retried, and with a second source to download from. On 2026-10-22
# pecl.php.net answered this download with 504 for about an hour, right after
# the PHP 8.3.36 security release, so the build failed at the one moment a
# rebuild was needed. PECL is tried three times; the same version's tag on
# GitHub is the fallback, built the way the base image builds an extension of
# its own. The version is pinned so both sources install the same code.
ARG REDIS_VERSION=6.3.0
RUN set -eu; \
    ext_dir="$(php -r 'echo ini_get("extension_dir");')"; \
    for attempt in 1 2 3; do \
        if pecl install --force "redis-$REDIS_VERSION"; then break; fi; \
        echo "pecl install redis-$REDIS_VERSION failed (attempt $attempt of 3)."; \
        sleep 5; \
    done; \
    if [ -f "$ext_dir/redis.so" ]; then \
        docker-php-ext-enable redis; \
    else \
        echo "pecl.php.net did not serve redis-$REDIS_VERSION; building that version from its GitHub tag instead."; \
        if ! curl -fsSL --retry 3 --retry-delay 5 -o /tmp/phpredis.tar.gz \
                "https://github.com/phpredis/phpredis/archive/refs/tags/$REDIS_VERSION.tar.gz"; then \
            echo "Neither pecl.php.net nor github.com served phpredis $REDIS_VERSION." >&2; \
            echo "An ordinary build reaches both, so run the build again once they answer." >&2; \
            exit 1; \
        fi; \
        docker-php-source extract; \
        mkdir -p /usr/src/php/ext/redis; \
        tar -xzf /tmp/phpredis.tar.gz -C /usr/src/php/ext/redis --strip-components=1; \
        rm -f /tmp/phpredis.tar.gz; \
        docker-php-ext-install redis; \
        docker-php-source delete; \
    fi; \
    php -m | grep -qx redis

# Copy PHP configuration file
COPY ./php/php.ini /usr/local/etc/php/conf.d/uploads.ini
COPY ./php/fpm-security.conf /usr/local/etc/php-fpm.d/zz-security.conf

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Trust /var/www/html no matter who owns it. app-entrypoint.sh chowns the
# html root to www-data on every start so the install wizard can create
# .env there, but everything invoked through `docker compose exec` runs as
# root. git then refuses the bind-mounted core checkout with "detected
# dubious ownership in repository at '/var/www/html'", which composer
# surfaces as a fatal-looking block on every install while it probes the
# root package version. The container is single-tenant and the directory
# is the app itself, so the ownership check protects nothing here.
RUN git config --global --add safe.directory /var/www/html

# php-fpm workers run as www-data, whose home directory is /var/www, but the
# base image leaves that directory root-owned. Anything following the XDG
# spec then fails the moment it tries to create state under $HOME: psysh
# (pulled in by laravel/tinker) throws "Writing to directory
# /var/www/.config/psysh is not allowed", which core logs as a production
# error and emails to the operator. Give www-data its own home so
# $HOME/.config, $HOME/.local/share and friends can be created on demand.
# Non-recursive: /var/www/html is a bind mount at runtime and keeps the
# ownership app-entrypoint.sh gives it.
RUN chown www-data:www-data /var/www

# Install dependencies (only if html/ exists)
# Core dropped cweagans/composer-patches and its patches/ directory in the
# passkeys migration, so there is nothing to copy here any more — and a COPY
# of a missing path is a hard build failure, not a no-op.
COPY ./html/composer.json ./html/composer.lock ./
# Every package core requires is public, so this resolves with no
# credential of any kind.
RUN composer install --no-scripts --optimize-autoloader

# Install npm packages
COPY ./html/package.json ./

# npm install
RUN npm install

# Copy application source code
COPY ./html .

# Build the application
RUN composer dump-autoload --optimize --no-scripts

# Entrypoint chowns bind-mounted Laravel writable dirs to www-data so
# php-fpm workers can write compiled views / caches / sessions.
COPY app-entrypoint.sh /usr/local/bin/app-entrypoint.sh
RUN chmod +x /usr/local/bin/app-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/app-entrypoint.sh"]

# Default command
CMD ["php-fpm"]
