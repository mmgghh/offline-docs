# Offline Docs

A fully offline, self-hosted documentation server. One `docker compose up` gives you searchable, browsable docs for 11 tools and frameworks — no internet required at runtime.

## Included Documentation

| Documentation | Source | Version |
|---|---|---|
| Python | [docs.python.org](https://docs.python.org) | 3.13 |
| Go (stdlib) | [pkg.go.dev](https://pkg.go.dev) via pkgsite | 1.25 |
| PostgreSQL | PGDG apt repo | 17 |
| Git | [kernel.org](https://mirrors.edge.kernel.org) | 2.53.0 |
| Docker CLI | [github.com/docker/cli](https://github.com/docker/cli) | latest |
| Debian Reference | Debian packages | bookworm |
| SQLAlchemy | [docs.sqlalchemy.org](https://docs.sqlalchemy.org) | 20 |
| Django | [djangoproject.com](https://www.djangoproject.com) | 5.1 |
| Nginx | [nginx.org](https://nginx.org/en/docs/) | latest |
| uWSGI | [github.com/unbit/uwsgi-docs](https://github.com/unbit/uwsgi-docs) | latest |
| Celery | [github.com/celery/celery](https://github.com/celery/celery) | latest |

## Quick Start

```bash
docker compose up --build -d
```

Browse to [http://localhost:8080](http://localhost:8080).

## Architecture

The build uses a multi-stage Dockerfile. Each documentation set is fetched in its own stage, and BuildKit builds them all in parallel. The final stage copies everything into a single nginx container that serves static files.

Go docs are the exception — they run as a separate `go-doc` service using [pkgsite](https://pkg.go.dev/golang.org/x/pkgsite), which provides full search and API browsing of the Go standard library. The main nginx container reverse-proxies to it under `/go/`.

```
┌──────────────────────────────────────────┐
│            nginx  (:8080)                │
│                                          │
│  /python/       static HTML              │
│  /postgresql/   static HTML              │
│  /git/          static HTML              │
│  /docker/       static HTML (from md)    │
│  /debian/       static HTML              │
│  /sqlalchemy/   static HTML              │
│  /django/       static HTML (Sphinx)     │
│  /nginx/        static HTML (mirrored)   │
│  /uwsgi/        static HTML (Sphinx)     │
│  /celery/       static HTML (Sphinx)     │
│  /go/  ──────►  go-doc pkgsite (:8080)   │
└──────────────────────────────────────────┘
```

## Updating Versions

Edit the `ARG` values at the top of each build stage in `Dockerfile`:

```dockerfile
ARG PYTHON_VERSION=3.13
ARG PG_MAJOR=17
ARG GIT_VERSION=2.53.0
ARG SQLA_VERSION=20
ARG DJANGO_VERSION=5.1
```

Then rebuild:

```bash
docker compose up --build -d
```

## License

[Apache License 2.0](LICENSE)
