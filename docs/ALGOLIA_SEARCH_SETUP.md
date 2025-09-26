# Algolia Search Setup for Docusaurus

This document explains how to configure Algolia search for the Declarative SQLite documentation site.

## Current Status

The Algolia search functionality has been integrated into the Docusaurus configuration. The search interface is fully functional and appears in the top navigation bar.

## Configuration

The search configuration is located in `docusaurus.config.ts` in the `themeConfig.algolia` section:

```typescript
algolia: {
  // The application ID provided by Algolia (from environment variable)
  appId: process.env.ALGOLIA_APP_ID!,
  // Public API key: it is safe to commit it (from environment variable)
  apiKey: process.env.ALGOLIA_API_KEY!,
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

### 1. Add GitHub Secrets

The Algolia credentials are loaded from environment variables for security. You need to add the following secrets to your GitHub repository:

1. Go to your GitHub repository
2. Navigate to Settings → Secrets and variables → Actions
3. Add the following repository secrets:
   - `ALGOLIA_APP_ID`: Your Algolia Application ID
   - `ALGOLIA_API_KEY`: Your Algolia Search API Key (public/search-only key)

### 2. Environment Variables for Local Development

For local development, create a `.env.local` file in the `docs` directory:

```bash
# docs/.env.local
ALGOLIA_APP_ID=your_actual_app_id
ALGOLIA_API_KEY=your_actual_api_key
```

**Note**: Never commit the `.env.local` file. It's already excluded by the default `.gitignore`.

### 3. Index Your Documentation

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

### 4. Test the Search

After setting up the secrets and environment variables:

1. Run `npm run start` to start the development server (with `.env.local` for local testing)
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

- **"No results" or connection errors**: Verify your `ALGOLIA_APP_ID` and `ALGOLIA_API_KEY` secrets are set correctly
- **Build failures**: Ensure the environment variables are available during the build process
- **Outdated results**: If using DocSearch, Algolia crawls periodically. Manual indexing gives you more control
- **Search not appearing**: Check the browser console for errors related to missing environment variables

## Additional Configuration Options

You can customize the search behavior with additional options:

```typescript
algolia: {
  appId: process.env.ALGOLIA_APP_ID!,
  apiKey: process.env.ALGOLIA_API_KEY!,
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

## Security

The configuration now uses environment variables for sensitive data:
- GitHub Secrets are used for CI/CD deployment
- Local development uses `.env.local` file (never committed)
- No sensitive credentials are stored in the codebase

For more details, see the [Docusaurus Algolia Search documentation](https://docusaurus.io/docs/search#using-algolia-docsearch).