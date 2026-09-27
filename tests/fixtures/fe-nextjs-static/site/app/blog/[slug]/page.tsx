import type { Metadata } from 'next';

type Props = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return [{ slug: 'hello' }];
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const description = 'The first post on the Toy Studio blog, written to give the checks a nested route.';
  return {
    title: 'Hello',
    description,
    alternates: { canonical: `/blog/${slug}` },
    openGraph: {
      title: 'Hello | Toy Studio',
      description,
      url: `/blog/${slug}`,
      siteName: 'Toy Studio',
      type: 'article',
      images: '/opengraph-image',
    },
  };
}

export default async function Post({ params }: Props) {
  const { slug } = await params;
  const data = {
    '@context': 'https://schema.org',
    '@graph': [
      { '@type': 'BlogPosting', headline: 'Hello', datePublished: '2026-01-15', image: 'https://example.com/opengraph-image' },
      {
        '@type': 'BreadcrumbList',
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'Home', item: 'https://example.com/' },
          { '@type': 'ListItem', position: 2, name: 'Hello' },
        ],
      },
    ],
  };
  return (
    <main>
      <article>
        <h1>{slug === 'hello' ? 'Hello' : slug}</h1>
      </article>
      <a href="../about">About</a>
      <script type="application/ld+json">{JSON.stringify(data).replace(/</g, '\\u003c')}</script>
    </main>
  );
}
