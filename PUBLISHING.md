# Publishing Guide for Declarative SQLite Packages

This guide explains how to publish new versions of the Declarative SQLite ecosystem packages to pub.dev.

## Overview

The Declarative SQLite ecosystem consists of three publishable packages:

1. **`declarative_sqlite`** (Core library) - Path: `/declarative_sqlite/`
2. **`declarative_sqlite_flutter`** (Flutter integration) - Path: `/declarative_sqlite_flutter/`  
3. **`declarative_sqlite_generator`** (Code generation) - Path: `/declarative_sqlite_generator/`

## Publishing Methods

### Method 1: Automated Script (Recommended)

Use the provided publishing script for a streamlined experience:

```bash
# Publish individual packages
./scripts/publish.sh core 1.1.1           # Publish declarative_sqlite
./scripts/publish.sh flutter 1.1.1        # Publish declarative_sqlite_flutter  
./scripts/publish.sh generator 1.1.1      # Publish declarative_sqlite_generator

# Publish all packages at once (recommended for coordinated releases)
./scripts/publish.sh all 1.2.0

# Dry run to test without publishing
./scripts/publish.sh all 1.2.0 --dry-run
```

The script will:
- Update `pubspec.yaml` versions
- Remind you to update `CHANGELOG.md` files
- Update inter-package dependencies automatically
- Create appropriate git tags
- Trigger automated GitHub Actions workflows

### Method 2: Manual Process

#### Step 1: Version Updates

Update the version in each package's `pubspec.yaml`:

```yaml
# In declarative_sqlite/pubspec.yaml
version: 1.1.1  # Update this

# In declarative_sqlite_flutter/pubspec.yaml  
version: 1.1.1  # Update this
dependencies:
  declarative_sqlite: ^1.1.1  # Update dependency

# In declarative_sqlite_generator/pubspec.yaml
version: 1.1.1  # Update this
dependencies:
  declarative_sqlite: ^1.1.1  # Update dependency
```

#### Step 2: Update Changelogs

Update each package's `CHANGELOG.md` with the new version and changes:

```markdown
## 1.1.1

### Bug Fixes
- Fixed issue with schema migration edge case
- Improved error handling in query builder

## 1.1.0
# ... existing entries
```

#### Step 3: Create Git Tags

Create properly formatted git tags:

```bash
# Single package
git tag declarative_sqlite-1.1.1
git push origin declarative_sqlite-1.1.1

# Multiple packages (if publishing together)
git tag declarative_sqlite-1.1.1
git tag declarative_sqlite_flutter-1.1.1
git tag declarative_sqlite_generator-1.1.1
git push origin --tags
```

#### Step 4: Monitor Automated Publishing

The GitHub Actions workflows will automatically publish to pub.dev when tags are pushed.

### Method 3: Manual Workflow Dispatch

You can also trigger publishing workflows manually from the GitHub Actions tab:

1. Go to the repository's Actions tab
2. Select the desired publishing workflow
3. Click "Run workflow"
4. Enter the version to publish
5. Click "Run workflow"

## Version Guidelines

Follow semantic versioning (semver):

- **Patch (X.Y.Z)**: Bug fixes, documentation updates, minor improvements
  - `1.1.0` → `1.1.1`
- **Minor (X.Y.z)**: New features, non-breaking API additions  
  - `1.1.0` → `1.2.0`
- **Major (X.y.z)**: Breaking changes, major API redesigns
  - `1.1.0` → `2.0.0`

## Inter-Package Dependencies

When publishing the core library (`declarative_sqlite`), ensure dependent packages reference the correct version:

- `declarative_sqlite_flutter` depends on `declarative_sqlite`
- `declarative_sqlite_generator` depends on `declarative_sqlite`

The automated script handles this automatically when using `./scripts/publish.sh all`.

## Publishing Scenarios

### Scenario 1: Bug Fix in Core Library

```bash
# Update core library only
./scripts/publish.sh core 1.1.1
```

### Scenario 2: New Feature in Flutter Package

```bash
# Update Flutter package (may need core library update too)
./scripts/publish.sh flutter 1.2.0
```

### Scenario 3: Coordinated Release

```bash
# Update all packages together (recommended)
./scripts/publish.sh all 1.2.0
```

## Prerequisites

### GitHub Repository Secrets

The following secrets must be configured in the GitHub repository:

- `PUB_TOKEN`: Your pub.dev access token
- `PUB_REFRESH_TOKEN`: Your pub.dev refresh token

### Obtaining pub.dev Credentials

1. Run `dart pub token add https://pub.dev` locally
2. Complete the OAuth flow
3. Find your credentials in `~/.config/dart/pub-credentials.json`
4. Extract the `accessToken` and `refreshToken` values
5. Add them as repository secrets

## Workflow Files

The repository includes three GitHub Actions workflows:

- `.github/workflows/publish-declarative-sqlite.yml`
- `.github/workflows/publish-declarative-sqlite-flutter.yml`  
- `.github/workflows/publish-declarative-sqlite-generator.yml`

These workflows:
- Run on git tag pushes matching the pattern `<package-name>-<version>`
- Support manual dispatch with version input
- Verify package versions match tags
- Run tests before publishing
- Publish to pub.dev automatically

## Verification Steps

After publishing:

1. **Check pub.dev**: Verify new versions appear on pub.dev
2. **Test Installation**: `dart pub add package_name:^new_version`
3. **Monitor Scores**: Ensure package analysis scores remain high
4. **Test Examples**: Verify demo applications work with new versions

## Troubleshooting

### Common Issues

1. **Version Mismatch**: Ensure `pubspec.yaml` version matches git tag
2. **Missing Dependencies**: Update inter-package dependencies before publishing
3. **Test Failures**: All tests must pass before publishing
4. **Credential Issues**: Verify pub.dev tokens are valid and have correct permissions

### Manual Recovery

If automated publishing fails:

```bash
# Navigate to package directory
cd declarative_sqlite

# Setup credentials manually
mkdir -p ~/.config/dart
echo '{"accessToken":"YOUR_TOKEN","refreshToken":"YOUR_REFRESH_TOKEN",...}' > ~/.config/dart/pub-credentials.json

# Publish manually
dart pub publish --force
```

## Best Practices

1. **Test Before Publishing**: Always run `--dry-run` first
2. **Update Changelogs**: Keep detailed changelog entries
3. **Coordinate Releases**: Use `all` option for ecosystem-wide changes
4. **Version Consistency**: Maintain version alignment across dependent packages
5. **Monitor Actions**: Watch GitHub Actions for successful completion

## Support

For issues with the publishing process:

1. Check GitHub Actions logs for detailed error messages
2. Verify repository secrets are correctly configured
3. Ensure pub.dev credentials have appropriate permissions
4. Test manually with `dart pub publish --dry-run`

The publishing workflows are designed to be robust and provide clear error messages to help diagnose any issues.