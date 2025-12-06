# Contributing Guidelines

## Branch Workflow

This project follows standard Git Flow practices:

### Branch Structure

- **`main`**: Stable/production branch - only updated via Pull Requests
- **`feat/*`**: Feature branches for new functionality (e.g., `feat/garaga-ed25519-support`)
- **`test/*`**: Test/experimental branches
- **`fix/*`**: Bug fix branches
- **`docs/*`**: Documentation-only changes

### Best Practices

1. **Never commit directly to `main`** - all changes go through feature branches and Pull Requests
2. **Create feature branches from `main`**:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feat/your-feature-name
   ```
3. **Keep feature branches up to date**:
   ```bash
   git checkout feat/your-feature-name
   git pull origin main
   git rebase main  # or git merge main
   ```
4. **Use descriptive branch names** with prefixes:
   - `feat/` for new features
   - `fix/` for bug fixes
   - `test/` for test-related changes
   - `docs/` for documentation
5. **Merge via Pull Request**: All changes to `main` must go through a PR with review

### Current Active Branches

- **`feat/garaga-ed25519-support`**: Active development for Garaga Ed25519 integration

### Commit Message Format

Use conventional commit format:
- `feat: add new feature`
- `fix: resolve bug`
- `docs: update documentation`
- `test: add test cases`
- `refactor: restructure code`

