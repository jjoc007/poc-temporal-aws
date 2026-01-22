package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// WorkflowB es un workflow hijo que es invocado por WorkflowA
// Este workflow ejecuta su propia activity (Activity4)
func WorkflowB(ctx workflow.Context, input string) (string, error) {
	logger := workflow.GetLogger(ctx)
	logger.Info("WorkflowB (child workflow) started", "input", input)

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
	// Ejecutar Activity4 (específica de WorkflowB)
	// ==========================================
	logger.Info("Executing Activity4...")
	var result string
	err := workflow.ExecuteActivity(ctx, "Activity4", input).Get(ctx, &result)
	if err != nil {
		logger.Error("Activity4 failed", "error", err)
		return "", fmt.Errorf("Activity4 failed: %w", err)
	}
	logger.Info("Activity4 completed", "result", result)

	// ==========================================
	// WorkflowB completado exitosamente
	// ==========================================
	logger.Info("WorkflowB completed successfully", "result", result)
	return result, nil
}
