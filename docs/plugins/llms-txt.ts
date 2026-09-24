import fs from 'node:fs/promises';
import path from 'node:path';
import type {LoadContext, Plugin} from '@docusaurus/types';

/**
 * Publishes the docs for LLMs and coding agents, following https://llmstxt.org:
 * `/llms.txt` (an index), `/llms-full.txt` (every page concatenated) and a raw
 * `/docs/<id>.md` next to each rendered page. Pages come from `docs/` in the
 * order given, so the output always matches the sidebar.
 */
export default function llmsTxtPlugin(
  context: LoadContext,
  options: {pages: string[]; summary: string},
): Plugin {
  return {
    name: 'llms-txt',
    async postBuild({outDir}) {
      const siteUrl = context.siteConfig.url;
      const pages = await Promise.all(
        options.pages.map(async (id) => {
          const raw = await fs.readFile(path.join(context.siteDir, 'docs', `${id}.md`), 'utf8');
          return {id, ...parse(raw)};
        }),
      );

      const index = [
        `# ${context.siteConfig.title}`,
        '',
        `> ${options.summary}`,
        '',
        `Full documentation in one file: ${siteUrl}/llms-full.txt`,
        '',
        '## Docs',
        '',
        ...pages.map((p) => `- [${p.title}](${siteUrl}/docs/${p.id}.md)${p.description ? `: ${p.description}` : ''}`),
        '',
      ].join('\n');

      const full = [
        `# ${context.siteConfig.title}`,
        '',
        `> ${options.summary}`,
        '',
        ...pages.map((p) => `<!-- ${siteUrl}/docs/${p.id}/ -->\n\n${p.body.trim()}\n`),
      ].join('\n');

      await fs.writeFile(path.join(outDir, 'llms.txt'), index);
      await fs.writeFile(path.join(outDir, 'llms-full.txt'), full);
      await fs.mkdir(path.join(outDir, 'docs'), {recursive: true});
      for (const p of pages) {
        await fs.writeFile(path.join(outDir, 'docs', `${p.id}.md`), `${p.body.trim()}\n`);
      }
    },
  };
}

/** Every doc id in a sidebar, in order, so the llms.txt files follow the site's navigation. */
export function sidebarPageIds(items: unknown): string[] {
  const ids: string[] = [];
  const walk = (list: unknown[]) => {
    for (const item of list) {
      if (typeof item === 'string') ids.push(item);
      else if (item && typeof item === 'object' && 'items' in item) walk((item as {items: unknown[]}).items);
    }
  };
  walk(items as unknown[]);
  return ids;
}

/** Splits front matter from the body and picks out `title` and `description`; the first paragraph stands in for a missing description. */
function parse(raw: string): {title: string; description: string; body: string} {
  const match = /^---\n([\s\S]*?)\n---\n/.exec(raw.replace(/\r\n/g, '\n'));
  const front = match?.[1] ?? '';
  const body = match ? raw.replace(/\r\n/g, '\n').slice(match[0].length) : raw;
  const field = (name: string) =>
    (new RegExp(`^${name}:\\s*(.+)$`, 'm').exec(front)?.[1]?.trim() ?? '').replace(/^"(.*)"$/, '$1');
  const firstParagraph =
    body
      .split('\n\n')
      .map((block) => block.trim())
      .find((block) => block && !block.startsWith('#') && !block.startsWith(':::') && !block.startsWith('```') && !block.startsWith('|')) ?? '';
  return {
    title: field('title') || /^# (.+)$/m.exec(body)?.[1] || '',
    description: field('description') || firstParagraph.replace(/\s+/g, ' '),
    body,
  };
}
