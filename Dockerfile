# syntax=docker/dockerfile:1.4
FROM php:7.4-cli-alpine AS build
ARG WS_VERSION=0.2.x

RUN apk add --no-cache bash git icu-dev

RUN <<EOF
  set -o errexit
  set -o nounset

  # box
  wget -O /usr/local/bin/box https://github.com/box-project/box/releases/download/3.11.1/box.phar
  chmod +x /usr/local/bin/box

  # composer
  wget -O /tmp/installer.php https://raw.githubusercontent.com/composer/getcomposer.org/e3e43bde99447de1c13da5d1027545be81736b27/web/installer
  php -r " \
    \$signature = '756890a4488ce9024fc62c56153228907f1545c228516cbf63f885e036d37e9a59d27d63f46af1d4d07ee0f76181c7d3'; \
    \$hash = hash('sha384', file_get_contents('/tmp/installer.php')); \
    if (!hash_equals(\$signature, \$hash)) { \
        unlink('/tmp/installer.php'); \
        echo 'Integrity check failed, installer is either corrupt or worse.' . PHP_EOL; \
        exit(1); \
    }"
  php /tmp/installer.php --no-ansi --install-dir=/usr/bin --filename=composer

  # extensions
  docker-php-ext-install intl

  # workspace
  wget -O /tmp/ws.tar.gz "https://github.com/my127/workspace/archive/${WS_VERSION}.tar.gz"
  tar -C /usr/src -xvf /tmp/ws.tar.gz
  cd "/usr/src/workspace-${WS_VERSION}"
  export COMPOSER_ALLOW_SUPERUSER=1
  composer install
  composer compile
EOF

FROM php:7.4-cli-alpine as alpine
ARG WS_VERSION=0.2.x

RUN <<EOF
  set -o errexit
  set -o nounset

  apk add --no-cache \
    aws-cli \
    bash \
    docker-cli \
    docker-compose \
    git \
    grep \
    jq \
    openssh-client \
    rsync

  # docker compose v2
  mkdir -p /usr/libexec/docker/cli-plugins
  wget -O /usr/libexec/docker/cli-plugins/docker-compose https://github.com/docker/compose/releases/download/v2.12.1/docker-compose-linux-x86_64
  chmod +x  /usr/libexec/docker/cli-plugins/docker-compose

  # helm2
  wget -O helm.tar.gz "https://get.helm.sh/helm-v2.17.0-linux-amd64.tar.gz"
  tar -C /usr/local/bin --strip-components=1 -zxvf helm.tar.gz "linux-amd64/helm"
  mv /usr/local/bin/helm /usr/local/bin/helm2
  rm ./helm.tar.gz

  # helm 
  wget -O helm.tar.gz "https://get.helm.sh/helm-v3.8.2-linux-amd64.tar.gz"
  tar -C /usr/local/bin --strip-components=1 -zxvf helm.tar.gz "linux-amd64/helm"
  rm ./helm.tar.gz

  # mutagen
  wget -O mutagen.tar.gz  "https://github.com/mutagen-io/mutagen/releases/download/v0.11.8/mutagen_linux_amd64_v0.11.8.tar.gz"
  tar -C /usr/local/bin -zxvf mutagen.tar.gz
  rm ./mutagen.tar.gz

  # kubeseal
  wget -O /usr/local/bin/kubeseal https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.12.5/kubeseal-linux-amd64
  chmod +x /usr/local/bin/kubeseal
  addgroup -g 998 docker
  adduser -u 1000 -D ws
  adduser ws docker
EOF

COPY --from=build "/usr/src/workspace-${WS_VERSION}/ws.phar" /usr/local/bin/ws
RUN chmod +x /usr/local/bin/ws && /usr/local/bin/ws

ENTRYPOINT [ "/usr/local/bin/ws" ]

FROM php:7.4-cli-buster as buster
ARG WS_VERSION=0.2.x
ARG HELM_VERSION=2.17.0

RUN <<EOF
  set -o errexit
  set -o nounset

  # docker compose v1
  curl --silent --show-error --fail --location "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  # docker compose v2
  mkdir -p /usr/libexec/docker/cli-plugins
  curl --silent --show-error --fail --location -o /usr/libexec/docker/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/v2.12.1/docker-compose-$(uname -s)-$(uname -m)"
  chmod +x  /usr/libexec/docker/cli-plugins/docker-compose

  echo 'APT::Install-Recommends 0;' >> /etc/apt/apt.conf.d/01norecommends
  echo 'APT::Install-Suggests 0;' >> /etc/apt/apt.conf.d/01norecommends
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get -qq -y --no-install-recommends install \
    apt-transport-https ca-certificates curl gnupg

  curl --silent --show-error --fail --location https://download.docker.com/linux/debian/gpg | apt-key add -qq - >/dev/null
  echo "deb [arch=amd64] https://download.docker.com/linux/debian buster stable" > /etc/apt/sources.list.d/docker.list
 
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get -s dist-upgrade | grep "^Inst" | \
      grep -i securi | awk -F " " '{print $2}' | \
      xargs apt-get -qq -y --no-install-recommends install
 
  DEBIAN_FRONTEND=noninteractive apt-get -qq -y --no-install-recommends install \
   awscli docker-ce-cli git openssh-client jq rsync
   apt-get auto-remove -qq -y
   apt-get clean
   rm -rf /var/lib/apt/lists/*
 
  curl --silent --show-error --fail --location --output helm.tar.gz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
  tar -C /usr/local/bin --strip-components=1 -zxvf helm.tar.gz "linux-amd64/helm"
  rm ./helm.tar.gz

  # kubeseal
  curl --silent --show-error --fail --location --output /usr/local/bin/kubeseal https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.12.5/kubeseal-linux-amd64
  chmod +x /usr/local/bin/kubeseal
EOF

COPY --from=build "/usr/src/workspace-${WS_VERSION}/ws.phar" /usr/local/bin/ws
RUN chmod +x /usr/local/bin/ws && /usr/local/bin/ws

ENTRYPOINT [ "/usr/local/bin/ws" ]
