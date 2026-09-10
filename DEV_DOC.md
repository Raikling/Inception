# Developer Documentation

This guide explains how to set up the Inception project from scratch, build and run it, manage its containers and volumes, and understand where data lives and how it persists.

For everyday usage (accessing the site, credentials, health checks), see [USER_DOC.md](USER_DOC.md).

---

## 1. Prerequisites

| Tool | Why | Check |
|------|-----|-------|
| Linux VM (Debian) | Target environment | `cat /etc/os-release` |
| Docker Engine | Builds and runs the containers | `docker --version` |
| Docker Compose V2 plugin | Orchestrates the stack (`docker compose`) | `docker compose version` |
| Make | Entry point for every command | `make --version` |
| Git | Clone the repository | `git --version` |
| `sudo` rights | Edit `/etc/hosts`, wipe data in `make fclean` | `sudo -v` |

Install Docker following the [official Debian guide](https://docs.docker.com/engine/install/debian/)
(packages `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`),
then allow your user to run Docker without `sudo`:

```bash
sudo usermod -aG docker "$USER"   # log out and back in afterwards
```

---

## 2. Setting Up the Environment from Scratch

### 2.1 Clone the repository

```bash
git clone <repository-url> inception
cd inception
```

### 2.2 Map the domain name

```bash
echo "127.0.0.1 aben-hzz.42.fr" | sudo tee -a /etc/hosts
```

### 2.3 Create `srcs/.env` (non-sensitive configuration)

This file is git-ignored and must be created by hand. It is used in two ways:
- by Docker Compose to interpolate `${HTTPS_PORT}` in `docker-compose.yml`
- loaded with `env_file` into **all three** containers

```env
DOMAIN_NAME=aben-hzz.42.fr
HTTPS_PORT=443

#MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user

#Wordpress
WP_TITLE=Inception
WP_DB_HOST=mariadb
WP_ADMIN_USER=<admin_username>
WP_ADMIN_EMAIL=<admin_email>
WP_USER=<second_username>
WP_USER_EMAIL=<second_user_email>
```

| Variable | Used by | Notes |
|----------|---------|-------|
| `DOMAIN_NAME` | WordPress | Builds the site URL. NGINX's `server_name` and certificate CN are hardcoded — see [7.4](#74-changing-the-domain-or-login) |
| `HTTPS_PORT` | Compose, WordPress | Host port mapped to NGINX's 443 (default `443`). Non-443 values are appended to the site URL |
| `MYSQL_DATABASE` | MariaDB, WordPress | Database created at first run |
| `MYSQL_USER` | MariaDB, WordPress | Database user WordPress connects as |
| `WP_TITLE` | WordPress | Site title |
| `WP_DB_HOST` | WordPress | Must be `mariadb` (the Compose service name), **without** a port |
| `WP_ADMIN_USER` | WordPress | Must not contain `admin` / `administrator` (subject rule) |
| `WP_ADMIN_EMAIL` | WordPress | Must be a valid email address |
| `WP_USER` | WordPress | Second user, created with the `author` role. Must differ from the admin |
| `WP_USER_EMAIL` | WordPress | Must be valid **and different** from `WP_ADMIN_EMAIL` |

### 2.4 Create `secrets/` (passwords)

Passwords are passed as **Compose file-based secrets**: each file is mounted read-only into the containers that declare it, at `/run/secrets/<name>`.
The directory is at the repository root and is git-ignored.

```bash
mkdir -p secrets
openssl rand -base64 18 > secrets/db_password.txt
openssl rand -base64 18 > secrets/db_root_password.txt
openssl rand -base64 18 > secrets/credentials.txt
openssl rand -base64 18 > secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

| File | Secret name | Mounted in | Used for |
|------|-------------|------------|----------|
| `secrets/db_password.txt` | `db_password` | mariadb, wordpress | `MYSQL_USER` password (DB creation + `wp-config.php`) |
| `secrets/db_root_password.txt` | `db_root_password` | mariadb | MariaDB `root@localhost` password |
| `secrets/credentials.txt` | `credentials` | wordpress | WordPress administrator password |
| `secrets/wp_user_password.txt` | `wp_user_password` | wordpress | WordPress author password |

> **Password characters:** passwords are inserted into SQL between single quotes (`IDENTIFIED BY '...'`).
> Avoid `'` and `\`. The base64 output above is safe. A trailing newline is fine — scripts read files with `$(cat ...)`, which strips it.

### 2.5 Data directories

The volumes are bound to `/home/aben-hzz/data/mariadb` and `/home/aben-hzz/data/wordpress`.
These directories **must exist before** the stack starts. `make` / `make up` / `make build` create them automatically; if you call `docker compose` directly, create them first:

```bash
mkdir -p /home/aben-hzz/data/mariadb /home/aben-hzz/data/wordpress
```

---

## 3. Building and Launching

### 3.1 Makefile targets

The Makefile defines `COMPOSE = docker compose -f srcs/docker-compose.yml`.

| Target | Runs | Use it when |
|--------|------|-------------|
| `all` / `up` | `mkdir -p` data dirs + `$(COMPOSE) up -d` | Normal start (builds images only if missing) |
| `build` | `mkdir -p` data dirs + `$(COMPOSE) up -d --build` | After editing a Dockerfile, `conf/` or `tools/` file |
| `down` | `$(COMPOSE) down` | Remove containers and network |
| `stop` | `$(COMPOSE) stop` | Stop containers, keep them |
| `start` | `$(COMPOSE) start` | Restart stopped containers |
| `logs` | `$(COMPOSE) logs -f` | Follow all logs |
| `clean` | `down` + `docker system prune -af` | Remove images and build cache |
| `fclean` | `clean` + `docker volume rm` + `sudo rm -rf` data | Full reset, **deletes all data** |
| `re` | `fclean` + `all` | Rebuild a blank installation |

> ⚠️ `docker system prune -af` affects **every** unused image, container, network and build cache on the machine, not only this project.

### 3.2 What `make` does

1. Creates `/home/aben-hzz/data/{mariadb,wordpress}`
2. Builds three images from `srcs/requirements/*/Dockerfile`: `srcs-mariadb`, `srcs-wordpress`, `srcs-nginx`
3. Creates the network `srcs_inception` and the volumes `srcs_db_data`, `srcs_wp_files`
   (Compose prefixes names with the project name, `srcs`, taken from the compose file's directory)
4. Starts the containers in `depends_on` order: **mariadb → wordpress → nginx**

`depends_on` only waits for a container to **start**, not to be **ready** — which is why `setup.sh` polls MariaDB before installing WordPress.

### 3.3 Working with Compose directly

```bash
docker compose -f srcs/docker-compose.yml config                  # print the resolved configuration
docker compose -f srcs/docker-compose.yml up -d --build nginx     # rebuild and restart one service
docker compose -f srcs/docker-compose.yml build --no-cache wordpress  # rebuild without cache
docker compose -f srcs/docker-compose.yml restart wordpress       # restart one service
```

Since `conf/` and `tools/` files are **copied into the images**, any change to them requires a rebuild (`make build` or `up -d --build <service>`).
A change to `srcs/.env` only requires `make up` (Compose recreates the affected containers).

---

## 4. Managing Containers

### 4.1 General commands

| Command | Purpose |
|---------|---------|
| `docker compose -f srcs/docker-compose.yml ps` | Status of the three services |
| `docker logs -f <container>` | Follow one service's logs |
| `docker exec -it <container> bash` | Open a shell inside a container |
| `docker top <container>` | Processes running in a container (check PID 1) |
| `docker inspect <container>` | Full config: mounts, network, restart policy |
| `docker exec <container> ls -l /run/secrets` | List secrets mounted in a container |

Container names: `mariadb`, `wordpress`, `nginx`.

### 4.2 NGINX

```bash
docker exec nginx nginx -t                                   # validate configuration
docker exec nginx openssl x509 -in /etc/nginx/ssl/inception.crt \
    -noout -subject -dates                                   # inspect the certificate
openssl s_client -connect aben-hzz.42.fr:443 -tls1_2 </dev/null   # test TLS from the host
```

### 4.3 WordPress (WP-CLI)

WP-CLI is installed at `/usr/local/bin/wp`. Inside the container it runs as root, so always pass `--allow-root` and `--path`:

```bash
docker exec wordpress wp user list        --path=/var/www/html --allow-root
docker exec wordpress wp option get siteurl --path=/var/www/html --allow-root
docker exec wordpress wp core version     --path=/var/www/html --allow-root
docker exec wordpress wp plugin list      --path=/var/www/html --allow-root
docker exec wordpress php-fpm8.2 -t       # validate PHP-FPM configuration
```

### 4.4 MariaDB

```bash
# root shell (password: secrets/db_root_password.txt)
docker exec -it mariadb mariadb -u root -p

# as the WordPress user, without typing the password
docker exec mariadb sh -c \
    'mariadb -u "$MYSQL_USER" -p"$(cat /run/secrets/db_password)" "$MYSQL_DATABASE" -e "SHOW TABLES;"'

# list database users
docker exec mariadb sh -c \
    'mariadb -u root -p"$(cat /run/secrets/db_root_password)" -e "SELECT user, host FROM mysql.user;"'
```

### 4.5 Network

```bash
docker network ls
docker network inspect srcs_inception      # connected containers and their IPs
docker exec wordpress sh -c \
    'mariadb -h mariadb -u "$MYSQL_USER" -p"$(cat /run/secrets/db_password)" -e "SELECT 1;"'   # wordpress → mariadb
```

---

## 5. Data Storage and Persistence

### 5.1 Volumes

| Compose volume | Docker name | Host path | Container path | Contents |
|----------------|-------------|-----------|----------------|----------|
| `db_data` | `srcs_db_data` | `/home/aben-hzz/data/mariadb` | `/var/lib/mysql` (mariadb) | Database files |
| `wp_files` | `srcs_wp_files` | `/home/aben-hzz/data/wordpress` | `/var/www/html` (wordpress, nginx) | WordPress core, `wp-config.php`, themes, plugins, uploads |

Both are **named volumes** using the `local` driver with bind options:

```yaml
driver_opts:
  type: none
  o: bind
  device: /home/aben-hzz/data/mariadb
```

Docker manages them by name (`docker volume ls`, `docker volume inspect srcs_db_data`) while the data is physically stored in the host directory.

### 5.2 What survives what

| Action | Containers | Images | Volumes / data |
|--------|:----------:|:------:|:--------------:|
| `make stop` | kept | kept | ✅ kept |
| `make down` | removed | kept | ✅ kept |
| `make build` | recreated | rebuilt | ✅ kept |
| `make clean` | removed | removed | ✅ kept |
| `make fclean` / `make re` | removed | removed | ❌ **deleted** |
| Container crash | restarted (`restart: always`) | kept | ✅ kept |

### 5.3 First-run initialization

Both entrypoint scripts only initialize when their volume is empty:

| Service | Skip condition | First-run actions |
|---------|----------------|-------------------|
| MariaDB (`init.sh`) | `/var/lib/mysql/mysql` exists | `mariadb-install-db`, create database and user, set root password |
| WordPress (`setup.sh`) | `/var/www/html/wp-config.php` exists | Download core, create `wp-config.php`, install site, create both users |

**Consequence:** once the volumes are populated, changes to `MYSQL_*`, `WP_*` user variables or any secret file have **no effect**.
Only `DOMAIN_NAME` and `HTTPS_PORT` are re-applied on every start (`wp option update home/siteurl`).
To apply other changes, reset with `make re`.

### 5.4 File ownership

Files in `/home/aben-hzz/data/` are owned by container users (`mysql`, `www-data`), not by your host user.
That is why `make fclean` uses `sudo rm -rf`. Don't edit these files by hand while containers run.


---

## 6. Project Internals

### 6.1 File map

| Path | Role |
|------|------|
| `Makefile` | Wraps Docker Compose, creates / wipes data directories |
| `srcs/docker-compose.yml` | Services, network, volumes, secrets |
| `srcs/.env` | Non-sensitive configuration (git-ignored) |
| `secrets/*.txt` | Passwords (git-ignored) |
| `srcs/requirements/mariadb/Dockerfile` | Installs `mariadb-server`, prepares `/run/mysqld` |
| `srcs/requirements/mariadb/conf/50-server.cnf` | `bind-address = 0.0.0.0` so WordPress can connect over the network |
| `srcs/requirements/mariadb/tools/init.sh` | First-run DB setup, then `exec mariadbd` |
| `srcs/requirements/wordpress/Dockerfile` | Installs PHP-FPM 8.2, `php8.2-mysql`, MariaDB client, WP-CLI |
| `srcs/requirements/wordpress/conf/www.conf` | PHP-FPM pool: listens on `0.0.0.0:9000`, `clear_env = no`, logs to stdout/stderr |
| `srcs/requirements/wordpress/tools/setup.sh` | Waits for DB, installs WordPress, then `exec php-fpm8.2 -F` |
| `srcs/requirements/nginx/Dockerfile` | Installs NGINX, generates the self-signed certificate |
| `srcs/requirements/nginx/conf/nginx.conf` | HTTPS server, TLS 1.2/1.3, FastCGI to `wordpress:9000` |

### 6.2 Request flow

```
browser ──HTTPS:443──▶ nginx ──┬─ static file ─▶ served from /var/www/html (wp_files)
                               └─ *.php ──FastCGI──▶ wordpress:9000 (php-fpm)
                                                          │
                                                          └─SQL──▶ mariadb:3306 (db_data)
```

- `try_files $uri $uri/ /index.php?$args` sends unknown paths to WordPress (pretty permalinks).
- NGINX and PHP-FPM share the `wp_files` volume, so `SCRIPT_FILENAME` resolves to the same path in both containers.

### 6.3 PID 1 and restarts

Each container's main process runs in the foreground as PID 1 (`exec mariadbd`, `exec php-fpm8.2 -F`, `nginx -g "daemon off;"`).
Docker therefore sees a real crash when the service dies, and `restart: always` restarts it. No `tail -f`, `sleep infinity` or `while true` are used.

---

## 7. Modifying the Project

### 7.1 Adding an environment variable

1. Add it to `srcs/.env`
2. Use it in the entrypoint script (all variables in `.env` are available in every container)
3. `make build` if the script changed, otherwise `make up`

### 7.2 Adding a secret

1. Create `secrets/<name>.txt`
2. Declare it at the bottom of `docker-compose.yml`:
   ```yaml
   secrets:
     <name>:
       file: ../secrets/<name>.txt
   ```
3. Add `- <name>` to the `secrets:` list of each service that needs it
4. Read it in the script with `$(cat /run/secrets/<name>)`

### 7.3 Changing a service configuration

Edit the file in `conf/` or `tools/`, then rebuild only that service:

```bash
docker compose -f srcs/docker-compose.yml up -d --build <service>
```

### 7.4 Changing the domain or login

The login and domain appear in several places:

| What | Where |
|------|-------|
| Domain | `srcs/.env` (`DOMAIN_NAME`), `nginx/conf/nginx.conf` (`server_name`), `nginx/Dockerfile` (`CN=` in `-subj`), `/etc/hosts` |
| Data path | `Makefile` (`DATA`), `srcs/docker-compose.yml` (both `device:` entries) |

### 7.5 Subject rules to keep

- One Dockerfile per service, `debian:bookworm` base, never `latest`
- No passwords in Dockerfiles; credentials only via `.env` / secrets
- No `network: host`, `links` or `--link`
- No infinite-loop hacks; the service must be PID 1
- NGINX on 443 as the only entry point, TLS 1.2/1.3 only
- Named volumes in `/home/aben-hzz/data`
- Two WordPress users, admin name without `admin` / `administrator`

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `failed to mount local volume ... no such file or directory` | Data directory missing | Use `make`, or `mkdir -p` the directories ([2.5](#25-data-directories)) |
| `secret ... file not found` / `open ../secrets/...` | Secret file missing | Create it ([2.4](#24-create-secrets-passwords)) |
| `Bind for 0.0.0.0:443 failed: port is already allocated` | Another service uses 443 | Stop it, or set `HTTPS_PORT` in `srcs/.env` |
| Endless `waiting for database...` | MariaDB down, or `db_password.txt` changed after the DB was initialized | `docker logs mariadb`; restore the old password or `make re` |
| `wordpress` keeps restarting | `setup.sh` failed (`set -e`): invalid email, duplicate username/email, bad DB credentials | `docker logs wordpress`, fix `.env`, then `make re` |
| Second WordPress user missing | Install succeeded but `wp user create` failed; `wp-config.php` now exists, so setup is skipped on restart | Fix `.env`, then `make re` |
| **502 Bad Gateway** | PHP-FPM not running or not reachable | `docker logs wordpress`, `docker exec wordpress php-fpm8.2 -t` |
| NGINX exits at start | Configuration error | `docker logs nginx`; fix and `up -d --build nginx` |
| `Permission denied` when deleting data | Files owned by container users | Use `make fclean` (uses `sudo`) |
