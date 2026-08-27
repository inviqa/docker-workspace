# syntax=docker/dockerfile:1.4
ARG BUILDX_VERSION=0.12.1
ARG COMPOSE_VERSION=2.24.5
ARG HELM_VERSION=3.14.0
ARG KUBESEAL_VERSION=0.25.0
ARG PHP_MAJOR_VERSION=8.2
ARG ALPINE_VERSION=3.19
FROM --platform=$BUILDPLATFORM php:${PHP_MAJOR_VERSION}-cli-alpine${ALPINE_VERSION} AS build
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
  mv "/usr/src/workspace-${WS_VERSION}" /usr/src/workspace
  cd /usr/src/workspace
  export COMPOSER_ALLOW_SUPERUSER=1
  composer install
  composer compile
EOF

FROM docker/buildx-bin:$BUILDX_VERSION as buildx

FROM php:${PHP_MAJOR_VERSION}-cli-alpine${ALPINE_VERSION} as alpine
ARG TARGETARCH
ARG COMPOSE_VERSION
ARG COMPOSE_V1_INSTALL=no
ARG HELM_VERSION
ARG KUBESEAL_VERSION

COPY --from=buildx /buildx /usr/libexec/docker/cli-plugins/docker-buildx

RUN <<EOF
  set -o errexit
  set -o nounset

  apk add --no-cache \
    aws-cli \
    bash \
    docker-cli \
    $([ "$COMPOSE_V1_INSTALL" != yes ] || echo docker-compose) \
    git \
    git-lfs \
    grep \
    jq \
    openssh-client \
    rsync

  # docker compose v2
  mkdir -p /usr/libexec/docker/cli-plugins
  wget -O /usr/libexec/docker/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)"
  chmod +x  /usr/libexec/docker/cli-plugins/docker-compose

  # docker compose v2 standalone alias
  if [ "$COMPOSE_V1_INSTALL" != yes ]; then
    ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose
  fi

  # helm2
  wget -O helm.tar.gz "https://get.helm.sh/helm-v2.17.0-linux-${TARGETARCH}.tar.gz"
  tar -C /usr/local/bin --strip-components=1 -zxvf helm.tar.gz "linux-${TARGETARCH}/helm"
  mv /usr/local/bin/helm /usr/local/bin/helm2
  rm ./helm.tar.gz

  # helm 
  wget -O helm.tar.gz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"
  tar -C /usr/local/bin --strip-components=1 -zxvf helm.tar.gz "linux-${TARGETARCH}/helm"
  rm ./helm.tar.gz

  # mutagen
  if [ "$TARGETARCH" = amd64 ]; then
    wget -O mutagen.tar.gz  "https://github.com/mutagen-io/mutagen/releases/download/v0.18.1/mutagen_linux_${TARGETARCH}_v0.18.1.tar.gz"
    tar -C /usr/local/bin -zxvf mutagen.tar.gz
    rm ./mutagen.tar.gz
  fi

  # kubeseal
  curl --silent --show-error --fail --location --output kubeseal.tar.gz "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${TARGETARCH}.tar.gz"
  tar -C /usr/local/bin -zxvf kubeseal.tar.gz kubeseal
  rm ./kubeseal.tar.gz

  addgroup -g 998 docker
  adduser -u 1000 -D ws
  adduser ws docker
EOF

COPY --from=build "/usr/src/workspace/ws.phar" /usr/local/bin/ws
RUN chmod +x /usr/local/bin/ws && /usr/local/bin/ws --help

ENTRYPOINT [ "/usr/local/bin/ws" ]
