*This project has been created as part of the 42 curriculum by aben-hzz.*

# Inception

## Description

**Inception** is a System Administration project that introduces containerization using **Docker** and **Docker Compose**.
The goal is to design and deploy a small, secure, and modular infrastructure composed of multiple services, each running in its own isolated container.

This project is deployed inside a **Virtual Machine**, and every Docker image is built from a custom Dockerfile.
No pre-built service images are used — only the official `debian:bookworm` base image.

The infrastructure includes:
- An **NGINX** web server secured with **TLS (v1.2 / v1.3)**, the only entry point to the stack
- A **WordPress** site running on **PHP-FPM 8.2**, installed and configured with **WP-CLI**
- A **MariaDB** database
- Persistent storage using **Docker named volumes**
- A private **Docker bridge network** connecting all services
- Credentials handled with **Docker secrets** instead of plain environment variables

---

## Project Description

### Docker and Sources Overview

Each service runs in its own container, built from a Dockerfile located in `srcs/requirements/<service>/`.
The whole stack is described in `srcs/docker-compose.yml` and driven by the root `Makefile`.

**Key Design Choices:**

1. **Base Image**: `debian:bookworm` (Debian 12, the penultimate stable release) for every service — pinned, never `latest`
2. **Service Isolation**: NGINX, WordPress and MariaDB each run in a dedicated container, with `restart: always`
3. **Network Architecture**: A private bridge network (`inception`); containers reach each other by service name (`wordpress:9000`, `mariadb:3306`)
4. **Data Persistence**: Two named volumes (`db_data`, `wp_files`) stored under `/home/aben-hzz/data/`
5. **Security**: TLS 1.2/1.3 only, self-signed certificate generated at build time, passwords passed as Docker secrets, no credentials in Dockerfiles or in Git
6. **Entry Point**: NGINX is the only container that publishes a port (443)
7. **PID 1**: Every entrypoint script ends with `exec` so the service daemon (`mariadbd`, `php-fpm8.2 -F`, `nginx -g "daemon off;"`) runs in the foreground as PID 1 — no `tail -f`, `sleep infinity` or other hacks

### Technical Comparisons

#### Virtual Machines vs Docker

| Aspect | Virtual Machines | Docker Containers |
|--------|------------------|-------------------|
| **Architecture** | Full guest OS on a hypervisor | Shared host kernel, isolated processes |
| **Resource Usage** | Heavy (GBs of RAM/disk) | Lightweight (MBs) |
| **Startup Time** | Minutes | Seconds |
| **Isolation** | Hardware-level virtualization | Process-level isolation (namespaces, cgroups) |
| **Portability** | Large images, hypervisor dependent | Small images, runs anywhere Docker runs |
| **Use Case** | Running a full, separate OS | Packaging and deploying individual services |

**Why Docker for this project?**
Docker gives each service a lightweight, reproducible environment. Services can be rebuilt, restarted and updated independently, and the whole stack can be recreated from source with a single `make`.

#### Secrets vs Environment Variables

| Feature | Docker Secrets | Environment Variables |
|---------|----------------|----------------------|
| **Storage** | Mounted as read-only files in `/run/secrets/` | Stored in the container's environment |
| **Visibility** | Only in the containers that request them | Visible in `docker inspect` and `/proc/<pid>/environ` |
| **Leak risk** | Not inherited by child processes, not printed in logs by default | Easily leaked through logs, crash dumps, `env` |
| **Best For** | Passwords, API keys, certificates | Non-sensitive configuration |
| **Swarm Mode** | Encrypted at rest with Swarm; file-based secrets also work with plain Compose | Works everywhere |

**Implementation in this project:**
The project uses **both**, each for what it is good at:

- **Docker secrets** (`secrets/*.txt`, declared in `docker-compose.yml`) hold every password. The entrypoint scripts read them from `/run/secrets/` at startup.
- **Environment variables** (`srcs/.env`) hold non-sensitive configuration: domain name, database name, usernames, emails, site title.

