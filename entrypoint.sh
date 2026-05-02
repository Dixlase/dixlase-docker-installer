#!/bin/bash

echo "=== Checking if node_modules exists ==="
if [ ! -d "/var/www/html/node_modules/tailwindcss" ]; then
  echo "No node_modules found or incomplete. Running fresh npm install for Linux..."
  cd /var/www/html
  cp package.json /tmp/package.json.bak
  npm install --no-package-lock
  echo "npm install complete."
fi

exec "$@"
