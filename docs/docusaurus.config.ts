import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

const config: Config = {
  title: 'Declarative SQLite',
  tagline: 'A comprehensive Dart and Flutter library ecosystem for declarative SQLite schema management and database operations',
  favicon: 'img/logo.png',

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // Set the production url of your site here
  url: 'https://declarative-sqlite.linden.no',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'graknol', // Usually your GitHub org/user name.
  projectName: 'declarative_sqlite', // Usually your repo name.

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  // Add trailing slashes to URLs to avoid redirects (required for GitHub Pages and Algolia crawler)
  trailingSlash: true,

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
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
          // Please change this to your repo.
          // Remove this to remove the "edit this page" links.
          editUrl:
            'https://github.com/graknol/declarative_sqlite/tree/main/docs/',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
        sitemap: {
          lastmod: 'date',
          changefreq: 'weekly',
          priority: 0.5,
          ignorePatterns: ['/tags/**'],
          filename: 'sitemap.xml',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Algolia search configuration
    ...(process.env.ALGOLIA_APP_ID && process.env.ALGOLIA_API_KEY && {
      algolia: {
        // The application ID provided by Algolia (from environment variable)
        appId: process.env.ALGOLIA_APP_ID,
        // Public API key: it is safe to commit it (from environment variable)
        apiKey: process.env.ALGOLIA_API_KEY,
        indexName: 'declarative_sqlite',
        // Optional: see doc section below
        contextualSearch: true,
        // Optional: Algolia search parameters
        searchParameters: {},
        // Optional: path for search page that enabled by default (`false` to disable it)
        searchPagePath: 'search',
      },
    }),
    colorMode: {
      defaultMode: 'dark',
      disableSwitch: false,
      respectPrefersColorScheme: false,
    },
    // Replace with your project's social card
    image: 'img/docusaurus-social-card.jpg',
    navbar: {
      title: '💾 Declarative SQLite',
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docs',
          position: 'left',
          label: 'Documentation',
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
          title: 'Documentation',
          items: [
            {
              label: 'Getting Started',
              to: '/docs/intro',
            },
            {
              label: 'Core Library',
              to: '/docs/core-library/intro',
            },
            {
              label: 'Query Builder',
              to: '/docs/core-library/query-builder',
            },
            {
              label: 'Flutter Integration',
              to: '/docs/flutter-integration/intro',
            },
          ],
        },
        {
          title: 'Packages',
          items: [
            {
              label: 'declarative_sqlite',
              href: 'https://pub.dev/packages/declarative_sqlite',
            },
            {
              label: 'declarative_sqlite_flutter',
              href: 'https://pub.dev/packages/declarative_sqlite_flutter',
            },
            {
              label: 'declarative_sqlite_generator',
              href: 'https://pub.dev/packages/declarative_sqlite_generator',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/graknol/declarative_sqlite',
            },
            {
              label: 'Issues',
              href: 'https://github.com/graknol/declarative_sqlite/issues',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Declarative SQLite. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['dart'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
