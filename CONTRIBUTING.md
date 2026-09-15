# Contributing to Secure Content

Thank you for helping to improve Secure Content.

Read the [README](README.md) for the public API and the
[example guide](example/README.md) for a complete app. Read the
[changelog](CHANGELOG.md) for release history and the
[code of conduct](CODE_OF_CONDUCT.md) before you contribute.

## Report an Issue

Search the [open issues](https://github.com/codenameakshay/secure_content/issues)
before you create an issue. Add details to an existing issue when it matches
your problem.

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) for a bug.
Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md)
for a feature request.

Include these details:

- Flutter and Dart versions
- Platform and OS version
- Package version
- Steps to reproduce the problem
- Expected and actual results
- Logs or a small reproduction when available

## Architecture

`SecureContentScope` owns the Flutter UI for one protected subtree. It renders
the capture overlay, lock screen, hard-block screen, and risk watermark.

`SecureContentService` tracks active scopes and combines their native settings.
It sends the combined settings through the typed Pigeon platform API.

`SecureContentController` provides global protection through the same service.
The Android and iOS plugins apply native window protection and send platform
events back to Flutter.

Keep Flutter UI behavior in `lib/src/secure_content_scope.dart`. Keep shared
native state in `lib/src/secure_content_service.dart`. Update the Pigeon input
and generated files together when the platform API changes.

## Pull Requests

Before you open a pull request:

- Keep the change focused.
- Add or update tests for behavior changes.
- Update the README or changelog when public behavior changes.
- Run `make check`.
- Run the relevant Android or iOS build when native files change.

Describe the change, test commands, and known limits in the pull request.

## Commits

Use Conventional Commit subjects, such as:

```text
fix(android): protect the app window during capture
docs(readme): clarify screenshot detection
```

Use the imperative mood. Keep the subject short. Add a body when the reason
for the change is not clear from the diff.

## Security

Do not report security problems in a public issue. Contact the maintainer at
[akshaymaurya3006@gmail.com](mailto:akshaymaurya3006@gmail.com) with the
details.
