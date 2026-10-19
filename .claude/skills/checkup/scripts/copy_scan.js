#!/usr/bin/env node
// Scans user-facing text in Dart files for AI-writing patterns, using the
// detector shipped with the avoid-ai-writing plugin.
//
//   node copy_scan.js [--json] [FILE_OR_DIR...]     (default: lib/)
//
// Only string literals that read like prose are checked (at least two words,
// not an import, URL, asset path or SQL). Comments are ignored. Exit code 1 when
// anything is flagged.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

function findDetector() {
  const roots = [
    path.join(os.homedir(), '.claude/plugins/cache/conorbronsdon-skills/avoid-ai-writing'),
  ];
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    const versions = fs.readdirSync(root).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
    for (const v of versions) {
      const p = path.join(root, v, 'skills/avoid-ai-writing/detector/patterns.js');
      if (fs.existsSync(p)) return p;
    }
  }
  console.error('avoid-ai-writing plugin not found. Install it with: claude plugin install avoid-ai-writing@conorbronsdon-skills');
  process.exit(2);
}

// Pull string literals (with their line numbers) out of Dart source, skipping comments.
function dartStrings(src) {
  const out = [];
  let i = 0, line = 1;
  while (i < src.length) {
    const c = src[i];
    if (c === '\n') { line++; i++; continue; }
    if (c === '/' && src[i + 1] === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && src[i + 1] === '*') {
      const end = src.indexOf('*/', i + 2);
      const stop = end < 0 ? src.length : end + 2;
      for (let k = i; k < stop; k++) if (src[k] === '\n') line++;
      i = stop; continue;
    }
    if (c === "'" || c === '"') {
      const raw = src[i - 1] === 'r';
      const triple = src.substr(i, 3) === c.repeat(3);
      const q = triple ? c.repeat(3) : c;
      const startLine = line;
      let j = i + q.length, text = '', depth = 0;
      while (j < src.length && !(depth === 0 && src.substr(j, q.length) === q)) {
        const ch = src[j];
        if (ch === '\n') { line++; if (!triple) break; }
        if (!raw && ch === '\\') { text += src[j + 1] === 'n' ? '\n' : src[j + 1]; j += 2; continue; }
        if (!raw && ch === '$' && src[j + 1] === '{') { depth++; text += 'X'; j += 2; continue; }
        if (depth > 0) { if (ch === '{') depth++; if (ch === '}') depth--; j++; continue; }
        if (!raw && ch === '$' && /[A-Za-z_]/.test(src[j + 1] || '')) {
          j++; while (/[A-Za-z0-9_.]/.test(src[j] || '')) j++; text += 'X'; continue;
        }
        text += ch; j++;
      }
      const prev = out[out.length - 1];
      if (prev && /^\s*$/.test(src.slice(prev.end, i).replace(/\/\/[^\n]*/g, ''))) {
        prev.text += text; prev.end = j + q.length;  // 'a' 'b' is one string in Dart
      } else {
        out.push({ line: startLine, text, end: j + q.length });
      }
      i = j + q.length; continue;
    }
    i++;
  }
  return out;
}

function looksLikeProse(s, lineText) {
  if (/^\s*(import|export|part)\b/.test(lineText)) return false;
  const t = s.trim();
  if (!/[A-Za-z]/.test(t) || !/\s/.test(t)) return false;
  if (/^(package:|dart:|https?:|assets\/|mailto:)/.test(t)) return false;
  if (/^\s*(select|insert|update|delete|create|alter)\s/i.test(t)) return false;
  if (/^[\w.:/-]+$/.test(t)) return false;
  return true;
}

function collect(targets) {
  const files = [];
  const walk = (p) => {
    const st = fs.statSync(p);
    if (st.isDirectory()) fs.readdirSync(p).forEach((f) => walk(path.join(p, f)));
    else if (p.endsWith('.dart')) files.push(p);
  };
  targets.forEach((t) => fs.existsSync(t) && walk(t));
  return files.sort();
}

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const targets = args.filter((a) => a !== '--json');
const Detector = require(findDetector());
const findings = [];
for (const file of collect(targets.length ? targets : ['lib'])) {
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split('\n');
  for (const { line, text } of dartStrings(src)) {
    if (!looksLikeProse(text, lines[line - 1] || '')) continue;
    const { issues } = Detector.analyzeText(text);
    const all = (issues || []).filter((iss) => iss.type !== 'em-dash');
    if (/\u2014/.test(text)) all.push({ type: 'em-dash', severity: 'medium', text: '\u2014', suggestion: 'period, comma, colon, or parentheses' });
    for (const iss of all) {
      if (iss.severity === 'low') continue;
      findings.push({ file, line, type: iss.type, severity: iss.severity, match: iss.text,
        suggestion: iss.suggestion || null, string: text.length > 140 ? text.slice(0, 137) + '...' : text });
    }
  }
}

if (asJson) console.log(JSON.stringify(findings, null, 2));
else if (!findings.length) console.log('No AI-writing patterns found in user-facing strings.');
else {
  for (const f of findings) {
    console.log(`${f.file}:${f.line}  [${f.severity}] ${Detector.getLabel ? Detector.getLabel(f.type) : f.type}: "${f.match}"` +
      (f.suggestion ? `  → ${f.suggestion}` : ''));
    console.log(`    "${f.string.replace(/\n/g, ' ')}"`);
  }
  console.log(`\n${findings.length} finding(s) in ${new Set(findings.map((f) => f.file)).size} file(s).`);
}
process.exit(findings.length ? 1 : 0);
