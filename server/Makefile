.PHONY: server test fmt

server:
	go run ./cmd/cyaichi-server

test:
	go test ./...

fmt:
	gofmt -w $$(find . -name '*.go' -type f)
