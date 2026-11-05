import React from "react";
import ReactDOM from "react-dom/client";
import "./index.css";
import { App } from "./App";

async function start() {
  if (
    import.meta.env.DEV &&
    new URLSearchParams(location.search).has("preview")
  ) {
    const { installPreview } = await import("./workspace/preview");
    installPreview();
  }
  ReactDOM.createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  );
}
void start();
