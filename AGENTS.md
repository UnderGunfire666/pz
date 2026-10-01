# Repository workflow preferences

- Before drafting a commit comment for this repository, inspect the changes since the latest commit and update `README.md` with accurate summaries of newly implemented user-facing features and remaining limitations. Drafting a comment does not itself authorize creating a commit.
- When the user explicitly requests “commit and push”, first update `README.md`, then prepare the commit comment, create the commit, and push the current branch. Preserve unrelated working-tree changes, run relevant checks, and report any commit or push failure.
