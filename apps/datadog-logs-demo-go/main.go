package main

import (
	"math/rand"
	"os"
	"time"

	log "github.com/sirupsen/logrus"
)

func init() {
	// Configure logrus to output JSON for Datadog
	log.SetFormatter(&log.JSONFormatter{})
	log.SetOutput(os.Stdout)
	log.SetLevel(log.InfoLevel)
}

func main() {
	log.Info("Starting Datadog Logs Demo Application")

	// Run different log generation scenarios
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	scenario := 0
	for range ticker.C {
		scenario = (scenario + 1) % 8

		switch scenario {
		case 0:
			generateBusinessKPILogs()
		case 1:
			generateTransactionLogs()
		case 2:
			generateErrorLogs()
		case 3:
			generatePerformanceLogs()
		case 4:
			generateUserActivityLogs()
		case 5:
			generateAPIRequestLogs()
		case 6:
			generatePaymentProcessingLogs()
		case 7:
			generateSecurityEventLogs()
		}
	}
}

// generateBusinessKPILogs - Logs for business metrics and KPI dashboards
// Use cases: Revenue tracking, conversion rates, customer acquisition
func generateBusinessKPILogs() {
	revenue := rand.Float64() * 1000
	orderCount := rand.Intn(50) + 1
	avgOrderValue := revenue / float64(orderCount)

	log.WithFields(log.Fields{
		"event_type":       "business_kpi",
		"metric_name":      "revenue",
		"revenue":          revenue,
		"order_count":      orderCount,
		"avg_order_value":  avgOrderValue,
		"currency":         "USD",
		"region":           randomRegion(),
		"business_unit":    "ecommerce",
		"payment_method":   randomPaymentMethod(),
		"conversion_rate":  rand.Float64() * 10,
		"customer_segment": randomCustomerSegment(),
	}).Info("Business KPI metrics generated")

	// Generate logs that can be used for custom metrics
	// In Datadog, create a metric from logs using count, sum, avg aggregations on these fields
	log.WithFields(log.Fields{
		"event_type":    "order_completed",
		"order_value":   revenue / float64(orderCount),
		"order_id":      generateOrderID(),
		"customer_type": randomCustomerSegment(),
		"product_count": rand.Intn(10) + 1,
		"discount":      rand.Float64() * 50,
	}).Info("Order completed successfully")
}

// generateTransactionLogs - Logs for transaction tracking and financial monitoring
// Use cases: Payment success/failure rates, transaction volume, fraud detection
func generateTransactionLogs() {
	transactionValue := rand.Float64() * 500
	status := randomTransactionStatus()
	duration := rand.Intn(3000) + 100

	logEntry := log.WithFields(log.Fields{
		"event_type":        "transaction",
		"transaction_id":    generateTransactionID(),
		"transaction_value": transactionValue,
		"transaction_status": status,
		"duration_ms":       duration,
		"payment_gateway":   randomPaymentGateway(),
		"currency":          "USD",
		"country":           randomCountry(),
		"risk_score":        rand.Float64() * 100,
		"merchant_id":       generateMerchantID(),
	})

	if status == "failed" {
		logEntry.Warn("Transaction failed")
	} else if status == "pending" {
		logEntry.Info("Transaction pending")
	} else {
		logEntry.Info("Transaction completed successfully")
	}
}

