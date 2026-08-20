package drive

import (
	"context"
	"errors"
	"math/rand"
	"net/http"
	"time"

	"golang.org/x/oauth2"
	"google.golang.org/api/googleapi"
)

// Backoff parameters. Google recommends
// min(((2^n)+random_number_milliseconds), maximum_backoff) with jitter up to
// 1000 ms; docs/ARCHITECTURE.md caps us at ~32 s.
const (
	maxAttempts = 6
	maxBackoff  = 32 * time.Second
)

// backoffBase is the 2^0 delay unit. It is a variable purely so tests can
// shrink it; production always uses one second.
var backoffBase = time.Second

// Retryable classifies a Drive API error per docs/ARCHITECTURE.md:
// retry 429 and 5xx, and a 403 ONLY when its reason is a rate limit. Never
// retry 400/401/404, and never retry 403 storageQuotaExceeded — that one is
// permanent (out of space, or a service account, which owns no quota).
//
// The generated Drive client wraps its errors, so this must use errors.As
// rather than a bare type assertion.
func Retryable(err error) bool {
	if err == nil {
		return false
	}
	var ae *googleapi.Error
	if !errors.As(err, &ae) {
		// Not an API error: a transport/DNS failure. The caller treats these
		// as "offline" and simply waits for the next scheduled pass.
		return false
	}
	switch ae.Code {
	case http.StatusTooManyRequests,
		http.StatusInternalServerError,
		http.StatusBadGateway,
		http.StatusServiceUnavailable,
		http.StatusGatewayTimeout:
		return true
	case http.StatusForbidden:
		for _, e := range ae.Errors {
			switch e.Reason {
			case "rateLimitExceeded", "userRateLimitExceeded", "sharingRateLimitExceeded":
				return true
			case "storageQuotaExceeded":
				return false
			}
		}
		return false
	}
	return false
}

// IsAuthError reports a refresh token Google has rejected. It is not
// transient: the user has to re-run `tally auth`.
//
// Two very different error shapes mean the same thing:
//
//   - A *googleapi.Error with code 401 — the access token in hand was refused
//     by the Drive API.
//   - A *oauth2.RetrieveError — the refresh itself was refused at the token
//     endpoint. This is the shape a revoked or expired (consent screen left
//     "In testing" → 7-day) refresh token actually produces: oauth2's
//     Transport fails inside RoundTrip, so no Drive response ever exists for
//     googleapi.CheckResponse to look at and http.Client hands back a
//     *url.Error instead. Without this branch Classify falls through to its
//     net/url branch and reports the dead token as `offline` forever.
//
// A token endpoint that is merely unhappy (429 or 5xx) is NOT an auth error:
// the saved token may still be perfectly good, so those stay transient.
func IsAuthError(err error) bool {
	var ae *googleapi.Error
	if errors.As(err, &ae) && ae.Code == http.StatusUnauthorized {
		return true
	}
	var re *oauth2.RetrieveError
	if !errors.As(err, &re) {
		return false
	}
	if re.Response == nil {
		return true
	}
	code := re.Response.StatusCode
	return code != http.StatusTooManyRequests && code < 500
}

// IsNotFound reports HTTP 404 — used to invalidate a cached folder id.
func IsNotFound(err error) bool {
	var ae *googleapi.Error
	return errors.As(err, &ae) && ae.Code == http.StatusNotFound
}

// withBackoff runs op, retrying only errors Retryable accepts, with
// exponential backoff plus jitter capped at maxBackoff.
func withBackoff(ctx context.Context, op func() error) error {
	var err error
	for n := 0; n < maxAttempts; n++ {
		if err = op(); err == nil || !Retryable(err) {
			return err
		}
		d := time.Duration(1<<uint(n))*backoffBase + time.Duration(rand.Int63n(int64(backoffBase)))
		if d > maxBackoff {
			d = maxBackoff
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(d):
		}
	}
	return err
}
