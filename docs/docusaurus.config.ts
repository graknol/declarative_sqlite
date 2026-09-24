import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import llmsTxtPlugin, {sidebarPageIds} from './plugins/llms-txt';
import sidebars from './sidebars';

const config: Config = {
  title: 'declarative-sqlite',
  tagline: 'An offline-first sync data layer for SQLite in the browser',
  favicon: 'img/logo.png',

  future: {
    v4: true,
  },

  url: 'https://declarative-sqlite.linden.no',
  baseUrl: '/',
  organizationName: 'graknol',
  projectName: 'declarative_sqlite',
  trailingSlash: true,

  onBrokenLinks: 'throw',
  markdown: {
    format: 'detect',
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/graknol/declarative_sqlite/tree/main/docs/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
        sitemap: {
          lastmod: 'date',
          changefreq: 'weekly',
          priority: 0.5,
          filename: 'sitemap.xml',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    [
      llmsTxtPlugin,
      {
        pages: sidebarPageIds(sidebars.docs),
        summary:
          'declarative-sqlite is a TypeScript library for offline-first browser apps: SQLite (WebAssembly, OPFS) with a declarative schema, automatic additive migration, live queries, and a sync layer (cursor-based pull, column-level outbox, idempotent batched push). Install v3 with `npm install declarative-sqlite`.',
      },
    ],
  ],

  themeConfig: {
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'declarative-sqlite',
      logo: {
        alt: 'declarative-sqlite',
        src: 'img/logo.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docs',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://www.npmjs.com/package/declarative-sqlite',
          label: 'npm',
          position: 'right',
        },
        {
          href: 'https://github.com/graknol/declarative_sqlite',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {label: 'Getting started', to: '/docs/getting-started'},
            {label: 'Sync', to: '/docs/sync'},
            {label: 'Server protocol', to: '/docs/server-protocol'},
            {label: 'React', to: '/docs/react'},
          ],
        },
        {
          title: 'Project',
          items: [
            {label: 'npm', href: 'https://www.npmjs.com/package/declarative-sqlite'},
            {label: 'GitHub', href: 'https://github.com/graknol/declarative_sqlite'},
            {label: 'Issues', href: 'https://github.com/graknol/declarative_sqlite/issues'},
            {
              label: 'Changelog',
              href: 'https://github.com/graknol/declarative_sqlite/blob/main/packages/core/CHANGELOG.md',
            },
          ],
        },
      ],
      copyright: `MIT licensed · © ${new Date().getFullYear()} declarative-sqlite`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
