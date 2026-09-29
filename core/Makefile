.PHONY: all windows android linux darwin clean

all: windows

windows:
	@echo "Building Windows DLL..."
	go build -ldflags="-s -w" -buildmode=c-shared -o ../lib/assets/bin/windows/easycore.dll ./cmd/libeasycore/main.go

linux:
	@echo "Building Linux .so..."
	GOOS=linux GOARCH=amd64 CGO_ENABLED=1 go build -ldflags="-s -w" -buildmode=c-shared -o ../lib/assets/bin/linux/libeasycore.so ./cmd/libeasycore/main.go

darwin:
	@echo "Building macOS .dylib..."
	GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 go build -ldflags="-s -w" -buildmode=c-shared -o ../lib/assets/bin/macos/libeasycore.dylib ./cmd/libeasycore/main.go

android-arm64:
	@echo "Building Android arm64-v8a .so..."
	GOOS=android GOARCH=arm64 CGO_ENABLED=1 go build -ldflags="-s -w" -buildmode=c-shared -o ../android/app/src/main/jniLibs/arm64-v8a/libeasycore.so ./cmd/libeasycore/main.go

clean:
	rm -rf ../lib/assets/bin