Both `secrets/` and `srcs/.env` are listed in `.gitignore`, so no credential is ever committed.

| Secret | Used by | Purpose |
|--------|---------|---------|
| `db_password` | MariaDB, WordPress | Password of the WordPress database user |
| `db_root_password` | MariaDB | MariaDB `root` password |
| `credentials` | WordPress | WordPress administrator password |
| `wp_user_password` | WordPress | WordPress second (author) user password |

#### Docker Network vs Host Network

| Aspect | Docker Bridge Network | Host Network |
|--------|----------------------|--------------|
| **Isolation** | Each container has its own network stack | Container shares the host's network stack |
| **Port Mapping** | Ports must be explicitly published | Every listening port is exposed on the host |
| **Security** | Controlled exposure, internal traffic stays private | No isolation from the host |
| **Performance** | Small NAT overhead | No overhead |
| **DNS** | Built-in service discovery by name | None, uses `localhost` / host IPs |

**Why a Docker Network?**
This project uses a custom bridge network (`inception`) to get:
- Service discovery by name (NGINX forwards PHP requests to `wordpress:9000`, WordPress connects to `mariadb`)
- MariaDB (3306) and PHP-FPM (9000) reachable **only** from inside the network
- A single port (443) published to the host
- No `network: host`, `links` or `--link` (forbidden by the subject)

#### Docker Volumes vs Bind Mounts

| Feature | Named Volumes | Bind Mounts |
|---------|--------------|-------------|
| **Management** | Created and tracked by Docker (`docker volume ls`) | Just a host path, invisible to Docker |
| **Location** | Docker's storage area, or a custom path via `driver_opts` | Any host path |
| **Portability** | Referenced by name in Compose | Tied to the host filesystem layout |
| **Permissions** | Initialized by Docker | Managed manually on the host |
| **Lifecycle** | Survives `docker compose down`, removed explicitly | Independent of Docker |

**Why Named Volumes?**
The subject requires named volumes whose data lives in `/home/<login>/data`. This project declares two named volumes using the `local` driver with `type: none` and `o: bind`, so Docker manages them by name while the data sits in a known host directory:

| Volume | Host path | Mounted in | Container path |
|--------|-----------|------------|----------------|
| `db_data` | `/home/aben-hzz/data/mariadb` | MariaDB | `/var/lib/mysql` |
| `wp_files` | `/home/aben-hzz/data/wordpress` | WordPress, NGINX | `/var/www/html` |

`wp_files` is shared by WordPress (which runs the PHP) and NGINX (which serves static files and forwards `.php` requests).

---

## Instructions

### Prerequisites

- **Linux Virtual Machine** (Debian recommended)
- **Docker Engine** with the **Docker Compose V2** plugin (`docker compose`)
- **Make**
- `sudo` rights (used by `make fclean` to wipe the data directories)

### Installation

1. **Clone the repository:**
   ```bash
   git clone <repository-url> inception
   cd inception
   ```

2. **Create the environment file** `srcs/.env`:
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
   > The administrator username must **not** contain `admin` or `administrator`.

3. **Create the secrets** (one password per file, at the repository root):
   ```bash
   mkdir -p secrets
   echo '<db_user_password>'  > secrets/db_password.txt
   echo '<db_root_password>'  > secrets/db_root_password.txt
   echo '<wp_admin_password>' > secrets/credentials.txt
   echo '<wp_user_password>'  > secrets/wp_user_password.txt
   ```

4. **Point the domain name to the VM:**
   ```bash
   echo "127.0.0.1 aben-hzz.42.fr" | sudo tee -a /etc/hosts
   ```

The data directories (`/home/aben-hzz/data/mariadb` and `/home/aben-hzz/data/wordpress`) are created automatically by the Makefile.

### Usage

