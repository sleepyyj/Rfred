# Agent instructions

## Commit messages

Every commit must describe the full set of changes it contains. Do not use a single subject line for a multi-change commit and hide the other work in the diff.

- Subject: one short imperative sentence naming the main goal of the commit.
- Body: a bullet list covering every feature, fix, UI change, documentation update, and test in the commit.
- When a commit contains multiple features, keep the subject as a summary and list every feature in the body.
- Do not omit small changes. Describe user-visible behavior, data migrations, and compatibility changes.
- Prefer splitting unrelated changes into separate commits.

## Code signing

Release builds sign `Jfred.app` with one self-signed certificate, common name `Jfred Codesign`. The designated requirement is:

```text
identifier "dev.jim.jfred.local" and certificate leaf = H"e4bb0d4d89c4d6d1ab0c3617de5d88225c5a3910"
```

macOS stores Desktop, Documents, and Downloads consent against that requirement, not against the app name or the install path. `codesign --sign -` sets the requirement to the build's cdhash. Every GitHub Actions runner then produces a different identity, and each installed update asks for those folders again.

The leaf hash comes from the certificate. Importing the same certificate on every runner keeps the hash stable, including across version bumps. `scripts/codesign-app.sh` signs with it and checks the requirement. `scripts/build-app.sh` calls that script. The release workflow refuses to build a DMG when the certificate secrets are missing, so a release cannot silently fall back to an ad-hoc signature.

The private key is not in git.

- Local copy: `~/.config/jfred/codesign/jfred-codesign.p12`, with the password in `~/.config/jfred/codesign/password`. A local `scripts/build-app.sh` uses these files when they exist.
- Actions secrets: `JFRED_CODESIGN_P12` (base64 of the same `.p12`) and `JFRED_CODESIGN_PASSWORD`.

Do not generate a replacement certificate. A new certificate is a new leaf hash, and the next update asks for folder access again. The certificate is not an Apple Developer ID and the app is not notarized. Gatekeeper still treats a freshly downloaded copy as an unidentified developer; the in-app updater removes the quarantine attribute before it replaces `Jfred.app`. The signature still has to pass `codesign --verify --deep --strict`, which is what the updater checks before swapping the bundle.

Example:

```text
Rebuild workflows around Alfred object graphs

- Replace the flat action model with Alfred objects, connections and uidata
- Add Script Filter JSON/XML handling and graph execution
- Support multiple output connections and workflow-relative scripts
- Rework the Workflows pane, object palette and configuration sheets
- Fix disabled workflow styling and Configure Workflow behavior
- Add REA evidence, documentation and regression tests
```
