package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// WorkflowC es un workflow de validación simple
// Ejecuta activities secuenciales para validar y procesar datos
func WorkflowC(ctx workflow.Context, input string) (string, error) {
	logger := workflow.GetLogger(ctx)
	logger.Info("WorkflowC (validation) started", "input", input)

	// Configurar opciones de activities
	activityOptions := workflow.ActivityOptions{
		StartToCloseTimeout: 30 * time.Second,
		RetryPolicy: &temporal.RetryPolicy{
			InitialInterval:    time.Second,
			BackoffCoefficient: 2.0,
			MaximumInterval:    time.Minute,
			MaximumAttempts:    3,
		},
	}
	ctx = workflow.WithActivityOptions(ctx, activityOptions)

	// ==========================================
	// PASO 1: Validar input con Activity1
	// ==========================================
	logger.Info("WorkflowC: Validating input with Activity1...")
	var validationResult string
	err := workflow.ExecuteActivity(ctx, "Activity1", input).Get(ctx, &validationResult)
	if err != nil {
		logger.Error("WorkflowC: Validation failed", "error", err)
		return "", fmt.Errorf("validation failed: %w", err)
	}
	logger.Info("WorkflowC: Validation successful", "result", validationResult)

	// ==========================================
	// PASO 2: Procesar datos validados con Activity2
	// ==========================================
	logger.Info("WorkflowC: Processing validated data with Activity2...")
	var processResult string
	err = workflow.ExecuteActivity(ctx, "Activity2", validationResult).Get(ctx, &processResult)
	if err != nil {
		logger.Error("WorkflowC: Processing failed", "error", err)
		return "", fmt.Errorf("processing failed: %w", err)
	}
	logger.Info("WorkflowC: Processing successful", "result", processResult)

	// ==========================================
	// WorkflowC completado exitosamente
	// ==========================================
	logger.Info("WorkflowC completed successfully", "finalResult", processResult)
	return processResult, nil
}
