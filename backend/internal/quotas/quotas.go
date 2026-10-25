// Package quotas provides per-user daily quotas for actions like creating
// spots, updates, reviews and reports. Quotas reset at midnight UTC.
package quotas

import (
	"sync"
	"time"
)

// Tracker holds per-user daily counters. It is safe for concurrent use.
type Tracker struct {
	mu           sync.Mutex
	counters     map[uint64]*userCounters
	limitSpots   int
	limitUpdates int
	limitReviews int
	limitReports int
}

type userCounters struct {
	day       int // YYYYMMDD in UTC
	spots     int
	updates   int
	reviews   int
	reports   int
}

// Config holds the daily limits per user. Zero means unlimited.
type Config struct {
	SpotsPerDay   int
	UpdatesPerDay int
	ReviewsPerDay int
	ReportsPerDay int
}

// NewTracker returns a quota tracker with the given config.
func NewTracker(cfg Config) *Tracker {
	if cfg.SpotsPerDay == 0 {
		cfg.SpotsPerDay = 10
	}
	if cfg.UpdatesPerDay == 0 {
		cfg.UpdatesPerDay = 50
	}
	if cfg.ReviewsPerDay == 0 {
		cfg.ReviewsPerDay = 20
	}
	if cfg.ReportsPerDay == 0 {
		cfg.ReportsPerDay = 10
	}
	return &Tracker{
		counters:     make(map[uint64]*userCounters),
		limitSpots:   cfg.SpotsPerDay,
		limitUpdates: cfg.UpdatesPerDay,
		limitReviews: cfg.ReviewsPerDay,
		limitReports: cfg.ReportsPerDay,
	}
}

// Allow checks if the user can perform an action of the given kind today.
// It returns true if allowed (and increments the counter), false if quota exceeded.
func (t *Tracker) Allow(uid uint64, kind Kind) bool {
	t.mu.Lock()
	defer t.mu.Unlock()

	now := time.Now().UTC()
	today := now.Year()*10000 + int(now.Month())*100 + now.Day()

	uc := t.counters[uid]
	if uc == nil || uc.day != today {
		uc = &userCounters{day: today}
		t.counters[uid] = uc
	}

	// Clean up old entries occasionally
	if len(t.counters) > 10000 && now.Minute() == 0 {
		for k, v := range t.counters {
			if v.day != today {
				delete(t.counters, k)
			}
		}
	}

	switch kind {
	case Spots:
		if t.limitSpots > 0 && uc.spots >= t.limitSpots {
			return false
		}
		uc.spots++
	case Updates:
		if t.limitUpdates > 0 && uc.updates >= t.limitUpdates {
			return false
		}
		uc.updates++
	case Reviews:
		if t.limitReviews > 0 && uc.reviews >= t.limitReviews {
			return false
		}
		uc.reviews++
	case Reports:
		if t.limitReports > 0 && uc.reports >= t.limitReports {
			return false
		}
		uc.reports++
	}
	return true
}

// Kind identifies the action type for quota tracking.
type Kind int

const (
	Spots Kind = iota
	Updates
	Reviews
	Reports
)