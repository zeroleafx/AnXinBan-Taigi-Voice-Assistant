# Deprecation audit (2026-11-15)

Validated with the project's Flutter 3.47.9, Gradle 9.3.1 and AGP 9.1.0.

## Applied

- CI: checkout v6, setup-java v5 and cache v5 replace their Node 20 actions.
- Android: enable AGP built-in Kotlin instead of the deprecated legacy Kotlin switch.
- Dart analyzer reports no issues.

## Remaining upstream dependencies

Do not remove these compatibility settings or hide warnings without validating replacement tooling.

| Source | Warning | Required follow-up |
| --- | --- | --- |
| Flutter Gradle plugin | `android.newDsl=false` | Upgrade to a Flutter toolchain using the public AGP DSL. The installed FlutterPlugin.kt still casts to AbstractAppExtension. |
| Flutter Gradle tasks | Task.project accessed during task execution | Requires an upstream Flutter Gradle plugin migration for Gradle 10. |
| audioplayers_android 5.3.0 | Groovy space-assignment syntax | Upstream update or maintained local fork. No newer resolvable release found in pub outdated. |
| geolocator_android 5.2.1 | Groovy space-assignment syntax, Java 8 source/target, deprecated LocationMapper API | Upstream update or maintained local fork with Android API compatibility tests. No newer resolvable release found in pub outdated. |

The Java 8 warnings were emitted by local JDK 25; CI uses JDK 17. They are not an instruction to raise the app's minimum Android version.

## Verification

- flutter analyze --no-pub
- flutter build apk --release --no-pub
- Android :app:testDebugUnitTest --warning-mode all
- flutter build ios --release --no-codesign --no-pub

All passed. The iOS build emitted no deprecation messages in its captured Flutter output; this was not a clean rebuild of every dependency. GitHub Actions changes still need a remote CI run. No physical-device behavior was tested in this audit.
