# EasyVPN Go core build targets.
#
# easycoreproc (process-mode core, CGO_ENABLED=0):
#   builds everywhere without a C compiler — the desktop default.
# libeasycore (c-shared FFI library):
#   requires a C toolchain (gcc/clang); used on Android (jniLibs) and as the
#   desktop in-process fallback. CI sets CGO_ENABLED=1 with mingw/clang.

.PHONY: all proc windows-proc linux-proc darwin-proc lib-windows lib-linux lib-darwin lib-android clean

all: proc

proc: windows-proc

windows-proc:
	@echo "Building Windows process core..."
	CGO_ENABLED=0 go build -ldflags="-s -w" -o ../bin/easycoreproc-windows-amd64.exe ./cmd/easycoreproc

linux-proc:
	@echo "Building Linux process core..."
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ../bin/easycoreproc-linux-amd64 ./cmd/easycoreproc

darwin-proc:
	@echo "Building macOS process core..."
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o ../bin/easycoreproc-darwin-arm64 ./cmd/easycoreproc

lib-windows:
	@echo "Building Windows FFI DLL (requires gcc/mingw)..."
	CGO_ENABLED=1 go build -ldflags="-s -w" -buildmode=c-shared -o ../bin/easycore.dll ./cmd/libeasycore

lib-linux:
	@echo "Building Linux FFI .so (requires gcc)..."
	CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -buildmode=c-shared -o ../bin/libeasycore.so ./cmd/libeasycore

lib-darwin:
	@echo "Building macOS FFI .dylib (requires clang)..."
	CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -buildmode=c-shared -o ../bin/libeasycore.dylib ./cmd/libeasycore

lib-android:
	@echo "Building Android FFI .so (requires NDK toolchain in PATH)..."
	CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$(NDK_CC)" go build -ldflags="-s -w" -buildmode=c-shared -o ../android/app/src/main/jniLibs/arm64-v8a/libeasycore.so ./cmd/libeasycore

clean:
	rm -rf ../bin
