# Building dlu-certbot with the `certbot renew` run command.
# 02.09.2021 | v1.0
cd /***/***/certbot
docker build -t 'dlu-certbot:renew' -f renew/Dockerfile . 2>&1 | tee -a /***/***/logs/dlu-certbot-build_$(date +'%Y_%m').log
