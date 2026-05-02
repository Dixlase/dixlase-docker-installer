<?php

/**
 * Comment dictionary for setup.sh — Japanese.
 */

return [
    '# Dixlase setup script' => '# Dixlase セットアップスクリプト',
    '# Purpose: Clone the core from GitHub and build the Docker environment.' => '# 用途: GitHub からコアをクローンし、Docker 環境を構築',
    '# Usage:' => '# 使い方:',
    '#   ./setup.sh                  # Production mode (pre-built assets)' => '#   ./setup.sh                  # 本番モード (ビルド済みアセット運用)',
    '#   ./setup.sh --dev            # Development mode (Vite hot-reload)' => '#   ./setup.sh --dev            # 開発モード (Vite hot-reload 有効)',
    '#   ./setup.sh <branch>         # Clone the specified branch (default: main)' => '#   ./setup.sh <branch>         # 指定ブランチをクローン (デフォルト: main)',
    '#   ./setup.sh --dev <branch>   # Development mode + specified branch' => '#   ./setup.sh --dev <branch>   # 開発モード + ブランチ指定',
    '# Repository URLs can be overridden via environment variables. Default is public HTTPS.' => '# リポジトリ URL は環境変数で上書き可能。デフォルトは公開 HTTPS。',
    '# Parse arguments: --dev flag and branch name' => '# 引数パース: --dev フラグとブランチ名',
    '# 1. Clone the core from GitHub' => '# 1. GitHub からコアをクローン',
    '# 1.5. Fetch submodules (themes etc.)' => '# 1.5. サブモジュール（テーマ等）を取得',
    '# Clone directly instead of using a submodule (handles commits the core may not reach)' => '# サブモジュールではなく直接クローン（コアが参照するコミットが存在しない場合に対応）',
    '# 2. Set up .env' => '# 2. .env のセットアップ',
    '# Root .env (used by Docker Compose to interpolate ports / DB credentials)' => '# ルート .env (Docker Compose 用) — ポート/DB認証情報の補間に使用',
    '# Laravel .env (used by the application)' => '# Laravel .env (アプリケーション用)',
    '# 3. Generate SSL certificate' => '# 3. SSL 証明書の生成',
    '# 4. Build and start Docker containers' => '# 4. Docker イメージのビルドと起動',
    '# Wait for containers to start' => '# コンテナの起動を待つ',
    '# 5. Set up Laravel' => '# 5. Laravel のセットアップ',
    '# Reinstall because vendor/node_modules are missing on the host due to the volume mount' => '# ボリュームマウントにより vendor/node_modules がホスト側で欠落しているため再インストール',
    '# Generate APP_KEY' => '# APP_KEY を生成',
    '# Create the storage symlink' => '# ストレージリンクを作成',
    '# Clear caches (skipped if DB does not exist yet)' => '# キャッシュをクリア（DB 未作成時はスキップ）',
    '# 6. Build assets (production mode only)' => '# 6. アセットのビルド (本番モードのみ)',
    '# Remove the hot file so the built assets are used' => '# hot ファイルを削除してビルド済みアセットを使用させる',
    '# Done' => '# 完了',
    '# Read the actual ports from .env and display them' => '# .env から実際のポートを読み取って表示',
    '# Omit the port from the URL when it is the standard 443/80' => '# ポート 443/80 の場合は URL から省略',
];
