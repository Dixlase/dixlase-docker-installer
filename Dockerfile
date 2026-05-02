# Dockerfile - Dixlase
FROM php:8.3-fpm

# システムパッケージをインストール
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
    libicu-dev

# Node.js 20 をインストール (NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# 拡張機能をインストール
RUN docker-php-ext-install pdo_mysql mbstring zip exif pcntl bcmath intl

# GDライブラリの設定
RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install gd

# PHP設定ファイルをコピー
COPY ./php/php.ini /usr/local/etc/php/conf.d/uploads.ini

# Composerをインストール
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# 作業ディレクトリを設定
WORKDIR /var/www/html

# 依存関係をインストール（html/ が存在する場合のみ）
COPY ./html/composer.json ./html/composer.lock ./
COPY ./html/patches ./patches
RUN composer install --no-scripts --optimize-autoloader

# パッケージをインストール
COPY ./html/package.json ./

# npm install
RUN npm install

# アプリケーションのソースコードをコピー
COPY ./html .

# アプリケーションをビルド
RUN composer dump-autoload --optimize --no-scripts

# デフォルトコマンド
CMD ["php-fpm"]
