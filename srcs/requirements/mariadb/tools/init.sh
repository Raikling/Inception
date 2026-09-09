#!/bin/sh
set -e

DB_PASS=$(cat /run/secrets/db_password)
DB_ROOT_PASS=$(cat /run/secrets/db_root_password)

if [ ! -d "/var/lib/mysql/mysql" ]; then
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql

    mariadbd --user=mysql --skip-networking &
    MARIADB_PID=$!

    until mariadb-admin ping --silent 2>/dev/null; do
        sleep 1
    done

    mariadb <<EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
FLUSH PRIVILEGES;
EOF

    mariadb-admin -u root -p"${DB_ROOT_PASS}" shutdown
    wait "${MARIADB_PID}"

fi

exec mariadbd --user=mysql
