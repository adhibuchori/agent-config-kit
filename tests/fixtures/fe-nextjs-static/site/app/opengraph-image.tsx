import { ImageResponse } from 'next/og';

export const dynamic = 'force-static';
export const alt = 'Toy Studio';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default function OpengraphImage() {
  return new ImageResponse(<div style={{ display: 'flex', fontSize: 96 }}>Toy Studio</div>, size);
}
