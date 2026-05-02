<?php

/**
 * Comment dictionary for reset.sh — Japanese.
 */

return [
    '# Dixlase complete reset' => '# Dixlase 完全リセット',
    '# Deletes all DB / source / Docker volumes and rebuilds from scratch.' => '# DB・ソース・Docker ボリュームをすべて削除して再構築',
    '# Usage:' => '# 使い方:',
    '#   ./reset.sh             # Re-setup in production mode' => '#   ./reset.sh             # 本番モードで再セットアップ',
    '#   ./reset.sh --dev       # Re-setup in development mode' => '#   ./reset.sh --dev       # 開発モードで再セットアップ',
    '# node_modules etc. are created as root inside Docker, so delete via sudo' => '# node_modules 等は Docker 内で root 作成のためコンテナ経由で削除',
];
