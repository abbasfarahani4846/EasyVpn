# EasyVPN Go core build targets.
#
# TAGS is mandatory: without it sing-box silently drops protocols ("uTLS is not
# included in this build", QUIC/Hysteria2/TUIC, WireGuard, OpenVPN, ...).
# `make test` runs the registration test against the same tag set.
#
# easycoreproc (process-mode core, CGO_ENABLED=0): builds everywhere without a C
#   compiler — the desktop default.
# libeasycore (c-shared FFI library): needs a C toolchain; used on Android
#   (jniLibs) and as the desktop in-process fallback.

TAGS := with_quic,with_wireguard,with_openvpn,with_clash_api,with_gvisor,with_utls
LDFLAGS := -s -w
OUT := ../bin

.PHONY: all test vet proc windows-proc linux-proc darwin-proc lib-windows lib-linux lib-darwin lib-android clean

all: proc

test:
	go vet -tags $(TAGS) ./...
	go test -tags $(TAGS) ./...

vet:
	go vet -tags $(TAGS) ./...

proc: linux-proc windows-proc darwin-proc

windows-proc:
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -o $(OUT)/easycoreproc-windows-amd64.exe ./cmd/easycoreproc

linux-proc:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -o $(OUT)/easycoreproc-linux-amd64 ./cmd/easycoreproc

darwin-proc:
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -o $(OUT)/easycoreproc-darwin-arm64 ./cmd/easycoreproc

lib-windows:
	CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -buildmode=c-shared -o $(OUT)/easycore.dll ./cmd/libeasycore

lib-linux:
	CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -buildmode=c-shared -o $(OUT)/libeasycore.so ./cmd/libeasycore

lib-darwin:
	CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -buildmode=c-shared -o $(OUT)/libeasycore.dylib ./cmd/libeasycore

# Android needs the NDK: NDK_BIN=<ndk>/toolchains/llvm/prebuilt/<host>/bin  API=24
lib-android:
	CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC=$(NDK_BIN)/aarch64-linux-android$(API)-clang go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -buildmode=c-shared -o ../android/app/src/main/jniLibs/arm64-v8a/libeasycore.so ./cmd/libeasycore
	CGO_ENABLED=1 GOOS=android GOARCH=amd64 CC=$(NDK_BIN)/x86_64-linux-android$(API)-clang go build -tags $(TAGS) -ldflags="$(LDFLAGS)" -buildmode=c-shared -o ../android/app/src/main/jniLibs/x86_64/libeasycore.so ./cmd/libeasycore

clean:
	rm -rf $(OUT)
