import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "RescuePOV Cloud — リアルタイム救難・空間照射管制システム",
  description: "Apple Intelligence / CoreMotion / POV空間残像技術と連携するクラウド救助管制ダッシュボード",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja" className="dark">
      <body className="min-h-screen bg-black text-white antialiased selection:bg-red-500/30">
        {children}
      </body>
    </html>
  );
}
