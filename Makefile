# Test DSN (needs CREATE/DROP DATABASE, hence root):
#   root:stonerspots@tcp(127.0.0.1:3307)/?parseTime=true&multiStatements=true
# Override with TEST_DATABASE_URL.
TEST_DATABASE_URL ?= root:stonerspots@tcp(127.0.0.1:3307)/?parseTime=true&multiStatements=true
export TEST_DATABASE_URL

.PHONY: db-up test run
db-up:
	docker compose up -d --wait

test:
	cd backend && go test ./...

run:
	cd backend && go run ./cmd/api
