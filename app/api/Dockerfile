FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY src/ ./src/

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o api-service ./src

FROM scratch

WORKDIR /app

COPY --from=builder /app/api-service /api-service

EXPOSE 8080

ENV PORT=8080
ENV FAIL_RATE=0.0

USER 1000:1000

CMD ["/api-service"]