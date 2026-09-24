# ERoute Mobile

Flutter client for the Emergency Map MVP. The initial flow is Emergency Landing → nationwide GPS/manual Map → HPID-backed Hospital Detail. Development and automated-test compositions always use `MockEmergencyDialer`.

Run from the repository root after starting PostgreSQL and the Backend:

```sh
API_BASE_URL=http://10.0.2.2:18081 python3 scripts/run_mobile.py
```

Run local checks from this directory:

```sh
flutter analyze
flutter test
flutter build apk --debug --flavor dev
```

See the root `README.md`, `DESIGN.md`, `UX-CONTRACT.md`, and `docs/operations/map-ux-v0.1.md` for configuration and behavioral contracts.
