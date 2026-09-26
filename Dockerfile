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
RUN pecl install redis && docker-php-ext-enable redis

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
# Core's composer.json requires the private `dixlase/dixlase-onepage`
# theme from a private GitHub repo. Mount the host's
# ~/.composer/auth.json as a BuildKit secret so the token is available
# only at build time (never baked into the resulting image). The
# `required=false` keeps builds that do not need private deps working
# without an auth.json on the host.
RUN --mount=type=secret,id=composer_auth,target=/root/.composer/auth.json,required=false \
    composer install --no-scripts --optimize-autoloader

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
