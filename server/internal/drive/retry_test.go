package drive

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/url"
	"testing"
	"time"

	"google.golang.org/api/googleapi"
)

// fastBackoff shrinks the retry delay so a test that deliberately exhausts
// the budget finishes in milliseconds instead of half a minute.
func fastBackoff(t *testing.T) {
	t.Helper()
	prev := backoffBase
	backoffBase = time.Millisecond
	t.Cleanup(func() { backoffBase = prev })
}

func apiErr(code int, reasons ...string) *googleapi.Error {
	e := &googleapi.Error{Code: code, Message: "boom"}
	for _, r := range reasons {
		e.Errors = append(e.Errors, googleapi.ErrorItem{Reason: r, Message: r})
	}
	return e
}

func TestRetryableClassifier(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"429 too many requests", apiErr(429), true},
		{"500", apiErr(500), true},
		{"502", apiErr(502), true},
		{"503", apiErr(503), true},
		{"504", apiErr(504), true},
		{"403 rateLimitExceeded", apiErr(403, "rateLimitExceeded"), true},
		{"403 userRateLimitExceeded", apiErr(403, "userRateLimitExceeded"), true},
		{"403 sharingRateLimitExceeded", apiErr(403, "sharingRateLimitExceeded"), true},
		{"403 storageQuotaExceeded", apiErr(403, "storageQuotaExceeded"), false},
		{"403 storageQuotaExceeded listed first", apiErr(403, "storageQuotaExceeded", "rateLimitExceeded"), false},
		{"403 no reason", apiErr(403), false},
		{"403 unknown reason", apiErr(403, "insufficientFilePermissions"), false},
		{"400", apiErr(400), false},
		{"401", apiErr(401), false},
		{"404", apiErr(404), false},
		{"501", apiErr(501), false},
		{"plain error", errors.New("nope"), false},
		// The generated Drive client wraps its errors, so a bare type
		// assertion would miss every one of these.
		{"wrapped 503", fmt.Errorf("list snapshots: %w", apiErr(503)), true},
		{"double-wrapped 403 quota", fmt.Errorf("a: %w", fmt.Errorf("b: %w", apiErr(403, "storageQuotaExceeded"))), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Retryable(tc.err); got != tc.want {
				t.Fatalf("Retryable(%v) = %v, want %v", tc.err, got, tc.want)
			}
		})
	}
}

func TestAuthAndNotFoundClassifiers(t *testing.T) {
	if !IsAuthError(fmt.Errorf("wrapped: %w", apiErr(401))) {
		t.Fatal("401 not recognized as an auth error")
	}
	if IsAuthError(apiErr(403, "rateLimitExceeded")) {
		t.Fatal("403 misread as an auth error")
	}
	if IsAuthError(errors.New("plain")) {
		t.Fatal("plain error misread as an auth error")
	}
	if !IsNotFound(fmt.Errorf("wrapped: %w", apiErr(404))) {
		t.Fatal("404 not recognized")
	}
	if IsNotFound(apiErr(400)) {
		t.Fatal("400 misread as 404")
	}
}

func TestClassifyStatus(t *testing.T) {
	netErr := &url.Error{Op: "Post", URL: "https://www.googleapis.com", Err: &net.DNSError{Err: "no such host"}}
	cases := []struct {
		name string
		err  error
		want Status
	}{
		{"nil", nil, StatusIdle},
		{"401", apiErr(401), StatusError},
		{"403 quota", apiErr(403, "storageQuotaExceeded"), StatusError},
		{"429 after backoff", apiErr(429), StatusOffline},
		{"dns failure", netErr, StatusOffline},
		{"context cancelled", context.Canceled, StatusOffline},
		{"local bug", errors.New("merge peer rows: database is locked"), StatusError},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, _ := Classify(tc.err)
			if got != tc.want {
				t.Fatalf("Classify(%v) = %q, want %q", tc.err, got, tc.want)
			}
		})
	}
	if _, msg := Classify(apiErr(401)); msg == "" {
		t.Fatal("401 produced no user-facing message")
	}
}

func TestWithBackoffRetriesOnlyRetryable(t *testing.T) {
	fastBackoff(t)
	ctx := context.Background()

	// A non-retryable error must be returned on the first attempt.
	calls := 0
	err := withBackoff(ctx, func() error {
		calls++
		return apiErr(403, "storageQuotaExceeded")
	})
	if calls != 1 {
		t.Fatalf("storageQuotaExceeded was retried %d times", calls-1)
	}
	if err == nil {
		t.Fatal("non-retryable error was swallowed")
	}

	// A retryable error that clears on the second attempt succeeds.
	calls = 0
	err = withBackoff(ctx, func() error {
		calls++
		if calls == 1 {
			return apiErr(503)
		}
		return nil
	})
	if err != nil || calls != 2 {
		t.Fatalf("withBackoff: err = %v, calls = %d, want nil / 2", err, calls)
	}

	// A cancelled context stops the retry loop instead of sleeping it out.
	cctx, cancel := context.WithCancel(context.Background())
	cancel()
	calls = 0
	start := time.Now()
	err = withBackoff(cctx, func() error {
		calls++
		return apiErr(429)
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("withBackoff on a cancelled context returned %v", err)
	}
	if calls != 1 {
		t.Fatalf("cancelled context still made %d attempts", calls)
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Fatalf("cancelled context slept for %s", elapsed)
	}
}
