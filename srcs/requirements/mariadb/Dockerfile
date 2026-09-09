FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    mariadb-server mariadb-client 

RUN rm -rf /var/lib/mysql/*

RUN mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/
COPY tools/init.sh /usr/local/bin/init.sh

RUN chmod +x /usr/local/bin/init.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/init.sh"]
