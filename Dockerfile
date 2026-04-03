# Offline documentation — single image, multi-stage build
#
# Each stage fetches docs from upstream; BuildKit builds them in parallel.
# The final stage copies everything into one nginx container.
#
# Update the ARGs below when newer versions are released.

# ===== Python docs from docs.python.org =====
FROM alpine:3.21 AS python-docs
ARG PYTHON_VERSION=3.13
RUN apk add --no-cache curl && mkdir /docs && \
    curl -fsSL \
      "https://docs.python.org/${PYTHON_VERSION}/archives/python-${PYTHON_VERSION}-docs-html.tar.bz2" \
    | tar xj --strip-components=1 -C /docs/

# ===== PostgreSQL docs from PGDG apt repo =====
FROM debian:bookworm-slim AS pgsql-docs
ARG PG_MAJOR=17
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    install -d /usr/share/postgresql-common/pgdg && \
    curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get download "postgresql-doc-${PG_MAJOR}" && \
    dpkg -x postgresql-doc-${PG_MAJOR}_*.deb /tmp/pkg && \
    html=$(find /tmp/pkg -name "index.html" -printf '%h\n' | head -1) && \
    [ -n "$html" ] && cp -r "$html" /docs

# ===== Git HTML docs from kernel.org =====
FROM alpine:3.21 AS git-docs
ARG GIT_VERSION=2.53.0
RUN apk add --no-cache curl && mkdir /docs && \
    curl -fsSL \
      "https://mirrors.edge.kernel.org/pub/software/scm/git/git-htmldocs-${GIT_VERSION}.tar.gz" \
    | tar xz -C /docs/

# ===== Docker CLI docs from GitHub (latest) =====
FROM alpine:3.21 AS docker-docs
RUN apk add --no-cache curl pandoc && \
    mkdir -p /tmp/src /docs && \
    curl -fsSL "https://github.com/docker/cli/archive/refs/heads/master.tar.gz" \
      | tar xz -C /tmp/src --strip-components=1 && \
    find /tmp/src/docs -name "*.md" | sort | while read mdfile; do \
        rel="${mdfile#/tmp/src/docs/}"; \
        outfile="/docs/${rel%.md}.html"; \
        mkdir -p "$(dirname "$outfile")"; \
        pandoc --standalone --metadata title="$(basename "${rel%.md}")" \
               -f markdown -t html5 "$mdfile" -o "$outfile" 2>/dev/null || true; \
    done && \
    printf '<html><head><meta charset="utf-8"><title>Docker CLI Reference</title></head><body>\n<h1>Docker CLI Reference</h1><ul>\n' \
        > /docs/index.html && \
    find /docs -name "*.html" ! -name "index.html" | sort | while read f; do \
        rel="${f#/docs/}"; \
        printf '<li><a href="%s">%s</a></li>\n' "$rel" "${rel%.html}"; \
    done >> /docs/index.html && \
    printf '</ul></body></html>\n' >> /docs/index.html

# ===== Debian Reference from Debian packages =====
FROM debian:bookworm-slim AS debian-docs
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && \
    apt-get download debian-reference-common debian-reference-en && \
    dpkg -x debian-reference-common_*.deb /tmp/pkg && \
    dpkg -x debian-reference-en_*.deb /tmp/pkg && \
    cp -r /tmp/pkg/usr/share/debian-reference /docs && \
    printf '<html><head><meta http-equiv="refresh" content="0; url=index.en.html"></head>\n<body><a href="index.en.html">Debian Reference</a></body></html>\n' \
        > /docs/index.html

# ===== SQLAlchemy docs — self-hosted zip =====
FROM alpine:3.21 AS sqlalchemy-docs
ARG SQLA_VERSION=20
RUN apk add --no-cache curl unzip && mkdir /docs && \
    curl -fsSL -o /tmp/docs.zip \
      "https://docs.sqlalchemy.org/en/${SQLA_VERSION}/sqlalchemy_${SQLA_VERSION}.zip" && \
    unzip -q /tmp/docs.zip -d /tmp/u && \
    f=$(find /tmp/u -mindepth 1 -maxdepth 1 -name index.html | head -1) && d=$(dirname "$f") && \
    [ -n "$d" ] && cp -a "$d"/. /docs/ && \
    rm -rf /tmp/docs.zip /tmp/u

# ===== Django docs — official HTML zip =====
FROM alpine:3.21 AS django-docs
ARG DJANGO_VERSION=5.1
RUN apk add --no-cache curl unzip && mkdir /docs && \
    curl -fsSL -o /tmp/docs.zip \
      "https://media.djangoproject.com/docs/django-docs-${DJANGO_VERSION}-en.zip" && \
    unzip -q /tmp/docs.zip -d /tmp/u && \
    f=$(find /tmp/u -mindepth 1 -maxdepth 1 -name index.html | head -1) && d=$(dirname "$f") && \
    [ -n "$d" ] && cp -a "$d"/. /docs/ && \
    rm -rf /tmp/docs.zip /tmp/u

# ===== Nginx docs — mirror from nginx.org =====
FROM alpine:3.21 AS nginx-docs-dl
RUN apk add --no-cache wget && mkdir /docs && \
    wget -r -l5 -np -nH --cut-dirs=2 -k \
      -P /docs \
      "https://nginx.org/en/docs/" 2>/dev/null || true && \
    [ -f /docs/index.html ]

# ===== uWSGI docs — build from source with Sphinx =====
FROM python:3.13-slim AS uwsgi-docs
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    git clone --depth 1 https://github.com/unbit/uwsgi-docs.git /tmp/src && \
    pip install --no-cache-dir sphinx && \
    sphinx-build -b html /tmp/src /docs

# ===== Celery docs — build from source with Sphinx =====
FROM python:3.13-slim AS celery-docs
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    git clone --depth 1 https://github.com/celery/celery.git /tmp/src && \
    cd /tmp/src && \
    pip install --no-cache-dir -e . && \
    pip install --no-cache-dir sphinx sphinx_celery sphinx_click && \
    sphinx-build -b html /tmp/src/docs /docs

# ===== Final image — one nginx serves everything =====
FROM nginx:alpine

COPY --link --from=python-docs /docs/ /usr/share/nginx/html/python/
COPY --link --from=pgsql-docs  /docs/ /usr/share/nginx/html/postgresql/
COPY --link --from=git-docs    /docs/ /usr/share/nginx/html/git/
COPY --link --from=docker-docs /docs/ /usr/share/nginx/html/docker/
COPY --link --from=debian-docs /docs/ /usr/share/nginx/html/debian/
COPY --link --from=sqlalchemy-docs /docs/ /usr/share/nginx/html/sqlalchemy/
COPY --link --from=django-docs     /docs/ /usr/share/nginx/html/django/
COPY --link --from=nginx-docs-dl   /docs/ /usr/share/nginx/html/nginx/
COPY --link --from=uwsgi-docs      /docs/ /usr/share/nginx/html/uwsgi/
COPY --link --from=celery-docs     /docs/ /usr/share/nginx/html/celery/
COPY nginx.conf /etc/nginx/nginx.conf
RUN chmod -R a+rX /usr/share/nginx/html

USER 101
EXPOSE 8080
