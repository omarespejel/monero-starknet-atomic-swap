# Pull Request Checklist

## Branch Workflow

This project follows a standard Git Flow:

- **`main`**: Stable/production branch - only updated via Pull Requests
- **`feat/*`**: Feature branches for new functionality
- **`test/*`**: Test/experimental branches
- **`fix/*`**: Bug fix branches

## Best Practices

1. **Never commit directly to `main`** - all changes go through feature branches and PRs
2. **Create feature branches from `main`**: `git checkout main && git pull && git checkout -b feat/feature-name`
3. **Keep feature branches up to date**: Regularly rebase or merge `main` into your feature branch
4. **Use descriptive branch names**: `feat/`, `fix/`, `test/`, `docs/` prefixes
5. **Merge via Pull Request**: All changes to `main` must go through a PR review

## Current Feature Branch

- **Branch**: `feat/garaga-ed25519-support`
- **Status**: Active development
- **Base**: `main` (up to date)

