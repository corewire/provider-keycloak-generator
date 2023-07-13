FROM golang:1.20-alpine

RUN mkdir /.cache && chown 1000 /.cache
RUN apk update && apk add bash git make curl

USER 1000
RUN go install golang.org/x/tools/cmd/goimports@latest
