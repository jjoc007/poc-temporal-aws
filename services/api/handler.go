package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"go.temporal.io/sdk/client"
)

// StartWorkflowRequest define la estructura del payload para iniciar un workflow
type StartWorkflowRequest struct {
	WorkflowID string                 `json:"workflowId"`
	Input      map[string]interface{} `json:"input"`
}

// StartWorkflowResponse define la respuesta al iniciar un workflow
type StartWorkflowResponse struct {
	WorkflowID string `json:"workflowId"`
	RunID      string `json:"runId"`
	Message    string `json:"message"`
}

// WorkflowStatusResponse define la respuesta al consultar el estado
type WorkflowStatusResponse struct {
	WorkflowID string `json:"workflowId"`
	RunID      string `json:"runId"`
	Status     string `json:"status"`
	Result     string `json:"result,omitempty"`
	Error      string `json:"error,omitempty"`
}

// ErrorResponse define el formato de error estándar
type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

// healthHandler maneja el health check
func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
		"time":   time.Now().Format(time.RFC3339),
	})
}

// startWorkflowHandler inicia un nuevo workflow
func (s *Server) startWorkflowHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req StartWorkflowRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Error decoding request: %v", err)
		respondWithError(w, http.StatusBadRequest, "Invalid request payload", err.Error())
		return
	}

	// Validaciones básicas
	if req.WorkflowID == "" {
		respondWithError(w, http.StatusBadRequest, "workflowId is required", "")
		return
	}

	// Opciones del workflow
	workflowOptions := client.StartWorkflowOptions{
		ID:        req.WorkflowID,
		TaskQueue: "hello-world-queue",
	}

	// Iniciar el workflow
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Convertir el input a JSON string
	inputBytes, err := json.Marshal(req.Input)
	if err != nil {
		log.Printf("Error marshaling input: %v", err)
		respondWithError(w, http.StatusBadRequest, "Invalid input format", err.Error())
		return
	}
	inputStr := string(inputBytes)

	workflowRun, err := s.temporalClient.ExecuteWorkflow(
		ctx,
		workflowOptions,
		"WorkflowA", // Nombre del workflow
		inputStr,    // Pasar el input como string JSON
	)
	if err != nil {
		log.Printf("Error starting workflow: %v", err)
		respondWithError(w, http.StatusInternalServerError, "Failed to start workflow", err.Error())
		return
	}

	log.Printf("Started workflow - ID: %s, RunID: %s", workflowRun.GetID(), workflowRun.GetRunID())

	// Respuesta exitosa
	response := StartWorkflowResponse{
		WorkflowID: workflowRun.GetID(),
		RunID:      workflowRun.GetRunID(),
		Message:    "Workflow started successfully",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// workflowStatusHandler consulta el estado de un workflow
func (s *Server) workflowStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	workflowID := r.URL.Query().Get("workflowId")
	runID := r.URL.Query().Get("runId")

	if workflowID == "" {
		respondWithError(w, http.StatusBadRequest, "workflowId parameter is required", "")
		return
	}

	// Obtener el workflow
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	workflowRun := s.temporalClient.GetWorkflow(ctx, workflowID, runID)

	// Intentar obtener el resultado (esto espera si el workflow está corriendo)
	var result string
	err := workflowRun.Get(ctx, &result)

	response := WorkflowStatusResponse{
		WorkflowID: workflowID,
		RunID:      runID,
	}

	if err != nil {
		// Si hay error, el workflow puede estar corriendo o falló
		if ctx.Err() == context.DeadlineExceeded {
			response.Status = "running"
		} else {
			response.Status = "failed"
			response.Error = err.Error()
		}
	} else {
		response.Status = "completed"
		response.Result = result
	}

	// En producción, se debería usar DescribeWorkflowExecution para obtener más detalles
	describeCtx, describeCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer describeCancel()

	description, err := s.temporalClient.DescribeWorkflowExecution(describeCtx, workflowID, runID)
	if err == nil {
		response.Status = description.WorkflowExecutionInfo.Status.String()
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// respondWithError helper para enviar respuestas de error
func respondWithError(w http.ResponseWriter, code int, error string, details string) {
	response := ErrorResponse{
		Error:   error,
		Message: details,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(response)
}

// Añadir campo Message a WorkflowStatusResponse
type WorkflowStatusResponseExt struct {
	WorkflowStatusResponse
	Message string `json:"message,omitempty"`
}
