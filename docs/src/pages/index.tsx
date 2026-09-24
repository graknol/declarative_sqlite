import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';

import styles from './index.module.css';

const example = `const schema = new SchemaBuilder();
schema
  .table('task', (t) => {
    t.integer('project_id');
    t.text('title');
    t.real('hours');
  })
  .synced({ key: 'system_id', scope: ['project_id'] });

const { adapter } = await openAdapter({ name: 'app.db' });
const db = await Database.open({ schema: schema.build(), adapter });
const sync = await createSyncRuntime({ db, transport, deviceId });

await sync.pull.pull('task', { project_id: 42 });
await sync.outbox.record({ table: 'task', systemId, changes: { hours: 3.5 } });`;

const features = [
  {
    title: 'Declarative schema',
    body: 'Describe your tables in code. The database is migrated on open, and migrations only ever add: nothing is dropped behind your back.',
  },
  {
    title: 'Live queries',
    body: 'Plain SQL that stays current. A query re-runs only when a write touches the tables and scope it declared, and emits only when its rows changed.',
  },
  {
    title: 'Sync built in',
    body: 'Pull server rows by cursor, record edits in an outbox, push them in idempotent batches. What the user typed is never overwritten by a pull.',
  },
];

export default function Home(): ReactNode {
  return (
    <Layout
      title="Offline-first SQLite for the browser"
      description="declarative-sqlite: declarative schema, automatic migration, live queries and offline-first sync for SQLite in the browser.">
      <header className={styles.hero}>
        <div className="container">
          <Heading as="h1" className={styles.title}>
            declarative-sqlite
          </Heading>
          <p className={styles.tagline}>
            An offline-first sync data layer for SQLite in the browser.
          </p>
          <div className={styles.buttons}>
            <Link className="button button--primary button--lg" to="/docs/getting-started">
              Get started
            </Link>
            <Link className="button button--secondary button--lg" to="/docs/intro">
              How it works
            </Link>
          </div>
          <code className={styles.install}>npm install declarative-sqlite@alpha</code>
        </div>
      </header>
      <main className="container">
        <section className={styles.features}>
          {features.map((feature) => (
            <div key={feature.title} className={styles.feature}>
              <Heading as="h3">{feature.title}</Heading>
              <p>{feature.body}</p>
            </div>
          ))}
        </section>
        <section className={styles.example}>
          <CodeBlock language="ts">{example}</CodeBlock>
        </section>
      </main>
    </Layout>
  );
}
