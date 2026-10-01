# Repository workflow preferences

- Before designing or implementing gameplay, rendering, AI, inventory, navigation, audio, save migration, modding, or map-scale features, consult `docs/PZ_DEVELOPMENT_PITFALLS.md` and apply its relevant guardrails. Treat it as a risk checklist, not as a claim that every reported Project Zomboid issue is confirmed or present in this project. Keep simulation rules authoritative and separate from rendering; measure representative dense scenes; preserve versioned save migration and focused regression coverage.

- Before drafting a commit comment for this repository, inspect the changes since the latest commit and update `README.md` with accurate summaries of newly implemented user-facing features and remaining limitations. Drafting a comment does not itself authorize creating a commit.
- When the user explicitly requests “commit and push”, first update `README.md`, then prepare the commit comment, create the commit, and push the current branch. Preserve unrelated working-tree changes, run relevant checks, and report any commit or push failure.
