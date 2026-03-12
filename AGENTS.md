untracked files from parallel agents: if you encounter untracked files you did not create, do not commit them, do not ask about them, and do not let them block your task. leave them untouched and proceed with your own scoped commit.
tracked changes from parallel agents: if git status shows modified tracked files you did not touch, do not commit them, do not ask about them. use git add <your specific files> to stage only your own work and commit that alone.

whenever you finish an atomic task and verify it works thru testing, commit and push to the repo.
task tracking workflow:
- `tasks-active.txt` is the only task list agents should use as working context.
- when a task is completed, run `scripts/archive_task.sh <TASK_ID>` to move it out of `tasks-active.txt` and append it to `tasks-archive.txt`.
- do not leave completed tasks in `tasks-active.txt`.
- keep `tasks-archive.txt` as history/reference only.
when you make a mistake add it to `tasks/lessons.md` so it stays local and untracked.

Error handling — future note: Current convention uses fatalError for database errors (acceptable for personal v1). Before any wider distribution, all fatalError calls in Database.swift should be replaced with proper error propagation (throws) and user-facing error messages in the UI.

Review gate override: For UI-only changes scoped to a single view file with no model or persistence impact, skip the review gate and implement directly.
