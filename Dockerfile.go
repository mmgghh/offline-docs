# Go standard-library docs via pkgsite (the engine behind pkg.go.dev)
#
# Serves full, searchable API docs for the entire Go stdlib, built from
# the source in GOROOT — no network needed at runtime.

FROM golang:1.25-alpine AS builder
ENV GOBIN=/usr/local/bin
RUN go install golang.org/x/pkgsite/cmd/pkgsite@latest

FROM golang:1.25-alpine
COPY --from=builder /usr/local/bin/pkgsite /usr/local/bin/
ENV GOPROXY=off
WORKDIR /src
RUN go mod init placeholder
EXPOSE 8080
CMD ["pkgsite", "-http=:8080", "."]
