FROM golang:1.19 as builder

ENV GO111MODULE=on

WORKDIR /app

COPY go.mod go.mod
COPY go.sum go.sum

RUN go mod download

COPY main.go main.go

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -a -o simulated_server main.go

# TODO: see if this base image is good (consider using fedora)
#FROM alpine:3.14
FROM fedora:36
WORKDIR /
COPY --from=builder /app/simulated_server .
EXPOSE 8080

ENTRYPOINT ["/simulated_server"]

#docker build -f ./Dockerfile -t docker.io/yanivdocker92/simulated_tls_server:0.0.1 .
