// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "DexBarCore", targets: ["DexBarCore"]),
]

var targets: [Target] = [
    // MARK: - Shared portable library (macOS + Linux)
    .target(
        name: "DexBarCore",
        path: "Sources/DexBarCore"
    ),
]

#if os(Linux)
products += [
    .executable(name: "DexBarLinux", targets: ["DexBarLinux"]),
]

targets += [
    // MARK: - C system library wrappers (Linux only)
    .systemLibrary(
        name: "CGtk4",
        path: "DexBarLinux/Sources/CLibraries/CGtk4",
        pkgConfig: "gtk4",
        providers: [.apt(["libgtk-4-dev"])]
    ),
    .systemLibrary(
        name: "CDbusmenu",
        path: "DexBarLinux/Sources/CLibraries/CDbusmenu",
        pkgConfig: "dbusmenu-glib-0.4",
        providers: [.apt(["libdbusmenu-glib-dev"])]
    ),
    .systemLibrary(
        name: "CGtk4LayerShell",
        path: "DexBarLinux/Sources/CLibraries/CGtk4LayerShell",
        pkgConfig: "gtk4-layer-shell-0",
        providers: [.apt(["libgtk4-layer-shell-dev"])]
    ),
    .systemLibrary(
        name: "CLibSecret",
        path: "DexBarLinux/Sources/CLibraries/CLibSecret",
        pkgConfig: "libsecret-1",
        providers: [.apt(["libsecret-1-dev"])]
    ),
    .systemLibrary(
        name: "CLibNotify",
        path: "DexBarLinux/Sources/CLibraries/CLibNotify",
        pkgConfig: "libnotify",
        providers: [.apt(["libnotify-dev"])]
    ),

    // MARK: - C bridge (wraps variadic libsecret API for Swift)
    .target(
        name: "DexBarLinuxBridge",
        path: "DexBarLinux/Sources/Bridge",
        publicHeadersPath: "include",
        cSettings: [
            .unsafeFlags([
                "-I/usr/include/glib-2.0",
                "-I/usr/lib/x86_64-linux-gnu/glib-2.0/include",
                "-I/usr/lib/glib-2.0/include",
                "-I/usr/include/libsecret-1",
                "-I/usr/include/gio-unix-2.0",
            ], .when(platforms: [.linux])),
        ]
    ),

    // MARK: - Linux application
    .executableTarget(
        name: "DexBarLinux",
        dependencies: [
            "DexBarCore",
            .target(name: "DexBarLinuxBridge", condition: .when(platforms: [.linux])),
            .target(name: "CGtk4",             condition: .when(platforms: [.linux])),
            .target(name: "CDbusmenu",         condition: .when(platforms: [.linux])),
            .target(name: "CGtk4LayerShell",   condition: .when(platforms: [.linux])),
            .target(name: "CLibSecret",        condition: .when(platforms: [.linux])),
            .target(name: "CLibNotify",        condition: .when(platforms: [.linux])),
        ],
        path: "DexBarLinux/Sources",
        exclude: ["CLibraries", "Bridge"]
    ),
]
#endif

let package = Package(
    name: "DexBar",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    targets: targets
)
