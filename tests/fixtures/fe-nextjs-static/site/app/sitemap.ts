import type { MetadataRoute } from 'next';

export const dynamic = 'force-static';

export default function sitemap(): MetadataRoute.Sitemap {
  const languages = { en: 'https://example.com/', id: 'https://example.com/id', 'x-default': 'https://example.com/' };
  return [
    { url: 'https://example.com/', alternates: { languages } },
    { url: 'https://example.com/id', alternates: { languages } },
    { url: 'https://example.com/about' },
    { url: 'https://example.com/blog/hello' },
  ];
}
