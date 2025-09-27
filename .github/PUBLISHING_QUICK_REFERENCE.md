# Quick Publishing Reference

## Common Commands

### Publish Individual Package
```bash
# Core library
./scripts/publish.sh core 1.1.2

# Flutter integration
./scripts/publish.sh flutter 1.1.2  

# Code generator
./scripts/publish.sh generator 1.1.2
```

### Publish All Packages (Coordinated Release)
```bash
./scripts/publish.sh all 1.2.0
```

### Test Before Publishing
```bash
./scripts/publish.sh all 1.2.0 --dry-run
```

### Manual Git Tag Creation
```bash
# Single package
git tag declarative_sqlite-1.1.2
git push origin declarative_sqlite-1.1.2

# All packages
git tag declarative_sqlite-1.2.0
git tag declarative_sqlite_flutter-1.2.0  
git tag declarative_sqlite_generator-1.2.0
git push origin --tags
```

## Version Bump Examples

### Patch Release (Bug Fixes)
`1.1.0` → `1.1.1`

### Minor Release (New Features)  
`1.1.0` → `1.2.0`

### Major Release (Breaking Changes)
`1.1.0` → `2.0.0`

## Workflow Trigger Patterns

- Tag: `declarative_sqlite-X.Y.Z` → Triggers core library publishing
- Tag: `declarative_sqlite_flutter-X.Y.Z` → Triggers Flutter package publishing  
- Tag: `declarative_sqlite_generator-X.Y.Z` → Triggers generator publishing

## Files to Update

### Required for All Releases
- [ ] `<package>/pubspec.yaml` - Version number
- [ ] `<package>/CHANGELOG.md` - Release notes

### Required for Coordinated Releases
- [ ] Update inter-package dependencies in dependent packages
- [ ] All three pubspec.yaml files
- [ ] All three CHANGELOG.md files

## Pre-Publishing Checklist

- [ ] All tests pass (`dart test` or `flutter test`)
- [ ] Version follows semantic versioning
- [ ] CHANGELOG.md updated with changes
- [ ] Inter-package dependencies updated (if applicable)
- [ ] Dry-run completed successfully

## Post-Publishing Verification

- [ ] New versions appear on pub.dev
- [ ] Package analysis scores acceptable
- [ ] Demo applications work with new versions
- [ ] GitHub Actions completed successfully