FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
     nginx openssl

RUN mkdir -p /etc/nginx/ssl && \
     openssl req -x509 -nodes -days 365 \
          -newkey rsa:2048 \
          -keyout /etc/nginx/ssl/inception.key \
          -out /etc/nginx/ssl/inception.crt \
          -subj "/C=MA/L=BenGuerir/O=42/CN=aben-hzz.42.fr"

COPY conf/nginx.conf /etc/nginx/

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]


