# /apple-build-fix

Diagnose and fix Xcode/Swift build failures.

Steps:

1. Capture exact command and error.
2. Classify: target membership, SDK availability, Swift concurrency, signing, package resolution, plist/entitlement, generated code, test-only issue.
3. Make minimal fix.
4. Re-run focused build/test.
5. Summarize root cause and prevention hook/automation if applicable.
