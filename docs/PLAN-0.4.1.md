# 0.4.1 — Optional Keychain and local credentials

GOAL-041: Save Canvas/model credentials locally by default without unsolicited Keychain access, while retaining an explicit Keychain option. Preserve the user's installed app for update testing.

| Requirement / acceptance / test | Observable result |
| --- | --- |
| REQ/AC/TC-0411 | New and upgraded installs default to local storage; normal local reads/writes/deletes and background jobs never invoke Keychain. |
| REQ/AC/TC-0412 | Local JSON resides separately from the course archive, with owner-only directory/file permissions, atomic updates, symlink rejection, bounded decoding and serialized changes. Corrupt data is reported and not overwritten. |
| REQ/AC/TC-0413 | General settings selects Local or Keychain. Keychain selection copies local entries before committing and removes the plaintext copies only on success. Failure leaves local data and selection intact. Switching to Local never requires Keychain access. |
| REQ/AC/TC-0414 | An explicit Import from Keychain action copies only this app's entries; existing local values and explicit deletions win. Cancel/failure commits no partial import; original Keychain entries remain. Ordinary reads never fall back to Keychain. |
| REQ/AC/TC-0415 | Existing account IDs and Canvas/model call sites keep working; secrets never enter the web bridge, archive, logs, exports or release. Temporary verification uses synthetic credentials and APP_STORE. |
| REQ/AC/TC-0416 | English/Chinese settings communicate actual storage; active light/dark screenshots and app self-tests pass. 0.4.1/build6 source, signed packages and latest feed publish together; public downloads and unchanged local installation are verified. |

ADR-041: Use a separate owner-only local JSON file, not custom encryption with a bundled key. Keychain is opt-in. A non-main actor serializes reads/mutations and caches successful Keychain reads for the session; a file lock coordinates independent instances. Mode and local entries commit atomically in one envelope. No new dependency or database/schema migration is needed.

IF-041: CredentialStore readAsync/saveAsync/deleteAsync retain their call-site contract. New asynchronous mode/import operations expose only mode and counts, never secrets. Accounts are UTF-8 strings (1–4096 bytes), values at most 16 KiB, envelope at most 512 KiB/schema1. Missing values return nil; malformed/unsupported data fails closed without fallback. Blank saves remove the active credential and preserve an import exclusion. Disk and Keychain failures are retryable and never log secret values.

Migration policy: The old app used Keychain only, so no mode file means Local. Existing Keychain entries are not inspected at launch. Users may explicitly import them (system authorization can be required per entry) or re-enter keys. Switching back from Keychain to Local is always possible without authorization; importing is a separate action. Local files are plaintext protected by filesystem permissions, not equivalent to Keychain access isolation. This tradeoff was explicitly selected by the user.

Implementation order: storage contract and regression tests → native settings/call-site UX → isolated tests and affected real windows → release and public verification. Scope excludes stable certificate provisioning, password vaults, changes to Sparkle signing keys, automatic access to real credentials and modifying the installed app.

Evidence and 100-point score will be recorded in ACCEPTANCE-0.4.1.md after actual verification.