// generateErrorLogs - Logs for error tracking and alerting
// Use cases: Error rate monitoring, alert on error spikes, debugging
func generateErrorLogs() {
	errorTypes := []string{"validation_error", "database_error", "api_error", "timeout_error", "authentication_error"}
	errorType := errorTypes[rand.Intn(len(errorTypes))]
	errorRate := rand.Float64()

	// Occasionally generate actual errors for alerting
	if errorRate > 0.85 {
		log.WithFields(log.Fields{
			"event_type":     "error",
			"error_type":     errorType,
			"error_message":  generateErrorMessage(errorType),
			"error_code":     generateErrorCode(errorType),
			"service":        "checkout-service",
			"endpoint":       randomEndpoint(),
			"user_id":        generateUserID(),
			"session_id":     generateSessionID(),
			"stack_trace":    generateStackTrace(),
			"severity":       "high",
			"retry_count":    rand.Intn(3),
		}).Error("Critical error occurred")
	} else if errorRate > 0.70 {
		log.WithFields(log.Fields{
			"event_type":    "warning",
			"warning_type":  "rate_limit_approaching",
			"current_rate":  rand.Intn(900) + 100,
			"limit":         1000,
			"service":       "api-gateway",
			"endpoint":      randomEndpoint(),
		}).Warn("Rate limit threshold approaching")
	} else {
		log.WithFields(log.Fields{
			"event_type": "info",
			"message":    "Normal operation",
			"service":    "checkout-service",
		}).Info("Service operating normally")
	}
}

// generatePerformanceLogs - Logs for performance monitoring and analytics
// Use cases: Latency percentiles (p50, p95, p99), throughput, resource utilization
func generatePerformanceLogs() {
	latency := rand.Intn(1000) + 50
	throughput := rand.Intn(1000) + 100

	log.WithFields(log.Fields{
		"event_type":      "performance",
		"metric_type":     "latency",
		"latency_ms":      latency,
		"throughput_rps":  throughput,
		"cpu_usage":       rand.Float64() * 100,
		"memory_usage_mb": rand.Intn(2048),
		"db_query_time":   rand.Intn(500),
		"cache_hit_rate":  rand.Float64() * 100,
		"service":         "api-service",
		"endpoint":        randomEndpoint(),
		"method":          randomHTTPMethod(),
	}).Info("Performance metrics collected")

	// Measure and distribution examples for Datadog analytics
	log.WithFields(log.Fields{
		"event_type":       "measure",
		"measure_name":     "api_response_time",
		"measure_value":    float64(latency),
		"measure_unit":     "milliseconds",
		"endpoint":         randomEndpoint(),
		"status_code":      randomStatusCode(),
	}).Info("API response time measured")
}

// generateUserActivityLogs - Logs for user behavior analytics
// Use cases: User engagement, feature usage, session analytics
func generateUserActivityLogs() {
	activities := []string{"page_view", "button_click", "search", "add_to_cart", "checkout", "signup", "login"}
	activity := activities[rand.Intn(len(activities))]

	log.WithFields(log.Fields{
		"event_type":      "user_activity",
		"activity_type":   activity,
		"user_id":         generateUserID(),
		"session_id":      generateSessionID(),
		"page":            randomPage(),
		"duration_sec":    rand.Intn(300),
		"device_type":     randomDeviceType(),
		"browser":         randomBrowser(),
		"country":         randomCountry(),
		"referrer":        randomReferrer(),
		"ab_test_variant": randomABTestVariant(),
	}).Info("User activity recorded")
}

// generateAPIRequestLogs - Logs for API monitoring and rate limiting
// Use cases: API usage tracking, rate limiting, quota management
func generateAPIRequestLogs() {
	statusCode := randomStatusCode()
	duration := rand.Intn(2000) + 50

	logEntry := log.WithFields(log.Fields{
		"event_type":   "api_request",
		"method":       randomHTTPMethod(),
		"endpoint":     randomEndpoint(),
		"status_code":  statusCode,
		"duration_ms":  duration,
		"request_size": rand.Intn(10000),
		"response_size": rand.Intn(50000),
		"user_agent":   randomUserAgent(),
		"ip_address":   randomIPAddress(),
		"api_key":      generateAPIKey(),
		"rate_limit_remaining": rand.Intn(1000),
	})

	if statusCode >= 500 {
		logEntry.Error("API request failed with server error")
	} else if statusCode >= 400 {
		logEntry.Warn("API request failed with client error")
	} else {
		logEntry.Info("API request completed successfully")
	}
}

