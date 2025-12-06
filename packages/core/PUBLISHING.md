# Publishing Guide for @declarative-sqlite/core

## Prerequisites

1. You must be logged in to npm:
   ```bash
   npm login
   ```

2. Ensure you have the correct permissions for the @declarative-sqlite scope

## Publishing Workflow

### 1. Update Version

Manually update the version in `package.json`:

```json
{
  "name": "@declarative-sqlite/core",
  "version": "1.0.1",  // ← Update this
  ...
}
```

Follow [Semantic Versioning](https://semver.org/):
- **Patch** (1.0.x): Bug fixes, no breaking changes
- **Minor** (1.x.0): New features, no breaking changes
- **Major** (x.0.0): Breaking changes

### 2. Verify Build and Tests

```bash
cd packages/core

# Run tests
npm test

# Build the package
npm run build

# Type check
npm run typecheck

# Lint
npm run lint
```

All tests should pass (60/60) ✅

### 3. Verify Package Contents

Check what will be published:

```bash
npm pack --dry-run
```

Should include:
- `dist/` - Built JavaScript and TypeScript definitions
- `README.md` - Package documentation
- `LICENSE` - MIT license
- `package.json` - Package metadata

Should NOT include:
- `src/` - Source files
- `node_modules/` - Dependencies
- Test files
- Config files

### 4. Publish to npm

```bash
npm publish --access public
```

**Note**: The `--access public` flag is required for scoped packages (@declarative-sqlite/core)

### 5. Verify Publication

1. Check on npm: https://www.npmjs.com/package/@declarative-sqlite/core
2. Test installation in a new project:
   ```bash
   npm install @declarative-sqlite/core rxjs
   ```

## Automated Checks

The `prepublishOnly` script automatically runs before publishing:

```json
"prepublishOnly": "npm run build && npm test"
```

This ensures:
- Package builds successfully
- All tests pass
- Types are generated correctly

## Version History

- **1.0.0** - Initial release
  - Zero code generation with Proxy-based DbRecord
  - Automatic schema migration
  - Complete CRUD operations
  - RxJS streaming queries
  - HLC/LWW synchronization
  - File management
  - 60/60 tests passing

## Troubleshooting

### "You do not have permission to publish"

Ensure you're logged in with the correct npm account:
```bash
npm whoami
npm login
```

### "Package name already exists"

The @declarative-sqlite scope must be available. If this is the first publish, you may need to create the scope on npm.

### Build Errors

```bash
# Clean and rebuild
rm -rf dist node_modules
npm install
npm run build
```

### Test Failures

```bash
# Run tests in watch mode to debug
npm run test:watch
```

## Additional Commands

```bash
# Dry run (don't actually publish)
npm publish --dry-run

# Publish with tag (beta, alpha, etc.)
npm publish --tag beta

# Check package version
npm view @declarative-sqlite/core version

# List all published versions
npm view @declarative-sqlite/core versions
```

## Manual Publishing Process

Since you prefer manual version management:

1. Make your changes
2. Update version in `package.json`
3. Run tests: `npm test`
4. Build: `npm run build`
5. Publish: `npm publish --access public`

No GitHub Actions needed! ✅
