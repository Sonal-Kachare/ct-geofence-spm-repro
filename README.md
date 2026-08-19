# clevertap-geofence-ios SPM consumption repro

Minimal reproduction harness for a reported issue: Swift Package Manager
resolution of `clevertap-geofence-ios` fails or times out inside a CI pipeline,
while the same dependency resolves fine in Xcode on a developer machine.

This repo contains a sample iOS app that consumes the geofence SDK via SPM, plus
a GitHub Actions workflow that measures what a consumer actually pays for.

## What this is and is not

This is a **control experiment**, not a reproduction of the failure.

A GitHub-hosted macOS runner has fast, unthrottled network and will very likely
pass in a couple of minutes. That is the point. It produces a trustworthy
baseline for how long a genuinely cold resolve takes and how many bytes it
moves. If another CI runner takes dramatically longer on the identical
dependency graph, that localises the bottleneck to that runner's environment
rather than to the package.

It cannot reproduce a problem specific to another CI provider's network, proxy,
or runner configuration.

## Layout

```
SPMSample/                     Xcode app consuming CleverTapGeofence via SPM
  SPMSample.xcodeproj
    xcshareddata/xcschemes/    shared scheme, required for CI
.github/workflows/
  spm-verify.yml               the diagnostic pipeline
```

`SPMSample/SPMSample/AppDelegate.swift` deliberately imports
`CleverTapGeofence` and calls into it. A green build therefore proves the whole
consumption path compiles and links, not merely that resolution succeeded.

## The workflow

Three independent jobs, triggered on push to `main` or via
`workflow_dispatch`:

| Job | What it establishes |
|---|---|
| `clone-cost` | Bytes and seconds for a plain clone versus a recursive clone |
| `cold-resolve` | Cold `xcodebuild -resolvePackageDependencies` with isolated caches, run both with and without a committed `Package.resolved` |
| `build-sample` | The app builds and links against the package, signing disabled |

Each job writes its numbers to the run summary, and the resolve and build logs
are uploaded as artifacts.

## Measured findings

### SwiftPM pulls submodules recursively

`clevertap-geofence-ios` carries a `Vendors/CleverTap` submodule pointing at the
full `clevertap-ios-sdk` repository, which in turn carries a nested
`Vendors/SDWebImage` submodule. SwiftPM checks out package dependencies with
submodules recursively, so every consumer downloads that history.

`Package.swift` never references `Vendors/`. The build depends on
`clevertap-ios-sdk` through a normal `.package(url:)` declaration, which lands in
its own separate checkout. The submodule appears to be a leftover from the
Carthage and xcodeproj era, alongside `Cartfile` and the committed
`Vendors/*.framework` binaries.

Clone cost, measured directly:

| Clone mode | Time | On disk |
|---|---|---|
| `git clone` | 2.95s | 75 MB |
| `git clone --recurse-submodules` | 18.22s | 339 MB |

Resolved SPM footprint for a consumer:

| Path | Size |
|---|---|
| `checkouts/clevertap-geofence-ios` | 316 MB (237 MB of it `.git/modules`) |
| `checkouts/clevertap-ios-sdk` | 23 MB |
| total `SourcePackages` | 645 MB |
| `Sources/`, the only directory SPM compiles | 48 KB |

The wrapper package occupies roughly 14x the space of the SDK it wraps.

On a healthy connection this overhead costs seconds, not minutes. It is a real
and removable inefficiency, and it amplifies a slow or throttled link by about
4.5x, but on its own it does not explain a multi-minute stall.

### The SDK now ships as binary artifacts

Resolving the graph downloads two prebuilt xcframework archives in addition to
the git clones:

- `CleverTapSDK-7.8.1.xcframework.zip` from a CloudFront domain
- `SDWebImage-dynamic.xcframework.zip` 5.21.0 from GitHub releases

These are separate network endpoints from `github.com` git access. A CI
environment behind a proxy or an egress allowlist can reach the git remotes and
still fail on these, which is worth checking independently.

### Version range is open within the major

`Package.swift` declares `.upToNextMajor(from: "7.1.1")` for
`clevertap-ios-sdk`, so a fresh resolution is free to pick any 7.x. This repo
resolves to 7.8.1. A pipeline without a committed `Package.resolved` can
therefore pick up a different SDK version than the one a developer tested
against, which the `cold-resolve` matrix exercises on purpose.

## Reproducing locally

```sh
xcodebuild build \
  -project SPMSample/SPMSample.xcodeproj \
  -scheme SPMSample \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

To measure a cold resolve, point `-clonedSourcePackagesDirPath` at a fresh
directory and clear `~/Library/Caches/org.swift.swiftpm` first, otherwise a warm
cache hides the real cost.

## Provenance of the numbers

Every figure above was measured, not estimated. The clone timings and disk
figures come from a single developer machine on one network connection, so treat
the seconds as indicative and the byte counts as reliable. Toolchain used:

```
Xcode 26.3 (17C529)
Apple Swift version 6.2.4 (swiftlang-6.2.4.1.4)
```

Resolved graph: `clevertap-geofence-ios` 1.0.7, `clevertap-ios-sdk` 7.8.1.

The workflow re-measures all of it on a clean runner, which is the number worth
comparing against.
