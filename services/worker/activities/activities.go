package activities

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"go.temporal.io/sdk/activity"
)

// Activities struct contiene las implementaciones de todas las activities
type Activities struct{}

// Activity1 procesa el input inicial y retorna un resultado transformado
func (a *Activities) Activity1(ctx context.Context, input string) (string, error) {
	logger := activity.GetLogger(ctx)
	logger.Info("Activity1 started", "input", input)

	// Simular procesamiento
	time.Sleep(1 * time.Second)

	// Parsear el input si es JSON
	var inputData map[string]interface{}
	if err := json.Unmarshal([]byte(input), &inputData); err != nil {
		// Si no es JSON, usar como string simple
		inputData = map[string]interface{}{
			"raw_input": input,
		}
	}

	// Agregar información de procesamiento
	inputData["activity1_processed"] = true
	inputData["activity1_timestamp"] = time.Now().Format(time.RFC3339)
	inputData["activity1_message"] = "Input received and validated"

	// Convertir de vuelta a JSON
	result, err := json.Marshal(inputData)
	if err != nil {
		logger.Error("Failed to marshal result", "error", err)
		return "", fmt.Errorf("failed to marshal result: %w", err)
	}

	resultStr := string(result)
	logger.Info("Activity1 completed successfully", "result", resultStr)

	return resultStr, nil
}

// Activity2 valida y enriquece los datos del paso anterior
func (a *Activities) Activity2(ctx context.Context, input string) (string, error) {
	logger := activity.GetLogger(ctx)
	logger.Info("Activity2 started", "input", input)

	// Simular procesamiento más largo
	time.Sleep(2 * time.Second)

	// Parsear el input
	var inputData map[string]interface{}
	if err := json.Unmarshal([]byte(input), &inputData); err != nil {
		logger.Error("Failed to parse input", "error", err)
		return "", fmt.Errorf("failed to parse input: %w", err)
	}

	// Validar que Activity1 se ejecutó
	if processed, ok := inputData["activity1_processed"].(bool); !ok || !processed {
		logger.Warn("Activity1 was not executed properly")
	}

	// Enriquecer datos
	inputData["activity2_processed"] = true
	inputData["activity2_timestamp"] = time.Now().Format(time.RFC3339)
	inputData["activity2_validation"] = "Data validated and enriched"
	inputData["activity2_status"] = "success"

	// Agregar metadata adicional
	if message, exists := inputData["message"]; exists {
		inputData["original_message"] = message
		inputData["enriched_message"] = fmt.Sprintf("Processed: %v", message)
	}

	// Convertir de vuelta a JSON
	result, err := json.Marshal(inputData)
	if err != nil {
		logger.Error("Failed to marshal result", "error", err)
		return "", fmt.Errorf("failed to marshal result: %w", err)
	}

	resultStr := string(result)
	logger.Info("Activity2 completed successfully", "result", resultStr)

	return resultStr, nil
}

// Activity3 realiza el procesamiento final después del child workflow
func (a *Activities) Activity3(ctx context.Context, input string) (string, error) {
	logger := activity.GetLogger(ctx)
	logger.Info("Activity3 (final) started", "input", input)

	// Simular procesamiento
	time.Sleep(1 * time.Second)

	// Parsear el input
	var inputData map[string]interface{}
	if err := json.Unmarshal([]byte(input), &inputData); err != nil {
		logger.Error("Failed to parse input", "error", err)
		return "", fmt.Errorf("failed to parse input: %w", err)
	}

	// Validar que los pasos anteriores se ejecutaron
	validations := []string{}
	if processed, ok := inputData["activity1_processed"].(bool); ok && processed {
		validations = append(validations, "Activity1: OK")
	}
	if processed, ok := inputData["activity2_processed"].(bool); ok && processed {
		validations = append(validations, "Activity2: OK")
	}
	if processed, ok := inputData["activity4_processed"].(bool); ok && processed {
		validations = append(validations, "Activity4 (WorkflowB): OK")
	}

	// Crear resultado final
	finalData := map[string]interface{}{
		"workflow_completed": true,
		"completion_time":    time.Now().Format(time.RFC3339),
		"validations":        validations,
		"final_status":       "SUCCESS",
		"message":            "WorkflowA completed successfully with child workflow",
		"all_data":           inputData,
	}

	// Convertir a JSON
	result, err := json.Marshal(finalData)
	if err != nil {
		logger.Error("Failed to marshal result", "error", err)
		return "", fmt.Errorf("failed to marshal result: %w", err)
	}

	resultStr := string(result)
	logger.Info("Activity3 completed successfully - Workflow chain finished", "result", resultStr)

	return resultStr, nil
}

// Activity4 es específica del child workflow (WorkflowB)
func (a *Activities) Activity4(ctx context.Context, input string) (string, error) {
	logger := activity.GetLogger(ctx)
	logger.Info("Activity4 (in WorkflowB) started", "input", input)

	// Simular procesamiento
	time.Sleep(1500 * time.Millisecond)

	// Parsear el input
	var inputData map[string]interface{}
	if err := json.Unmarshal([]byte(input), &inputData); err != nil {
		logger.Error("Failed to parse input", "error", err)
		return "", fmt.Errorf("failed to parse input: %w", err)
	}

	// Procesar en el contexto del child workflow
	inputData["activity4_processed"] = true
	inputData["activity4_timestamp"] = time.Now().Format(time.RFC3339)
	inputData["activity4_message"] = "Processed in child workflow (WorkflowB)"
	inputData["child_workflow_execution"] = "WorkflowB"

	// Transformación específica del child workflow
	if enrichedMsg, exists := inputData["enriched_message"]; exists {
		inputData["child_transformation"] = strings.ToUpper(fmt.Sprintf("%v", enrichedMsg))
	}

	// Convertir de vuelta a JSON
	result, err := json.Marshal(inputData)
	if err != nil {
		logger.Error("Failed to marshal result", "error", err)
		return "", fmt.Errorf("failed to marshal result: %w", err)
	}

	resultStr := string(result)
	logger.Info("Activity4 completed successfully", "result", resultStr)

	return resultStr, nil
}

// NewActivities crea una nueva instancia de Activities
func NewActivities() *Activities {
	return &Activities{}
}
