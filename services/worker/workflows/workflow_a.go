package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// WorkflowA es el workflow principal que orquesta múltiples activities
// y ejecuta un workflow hijo (WorkflowB)
func WorkflowA(ctx workflow.Context, input string) (string, error) {
	logger := workflow.GetLogger(ctx)
	logger.Info("WorkflowA started", "input", input)

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
	// PASO 1: Ejecutar Activity1
	// ==========================================
	logger.Info("Executing Activity1...")
	var result1 string
	err := workflow.ExecuteActivity(ctx, "Activity1", input).Get(ctx, &result1)
	if err != nil {
		logger.Error("Activity1 failed", "error", err)
		return "", fmt.Errorf("Activity1 failed: %w", err)
	}
	logger.Info("Activity1 completed", "result", result1)

	// ==========================================
	// PASO 2: Ejecutar Activity2
	// ==========================================
	logger.Info("Executing Activity2...")
	var result2 string
	err = workflow.ExecuteActivity(ctx, "Activity2", result1).Get(ctx, &result2)
	if err != nil {
		logger.Error("Activity2 failed", "error", err)
		return "", fmt.Errorf("Activity2 failed: %w", err)
	}
	logger.Info("Activity2 completed", "result", result2)

	// ==========================================
	// PASO 3: Ejecutar Child Workflow (WorkflowB)
	// ==========================================
	logger.Info("Starting child workflow (WorkflowB)...")

	childWorkflowOptions := workflow.ChildWorkflowOptions{
		WorkflowID:          fmt.Sprintf("workflow-b-child-%d", workflow.Now(ctx).Unix()),
		TaskQueue:           "hello-world-queue",
		WorkflowRunTimeout:  5 * time.Minute,
		WorkflowTaskTimeout: 1 * time.Minute,
		RetryPolicy: &temporal.RetryPolicy{
			MaximumAttempts: 3,
		},
	}

	childCtx := workflow.WithChildOptions(ctx, childWorkflowOptions)

	var childResult string
	childWorkflowFuture := workflow.ExecuteChildWorkflow(childCtx, WorkflowB, result2)

	// Esperar a que el child workflow complete
	err = childWorkflowFuture.Get(childCtx, &childResult)
	if err != nil {
		logger.Error("Child workflow (WorkflowB) failed", "error", err)
		return "", fmt.Errorf("Child workflow failed: %w", err)
	}

	// Obtener información del child workflow
	var childExecution workflow.Execution
	childWorkflowFuture.GetChildWorkflowExecution().Get(childCtx, &childExecution)
	logger.Info("Child workflow completed",
		"childWorkflowID", childExecution.ID,
		"childRunID", childExecution.RunID,
		"result", childResult)

	// ==========================================
	// PASO 4: Ejecutar Activity3 (actividad final)
	// ==========================================
	logger.Info("Executing Activity3 (final activity)...")
	var finalResult string
	err = workflow.ExecuteActivity(ctx, "Activity3", childResult).Get(ctx, &finalResult)
	if err != nil {
		logger.Error("Activity3 failed", "error", err)
		return "", fmt.Errorf("Activity3 failed: %w", err)
	}
	logger.Info("Activity3 completed", "result", finalResult)

	// ==========================================
	// Workflow completado exitosamente
	// ==========================================
	logger.Info("WorkflowA completed successfully", "finalResult", finalResult)
	return finalResult, nil
}
