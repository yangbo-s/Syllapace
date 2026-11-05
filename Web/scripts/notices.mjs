import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const lock = JSON.parse(
  fs.readFileSync(path.join(root, "package-lock.json"), "utf8"),
);
const sections = [
  "# Syllapace Web workspace — third-party notices",
  "\n## ReUI\n\n" + fs.readFileSync(path.join(root, "LICENSE.reui.md"), "utf8"),
];
const missing = [];
const entries = Object.entries(lock.packages).filter(
  ([name, value]) =>
    name.startsWith("node_modules/") &&
    (!value.dev || name === "node_modules/shadcn"),
);
for (const [directory] of entries.sort(([a], [b]) => a.localeCompare(b))) {
  const packagePath = path.join(root, directory);
  if (!fs.existsSync(packagePath)) continue;
  const manifest = JSON.parse(
    fs.readFileSync(path.join(packagePath, "package.json"), "utf8"),
  );
  const licenses = fs
    .readdirSync(packagePath)
    .filter(
      (name) =>
        /^(license|licence|copying|notice)(\.|$|-)/i.test(name) &&
        fs.statSync(path.join(packagePath, name)).isFile(),
    );
  sections.push(
    `\n## ${manifest.name} ${manifest.version}\n\nLicense: ${typeof manifest.license === "string" ? manifest.license : JSON.stringify(manifest.license)}\n`,
  );
  if (!licenses.length) missing.push(manifest.name);
  for (const license of licenses)
    sections.push(fs.readFileSync(path.join(packagePath, license), "utf8"));
}
if (missing.length)
  throw new Error(`Missing installed license texts: ${missing.join(", ")}`);
fs.writeFileSync(
  path.join(root, "dist", "THIRD_PARTY_NOTICES.txt"),
  sections.join("\n"),
);
const scriptFiles = fs
  .readdirSync(path.join(root, "dist", "assets"))
  .filter((name) => name.endsWith(".js"));
const index = fs.readFileSync(path.join(root, "dist", "index.html"), "utf8");
if (
  scriptFiles.length !== 1 ||
  !/<script defer src="\.\/assets\/[^"/]+\.js"><\/script>/.test(index) ||
  /\b(?:crossorigin|type="module"|rel="modulepreload")/.test(index)
)
  throw new Error(
    "The offline WebKit release must use one deferred classic local script without CORS resource requests.",
  );
if (
  !index.includes("script-src 'self'") ||
  !index.includes("connect-src 'none'")
)
  throw new Error(
    "The release must retain its local-only Content Security Policy.",
  );
const bundle = scriptFiles
  .map((name) =>
    fs.readFileSync(path.join(root, "dist", "assets", name), "utf8"),
  )
  .join("\n");
for (const marker of [
  "Synthetic preview event.",
  "course-algorithms",
  "installPreview",
  "127.0.0.1:5173",
]) {
  if (bundle.includes(marker))
    throw new Error(`Development fixture leaked into release: ${marker}`);
}
console.log(
  `Bundled MIT ReUI notice + ${entries.length} dependency notices; production fixture check passed.`,
);
