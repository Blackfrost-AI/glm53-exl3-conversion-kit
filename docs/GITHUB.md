# Publish to GitHub

Run the local safety checks first:

```bash
./scripts/check_repo.sh
git status --short
git log -1 --oneline
```

Create and push a public repository with GitHub CLI:

```bash
gh repo create Blackfrost-AI/glm53-exl3-conversion-kit \
  --public \
  --source . \
  --remote origin \
  --push \
  --description "Reproducible GLM-5.3 BF16 to EXL3 2.04 bpw HQ conversion kit"
```

Use `--private` instead of `--public` if you want a review pass before making
it visible. Repository creation and pushing are intentionally not automated by
the kit.
