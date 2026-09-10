COMPOSE = docker compose -f srcs/docker-compose.yml
DATA    = /home/aben-hzz/data

all: up

up:
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	$(COMPOSE) up -d

build:
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

logs:
	$(COMPOSE) logs -f

clean: down
	docker system prune -af

fclean: clean
	docker volume rm srcs_db_data srcs_wp_files 2>/dev/null || true
	sudo rm -rf $(DATA)/mariadb/* $(DATA)/wordpress/*

re: fclean all

.PHONY: all up down stop start logs clean fclean re