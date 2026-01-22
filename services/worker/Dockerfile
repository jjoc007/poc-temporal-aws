# Multi-stage build para Worker Service
# Stage 1: Build
FROM golang:1.21-alpine AS builder

# Instalar dependencias de compilación
RUN apk add --no-cache git ca-certificates tzdata

# Establecer directorio de trabajo
WORKDIR /build

# Copiar módulos de Go primero (mejor caching)
COPY go.mod go.sum ./
RUN go mod download
RUN go mod verify

# Copiar código fuente
COPY . .

# Compilar el binario (estático, sin CGO)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-w -s -extldflags "-static"' \
    -a \
    -o worker-service .

# Stage 2: Runtime
FROM alpine:3.19

# Instalar certificados CA y timezone data
RUN apk --no-cache add ca-certificates tzdata

# Crear usuario no-root
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Crear directorio de la aplicación
WORKDIR /app

# Copiar binario desde builder
COPY --from=builder /build/worker-service /app/worker-service

# Cambiar ownership
RUN chown -R appuser:appuser /app

# Cambiar a usuario no-root
USER appuser

# Variables de entorno por defecto
ENV TEMPORAL_HOST_PORT=temporal-frontend:7233
ENV TASK_QUEUE=hello-world-queue

# Ejecutar el worker
ENTRYPOINT ["/app/worker-service"]
