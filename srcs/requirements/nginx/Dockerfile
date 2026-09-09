FROM debian:bookworm
#the "no-install-recommends => skips extra"recommended packages by debian".
RUN apt-get update && apt-get install -y --no-install-recommends \
     nginx openssl

RUN mkdir -p /etc/nginx/ssl && \
     openssl req -x509 -nodes -days 356 \
          -newkey rsa:2048 \
          -keyout /etc/nginx/ssl/inception.key \
          -out /etc/nginx/ssl/inception.crt \
          -subj "/C=MA/L=BenGuerir/O=42/CN=aben-hzz.42.fr"

COPY conf/nginx.conf /etc/nginx/

CMD ["nginx", "-g", "daemon off;"]












# next step the conf of nginx
# read about deleting the APT package list in RUN later