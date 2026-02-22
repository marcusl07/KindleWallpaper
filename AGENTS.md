untracked files from parallel agents: if you encounter untracked files you did not create, do not commit them, do not ask about them, and do not let them block your task. leave them untouched and proceed with your own scoped commit.
tracked changes from parallel agents: if git status shows modified tracked files you did not touch, do not commit them, do not ask about them. use git add <your specific files> to stage only your own work and commit that alone.

whenever you finish an atomic task and verify it works thru testing, commit and push to the repo.
when you make a mistake add it here so you dont do it again.- mistake logged (2026-02-21): avoid using xcodebuild-based verification in this sandbox; use deterministic project-file verification scripts unless elevated execution is explicitly needed.
- mistake logged (2026-02-22): when compiling Swift in this sandbox, set `swiftc -module-cache-path` to a writable temp directory and use `main.swift` for top-level executable verification code.

Error handling — future note: Current convention uses fatalError for database errors (acceptable for personal v1). Before any wider distribution, all fatalError calls in Database.swift should be replaced with proper error propagation (throws) and user-facing error messages in the UI.
