# Backend service — a Bash HTTP server on Alpine (busybox nc provides the socket).
FROM alpine:3.20

# bash for the script, busybox nc is already in the base image.
RUN apk add --no-cache bash

WORKDIR /app
COPY app/server.sh /app/server.sh
RUN chmod +x /app/server.sh

ENV PORT=8080 APP_VERSION=1.0.0
EXPOSE 8080

# Run as an unprivileged user — zero-trust habit from Day 18.
RUN adduser -D -H app
USER app

ENTRYPOINT ["/app/server.sh"]
