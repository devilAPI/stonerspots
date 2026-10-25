package mail

import (
	"context"
	"testing"
)

func TestConfig_Enabled(t *testing.T) {
	tests := []struct {
		name   string
		cfg    Config
		expect bool
	}{
		{
			name:   "disabled - empty host",
			cfg:    Config{Port: 587, From: "test@example.com"},
			expect: false,
		},
		{
			name:   "disabled - empty from",
			cfg:    Config{Host: "smtp.example.com", Port: 587},
			expect: false,
		},
		{
			name:   "enabled",
			cfg:    Config{Host: "smtp.example.com", Port: 587, From: "test@example.com"},
			expect: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.cfg.Enabled(); got != tt.expect {
				t.Fatalf("Enabled() = %v, want %v", got, tt.expect)
			}
		})
	}
}

func TestNewClient(t *testing.T) {
	cfg := Config{Host: "smtp.example.com", Port: 587, From: "test@example.com"}
	client := NewClient(cfg)
	if client == nil {
		t.Fatal("NewClient returned nil")
	}
}

func TestSend_Disabled(t *testing.T) {
	client := NewClient(Config{})
	err := client.Send(context.Background(), "to@example.com", "Subject", "Body")
	if err != ErrMailDisabled {
		t.Fatalf("expected ErrMailDisabled, got %v", err)
	}
}