import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docs: [
    'intro',
    'getting-started',
    {
      type: 'category',
      label: 'Local data',
      collapsed: false,
      items: ['schema', 'storage', 'reading-and-writing', 'live-queries', 'migrations'],
    },
    {
      type: 'category',
      label: 'Sync',
      collapsed: false,
      items: ['sync', 'server-protocol'],
    },
    'react',
    'testing',
    'upgrading-from-v2',
    'ai-agents',
  ],
};


export default sidebars;
