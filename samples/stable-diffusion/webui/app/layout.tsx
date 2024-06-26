import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import QueryClientContextProvider from "./QueryClientContextProvider";
const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Stable Diffusion",
  description: "Generated images from text",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
      <html lang="en">
        <QueryClientContextProvider>
          <body className={inter.className}>{children}</body>
        </QueryClientContextProvider>
      </html>
  );
}
