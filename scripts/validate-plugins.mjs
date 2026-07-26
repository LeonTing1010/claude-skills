#!/usr/bin/env node
// validate-plugins.mjs — regression guard for the distributed Claude Code
// plugin marketplace. Zero-dependency (Node stdlib only); runs in CI on every
// push to main (taprun's release moment IS the push) AND locally before pushing:
//
//     node scripts/validate-plugins.mjs
//
// WHY THIS EXISTS (the regression it prevents):
//   2026-07-24 commit e273ade shipped `plugins/tap/.mcp.json` with
//     "command": "/opt/homebrew/bin/tap"
//   — a machine-local absolute path (Leo's arm64 Homebrew) that leaked from a
//   local binary-swap override into the DISTRIBUTED plugin. Any user who
//   installed `tap@taprun` got an MCP server that could not start: the path
//   does not exist on their machine. taprun has no build/test toolchain and the
//   core release pipeline never touches this repo, so nothing caught it.
//
//   Check M1 below pins the one canonical, portable invocation
//   (`npx -y @taprun/cli mcp stdio`) and Check P1 bans machine-local absolute
//   paths anywhere in a distributed manifest. Either would have failed e273ade
//   at push time.
//
// Scope: the Claude Code plugin marketplace only (marketplace.json + the plugins
// it declares). The SkillHub `workbuddy/` set is a separate distribution target
// (zh-CN localization, different schema) and is intentionally NOT validated here.

import { readFileSync, existsSync, statSync, readdirSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const errors = [];
const fail = (where, msg) => errors.push(`${where}: ${msg}`);

function readJson(path, where) {
  if (!existsSync(path)) {
    fail(where, `missing file ${rel(path)}`);
    return null;
  }
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    fail(where, `invalid JSON in ${rel(path)} — ${e.message}`);
    return null;
  }
}
const rel = (p) => p.replace(ROOT + "/", "");

// A string is a machine-local absolute path if it targets a real filesystem
// root we know installers land in. `${VAR}/...`, `./rel`, and `https://` URLs
// are all portable and must NOT trip this.
const LOCAL_ABS = /^\/(opt|usr|Users|home|private|var|Applications|nix|bin|sbin|snap)\b/;
const WIN_ABS = /^[A-Za-z]:\\/;
function scanForLocalPaths(node, where, path = "") {
  if (typeof node === "string") {
    if (LOCAL_ABS.test(node) || WIN_ABS.test(node)) {
      fail(where, `machine-local absolute path at ${path || "<root>"}: ${JSON.stringify(node)} — distributed manifests must be portable (use npx / \${CLAUDE_PLUGIN_ROOT} / relative paths)`);
    }
  } else if (Array.isArray(node)) {
    node.forEach((v, i) => scanForLocalPaths(v, where, `${path}[${i}]`));
  } else if (node && typeof node === "object") {
    for (const [k, v] of Object.entries(node)) scanForLocalPaths(v, where, path ? `${path}.${k}` : k);
  }
}

// ── marketplace ────────────────────────────────────────────────────────────
const marketplace = readJson(join(ROOT, ".claude-plugin/marketplace.json"), "marketplace.json");
if (marketplace) {
  scanForLocalPaths(marketplace, "marketplace.json");
  if (!Array.isArray(marketplace.plugins) || marketplace.plugins.length === 0) {
    fail("marketplace.json", "no plugins declared");
  }
  for (const entry of marketplace.plugins ?? []) {
    const where = `plugin "${entry.name}"`;
    if (!entry.name) fail("marketplace.json", "a plugin entry has no name");
    if (!entry.source || !entry.source.startsWith("./")) {
      fail(where, `source must be a repo-relative "./..." path (got ${JSON.stringify(entry.source)})`);
      continue;
    }
    const pdir = join(ROOT, entry.source);
    validatePlugin(entry, pdir, where);
  }
}

