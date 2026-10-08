# NEXUS Word Native

Native Flutter client for NEXUS Word.

## Principles

- No WebView and no embedded copy of nexusword.it.
- Native Flutter UI on Android, iOS, Windows, macOS and Linux.
- The client uses the same authenticated NEXUS services as the web app.
- Provider secrets never ship in the client.
- The backend adapter is isolated so it can move from the current Neon/RPC endpoints to `api.nexusword.it/v1` without rewriting the UI.

## Current V1 scope

- email/password sign in and registration
- authenticated session persistence in OS secure storage
- account access/credits
- persistent conversations and messages
- NEXUS cloud chat with local-PC fallback
- private Library listing
- job listing
- native file selection and secure upload path
- responsive mobile/desktop navigation

Google and Apple native sign-in are intentionally kept separate from the initial email/password path so they can use platform-native SDK/token flows rather than a WebView.

## Bootstrap

From this directory, with Flutter stable installed:

```
flutter create --org it.nexusword --project-name nexus_word --platforms=android,ios,windows,macos,linux .
flutter pub get
flutter analyze
flutter test
```

The generated platform folders are build output scaffolding; the maintained application source lives in `lib/`.
