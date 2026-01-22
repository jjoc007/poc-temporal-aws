package workflows

import (
	"fmt"
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"
)

// WorkflowD es un workflow de procesamiento que ejecuta activities en paralelo
// Demuestra el uso de workflow.Go() para ejecución concurrente
func WorkflowD(ctx workflow.Context, input string) (string, error) {
	logger := workflow.GetLogger(ctx)
	logger.Info("WorkflowD (parallel processing) started", "input", input)

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
	// PASO 1: Ejecutar 3 activities en paralelo
	// ==========================================
	logger.Info("WorkflowD: Starting parallel activities...")

	// Canales para recolectar resultados
	var activity1Result, activity2Result, activity4Result string
	var activity1Err, activity2Err, activity4Err error

	// Ejecutar Activity1 en paralelo
	workflow.Go(ctx, func(gCtx workflow.Context) {
		activity1Err = workflow.ExecuteActivity(gCtx, "Activity1", input).Get(gCtx, &activity1Result)
		if activity1Err != nil {
			logger.Error("WorkflowD: Activity1 failed", "error", activity1Err)
		} else {
			logger.Info("WorkflowD: Activity1 completed", "result", activity1Result)
		}
	})

	// Ejecutar Activity2 en paralelo
	workflow.Go(ctx, func(gCtx workflow.Context) {
		activity2Err = workflow.ExecuteActivity(gCtx, "Activity2", input).Get(gCtx, &activity2Result)
		if activity2Err != nil {
			logger.Error("WorkflowD: Activity2 failed", "error", activity2Err)
		} else {
			logger.Info("WorkflowD: Activity2 completed", "result", activity2Result)
		}
	})

	// Ejecutar Activity4 en paralelo
	workflow.Go(ctx, func(gCtx workflow.Context) {
		activity4Err = workflow.ExecuteActivity(gCtx, "Activity4", input).Get(gCtx, &activity4Result)
		if activity4Err != nil {
			logger.Error("WorkflowD: Activity4 failed", "error", activity4Err)
		} else {
			logger.Info("WorkflowD: Activity4 completed", "result", activity4Result)
		}
	})

	// Esperar a que todas las activities paralelas completen
	// Usar un selector o simplemente dormir para dar tiempo a las goroutines
	workflow.Sleep(ctx, 10*time.Second)

	// Verificar errores
	if activity1Err != nil {
		return "", fmt.Errorf("Activity1 failed: %w", activity1Err)
	}
	if activity2Err != nil {
		return "", fmt.Errorf("Activity2 failed: %w", activity2Err)
	}
	if activity4Err != nil {
		return "", fmt.Errorf("Activity4 failed: %w", activity4Err)
	}

	// ==========================================
	// PASO 2: Consolidar resultados con Activity3
	// ==========================================
	logger.Info("WorkflowD: All parallel activities completed, consolidating results...")

	// Combinar resultados
	consolidatedInput := fmt.Sprintf("Parallel results: [%s, %s, %s]",
		activity1Result, activity2Result, activity4Result)

	var finalResult string
	err := workflow.ExecuteActivity(ctx, "Activity3", consolidatedInput).Get(ctx, &finalResult)
	if err != nil {
		logger.Error("WorkflowD: Consolidation failed", "error", err)
		return "", fmt.Errorf("consolidation failed: %w", err)
	}

	// ==========================================
	// WorkflowD completado exitosamente
	// ==========================================
	logger.Info("WorkflowD completed successfully", "finalResult", finalResult)
	return finalResult, nil
}
