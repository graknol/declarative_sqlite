import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.
 */
const sidebars: SidebarsConfig = {
  // Main documentation sidebar
  tutorialSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Getting Started',
      items: [
        'getting-started/installation',
        'getting-started/quick-start',
      ],
    },
    {
      type: 'category',
      label: 'Core Library',
      items: [
        'core-library/schema-definition',
        'core-library/typed-records',
        'core-library/database-operations',
        'core-library/exception-handling',
        'core-library/streaming-queries',
        'core-library/advanced-features',
      ],
    },
    {
      type: 'category',
      label: 'Flutter Integration',
      items: [
        'flutter-integration/widgets',
      ],
    },
  ],
};

export default sidebars;
