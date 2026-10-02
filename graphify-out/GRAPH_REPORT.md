# Graph Report - EasyVpn  (2026-10-02)

## Corpus Check
- 197 files · ~196,703 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2441 nodes · 4297 edges · 137 communities (112 shown, 25 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 337 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9762b340`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- models.dart
- Server
- freePort
- Client
- core_provider.dart
- Manager
- settingsProvider
- NewEngine
- GeneratedPluginRegistrant.swift
- Manager
- ffi_transport.dart
- common.dart
- desktop_shell.dart
- parser.go
- core_bridge.dart
- NewParser
- node_list_provider.dart
- brand.dart
- app.dart
- build_outbound.go
- dashboard_page.dart
- package:flutter_riverpod/flutter_riverpod.dart
- core_integration_test.dart
- routing_page.dart
- update_service.dart
- simple_home.dart
- ConsumerState
- my_application.cc
- home_menu.dart
- adapter.go
- env.dart
- connection_page.dart
- ping_provider.dart
- location_picker.dart
- platform_service.dart
- Default
- rules_provider.dart
- profiles_provider.dart
- Engine
- node_repository.dart
- Options
- app_test.dart
- proxies_page.dart
- SingBoxAdapter
- ProxyNode
- BuildRouteRules
- pump_app.dart
- process_transport.dart
- subscription_page.dart
- fdPlatform
- string
- EasyVpnService
- strings.dart
- speed_test_page.dart
- xray.go
- MainActivity
- routing_actions.dart
- core_transport.dart
- package:flutter/material.dart
- app_database.dart
- bootstrap.dart
- profilesProvider
- FlutterWindow
- Fetch
- add_sheet.dart
- Create
- win32_window.cpp
- testChunk
- .Start
- Tracker
- export.go
- core_locator.dart
- formatters.dart
- site_check_page.dart
- update
- nav_provider.dart
- Win32Window
- engine.go
- Detect
- secret_store.dart
- wWinMain
- file_io.dart
- model.go
- fake_transport.dart
- bool get
- .TestNodesURL
- router_test.go
- models/models.dart
- VpnTileService
- buildChain
- dart:io
- .OpenInterface
- BootReceiver
- display_text.dart
- CoreTransport
- .OpenShellSession
- RegisterPlugins
- .CloseNeighborMonitor
- .CreateBridge
- .CreateDefaultInterfaceMonitor
- .FindConnectionOwner
- .ReadWIFIState
- platformLogger
- newFDPlatform
- TestWithLocalDNS
- strings_v2.dart
- generate_icons.py
- .Initialize
- .NetworkInterfaces
- .SendNotification
- fetch_wintun.sh
- package_macos.sh
- bool?
- ConnMode
- Size
- String?
- T
- easyvpn/core
- main
- sysproxy_darwin.go
- EasyVPN v2 plan: all-in-one, one-button
- database_test.dart
- Building EasyVPN
- Exception
- package:flutter_test/flutter_test.dart
- CLAUDE.md
- README.md
- README.md

## God Nodes (most connected - your core abstractions)
1. `ProxyNode` - 115 edges
2. `settingsProvider` - 57 edges
3. `envProvider` - 55 edges
4. `Engine` - 51 edges
5. `coreControllerProvider` - 41 edges
6. `fdPlatform` - 36 edges
7. `NewParser()` - 25 edges
8. `Manager` - 24 edges
9. `buildOptionsWithTags()` - 23 edges
10. `Win32Window` - 22 edges

## Surprising Connections (you probably didn't know these)
- `buildOptionsWithTags()` --calls--> `_Duration`  [EXTRACTED]
  core/pkg/adapter/adapter.go → lib/features/dashboard/dashboard_page.dart
- `URLTestOptions` --references--> `_Duration`  [EXTRACTED]
  core/pkg/adapter/urltest_batch.go → lib/features/dashboard/dashboard_page.dart
- `xrayURLTest()` --references--> `_Duration`  [EXTRACTED]
  core/pkg/adapter/urltest_xray.go → lib/features/dashboard/dashboard_page.dart
- `_DnsFieldState` --inherits--> `State`  [EXTRACTED]
  lib/features/routing/routing_page.dart → core/pkg/engine/engine.go
- `_ScanPageState` --inherits--> `State`  [EXTRACTED]
  lib/features/scan/scan_page.dart → core/pkg/engine/engine.go

## Import Cycles
- None detected.

## Communities (137 total, 25 thin omitted)

### Community 0 - "models.dart"
Cohesion: 0.02
Nodes (120): accent, activeNodeId, activeProfileId, allowLan, amoled, appearance, AppearanceSettings, autoBackup (+112 more)

### Community 1 - "Server"
Cohesion: 0.10
Nodes (30): AEAD, Decrypt(), Encrypt(), newGCM(), Open(), Seal(), T, TestRoundTripAndWrongPassphrase() (+22 more)

### Community 2 - "freePort"
Cohesion: 0.10
Nodes (50): matrixCase, optionsJSON, NewSingBoxAdapter(), Box, newBoxFromJSON(), countingForwarder(), Int64, T (+42 more)

### Community 3 - "Client"
Cohesion: 0.07
Nodes (40): Context, Engine, Expand(), FetchLocations(), flag(), Context, IsWindscribeConfig(), nodeName() (+32 more)

### Community 4 - "core_provider.dart"
Cohesion: 0.06
Nodes (38): dart:collection, LogLine, TrafficStats, add, capability, city, clear, connect (+30 more)

### Community 5 - "Manager"
Cohesion: 0.06
Nodes (22): platformBackend(), DefaultBypass(), Mutex, RawMessage, gset(), platformBackend(), New(), platformBackend() (+14 more)

### Community 6 - "settingsProvider"
Cohesion: 0.07
Nodes (53): ConsumerWidget, AppShell, build, EasyVpnApp, _handle, initState, _Root, _RootState (+45 more)

### Community 7 - "NewEngine"
Cohesion: 0.06
Nodes (41): Conn, T, TestStopCancelsStartInProgress(), NewEngine(), PrepareRuntime(), writable(), T, itoa() (+33 more)

### Community 8 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (34): Any, app_links, Cocoa, dynamic_color, file_picker, Flutter, flutter_secure_storage_macos, FlutterAppDelegate (+26 more)

### Community 9 - "Manager"
Cohesion: 0.11
Nodes (21): sha256hex(), Context, Mutex, Time, LoadBuiltinRegistry(), New(), T, TestAddCustomRejectsHTTP() (+13 more)

### Community 10 - "ffi_transport.dart"
Cohesion: 0.05
Nodes (42): dart:ffi, DynamicLibrary, Isolate, cacheDir, _Call, _CallC, _control, coreCall (+34 more)

### Community 11 - "common.dart"
Cohesion: 0.08
Nodes (23): action, build, c, confirm, copyText, hint, icon, initial (+15 more)

### Community 12 - "desktop_shell.dart"
Cohesion: 0.05
Nodes (40): advanced, applyWindowProfile, build, child, createState, DesktopShell, _DesktopShellState, dispose (+32 more)

### Community 13 - "parser.go"
Cohesion: 0.16
Nodes (29): clashConfig, parseAnyTLS(), parseSSH(), clashProxyToNode(), clashXHTTPExtra(), decodeBase64Loose(), displayName(), firstStr() (+21 more)

### Community 14 - "core_bridge.dart"
Cohesion: 0.06
Nodes (35): addRuleSet, backupDecrypt, backupEncrypt, cancelPing, countries, decodeQr, dumpConfig, events (+27 more)

### Community 15 - "NewParser"
Cohesion: 0.15
Nodes (24): T, TestSameNodeAcrossClashXrayURI(), T, TestAnyTLSAndSSH(), TestBase64WithSlashAndWrappedLines(), TestParseOVPN(), TestParseWGQuickWithAWG(), TestRealWorldFixtures() (+16 more)

### Community 16 - "node_list_provider.dart"
Cohesion: 0.06
Nodes (33): applyLatency, build, copyWith, cursor, _debounce, delete, favoritesFirst, _gen (+25 more)

### Community 17 - "brand.dart"
Cohesion: 0.06
Nodes (33): 1, bad, Brand, build, busy, child, cleanName, color (+25 more)

### Community 18 - "app.dart"
Cohesion: 0.08
Nodes (23): features/dashboard/dashboard_page.dart, features/home/simple_home.dart, features/logs/logs_page.dart, features/onboarding/onboarding_page.dart, features/proxies/proxies_page.dart, features/routing/routing_page.dart, features/settings/settings_page.dart, features/subscription/subscription_page.dart (+15 more)

### Community 19 - "build_outbound.go"
Cohesion: 0.17
Nodes (29): builtNode, UnsupportedError, orDefaultStr(), Endpoint, openVPNEndpoint(), anyTLSOutbound(), buildNode(), buildOutbound() (+21 more)

### Community 20 - "dashboard_page.dart"
Cohesion: 0.07
Nodes (30): AnimationController, CustomPainter, DateTime?, availableModes, canConnect, _ChartPainter, color, _ConnectButton (+22 more)

### Community 21 - "package:flutter_riverpod/flutter_riverpod.dart"
Cohesion: 0.17
Nodes (12): app.dart, ../../core/providers/nav_provider.dart, ../../core/providers/routing_actions.dart, build, _busy, _choices, createState, _detected (+4 more)

### Community 22 - "core_integration_test.dart"
Cohesion: 0.06
Nodes (31): package:easyvpn/core/bridge/ffi_transport.dart, package:easyvpn/core/bridge/process_transport.dart, blob, cancel, client, close, echo, expectLater (+23 more)

### Community 23 - "routing_page.dart"
Cohesion: 0.10
Nodes (20): ../../core/providers/rules_provider.dart, _ago, _c, _ChipList, _countryChoices, createState, _DnsField, _DnsFieldState (+12 more)

### Community 24 - "update_service.dart"
Cohesion: 0.06
Nodes (31): _arch, asset, buildChannel, _buildChannelDefine, buildLabel, check, copyWith, _core (+23 more)

### Community 25 - "simple_home.dart"
Cohesion: 0.07
Nodes (31): CoreStatus, _c, compact, core, createState, didUpdateWidget, dispose, icon (+23 more)

### Community 26 - "ConsumerState"
Cohesion: 0.05
Nodes (43): 10. IMPLEMENTATION ROADMAP (execute in order; each phase ends with its checklist), 11. EXPLICIT NON-GOALS (do not build now), 12. WHEN IN DOUBT (decision rules for the implementing AI), 1. MISSION, 2.1 Protocol matrix, 2.2 Censorship reality (design input, not a guarantee), 2. VERIFIED TECHNOLOGY STACK (use exactly these), 3.1 Core embedding rules (critical — do not deviate) (+35 more)

### Community 27 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 28 - "home_menu.dart"
Cohesion: 0.12
Nodes (15): ../add/add_sheet.dart, build, _items, _MenuSheet, MenuTarget, _pageFor, showHomeMenu, showModalBottomSheet (+7 more)

### Community 29 - "adapter.go"
Cohesion: 0.13
Nodes (20): ConnMode, CoreAdapter, platformLogger, selectable, StartRequest, TLSTricks, TunSettings, applyTricks() (+12 more)

### Community 30 - "env.dart"
Cohesion: 0.09
Nodes (23): ../bridge/core_bridge.dart, ../database/app_database.dart, ../database/node_repository.dart, GeneratedDatabase, CoreBridge, AppDatabase, AppEnv, core (+15 more)

### Community 31 - "connection_page.dart"
Cohesion: 0.12
Nodes (16): ../core/providers/core_provider.dart, ../../core/theme/app_theme.dart, ../../core/util/platform_service.dart, ../dashboard/dashboard_page.dart, Future, AppearancePage, build, _AppPicker (+8 more)

### Community 32 - "ping_provider.dart"
Cohesion: 0.09
Nodes (23): core_provider.dart, double get, _applyFinal, copyWith, done, error, _flushTimer, isTesting (+15 more)

### Community 33 - "location_picker.dart"
Cohesion: 0.07
Nodes (27): home_menu.dart, createState, _cursor, _debounce, dispose, _favOnly, initState, isTestingPing (+19 more)

### Community 34 - "platform_service.dart"
Cohesion: 0.08
Nodes (25): _ch, _desktopAutoStart, establishVpn, installApk, InstalledApp, installedApps, isAndroid, isDesktop (+17 more)

### Community 35 - "Default"
Cohesion: 0.20
Nodes (24): BuildOptions(), contains(), T, sampleNode(), TestBuildOptionsAllProtocols(), TestBuildOptionsRejectsInvalid(), TestBuildOptionsVLESSRealityFields(), TestBuildOptionsWireGuard() (+16 more)

### Community 36 - "rules_provider.dart"
Cohesion: 0.08
Nodes (25): env.dart, AppSettings, applyCountry, build, copyWith, _core, _init, lastError (+17 more)

### Community 37 - "profiles_provider.dart"
Cohesion: 0.08
Nodes (26): AsyncNotifier, ExitInfo?, ExitInfoNotifier, added, addSubscription, addWarp, addWindscribe, _autoName (+18 more)

### Community 38 - "Engine"
Cohesion: 0.12
Nodes (12): LocalAuth, ParseConnMode(), CancelFunc, ConnMode, Engine, Manager, Model, Mutex (+4 more)

### Community 39 - "node_repository.dart"
Cohesion: 0.08
Nodes (23): app_database.dart, allIds, clearLatencies, core, count, cursor, db, deleteNode (+15 more)

### Community 40 - "Options"
Cohesion: 0.09
Nodes (25): about_page.dart, appearance_page.dart, backup_page.dart, ../chain/chain_page.dart, connection_page.dart, core/bootstrap.dart, ../core/providers/env.dart, ../core/providers/settings_provider.dart (+17 more)

### Community 41 - "app_test.dart"
Cohesion: 0.20
Nodes (9): ButtonStyleButton, package:easyvpn/core/models/models.dart, package:easyvpn/core/providers/settings_provider.dart, support/fake_transport.dart, support/pump_app.dart, m, main, node (+1 more)

### Community 42 - "proxies_page.dart"
Cohesion: 0.09
Nodes (21): ../../core/database/node_repository.dart, ../../core/providers/capabilities_provider.dart, ../../core/providers/node_list_provider.dart, ../../core/providers/ping_provider.dart, ../../core/util/backup_service.dart, NodeSort, NodeRow, active (+13 more)

### Community 43 - "SingBoxAdapter"
Cohesion: 0.13
Nodes (10): ProbeResult, SingBoxAdapter, Stats, DumpConfig(), Box, Context, Manager, Mutex (+2 more)

### Community 44 - "ProxyNode"
Cohesion: 0.19
Nodes (14): boolStr(), itoa(), XrayRawNeedsCore(), Hysteria2Config, MuxConfig, OpenVPNConfig, OVPNRemote, ProxyNode (+6 more)

### Community 45 - "BuildRouteRules"
Cohesion: 0.19
Nodes (17): actionFor(), BuildDNSOptions(), BuildRouteRules(), BuildRuleSets(), DNSOptions, Model, orDefault(), parseUint16() (+9 more)

### Community 46 - "pump_app.dart"
Cohesion: 0.09
Nodes (21): CoreTransport? transport,
  Size, fake_transport.dart, package:easyvpn/app.dart, package:easyvpn/core/bridge/unavailable_transport.dart, package:easyvpn/core/providers/env.dart, core, db, env (+13 more)

### Community 47 - "process_transport.dart"
Cohesion: 0.09
Nodes (21): dart:isolate, _cacheDir, call, dispose, _disposed, _events, _exe, isAvailable (+13 more)

### Community 48 - "subscription_page.dart"
Cohesion: 0.07
Nodes (36): _AddSheet, ConsumerState, Profile, profilesProvider, tick, _AddSheetState, _import, _DurationState (+28 more)

### Community 50 - "string"
Cohesion: 0.23
Nodes (14): sbOutbound, sbTLSBlock, sbTransportBlock, xrayOutbound, xrayStreamSettings, applyRemarks(), applyXrayStreamSettings(), attachDeps() (+6 more)

### Community 51 - "EasyVpnService"
Cohesion: 0.17
Nodes (9): EasyVpnService, establishFromActivity(), Context, Intent, Notification, stopFromActivity(), updateNotificationInfo(), ParcelFileDescriptor (+1 more)

### Community 52 - "strings.dart"
Cohesion: 0.11
Nodes (19): BuildContext, delegate, _en, _fa, isFa, isSupported, load, locale (+11 more)

### Community 53 - "speed_test_page.dart"
Cohesion: 0.10
Nodes (21): Color?, dart:typed_data, IconData, build, _buildClient, color, createState, _downMbps (+13 more)

### Community 54 - "xray.go"
Cohesion: 0.20
Nodes (15): SidecarOptions, XraySidecar, Config, BuildXrayConfig(), chainEnd(), forceInsecureTLS(), freeLoopbackPort(), modelXrayOutbound() (+7 more)

### Community 55 - "MainActivity"
Cohesion: 0.20
Nodes (6): Intent, MainActivity, FlutterActivity, FlutterEngine, java, MethodChannel

### Community 56 - "routing_actions.dart"
Cohesion: 0.12
Nodes (17): CoreBridge get, dart:ui, build, _core, detect, detectAndApply, RoutingActions, routingActionsProvider (+9 more)

### Community 57 - "core_transport.dart"
Cohesion: 0.14
Nodes (13): call, CoreEvent, dispose, events, fromJson, heavyMethods, isAvailable, isUnsupported (+5 more)

### Community 58 - "package:flutter/material.dart"
Cohesion: 0.13
Nodes (14): ../home/home_menu.dart, ../l10n/strings.dart, env, link, name, raw, showModalBottomSheet, showShareNode (+6 more)

### Community 59 - "app_database.dart"
Cohesion: 0.11
Nodes (17): int get, Iterable, allSchemaEntities, allTables, exec, kvDelete, kvGet, kvSet (+9 more)

### Community 60 - "bootstrap.dart"
Cohesion: 0.12
Nodes (15): bridge/core_locator.dart, bootstrap, core, dataDir, db, dir, join, pass (+7 more)

### Community 61 - "profilesProvider"
Cohesion: 0.13
Nodes (22): CoreState, supportedCapsProvider, CoreController, disconnect, _ensureOpenVpnCredentials, _onEvents, _pullCrashReport, selectNode (+14 more)

### Community 62 - "FlutterWindow"
Cohesion: 0.06
Nodes (53): PluginRegistry, Point, RECT, unique_ptr, RegisterPlugins(), DartProject, HWND, LPARAM (+45 more)

### Community 63 - "Fetch"
Cohesion: 0.24
Nodes (10): decodeB64(), decodeTitle(), Fetch(), Context, ParseUserInfo(), T, TestFetchFallsBackToProxy(), TestFetchParsesHeaders() (+2 more)

### Community 64 - "add_sheet.dart"
Cohesion: 0.07
Nodes (29): ConsumerStatefulWidget, ../../core/util/file_io.dart, _AddSheet, build, _busy, _camera, createState, dispose (+21 more)

### Community 65 - "Create"
Cohesion: 0.12
Nodes (17): _Metric, _Small, _UnavailableBanner, _Empty, _FastestTile, _NodeTile, _Chip, _TopBar (+9 more)

### Community 66 - "win32_window.cpp"
Cohesion: 0.17
Nodes (12): ../../core/providers/profiles_provider.dart, _addWarpWithLicense, build, _busy, ChainPage, _ChainPageState, createState, _pickNode (+4 more)

### Community 67 - "testChunk"
Cohesion: 0.27
Nodes (12): URLTestOptions, URLTestResult, defaultTestDNS(), Context, DNSOptions, testChunk(), URLTestBatch(), Context (+4 more)

### Community 68 - ".Start"
Cohesion: 0.23
Nodes (5): T, TestFixtureNodesCompileForTheirEngine(), NormalizeNode(), NeedsXray(), State

### Community 69 - "Tracker"
Cohesion: 0.18
Nodes (6): Int64, Time, NewTracker(), Int32, Snapshot, Tracker

### Community 70 - "export.go"
Cohesion: 0.31
Nodes (12): clashNet(), clashProxy(), clashTLS(), ClashYAML(), Values, hostPort(), orStr(), tlsTransportQuery() (+4 more)

### Community 71 - "core_locator.dart"
Cohesion: 0.15
Nodes (12): ffi_transport.dart, exeDir, _libCandidates, names, openCoreTransport, _osTag, override, _processCandidates (+4 more)

### Community 72 - "formatters.dart"
Cohesion: 0.15
Nodes (12): a, flagEmoji, fmtBytes, fmtDuration, fmtSpeed, fromCharCodes, h, i (+4 more)

### Community 73 - "site_check_page.dart"
Cohesion: 0.15
Nodes (13): ../../core/util/formatters.dart, build, _busy, createState, e, _error, initState, _results (+5 more)

### Community 74 - "update"
Cohesion: 0.33
Nodes (9): Context, Intent, refresh(), setInfo(), update(), VpnWidget, AppWidgetManager, AppWidgetProvider (+1 more)

### Community 75 - "nav_provider.dart"
Cohesion: 0.10
Nodes (19): ../core/models/models.dart, build, dashboard, Dest, go, profiles, proxies, routing (+11 more)

### Community 76 - "Win32Window"
Cohesion: 0.24
Nodes (10): char, CoreCall(), currentServer(), FreeString(), getServer(), Engine, InitCore(), pumpEvents() (+2 more)

### Community 77 - "engine.go"
Cohesion: 0.21
Nodes (7): freeTCPPort(), Context, ParseExitJSON(), ExitInfo, FetchResult, Event, Result

### Community 78 - "Detect"
Cohesion: 0.29
Nodes (8): Detect(), Context, LookupIP(), norm(), T, TestDetectPriority(), Result, Signals

### Community 79 - "secret_store.dart"
Cohesion: 0.18
Nodes (10): dart:math, fixed, _generate, keyB64, _name, open, SecretStore, usesKeystore (+2 more)

### Community 80 - "wWinMain"
Cohesion: 0.18
Nodes (10): SupportedProtocols(), _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole() (+2 more)

### Community 81 - "file_io.dart"
Cohesion: 0.21
Nodes (7): ParseResult, cidrFromMask(), ParseOVPN(), Parser, looksLikeBase64(), LooksLikeWGQuick(), ParseWGQuick()

### Community 82 - "model.go"
Cohesion: 0.31
Nodes (8): DefaultServiceOverrides(), Model, RoutingMode, Rule, RuleKind, RuleSetRef, ServiceOverrides, ServiceOverrides

### Community 83 - "fake_transport.dart"
Cohesion: 0.18
Nodes (10): >, dart:async, Stream, call, calls, dispose, emit, _events (+2 more)

### Community 84 - "bool get"
Cohesion: 0.22
Nodes (8): bool get, core_transport.dart, call, dispose, events, isAvailable, reason, unavailableReason

### Community 85 - ".TestNodesURL"
Cohesion: 0.53
Nodes (4): Model, usableDNS(), useSystemResolver(), withLocalDNS()

### Community 86 - "router_test.go"
Cohesion: 0.54
Nodes (7): actions(), fakeSets(), T, TestDNSSchema(), TestIranRuleOrder(), TestMissingRuleSetsAreNeverReferenced(), TestModes()

### Community 87 - "models/models.dart"
Cohesion: 0.25
Nodes (7): accentPresets, AppTheme, build, mode, withDynamic, ../models/models.dart, package:dynamic_color/dynamic_color.dart

### Community 88 - "VpnTileService"
Cohesion: 0.33
Nodes (4): Context, refresh(), VpnTileService, TileService

### Community 89 - "buildChain"
Cohesion: 0.38
Nodes (6): buildChain(), Endpoint, TLSTricks, setDetour(), setDetourValue(), Value

### Community 90 - "dart:io"
Cohesion: 0.25
Nodes (8): dart:io, build, createState, _done, ScanPage, _ScanPageState, scanSupported, package:mobile_scanner/mobile_scanner.dart

### Community 91 - ".OpenInterface"
Cohesion: 0.33
Nodes (3): Addr, Tun, TunPlatformOptions

### Community 92 - "BootReceiver"
Cohesion: 0.33
Nodes (4): BootReceiver, Context, Intent, BroadcastReceiver

### Community 93 - "display_text.dart"
Cohesion: 0.33
Nodes (5): changed, _letterlike, out, plainName, toString

### Community 94 - "CoreTransport"
Cohesion: 0.18
Nodes (10): dart:convert, f, null, path, pickTextFile, r, saveText, package:file_picker/file_picker.dart (+2 more)

### Community 96 - "RegisterPlugins"
Cohesion: 0.36
Nodes (6): RawMessage, ns(), parseNS(), services(), nsBackend, nsService

### Community 102 - "platformLogger"
Cohesion: 0.27
Nodes (9): classify(), DefaultSites(), Context, Engine, shortErr(), statusText(), errorString, Site (+1 more)

### Community 104 - "TestWithLocalDNS"
Cohesion: 0.40
Nodes (5): CoreTransport, FfiTransport, ProcessTransport, UnavailableTransport, FakeTransport

### Community 127 - "main"
Cohesion: 0.22
Nodes (8): main(), serve(), InstallCrashLog(), LastCrash(), lastIndex(), T, TestCrashLogCapturesPanic(), ReadWriter

### Community 129 - "EasyVPN v2 plan: all-in-one, one-button"
Cohesion: 0.22
Nodes (8): 1. Auto-update from GitHub Releases (open source → GitHub is the update server), 2. Distinct look (Windscribe / NordVPN-class, not "stock Flutter Material"), 3. Windscribe servers (your account + the free locations), 4. Chains: proxy-in-proxy, WARP, WARP-in-WARP, "exit via WARP", 5. Shortcuts everywhere, 6. More connection types (all-in-one), EasyVPN v2 plan: all-in-one, one-button, Order of work

### Community 130 - "database_test.dart"
Cohesion: 0.22
Nodes (8): NodeRepository, package:easyvpn/core/bridge/core_bridge.dart, package:easyvpn/core/database/app_database.dart, package:easyvpn/core/database/node_repository.dart, db, main, node, repo

### Community 131 - "Building EasyVPN"
Cohesion: 0.33
Nodes (5): 1. Go core, 2. App, Building EasyVPN, Releases (GitHub Actions), Runtime layout

### Community 132 - "Exception"
Cohesion: 0.50
Nodes (4): Exception, CoreException, CoreUnavailable, CoreErr

### Community 133 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.50
Nodes (3): package:easyvpn/core/util/display_text.dart, package:flutter_test/flutter_test.dart, main

## Knowledge Gaps
- **955 isolated node(s):** `easyvpn/core`, `selectable`, `optionsJSON`, `clashConfig`, `sbTLSBlock` (+950 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **25 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_Duration` connect `SingBoxAdapter` to `add_sheet.dart`, `Client`, `testChunk`, `NewEngine`, `dashboard_page.dart`, `adapter.go`?**
  _High betweenness centrality (0.346) - this node is a cross-community bridge._
- **Why does `buildOptionsWithTags()` connect `adapter.go` to `Default`, `NewEngine`, `SingBoxAdapter`, `BuildRouteRules`, `build_outbound.go`, `buildChain`, `.OpenInterface`?**
  _High betweenness centrality (0.158) - this node is a cross-community bridge._
- **Why does `ProxyNode` connect `ProxyNode` to `Server`, `freePort`, `Client`, `NewEngine`, `parser.go`, `build_outbound.go`, `adapter.go`, `Default`, `Engine`, `SingBoxAdapter`, `string`, `xray.go`, `testChunk`, `.Start`, `export.go`, `engine.go`, `file_io.dart`, `.TestNodesURL`, `buildChain`?**
  _High betweenness centrality (0.119) - this node is a cross-community bridge._
- **Are the 45 inferred relationships involving `string` (e.g. with `.parseSingboxOutboundRaw()` and `.ParseWithWarnings()`) actually correct?**
  _`string` has 45 INFERRED edges - model-reasoned connections that need verification._
- **What connects `easyvpn/core`, `selectable`, `optionsJSON` to the rest of the system?**
  _955 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `models.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.01652892561983471 - nodes in this community are weakly interconnected._
- **Should `Server` be split into smaller, more focused modules?**
  _Cohesion score 0.09986504723346828 - nodes in this community are weakly interconnected._