| Command | Action |
|---------|--------|
| `make` / `make up` | Create data directories and start the stack (images are built on first run) |
| `make build` | Rebuild the images and restart the stack |
| `make down` | Stop and remove the containers and network |
| `make stop` | Stop the containers without removing them |
| `make start` | Start previously stopped containers |
| `make logs` | Follow the logs of all services |
| `make clean` | `down` + `docker system prune -af` |
| `make fclean` | `clean` + remove the volumes and wipe `/home/aben-hzz/data/*` |
| `make re` | `fclean` then `make` — full rebuild from scratch |

> ⚠️ `make clean` runs `docker system prune -af`, which removes **all** unused images, containers and networks on the machine, not only this project's.

### Accessing Services

- **WordPress Website**: `https://aben-hzz.42.fr`
- **WordPress Admin Panel**: `https://aben-hzz.42.fr/wp-admin`

The certificate is self-signed, so the browser will show a warning on first visit.

**Credentials:**
- Administrator: `WP_ADMIN_USER` from `srcs/.env`, password in `secrets/credentials.txt`
- Author: `WP_USER` from `srcs/.env`, password in `secrets/wp_user_password.txt`

**Useful checks:**
```bash
docker compose -f srcs/docker-compose.yml ps                     # container status
openssl s_client -connect aben-hzz.42.fr:443 -tls1_2 </dev/null  # TLS 1.2 accepted
openssl s_client -connect aben-hzz.42.fr:443 -tls1_1 </dev/null  # TLS 1.1 refused
docker exec -it mariadb mariadb -u root -p                       # open a database shell
```

---

## Project Structure

```
inception
├── DEV_DOC.md
├── Makefile
├── README.md
├── USER_DOC.md
├── secrets/                     # git-ignored
│   ├── credentials.txt
│   ├── db_password.txt
│   ├── db_root_password.txt
│   └── wp_user_password.txt
└── srcs
    ├── .env                     # git-ignored
    ├── docker-compose.yml
    └── requirements
        ├── mariadb
        │   ├── .dockerignore
        │   ├── Dockerfile
        │   ├── conf
        │   │   └── 50-server.cnf
        │   └── tools
        │       └── init.sh
        ├── nginx
        │   ├── .dockerignore
        │   ├── Dockerfile
        │   └── conf
        │       └── nginx.conf
        └── wordpress
            ├── Dockerfile
            ├── conf
            │   └── www.conf
            └── tools
                └── setup.sh
```

---

## Resources

### Official Documentation

