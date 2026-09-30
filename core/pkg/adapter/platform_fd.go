package adapter

import (
	"context"
	"errors"
	"net/netip"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/logger"
)

// fdPlatform is a minimal adapter.PlatformInterface for hosts that create the
// TUN device themselves and hand the file descriptor to the core (Android's
// VpnService.Builder.establish()). Everything except OpenInterface keeps the
// defaults so sing-box behaves as it does on desktop.
//
// The Android host excludes its own package from the VPN, so the core's outbound
// sockets never loop back into the tunnel and no per-socket protect() callback
// is required.
type fdPlatform struct {
	fd        int
	myAddress []netip.Addr
}

func newFDPlatform(fd int) adapter.PlatformInterface { return &fdPlatform{fd: fd} }

func (p *fdPlatform) Initialize(adapter.NetworkManager) error { return nil }

func (p *fdPlatform) UsePlatformAutoDetectInterfaceControl() bool { return false }
func (p *fdPlatform) AutoDetectInterfaceControl(int) error        { return nil }

func (p *fdPlatform) UsePlatformInterface() bool { return true }

func (p *fdPlatform) OpenInterface(options *tun.Options, _ option.TunPlatformOptions) (tun.Tun, error) {
	if p.fd <= 0 {
		return nil, errors.New("no TUN file descriptor was provided by the host")
	}
	dup, err := dupFD(p.fd)
	if err != nil {
		return nil, err
	}
	options.FileDescriptor = dup
	for _, a := range options.Inet4Address {
		p.myAddress = append(p.myAddress, a.Addr())
	}
	for _, a := range options.Inet6Address {
		p.myAddress = append(p.myAddress, a.Addr())
	}
	return tun.New(*options)
}

func (p *fdPlatform) ProcessPlatformOptions(option.TunPlatformOptions) error { return nil }

func (p *fdPlatform) UsePlatformDefaultInterfaceMonitor() bool { return false }
func (p *fdPlatform) CreateDefaultInterfaceMonitor(logger.Logger) tun.DefaultInterfaceMonitor {
	return nil
}

func (p *fdPlatform) UsePlatformNetworkInterfaces() bool { return false }
func (p *fdPlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) {
	return nil, nil
}

func (p *fdPlatform) UnderNetworkExtension() bool              { return false }
func (p *fdPlatform) NetworkExtensionIncludeAllNetworks() bool { return false }

func (p *fdPlatform) ClearDNSCache()                       {}
func (p *fdPlatform) RequestPermissionForWIFIState() error { return nil }
func (p *fdPlatform) ReadWIFIState(context.Context) adapter.WIFIState {
	return adapter.WIFIState{}
}

func (p *fdPlatform) UsePlatformConnectionOwnerFinder() bool { return false }
func (p *fdPlatform) FindConnectionOwner(*adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return nil, errors.New("not supported")
}
func (p *fdPlatform) UsePlatformWIFIMonitor() bool { return false }

func (p *fdPlatform) UsePlatformNotification() bool                { return false }
func (p *fdPlatform) SendNotification(*adapter.Notification) error { return nil }
func (p *fdPlatform) CancelNotification(string, int32) error       { return nil }

func (p *fdPlatform) MyInterfaceAddress() []netip.Addr { return p.myAddress }

func (p *fdPlatform) UsePlatformNeighborResolver() bool                         { return false }
func (p *fdPlatform) StartNeighborMonitor(adapter.NeighborUpdateListener) error { return nil }
func (p *fdPlatform) CloseNeighborMonitor(adapter.NeighborUpdateListener) error { return nil }

func (p *fdPlatform) UsePlatformShell() bool    { return false }
func (p *fdPlatform) CheckPlatformShell() error { return errors.New("not supported") }
func (p *fdPlatform) OpenShellSession(*adapter.PlatformUser, string, []string, string, int32, int32) (adapter.ShellSession, error) {
	return nil, errors.New("not supported")
}
func (p *fdPlatform) LookupUser(string) (*adapter.PlatformUser, error) {
	return nil, errors.New("not supported")
}
func (p *fdPlatform) LookupSFTPServer() (string, error)     { return "", errors.New("not supported") }
func (p *fdPlatform) ReadSystemSSHHostKey() ([]byte, error) { return nil, errors.New("not supported") }
func (p *fdPlatform) TailscaleHostname() string             { return "" }

func (p *fdPlatform) UsePlatformBridge() bool { return false }
func (p *fdPlatform) CreateBridge(adapter.BridgeOptions) (adapter.BridgeSession, error) {
	return nil, errors.New("not supported")
}
