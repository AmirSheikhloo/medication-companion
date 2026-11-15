# Architecture and deployment boundaries

**Status:** Architecture guardrails for the existing M0 Flutter prototype and future iterations. This document does **not** claim that the planned modules or server already exist.

## 1. Independent deployables

This is a small monorepo, not one all-in-one deployable.

- **`apps/mobile/`** owns the Flutter/Android app, local device storage, local notifications, and mobile presentation.
- **`apps/admin/` (future)** owns a web administration interface. It must build and deploy without a Flutter SDK.
- **`services/api/` (future)** owns any remote API, authentication, server-side business rules, persistence, and schema migrations. Its deployment must not rebuild the admin or Android app.
- **`packages/contracts/` (future)** owns explicit, versioned API contracts such as OpenAPI schemas and generated client bindings. It must contain no secrets, environment-specific addresses, or application entry points.

Every deployable will have its own dependency manifest, configuration, environment variables, tests, and release pipeline. On Liara, web admin and API must be configured as separate applications with their own build contexts and settings; a deployment of one must not implicitly rebuild the other.

**Prohibited:** importing implementation code directly from another deployable, having admin or mobile connect to a server database, and storing production credentials in the repository.

## 2. Flutter internals

Keep mobile feature code scoped by feature while retaining clear responsibilities.

Planned structure, introduced incrementally as features are implemented:

```text
apps/mobile/lib/
  app/                  # App assembly, navigation, dependency wiring
  core/                 # Small shared technical utilities
  features/
    medications/
      domain/           # Pure data types and business invariants
      data/             # Repository implementations, persistence
      presentation/     # Screens, widgets, view models
    reminders/
      domain/
      data/
      presentation/
    profiles/
      ...
    reports/
      ...
```

Dependency rules:

1. Presentation renders state and issues user commands; it does not execute SQL or call native plugins directly.
2. Repositories provide stable abstractions over local storage, native services, and eventual network clients.
3. Domain logic is independently testable and does not import Flutter UI packages.
4. Cross-feature operations go through explicit interfaces/use cases, not another feature's private database tables or widget internals.
5. Use dependency injection to make time, persistence, and notification behavior replaceable in tests.
6. Introduce use-case classes for real multi-step business rules, not as boilerplate around every getter.

The current M0 code is a **single-file engineering spike**. It will be migrated feature by feature; do not falsely treat this structure as already implemented.

## 3. Offline-first data boundaries

- Local operation must remain usable without internet connectivity for supported features.
- Treat medication schedules and dose events as separate concepts; preserve an auditable event record instead of silently overwriting history.
- Use explicit IDs and idempotency keys for events that might later synchronize.
- Document database schema migrations before changing existing on-device data.
- Synchronization, conflict policy, encryption at rest, and account-based backup need separate design and acceptance tests **before** they are called production-ready.
- Do not place real patient data, credentials, signing keys, or private local databases in Git.

## 4. API compatibility and isolated deployments

- The future API is the only supported interface between admin/mobile and server storage.
- Version contracts deliberately; maintain compatibility with mobile versions that remain installed after a backend release.
- Use independent CI jobs scoped to each deployable's directory.
- Each future Liara app gets its own build and deployment settings, runtime secrets, health checks, and rollback procedure.
- Start with a modular API service when a backend is needed. Do not split into microservices merely because multiple features exist.

## 5. Change safety

For every behavior-changing pull request:

- Identify the owned feature and affected contracts.
- Add or update focused domain/repository/widget tests.
- Run `flutter analyze` and `flutter test` for mobile modifications.
- Review data migration and rollback impact before modifying persistence.
- Do not merge a failing CI run without an explicit, documented reason.
- Keep `main` deployable; create work on short-lived branches.

## 6. M0 acceptance notes

Reported from manual testing on a Samsung A52s / Android 14:

- App launches and the regular notification path works.
- The full-screen reminder path lights/wakes the device and shows the app plus a notification; it must **not** yet be described as a reliable full-screen alarm on every device.
- The PDF can be generated and shared, but Persian numerals/punctuation still render with missing glyphs in places. Defer remediation to the dedicated reports feature.
- The M0 experience is a technical validation screen, not a medication management product.

Next work: establish CI, then deliver the first testable offline medication vertical slice, with a proper local database and replaceable reminder service. Device-level reminder reliability remains a separate acceptance gate.
