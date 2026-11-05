import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  base: "./",
  plugins: [
    react(),
    tailwindcss(),
    {
      name: "development-csp",
      apply: "serve",
      // Vite's dev-only HMR preamble is inline. The release keeps the strict bundle-only CSP.
      transformIndexHtml: (html) =>
        html.replace(/<meta http-equiv="Content-Security-Policy"[^>]*\/>/, ""),
    },
    {
      name: "offline-webkit-bundle",
      apply: "build",
      transformIndexHtml: {
        order: "post",
        // WKWebView's file origin cannot use CORS requests for local resources.
        // The release is one classic script; its CSP stays restricted to self.
        handler: (html) =>
          html
            .replace(
              /<script\b([^>]*)>/g,
              (_, attributes: string) =>
                `<script defer${attributes.replace(/\s+type="module"/g, "").replace(/\s+crossorigin(?:="[^"]*")?/g, "")}>`,
            )
            .replace(
              /<link\b([^>]*)>/g,
              (_, attributes: string) =>
                `<link${attributes.replace(/\s+crossorigin(?:="[^"]*")?/g, "")}>`,
            ),
      },
    },
  ],
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  build: {
    target: "safari18",
    sourcemap: false,
    cssCodeSplit: false,
    modulePreload: false,
    rollupOptions: {
      output: { format: "iife", inlineDynamicImports: true },
    },
  },
});
