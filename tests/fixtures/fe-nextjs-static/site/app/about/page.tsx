import type { Metadata } from 'next';
import Link from 'next/link';

const description = 'Who runs Toy Studio, how the studio works, and where to find the team.';

export const metadata: Metadata = {
  title: 'About',
  description,
  alternates: { canonical: '/about' },
};

export default function About() {
  return (
    <main>
      <h1>About</h1>
      <Link href="/">Home</Link> <Link href="/#contact">Contact</Link>
    </main>
  );
}
