import type { Metadata } from 'next';
import localFont from 'next/font/local';

const brand = localFont({ src: './fonts/brand.woff2', display: 'swap' });

export const metadata: Metadata = {
  metadataBase: new URL('https://example.com'),
  title: { default: 'Toy Studio', template: '%s | Toy Studio' },
  twitter: { card: 'summary_large_image' },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={brand.className}>
      <body>{children}</body>
    </html>
  );
}
