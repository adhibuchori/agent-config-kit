import type { Metadata } from 'next';
import Link from 'next/link';

const description = 'Toy Studio membuat situs contoh kecil untuk menguji pemeriksaan situs statis secara otomatis.';

export const metadata: Metadata = {
  title: { absolute: 'Toy Studio (Indonesia)' },
  description,
  alternates: { canonical: '/id', languages: { en: '/', id: '/id', 'x-default': '/' } },
  openGraph: {
    title: 'Toy Studio (Indonesia)',
    description,
    url: '/id',
    siteName: 'Toy Studio',
    type: 'website',
    images: '/opengraph-image',
  },
};

export default function HomeId() {
  return (
    <main lang="id">
      <h1>Toy Studio</h1>
      <Link href="/">English</Link> <Link href="/about">Tentang</Link>
    </main>
  );
}
