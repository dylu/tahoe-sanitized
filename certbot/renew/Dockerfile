# Dockerfile for certbot -- for used with DNS1 / NameSilo
# dlu
# 02.08.2021
# dlu-certbot renew v1.0

FROM certbot/certbot:v1.12.0
WORKDIR /var/***/cache
WORKDIR /var/***/letsencrypt
COPY common/*.sh ./
COPY common/cli.ini /***/letsencrypt

# Libraries and Directories that the auth hook scripts rely on.
RUN ["apk", "add", "--no-cache", "bash", "curl", "libxml2-utils", "grep"]

# CMD list of stuff to do after container starts (stuff to pass to certbot)
# If both ENTRYPOINT and CMD are specified, CMD is appended to ENTRYPOINT.
# The following Entrypoint is already specified by FROM container.
# ENTRYPOINT ["certbot"]

CMD ["renew"]
# CMD ["certonly"]
# CMD ["certonly",	\
# 	"--config-dir", "/***/letsencrypt"]
