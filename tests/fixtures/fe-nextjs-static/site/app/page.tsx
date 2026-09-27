import type { Metadata } from 'next';
import Image from 'next/image';
import Link from 'next/link';

const description = 'Toy Studio builds small example websites that exercise static-site checks in tests.';
const languages = { en: '/', id: '/id', 'x-default': '/' };

export const metadata: Metadata = {
  title: { absolute: 'Toy Studio' },
  description,
  alternates: { canonical: '/', languages },
  openGraph: { title: 'Toy Studio', description, url: '/', siteName: 'Toy Studio', type: 'website' },
};

const organization = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
  name: 'Toy Studio',
  url: 'https://example.com',
  logo: 'https://example.com/images/logo.png',
};

export default function Home() {
  return (
    <main>
      <h1>Toy Studio</h1>
      <Image src="/images/hero.png" alt="A toy hero" width={1200} height={630} priority />
      <nav aria-label="Main">
        <Link href="/about">About</Link> <Link href="/blog/hello">Blog</Link> <Link href="/id">Bahasa Indonesia</Link>{' '}
        <a href="#contact">Contact</a>
      </nav>
      <p>
        <a href="https://partner.example.org/" target="_blank" rel="noopener noreferrer">
          Our partner
        </a>{' '}
        <a href="mailto:hello@example.com">Email us</a>
      </p>
      <section id="contact">
        <h2>Contact</h2>
      </section>
      <script type="application/ld+json">{JSON.stringify(organization).replace(/</g, '\\u003c')}</script>
    </main>
  );
}
