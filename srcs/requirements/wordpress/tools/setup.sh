#!/bin/sh
set -e

DB_PASS=$(cat /run/secrets/db_password)
WP_ADMIN_PASS=$(cat /run/secrets/credentials)
WP_USER_PASS=$(cat /run/secrets/wp_user_password)

cd /var/www/html

if [ "${HTTPS_PORT:-443}" = "443" ]; then
    SITE_URL="https://${DOMAIN_NAME}"
else
    SITE_URL="https://${DOMAIN_NAME}:${HTTPS_PORT}"
fi

until mariadb -h "${WP_DB_HOST}" -u "${MYSQL_USER}" -p"${DB_PASS}" \
        -e "SELECT 1;" >/dev/null 2>&1; do
    echo "waiting for database..."
    sleep 2
done

if [ ! -f /var/www/html/wp-config.php ]; then

    wp core download --allow-root

    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASS}" \
        --dbhost="${WP_DB_HOST}" \
        --skip-check \
        --allow-root

    wp core install \
        --url="${SITE_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASS}" \
        --allow-root

    chown -R www-data:www-data /var/www/html

fi

wp option update home "${SITE_URL}" --allow-root
wp option update siteurl "${SITE_URL}" --allow-root

exec php-fpm8.2 -F