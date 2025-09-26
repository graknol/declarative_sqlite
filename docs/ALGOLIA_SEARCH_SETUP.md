# Algolia Search Setup for Docusaurus

This document explains how to configure Algolia search for the Declarative SQLite documentation site.

## Current Status

The Algolia search functionality has been integrated into the Docusaurus configuration. The search interface is fully functional and appears in the top navigation bar.

## Configuration

The search configuration is located in `docusaurus.config.ts` in the `themeConfig.algolia` section:

```typescript
algolia: {
  // The application ID provided by Algolia
  appId: 'YOUR_APP_ID',
  // Public API key: it is safe to commit it
  apiKey: 'YOUR_API_KEY', 
  indexName: 'declarative_sqlite',
  // Optional: see doc section below
  contextualSearch: true,
  // Optional: Algolia search parameters
  searchParameters: {},
  // Optional: path for search page that enabled by default (`false` to disable it)
  searchPagePath: 'search',
},
```

## Setup Steps

To complete the Algolia search setup with your open source key:

### 1. Replace Placeholder Values

Update the following values in `docs/docusaurus.config.ts`:

- `YOUR_APP_ID`: Replace with your Algolia Application ID
- `YOUR_API_KEY`: Replace with your Algolia Search API Key (public/search-only key)

### 2. Index Your Documentation

You'll need to create a search index of your documentation. There are two main approaches:

#### Option A: DocSearch (Recommended for Open Source)

If you're using Algolia's free DocSearch program:

1. Apply for DocSearch at https://docsearch.algolia.com/apply/
2. Once approved, Algolia will provide you with the correct `appId`, `apiKey`, and `indexName`
3. Algolia will automatically crawl and index your documentation

#### Option B: Manual Indexing

If you prefer to manage the indexing yourself:

1. Set up an Algolia index in your dashboard
2. Use Algolia's crawling tools or API to index your documentation content
3. Update the configuration with your custom index details

### 3. Test the Search

After updating the configuration:

1. Run `npm run start` to start the development server
2. Click the search icon in the navigation bar or use Ctrl+K (Cmd+K on Mac)
3. Try searching for documentation terms like "database", "flutter", "schema", etc.

## Features

The current configuration includes:

- **Search Interface**: Accessible via the navigation bar search icon or Ctrl+K shortcut
- **Contextual Search**: Enabled to provide more relevant results based on the current page
- **Search Page**: Dedicated search results page at `/search`
- **Keyboard Navigation**: Full keyboard support for search results
- **Mobile Support**: Search works on mobile devices

## Troubleshooting

- **"No results" or connection errors**: Verify your `appId` and `apiKey` are correct
- **Outdated results**: If using DocSearch, Algolia crawls periodically. Manual indexing gives you more control
- **Search not appearing**: Ensure the configuration is in the correct location in `docusaurus.config.ts`

## Additional Configuration Options

You can customize the search behavior with additional options:

```typescript
algolia: {
  appId: 'YOUR_APP_ID',
  apiKey: 'YOUR_API_KEY',
  indexName: 'declarative_sqlite',
  contextualSearch: true,
  searchParameters: {
    // Additional Algolia search parameters
    facetFilters: [],
  },
  searchPagePath: 'search',
  // Custom placeholder text
  placeholder: 'Search documentation...',
  // Disable search page
  searchPagePath: false,
},
```

For more details, see the [Docusaurus Algolia Search documentation](https://docusaurus.io/docs/search#using-algolia-docsearch).