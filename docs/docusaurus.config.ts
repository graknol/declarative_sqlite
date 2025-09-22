import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

const config: Config = {
  title: 'Declarative SQLite',
  tagline: 'A comprehensive Dart and Flutter library ecosystem for declarative SQLite schema management and database operations',
  favicon: 'img/favicon.ico',

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // Set the production url of your site here
  url: 'https://graknol.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/declarative_sqlite/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'graknol', // Usually your GitHub org/user name.
  projectName: 'declarative_sqlite', // Usually your repo name.

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

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
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/docusaurus-social-card.jpg',
    navbar: {
      title: 'Declarative SQLite',
      logo: {
        alt: 'Declarative SQLite Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'tutorialSidebar',
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
              label: 'Typed Records',
              to: '/docs/core-library/typed-records',
            },
            {
              label: 'Exception Handling',
              to: '/docs/core-library/exception-handling',
            },
            {
              label: 'Flutter Integration',
              to: '/docs/flutter-integration/widgets',
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
