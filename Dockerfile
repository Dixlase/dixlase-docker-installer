# Dockerfile - Dixlase
FROM php:8.3-fpm

# Install system packages
RUN apt-get update --allow-releaseinfo-change && apt-get install -y --allow-unauthenticated \
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

# Install Node.js 20 (NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
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

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Install dependencies (only if html/ exists)
COPY ./html/composer.json ./html/composer.lock ./
COPY ./html/patches ./patches
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
