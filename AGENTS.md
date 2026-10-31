# Agent instructions

## Commit messages

Every commit must describe the full set of changes it contains. Do not use a single subject line for a multi-change commit and hide the other work in the diff.

- Subject: one short imperative sentence naming the main goal of the commit.
- Body: a bullet list covering every feature, fix, UI change, documentation update, and test in the commit.
- When a commit contains multiple features, keep the subject as a summary and list every feature in the body.
- Do not omit small changes. Describe user-visible behavior, data migrations, and compatibility changes.
- Prefer splitting unrelated changes into separate commits.

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
