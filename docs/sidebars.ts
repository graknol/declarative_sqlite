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
        'getting-started/project-structure',
        'getting-started/examples',
      ],
    },
    {
      type: 'category',
      label: 'Core Library',
      items: [
        'core-library/installation',
        'core-library/schema-definition',
        'core-library/database-operations',
        'core-library/streaming-queries',
      ],
    },
    {
      type: 'category',
      label: 'Flutter Integration',
      items: [
        'flutter/installation',
      ],
    },
  ],

  // API Reference sidebar - temporarily disabled
  // apiSidebar: [
  //   'api/overview',
  // ],
};

export default sidebars;