// generatePaymentProcessingLogs - Logs for payment processing and fraud detection
// Use cases: Payment success rate, fraud detection, chargeback tracking
func generatePaymentProcessingLogs() {
	amount := rand.Float64() * 1000
	fraudScore := rand.Float64() * 100

	log.WithFields(log.Fields{
		"event_type":       "payment_processing",
		"payment_id":       generatePaymentID(),
		"amount":           amount,
		"currency":         "USD",
		"payment_method":   randomPaymentMethod(),
		"card_type":        randomCardType(),
		"fraud_score":      fraudScore,
		"fraud_status":     getFraudStatus(fraudScore),
		"3ds_verified":     rand.Float64() > 0.5,
		"country":          randomCountry(),
		"merchant_id":      generateMerchantID(),
		"processor":        randomPaymentGateway(),
		"retry_attempt":    rand.Intn(3),
	}).Info("Payment processed")

	// High fraud score alert
	if fraudScore > 80 {
		log.WithFields(log.Fields{
			"event_type":   "fraud_alert",
			"payment_id":   generatePaymentID(),
			"fraud_score":  fraudScore,
			"alert_level":  "high",
			"action_taken": "blocked",
		}).Warn("High fraud score detected - payment blocked")
	}
}

// generateSecurityEventLogs - Logs for security monitoring and compliance
// Use cases: Security alerts, audit trails, compliance reporting
func generateSecurityEventLogs() {
	eventTypes := []string{"login_success", "login_failure", "password_change", "permission_change", "access_denied"}
	eventType := eventTypes[rand.Intn(len(eventTypes))]

	log.WithFields(log.Fields{
		"event_type":    "security_event",
		"security_event": eventType,
		"user_id":       generateUserID(),
		"ip_address":    randomIPAddress(),
		"user_agent":    randomUserAgent(),
		"country":       randomCountry(),
		"timestamp":     time.Now().Unix(),
		"session_id":    generateSessionID(),
		"result":        getSecurityResult(eventType),
	}).Info("Security event logged")

	// Failed login attempts for alerting
	if eventType == "login_failure" && rand.Float64() > 0.7 {
		log.WithFields(log.Fields{
			"event_type":      "security_alert",
			"alert_type":      "multiple_failed_logins",
			"user_id":         generateUserID(),
			"attempt_count":   rand.Intn(10) + 5,
			"ip_address":      randomIPAddress(),
			"time_window_min": 5,
		}).Warn("Multiple failed login attempts detected")
	}
}

// Helper functions for generating random data
func randomRegion() string {
	regions := []string{"us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"}
	return regions[rand.Intn(len(regions))]
}

func randomPaymentMethod() string {
	methods := []string{"credit_card", "debit_card", "paypal", "apple_pay", "google_pay", "bank_transfer"}
	return methods[rand.Intn(len(methods))]
}

func randomCustomerSegment() string {
	segments := []string{"new", "returning", "vip", "enterprise", "small_business"}
	return segments[rand.Intn(len(segments))]
}

func randomTransactionStatus() string {
	statuses := []string{"success", "failed", "pending"}
	weights := []int{80, 10, 10} // 80% success, 10% failed, 10% pending
	r := rand.Intn(100)
	if r < weights[0] {
		return statuses[0]
	} else if r < weights[0]+weights[1] {
		return statuses[1]
	}
	return statuses[2]
}

func randomPaymentGateway() string {
	gateways := []string{"stripe", "paypal", "square", "braintree", "adyen"}
	return gateways[rand.Intn(len(gateways))]
}

func randomCountry() string {
	countries := []string{"US", "UK", "DE", "FR", "JP", "AU", "CA", "SG"}
	return countries[rand.Intn(len(countries))]
}

func randomEndpoint() string {
	endpoints := []string{"/api/v1/users", "/api/v1/orders", "/api/v1/products", "/api/v1/checkout", "/api/v1/payments"}
	return endpoints[rand.Intn(len(endpoints))]
}

func randomHTTPMethod() string {
	methods := []string{"GET", "POST", "PUT", "DELETE", "PATCH"}
	return methods[rand.Intn(len(methods))]
}

