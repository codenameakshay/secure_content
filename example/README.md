# secure_content example

This example demonstrates the package's v2 API, including:

- Global protection toggle
- Scoped protection with `SecureContentScope`
- Policy-based security behavior via `SecureContentPolicy`
- Biometric re-auth trigger
- Integrity check trigger
- Sensitive clipboard with auto-clear TTL
- Hard-block mode toggle
- Event stream updates in UI

## Run

```bash
fvm flutter run
```

## Notes

- Android screenshot callback requires Android 14+.
- Android clipboard copy toast is system-managed and cannot be suppressed by apps.
