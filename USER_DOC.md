# User Documentation

This guide explains how to use the Inception stack day to day:
what it provides, how to start and stop it, how to reach the website, where the credentials are, and how to check that everything is working.

If the project is not configured yet (no `srcs/.env` or `secrets/` directory), follow [DEV_DOC.md](DEV_DOC.md) first.

---

## 1. What the Stack Provides

The stack runs a **WordPress website** served over **HTTPS**, split into three containers:

| Service | Role | Reachable from |
|---------|------|----------------|
| **NGINX** | Secure web server (HTTPS, TLS 1.2 / 1.3). The only door into the stack. | `https://aben-hzz.42.fr` (port 443) |
| **WordPress** | The website itself and its administration panel (PHP-FPM). | Only through NGINX |
| **MariaDB** | The database storing posts, pages, users and settings. | Only from inside the stack |

All website content is saved in `/home/aben-hzz/data/`, so stopping or restarting the stack does **not** lose anything.

---

## 2. Starting and Stopping the Project

All commands are run from the root of the repository.

| Command | What it does |
|---------|--------------|
| `make` | Start the stack (builds everything the first time) |
| `make stop` | Pause the containers — fastest to resume |
| `make start` | Resume containers paused with `make stop` |
| `make down` | Stop and remove the containers (data is kept) |
| `make logs` | Show live logs of all services (`Ctrl+C` to exit) |
| `make build` | Rebuild and restart (after a configuration change) |

> ⚠️ **`make fclean` and `make re` permanently delete the website and database content.** Only use them to reset the project to a blank installation.

**First start:** the first `make` takes a few minutes — images are built, then WordPress is downloaded and installed.
Run `make logs` and wait for `Success: WordPress installed successfully.` before opening the site.

---

## 3. Accessing the Website

### Domain name

The domain `aben-hzz.42.fr` must point to the machine running the stack. Check it with:

```bash
grep aben-hzz.42.fr /etc/hosts
```

If nothing is printed, add it:

```bash
echo "127.0.0.1 aben-hzz.42.fr" | sudo tee -a /etc/hosts
```

### Addresses

| Page | URL |
|------|-----|
| Website | https://aben-hzz.42.fr |
| Administration panel | https://aben-hzz.42.fr/wp-admin |

- Only **`https://`** works — plain `http://` is not served.
- If `HTTPS_PORT` in `srcs/.env` is not `443`, add the port: `https://aben-hzz.42.fr:<port>`.

### Certificate warning

The site uses a **self-signed certificate**, so the browser shows a security warning on the first visit.
This is expected: choose **Advanced → Proceed to aben-hzz.42.fr** (wording depends on the browser).

---

## 4. Credentials

### Where they are

Usernames are in `srcs/.env`, passwords are in the `secrets/` directory (one password per file).

| Account | Username | Password file |
|---------|----------|---------------|
| WordPress administrator | `WP_ADMIN_USER` in `srcs/.env` | `secrets/credentials.txt` |
| WordPress author | `WP_USER` in `srcs/.env` | `secrets/wp_user_password.txt` |
| MariaDB WordPress user | `MYSQL_USER` in `srcs/.env` | `secrets/db_password.txt` |
| MariaDB root | `root` | `secrets/db_root_password.txt` |

To read them:

```bash
grep WP_ADMIN_USER srcs/.env
cat secrets/credentials.txt
```

### Keeping them safe

- `srcs/.env` and `secrets/` are ignored by Git — **never** commit, copy or share them.
- Passwords are never written in the Dockerfiles or in the containers' environment; containers read them from `/run/secrets/`.

### Changing a password

> **Important:** the password files are only read **during the first installation**.
> Editing a file afterwards does **not** change the existing password.

**WordPress passwords** — change them from the administration panel:
**Users → Profile → Set New Password**, then update the matching file in `secrets/` so it stays accurate.

Or from the terminal:

```bash
docker exec wordpress wp user update <username> --user_pass='<new_password>' \
    --path=/var/www/html --allow-root
```

**Database passwords** — the simplest way is to edit the files in `secrets/` and reinstall with `make re`.
⚠️ This deletes all website content.

---

## 5. Checking That Everything Works

### 1. Containers are running

```bash
docker compose -f srcs/docker-compose.yml ps
```

You should see `mariadb`, `wordpress` and `nginx`, each with a status of **Up**.
A status of **Restarting** means a service keeps crashing — check its logs (step 3).

### 2. The website answers

```bash
curl -kI https://aben-hzz.42.fr
```

The first line should be `HTTP/1.1 200 OK`.

### 3. Logs look normal

```bash
make logs                  # all services
docker logs wordpress      # one service: nginx, wordpress or mariadb
```

A few `waiting for database...` lines at startup are normal: WordPress waits for MariaDB to be ready.

### 4. The database is reachable

```bash
docker exec mariadb sh -c \
    'mariadb -u "$MYSQL_USER" -p"$(cat /run/secrets/db_password)" "$MYSQL_DATABASE" -e "SHOW TABLES;"'
```

This lists the WordPress tables (`wp_posts`, `wp_users`, ...).

### 5. HTTPS is secure

```bash
openssl s_client -connect aben-hzz.42.fr:443 -tls1_2 </dev/null   # handshake succeeds
openssl s_client -connect aben-hzz.42.fr:443 -tls1_3 </dev/null   # handshake succeeds
openssl s_client -connect aben-hzz.42.fr:443 -tls1_1 </dev/null   # handshake fails
```

---

## 6. Common Problems

| Symptom | Likely cause | What to do |
|---------|--------------|------------|
| Browser: *site can't be reached* | Domain not in `/etc/hosts`, or stack stopped | Check section 3, run `make` |
| Browser: *connection is not private* | Self-signed certificate | Expected — proceed anyway |
| **502 Bad Gateway** | WordPress still installing or crashed | Wait a minute, then `docker logs wordpress` |
| *Error establishing a database connection* | MariaDB is down | `docker logs mariadb`, then `make` |
| Endless `waiting for database...` | MariaDB not ready, or database password changed after installation | `docker logs mariadb`; see [DEV_DOC.md](DEV_DOC.md#8-troubleshooting) |
| A container stays in **Restarting** | Configuration error | `docker logs <container>` |
| Can't log in to `/wp-admin` | Wrong username or password changed in the panel | Check section 4 |

For anything deeper (rebuilding, internals, backups), see [DEV_DOC.md](DEV_DOC.md).
