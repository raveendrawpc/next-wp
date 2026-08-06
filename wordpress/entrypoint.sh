#!/bin/bash
set -euo pipefail

# Copy plugin and theme from staging to WordPress (after volume is mounted)
copy_custom_files() {
    echo "[setup] Waiting for WordPress files..."

    # Wait for WordPress core to be extracted (with timeout)
    local elapsed=0
    local timeout=120
    while [ ! -d /var/www/html/wp-content/plugins ]; do
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "[setup] ERROR: Timed out waiting for /var/www/html/wp-content/plugins after ${timeout}s" >&2
            return 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    # Copy plugin if not already present (idempotent — image updates don't overwrite volume)
    if [ ! -d /var/www/html/wp-content/plugins/next-revalidate ]; then
        echo "[setup] Installing next-revalidate plugin..."
        cp -r /usr/src/next-revalidate /var/www/html/wp-content/plugins/
        chown -R www-data:www-data /var/www/html/wp-content/plugins/next-revalidate
    else
        echo "[setup] next-revalidate plugin already present, skipping"
    fi

    # Copy theme if not already present
    if [ ! -d /var/www/html/wp-content/themes/nextjs-headless ]; then
        echo "[setup] Installing nextjs-headless theme..."
        cp -r /usr/src/nextjs-headless /var/www/html/wp-content/themes/
        chown -R www-data:www-data /var/www/html/wp-content/themes/nextjs-headless
    else
        echo "[setup] nextjs-headless theme already present, skipping"
    fi

    # Create robots.txt to block crawlers (Next.js is the public site) — only if missing
    if [ ! -f /var/www/html/robots.txt ]; then
        echo "[setup] Creating robots.txt..."
        cat > /var/www/html/robots.txt << 'EOF'
User-agent: *
Disallow: /
EOF
        chown www-data:www-data /var/www/html/robots.txt
    fi

    # Run the setup script
    echo "[setup] Running WordPress setup..."
    if ! /usr/local/bin/setup-wordpress.sh; then
        echo "[setup] WARNING: WordPress setup failed" >&2
    fi
}

# Run copy and setup in background after a delay for volume mount
(sleep 10 && copy_custom_files) &

# Run the original WordPress entrypoint
exec docker-entrypoint.sh "$@"