- [Docker Documentation](https://docs.docker.com/) - Official Docker reference
- [Docker Compose File Reference](https://docs.docker.com/reference/compose-file/)
- [Dockerfile Best Practices](https://docs.docker.com/build/building/best-practices/)
- [Secrets in Docker Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [Docker Volumes](https://docs.docker.com/engine/storage/volumes/)
- [Docker Networking](https://docs.docker.com/engine/network/)
- [NGINX Documentation](https://nginx.org/en/docs/) and [ngx_http_ssl_module](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [PHP-FPM Configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI Commands](https://developer.wordpress.org/cli/commands/)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/)
- [OpenSSL `req` manual](https://docs.openssl.org/master/man1/openssl-req/)

### AI Usage in This Project

<!-- Edit this section so it reflects exactly how you used AI. -->

**AI tools were used for:**

1. **Learning and Research**:
   - Understanding Docker networking, volumes and secrets
   - Clarifying Docker Compose syntax
   - Understanding TLS configuration in NGINX and the PHP-FPM / FastCGI setup

2. **Debugging**:
   - Interpreting container logs and configuration errors

3. **Documentation**:
   - Structuring and writing this README and its comparison tables

**Approach**: AI was used as a learning and documentation aid. Every Dockerfile, configuration file and script was written, tested and understood before being kept in the project.

---

## Technical Details

### Service Architecture

```
                          Client (browser)
                                 │
                    https://aben-hzz.42.fr:443
                                 │
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  network: inception  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                                 │
                          ┌──────▼──────┐
                          │    NGINX    │  TLSv1.2 / TLSv1.3
                          └──────┬──────┘
                                 │  FastCGI → wordpress:9000
                          ┌──────▼──────┐
                          │  WordPress  │  PHP-FPM 8.2 + WP-CLI
                          └──────┬──────┘
                                 │  SQL → mariadb:3306
                          ┌──────▼──────┐
                          │   MariaDB   │
                          └─────────────┘

  wp_files → /home/aben-hzz/data/wordpress   (NGINX + WordPress)
  db_data  → /home/aben-hzz/data/mariadb     (MariaDB)
```

### Container Startup Flow

**MariaDB** — `tools/init.sh`
1. Reads `db_password` and `db_root_password` from `/run/secrets/`
2. On first run only (no `/var/lib/mysql/mysql`): initializes the data directory, starts a temporary server with `--skip-networking`, creates the database and the WordPress user, sets the root password, then shuts the temporary server down
3. `exec mariadbd` in the foreground

**WordPress** — `tools/setup.sh`
1. Reads `db_password`, `credentials` and `wp_user_password` from `/run/secrets/`
2. Waits until MariaDB accepts connections
3. On first run only (no `wp-config.php`): downloads WordPress, generates `wp-config.php`, installs the site, creates the administrator and a second user with the `author` role
4. Updates `home` / `siteurl` to match `DOMAIN_NAME` and `HTTPS_PORT`
5. `exec php-fpm8.2 -F` in the foreground, listening on port 9000

**NGINX**
1. A self-signed certificate for `aben-hzz.42.fr` is generated with OpenSSL at image build time
2. Listens on 443 with `ssl_protocols TLSv1.2 TLSv1.3`, serves `/var/www/html` and forwards `.php` requests to `wordpress:9000`
3. Runs with `nginx -g "daemon off;"`

### Security Features

- ✅ TLS 1.2/1.3 only, HTTPS on port 443 as the single entry point
- ✅ No passwords in Dockerfiles, scripts, or Git
- ✅ Passwords delivered as Docker secrets in `/run/secrets/`
- ✅ `srcs/.env` and `secrets/` excluded via `.gitignore`
- ✅ MariaDB and PHP-FPM not published to the host
- ✅ Isolated bridge network (no `host` mode, no `links`)
- ✅ PHP-FPM workers run as `www-data`, NGINX workers as `www-data`, MariaDB as `mysql`
- ✅ MariaDB `root` restricted to `localhost` with its own password

### Data Persistence

- **Database Volume**: `/home/aben-hzz/data/mariadb` → MariaDB data directory
- **WordPress Volume**: `/home/aben-hzz/data/wordpress` → WordPress files, themes, plugins and uploads

Data survives `make down` and container rebuilds; only `make fclean` deletes it.

---

## Validation Checklist

- [x] Each service runs in a dedicated container
- [x] Custom Dockerfile for each service, built by `docker compose`
- [x] No pre-built service images (only `debian:bookworm` as base)
- [x] No `latest` tag used
- [x] NGINX with TLSv1.2 / TLSv1.3 only
- [x] WordPress + PHP-FPM only (no NGINX in the container)
- [x] MariaDB only (no NGINX in the container)
- [x] Two named volumes stored in `/home/aben-hzz/data`
- [x] Custom Docker network, no `host` / `links`
- [x] Containers restart on crash (`restart: always`)
- [x] No infinite-loop hacks (`tail -f`, `sleep infinity`, `while true`)
- [x] Two WordPress users (one administrator, one author)
- [x] Administrator username set without `admin` / `administrator`
- [x] Domain `aben-hzz.42.fr` points to the local IP
- [x] No passwords in Dockerfiles
- [x] Environment variables in `srcs/.env`, passwords in Docker secrets
- [x] Port 443 is the only entry point

---

## License

This project is part of the 42 School curriculum and is intended for educational purposes.

---

## Author

**aben-hzz** - 42 Network Student

For usage and administration, see [USER_DOC.md](USER_DOC.md). For setup, internals and maintenance, see [DEV_DOC.md](DEV_DOC.md).
