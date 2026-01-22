package main

import (
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"go.temporal.io/sdk/client"
)

type Server struct {
	temporalClient client.Client
}

func main() {
	log.Println("Starting Temporal API Service...")

	// Conectar al servidor Temporal
	temporalHostPort := os.Getenv("TEMPORAL_HOST_PORT")
	if temporalHostPort == "" {
		temporalHostPort = "localhost:7233"
	}
	log.Printf("Connecting to Temporal at: %s", temporalHostPort)

	c, err := client.Dial(client.Options{
		HostPort: temporalHostPort,
	})
	if err != nil {
		log.Fatalf("Unable to create Temporal client: %v", err)
	}
	defer c.Close()
	log.Println("Successfully connected to Temporal server")

	server := &Server{
		temporalClient: c,
	}

	// Configurar handlers HTTP
	http.HandleFunc("/health", server.healthHandler)
	http.HandleFunc("/workflows/start", server.startWorkflowHandler)
	http.HandleFunc("/workflows/status", server.workflowStatusHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Canal para capturar señales de shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Iniciar servidor HTTP en goroutine
	go func() {
		log.Printf("API Server listening on port %s", port)
		if err := http.ListenAndServe(":"+port, nil); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Esperar señal de shutdown
	<-sigChan
	log.Println("Shutting down API server gracefully...")
}
