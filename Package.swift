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
        name: "CGtk3",
        path: "DexBarLinux/Sources/CLibraries/CGtk3",
        pkgConfig: "gtk+-3.0",
        providers: [.apt(["libgtk-3-dev"])]
    ),
    .systemLibrary(
        name: "CAppIndicator",
        path: "DexBarLinux/Sources/CLibraries/CAppIndicator",
        pkgConfig: "ayatana-appindicator3-0.1",
        providers: [
            .apt(["libayatana-appindicator3-dev"]),
            .apt(["libappindicator3-dev"]),  // fallback for non-Ubuntu distros
        ]
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
            .target(name: "CGtk3",             condition: .when(platforms: [.linux])),
            .target(name: "CAppIndicator",     condition: .when(platforms: [.linux])),
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
