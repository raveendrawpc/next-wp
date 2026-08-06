#!/bin/bash
set -e

# Wait for database to be ready (with timeout)
# Use mysql client directly — wp db check fails with MySQL 8.0 + MariaDB client SSL defaults
echo "Waiting for database..."
attempts=0
max_attempts=20
until MYSQL_PWD="${WORDPRESS_DB_PASSWORD}" mysql -h "${WORDPRESS_DB_HOST}" -u "${WORDPRESS_DB_USER}" -e "SELECT 1;" "${WORDPRESS_DB_NAME}" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
        echo "ERROR: Database not available after $((max_attempts * 3))s — check WORDPRESS_DB_HOST/USER/PASSWORD" >&2
        exit 1
    fi
    echo "Waiting for database... ($attempts/$max_attempts)"
    sleep 3
done
echo "Database ready."

# Check if WordPress is already installed
if ! wp core is-installed --allow-root 2>/dev/null; then
    echo "Installing WordPress..."

    wp core install \
        --url="${WORDPRESS_URL:-http://localhost}" \
        --title="${WORDPRESS_TITLE:-My WordPress Site}" \
        --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
        --admin_password="${WORDPRESS_ADMIN_PASSWORD:-changeme}" \
        --admin_email="${WORDPRESS_ADMIN_EMAIL:-admin@example.com}" \
        --skip-email \
        --allow-root

    echo "WordPress installed successfully!"

    # Remove default plugins (keep only next-revalidate)
    echo "Removing default plugins..."
    wp plugin delete akismet --allow-root 2>/dev/null || true
    wp plugin delete hello --allow-root 2>/dev/null || true
fi

# Activate the revalidation plugin if not already active
if ! wp plugin is-active next-revalidate --allow-root 2>/dev/null; then
    echo "Activating Next.js Revalidation plugin..."
    wp plugin activate next-revalidate --allow-root
fi

# Activate the headless theme
echo "Activating Next.js Headless theme..."
if ! wp theme activate nextjs-headless --allow-root 2>/dev/null; then
    # Fallback for legacy directory name
    wp theme activate theme --allow-root 2>/dev/null || echo "WARNING: Could not activate headless theme" >&2
fi

# Configure the plugin if NEXTJS_URL is set
if [ -n "${NEXTJS_URL:-}" ]; then
    echo "Configuring Next.js Revalidation plugin..."
    # Use PHP to build JSON safely (avoids injection if URL/secret contains quotes)
    settings_json=$(NEXTJS_URL="$NEXTJS_URL" WEBHOOK_SECRET="${WORDPRESS_WEBHOOK_SECRET:-}" php -r '
        $data = [
            "nextjs_url" => getenv("NEXTJS_URL"),
            "webhook_secret" => getenv("WEBHOOK_SECRET"),
            "cooldown" => 2
        ];
        echo json_encode($data);
    ')
    echo "$settings_json" | wp option update next_revalidate_settings --format=json --allow-root
    echo "Plugin configured with Next.js URL: $NEXTJS_URL"
fi

echo "WordPress setup complete!"
