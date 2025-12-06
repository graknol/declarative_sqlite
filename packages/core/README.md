# @declarative-sqlite/core

TypeScript port of `declarative_sqlite` for PWA and Capacitor applications.

## Status

🚧 **Under Active Development** - Phase 1: Foundation Setup

This is the core library package of the TypeScript migration. Currently implementing the foundation layer.

## Installation

```bash
npm install @declarative-sqlite/core rxjs
```

## Architecture

This package provides:

- **SQLite Adapter Interface** - Abstraction layer for multiple SQLite backends
- **Schema Definition System** - Type-safe declarative schema builders
- **Auto-Migration Engine** - Automatic schema migration
- **CRUD Operations** - Type-safe database operations
- **Streaming Queries** - RxJS-based reactive queries
- **Sync System** - HLC-based conflict resolution

## Current Implementation Status

### Phase 1: Foundation (In Progress)

- [x] Project structure created
- [x] TypeScript configuration
- [x] Build tooling (tsup)
- [x] Testing framework (Vitest)
- [x] SQLite adapter interface
- [x] Basic schema types
- [ ] Schema builders
- [ ] Migration system
- [ ] Database operations

### Upcoming Phases

- **Phase 2**: Core Schema System
- **Phase 3**: Migration Engine
- **Phase 4**: Database Operations
- **Phase 5**: Synchronization
- **Phase 6**: File Management
- **Phase 7**: Streaming Queries
- **Phase 8**: DbRecord System

See [TYPESCRIPT_MIGRATION_PLAN.md](../../TYPESCRIPT_MIGRATION_PLAN.md) for complete roadmap.

## Development

```bash
# Install dependencies
pnpm install

# Build
pnpm build

# Watch mode
pnpm dev

# Run tests
pnpm test

# Type checking
pnpm typecheck

# Lint
pnpm lint
```

## Key Features (Planned)

### Zero Code Generation

Unlike the Dart version, the TypeScript implementation uses Proxy objects for typed record access:

```typescript
interface User {
  name: string;
  age: number;
}

const user = db.createRecord<User>('users');
user.name = 'Alice';  // Type-safe via Proxy, no build step!
```

### Pluggable SQLite Backend

```typescript
const db = new DeclarativeDatabase({
  adapter: new WaSqliteAdapter()      // Browser/PWA
  // OR new CapacitorSqliteAdapter()  // iOS/Android native
  // OR new BetterSqlite3Adapter()    // Node.js testing
});
```

### RxJS Streaming

```typescript
const users$ = db.stream(q => q.from('users'));

users$
  .pipe(
    map(users => users.filter(u => u.age > 18)),
    debounceTime(300)
  )
  .subscribe(users => updateUI(users));
```

## License

MIT

## Links

- [Migration Plan](../../TYPESCRIPT_MIGRATION_PLAN.md)
- [Architecture](../../TYPESCRIPT_ARCHITECTURE.md)
- [Feature Comparison](../../TYPESCRIPT_COMPARISON.md)
