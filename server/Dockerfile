# ---- build stage ----
FROM golang:1.26-alpine AS build
WORKDIR /src

# Cache dependencies first.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# modernc.org/sqlite is pure Go — no CGO needed.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /tally .

# ---- final stage ----
FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /tally /tally
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/tally"]
