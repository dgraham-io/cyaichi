.PHONY: run server test fmt

run:
	go run ./cmd/cyaichi-server

server: run

test:
	go test ./...

fmt:
	gofmt -w $$(find . -name '*.go' -type f)
