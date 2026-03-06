.PHONY: run server test fmt docs

run:
	go run ./cmd/cyaichi-server

server: run

test:
	go test ./...

fmt:
	gofmt -w $$(find . -name '*.go' -type f)

docs:
	go run ./cmd/apidocgen