func randomStatusCode() int {
	codes := []int{200, 201, 204, 400, 401, 403, 404, 500, 502, 503}
	weights := []int{70, 10, 5, 5, 2, 2, 2, 2, 1, 1}
	r := rand.Intn(100)
	cumulative := 0
	for i, weight := range weights {
		cumulative += weight
		if r < cumulative {
			return codes[i]
		}
	}
	return 200
}

func randomPage() string {
	pages := []string{"home", "products", "cart", "checkout", "account", "search"}
	return pages[rand.Intn(len(pages))]
}

func randomDeviceType() string {
	devices := []string{"desktop", "mobile", "tablet"}
	return devices[rand.Intn(len(devices))]
}

func randomBrowser() string {
	browsers := []string{"Chrome", "Firefox", "Safari", "Edge"}
	return browsers[rand.Intn(len(browsers))]
}

func randomReferrer() string {
	referrers := []string{"google", "facebook", "twitter", "direct", "email"}
	return referrers[rand.Intn(len(referrers))]
}

func randomABTestVariant() string {
	variants := []string{"control", "variant_a", "variant_b"}
	return variants[rand.Intn(len(variants))]
}

func randomUserAgent() string {
	agents := []string{
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0",
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/14.1",
		"Mozilla/5.0 (X11; Linux x86_64) Firefox/89.0",
	}
	return agents[rand.Intn(len(agents))]
}

func randomIPAddress() string {
	return randomIP()
}

func randomCardType() string {
	types := []string{"visa", "mastercard", "amex", "discover"}
	return types[rand.Intn(len(types))]
}

func getFraudStatus(score float64) string {
	if score > 70 {
		return "high_risk"
	} else if score > 40 {
		return "medium_risk"
	}
	return "low_risk"
}

func getSecurityResult(eventType string) string {
	if eventType == "login_failure" || eventType == "access_denied" {
		return "denied"
	}
	return "allowed"
}

func generateOrderID() string {
	return randomString("ORD", 10)
}

func generateTransactionID() string {
	return randomString("TXN", 12)
}

func generateMerchantID() string {
	return randomString("MER", 8)
}

func generateUserID() string {
	return randomString("USR", 8)
}

func generateSessionID() string {
	return randomString("SES", 16)
}

func generatePaymentID() string {
	return randomString("PAY", 12)
}

func generateAPIKey() string {
	return randomString("API", 20)
}

func generateErrorMessage(errorType string) string {
	messages := map[string]string{
		"validation_error":     "Invalid input parameters",
		"database_error":       "Database connection timeout",
		"api_error":            "External API request failed",
		"timeout_error":        "Request timeout exceeded",
		"authentication_error": "Invalid credentials",
	}
	if msg, ok := messages[errorType]; ok {
		return msg
	}
	return "Unknown error"
}

func generateErrorCode(errorType string) string {
	codes := map[string]string{
		"validation_error":     "ERR_VALIDATION_001",
		"database_error":       "ERR_DATABASE_002",
		"api_error":            "ERR_API_003",
		"timeout_error":        "ERR_TIMEOUT_004",
		"authentication_error": "ERR_AUTH_005",
	}
	if code, ok := codes[errorType]; ok {
		return code
	}
	return "ERR_UNKNOWN_000"
}

func generateStackTrace() string {
	return "at main.processPayment(main.go:123)\nat main.handleRequest(main.go:89)\nat main.main(main.go:45)"
}

func randomString(prefix string, length int) string {
	const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[rand.Intn(len(charset))]
	}
	return prefix + "_" + string(b)
}

func randomIP() string {
	return randomIPv4()
}

func randomIPv4() string {
	return randomIPSegment() + "." + randomIPSegment() + "." + randomIPSegment() + "." + randomIPSegment()
}

func randomIPSegment() string {
	segments := []string{"192", "10", "172", "203", "8"}
	return segments[rand.Intn(len(segments))]
}
