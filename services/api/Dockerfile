# Multi-stage build para API Service
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
    -o api-service .

# Stage 2: Runtime
FROM alpine:3.19

# Instalar certificados CA, timezone data y curl para health checks
RUN apk --no-cache add ca-certificates tzdata curl

# Crear usuario no-root
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Crear directorio de la aplicación
WORKDIR /app

# Copiar binario desde builder
COPY --from=builder /build/api-service /app/api-service

# Cambiar ownership
RUN chown -R appuser:appuser /app

# Cambiar a usuario no-root
USER appuser

# Exponer puerto
EXPOSE 8080

# Variables de entorno por defecto
ENV PORT=8080
ENV TEMPORAL_HOST_PORT=temporal-frontend:7233

# Nota: Health check manejado por ECS, no por Docker

# Ejecutar el servicio
ENTRYPOINT ["/app/api-service"]
