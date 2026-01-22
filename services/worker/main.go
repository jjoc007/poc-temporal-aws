package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"

	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"

	"github.com/temporal-aws-poc/worker/activities"
	"github.com/temporal-aws-poc/worker/workflows"
)

func main() {
	log.Println("Starting Temporal Worker Service...")

	// Obtener configuración desde variables de entorno
	temporalHostPort := os.Getenv("TEMPORAL_HOST_PORT")
	if temporalHostPort == "" {
		temporalHostPort = "localhost:7233"
	}

	taskQueue := os.Getenv("TASK_QUEUE")
	if taskQueue == "" {
		taskQueue = "hello-world-queue"
	}

	log.Printf("Connecting to Temporal at: %s", temporalHostPort)
	log.Printf("Task Queue: %s", taskQueue)

	// Crear cliente Temporal
	c, err := client.Dial(client.Options{
		HostPort: temporalHostPort,
	})
	if err != nil {
		log.Fatalf("Unable to create Temporal client: %v", err)
	}
	defer c.Close()
	log.Println("Successfully connected to Temporal server")

	// Crear worker
	w := worker.New(c, taskQueue, worker.Options{
		MaxConcurrentActivityExecutionSize:     5,
		MaxConcurrentWorkflowTaskExecutionSize: 5,
	})

	// Registrar workflows
	w.RegisterWorkflow(workflows.WorkflowA)
	w.RegisterWorkflow(workflows.WorkflowB)
	w.RegisterWorkflow(workflows.WorkflowC)
	w.RegisterWorkflow(workflows.WorkflowD)
	log.Println("Registered workflows: WorkflowA, WorkflowB, WorkflowC, WorkflowD")

	// Crear instancia de activities y registrarlas
	act := activities.NewActivities()
	w.RegisterActivity(act.Activity1)
	w.RegisterActivity(act.Activity2)
	w.RegisterActivity(act.Activity3)
	w.RegisterActivity(act.Activity4)
	log.Println("Registered activities: Activity1, Activity2, Activity3, Activity4")

	// Canal para capturar señales de shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Iniciar worker en goroutine
	go func() {
		log.Println("Worker started and listening for tasks...")
		err = w.Run(worker.InterruptCh())
		if err != nil {
			log.Fatalf("Worker failed: %v", err)
		}
	}()

	// Esperar señal de shutdown
	<-sigChan
	log.Println("Shutting down worker gracefully...")
	w.Stop()
	log.Println("Worker stopped successfully")
}
