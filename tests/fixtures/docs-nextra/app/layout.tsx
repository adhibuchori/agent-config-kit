import type { ReactNode } from 'react';

export const metadata = { title: { default: 'Toy docs', template: '%s | Toy docs' } };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