function validatePlugin(entry, pdir, where) {
  // plugin.json
  const manifest = readJson(join(pdir, ".claude-plugin/plugin.json"), where);
  if (manifest) {
    scanForLocalPaths(manifest, `${where} plugin.json`);
    if (manifest.name !== entry.name) {
      fail(where, `plugin.json name "${manifest.name}" != marketplace name "${entry.name}"`);
    }
    if (!manifest.version) fail(where, "plugin.json has no version");
  }

  // .mcp.json — the F1 regression surface
  const mcpPath = join(pdir, ".mcp.json");
  if (existsSync(mcpPath)) {
    const mcp = readJson(mcpPath, `${where} .mcp.json`);
    if (mcp) {
      scanForLocalPaths(mcp, `${where} .mcp.json`); // P1: no local abs paths
      const servers = mcp.mcpServers ?? {};
      if (Object.keys(servers).length === 0) fail(`${where} .mcp.json`, "mcpServers is empty");
      for (const [sid, cfg] of Object.entries(servers)) {
        const w = `${where} .mcp.json server "${sid}"`;
        const cmd = cfg?.command;
        // M1: command must be a portable launcher, never an absolute path.
        if (typeof cmd !== "string" || cmd.length === 0) {
          fail(w, "command missing");
        } else if (cmd.startsWith("/") || WIN_ABS.test(cmd)) {
          fail(w, `command is an absolute path "${cmd}" — a distributed plugin cannot assume a local install location; launch via npx`);
        }
        // Pin the one canonical invocation for the tap server specifically.
        if (sid === "tap") {
          const args = cfg?.args ?? [];
          const ok = cmd === "npx" && args.includes("@taprun/cli") && args.includes("mcp") && args.includes("stdio");
          if (!ok) {
            fail(w, `must launch as \`npx -y @taprun/cli mcp stdio\` (got command=${JSON.stringify(cmd)} args=${JSON.stringify(args)})`);
          }
        }
      }
    }
  }

  // hooks
  const hooksPath = join(pdir, "hooks/hooks.json");
  if (existsSync(hooksPath)) {
    const hooks = readJson(hooksPath, `${where} hooks.json`);
    if (hooks) {
      scanForLocalPaths(hooks, `${where} hooks.json`);
      for (const group of Object.values(hooks.hooks ?? {})) {
        for (const matcher of group ?? []) {
          for (const h of matcher.hooks ?? []) {
            const c = h.command ?? "";
            const w = `${where} hooks.json`;
            // Hook commands must resolve via ${CLAUDE_PLUGIN_ROOT}, never absolute.
            if (h.type === "command" && c.startsWith("/")) {
              fail(w, `hook command is absolute "${c}" — use \${CLAUDE_PLUGIN_ROOT}/...`);
            }
            const m = c.match(/\$\{CLAUDE_PLUGIN_ROOT\}\/(\S+)/);
            if (m) {
              const script = join(pdir, m[1]);
              if (!existsSync(script)) {
                fail(w, `hook script does not exist: ${m[1]}`);
              } else if (!(statSync(script).mode & 0o111)) {
                fail(w, `hook script is not executable (chmod +x): ${m[1]}`);
              }
            }
          }
        }
      }
    }
  }

  // skills — frontmatter name must equal the directory name
  const skillsDir = join(pdir, "skills");
  if (existsSync(skillsDir)) {
    for (const name of listDirs(skillsDir)) {
      const md = join(skillsDir, name, "SKILL.md");
      const w = `${where} skill "${name}"`;
      if (!existsSync(md)) {
        fail(w, "missing SKILL.md");
        continue;
      }
      const body = readFileSync(md, "utf8");
      const fm = body.match(/^---\n([\s\S]*?)\n---/);
      if (!fm) {
        fail(w, "SKILL.md has no YAML frontmatter");
        continue;
      }
      const nameLine = fm[1].match(/^name:\s*(.+)$/m);
      if (!nameLine) fail(w, "frontmatter has no `name:`");
      else if (nameLine[1].trim() !== name) {
        fail(w, `frontmatter name "${nameLine[1].trim()}" != directory "${name}"`);
      }
    }
  }
}

function listDirs(dir) {
  return readdirSync(dir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
}

// ── report ───────────────────────────────────────────────────────────────
if (errors.length) {
  console.error(`\n✗ plugin marketplace validation FAILED (${errors.length}):\n`);
  for (const e of errors) console.error(`  • ${e}`);
  console.error("");
  process.exit(1);
}
console.log("✓ plugin marketplace valid — all manifests portable, MCP launch canonical, hooks + skills consistent");
