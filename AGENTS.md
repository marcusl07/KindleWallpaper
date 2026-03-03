untracked files from parallel agents: if you encounter untracked files you did not create, do not commit them, do not ask about them, and do not let them block your task. leave them untouched and proceed with your own scoped commit.
tracked changes from parallel agents: if git status shows modified tracked files you did not touch, do not commit them, do not ask about them. use git add <your specific files> to stage only your own work and commit that alone.

whenever you finish an atomic task and verify it works thru testing, commit and push to the repo.
task tracking workflow:
- `tasks-active.txt` is the only task list agents should use as working context.
- when a task is completed, run `scripts/archive_task.sh <TASK_ID>` to move it out of `tasks-active.txt` and append it to `tasks-archive.txt`.
- do not leave completed tasks in `tasks-active.txt`.
- keep `tasks-archive.txt` as history/reference only.
when you make a mistake add it here so you dont do it again.
- mistake logged (2026-02-21): avoid using xcodebuild-based verification in this sandbox; use deterministic project-file verification scripts unless elevated execution is explicitly needed.
- mistake logged (2026-02-22): when compiling Swift in this sandbox, set `swiftc -module-cache-path` to a writable temp directory and use `main.swift` for top-level executable verification code.
- mistake logged (2026-02-22): when using `main.swift` for verification executables in this sandbox, do not use `@main`; run tests via top-level execution.
- mistake logged (2026-02-27): after running `scripts/archive_task.sh`, verify that only the target task moved; if it captures additional sections, restore `tasks-active.txt`/`tasks-archive.txt` before committing.
- mistake logged (2026-03-03): do not run `scripts/archive_task.sh` in parallel for multiple task IDs; it mutates shared task files and can duplicate or race entries.

Error handling — future note: Current convention uses fatalError for database errors (acceptable for personal v1). Before any wider distribution, all fatalError calls in Database.swift should be replaced with proper error propagation (throws) and user-facing error messages in the UI.

Review gate override: For UI-only changes scoped to a single view file with no model or persistence impact, skip the review gate and implement directly.
