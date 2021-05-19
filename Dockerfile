FROM php:7.4-cli-alpine AS build
ARG WS_VERSION=0.2.x

RUN apk add --no-cache git icu-dev

RUN \
    # box
    wget -O /usr/local/bin/box https://github.com/box-project/box/releases/download/3.11.1/box.phar \
    && chmod +x /usr/local/bin/box \
    # composer
    && wget -O /tmp/installer.php https://raw.githubusercontent.com/composer/getcomposer.org/e3e43bde99447de1c13da5d1027545be81736b27/web/installer \
    && php -r " \
        \$signature = '756890a4488ce9024fc62c56153228907f1545c228516cbf63f885e036d37e9a59d27d63f46af1d4d07ee0f76181c7d3'; \
        \$hash = hash('sha384', file_get_contents('/tmp/installer.php')); \
        if (!hash_equals(\$signature, \$hash)) { \
            unlink('/tmp/installer.php'); \
            echo 'Integrity check failed, installer is either corrupt or worse.' . PHP_EOL; \
            exit(1); \
        }" \
    && php /tmp/installer.php --no-ansi --install-dir=/usr/bin --filename=composer \
    # extensions
    && docker-php-ext-install intl \
    # workspace
    && wget -O /tmp/ws.tar.gz "https://github.com/my127/workspace/archive/${WS_VERSION}.tar.gz" \
    && tar -C /usr/src -xvf /tmp/ws.tar.gz \
    && cd "/usr/src/workspace-${WS_VERSION}" \
    && composer install \
    && composer compile

FROM php:7.4-cli-alpine
ARG WS_VERSION=0.2.x
ARG HELM_VERSION=2.17.0

RUN \
    apk add --no-cache aws-cli docker-cli bash docker-compose git openssh-client jq rsync \
    # helm
    && wget -O helm.tar.gz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -C /usr/local/bin --strip-components=1 -zxvf helm.tar.gz "linux-amd64/helm" \
    && rm ./helm.tar.gz \
    # kubeseal
    && wget -O /usr/local/bin/kubeseal https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.12.5/kubeseal-linux-amd64 \
    && chmod +x /usr/local/bin/kubeseal

COPY --from=build "/usr/src/workspace-${WS_VERSION}/my127ws.phar" /usr/local/bin/ws
RUN chmod +x /usr/local/bin/ws

ENTRYPOINT [ "/usr/local/bin/ws" ]
