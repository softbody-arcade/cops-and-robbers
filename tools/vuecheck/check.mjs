import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { homedir } from 'node:os'
import { pathToFileURL } from 'node:url'
import { spawnSync } from 'node:child_process'
import { parse, compileScript, compileTemplate, compileStyle } from '@vue/compiler-sfc'
import * as sass from 'sass'

const uiSrc = process.env.BNG_UI_SRC || join(homedir(), '.local/share/Steam/steamapps/common/BeamNG.drive/ui/ui-vue/src')
const iconFile = join(uiSrc, 'assets/fonts/bngIcons/bngIcons.js')

let icons = null
if (existsSync(iconFile)) {
  icons = new Set([...readFileSync(iconFile, 'utf8').matchAll(/^ {2}"?(\w+)"?: \{/gm)].map(m => m[1]))
} else {
  console.warn(`warning: ${iconFile} not found, skipping icon check`)
}

const errors = []
const fail = (file, msg) => errors.push(`${file}: ${msg}`)

function walk(dir, ext, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name)
    if (e.isDirectory()) {
      if (e.name !== 'node_modules') walk(p, ext, out)
    } else if (e.name.endsWith(ext)) out.push(p)
  }
  return out
}

function checkJs(file) {
  const r = spawnSync(process.execPath, ['--input-type=module', '--check'], { input: readFileSync(file, 'utf8'), encoding: 'utf8' })
  if (r.error) return fail(file, r.error.message)
  if (r.status === 0) return
  const lines = (r.stderr || '').split('\n').map(l => l.trim()).filter(Boolean)
  const at = ((lines.find(l => /^\[stdin\]:\d+/.test(l)) || '').match(/\d+/) || [])[0]
  const msg = lines.find(l => /Error/.test(l)) || `node --check exited with ${r.status}`
  fail(file, at ? `line ${at}: ${msg}` : msg)
}

function iconNames(text) {
  const names = new Set()
  for (const m of text.matchAll(/\bicons\.(\w+)/g)) names.add(m[1])
  for (const tag of text.matchAll(/<(Bng\w+)\b((?:[^>"']|"[^"]*"|'[^']*')*)>/g)) {
    const attr = tag[1] === 'BngIcon' ? 'type' : 'icon'
    for (const m of tag[2].matchAll(new RegExp(`(?:^|\\s)(:|v-bind:)?${attr}=(?:"([^"]*)"|'([^']*)')`, 'g'))) {
      const v = m[2] ?? m[3]
      const q = v.match(/^'([^']+)'$/)
      if (q) names.add(q[1])
      else if (!m[1] && /^\w+$/.test(v)) names.add(v)
    }
  }
  return names
}

function checkIcons(file, descriptor) {
  if (!icons) return
  const text = [descriptor.template, descriptor.scriptSetup, descriptor.script].map(b => b?.content || '').join('\n')
  for (const n of iconNames(text)) {
    if (!icons.has(n)) fail(file, `unknown icon "${n}"`)
  }
}

function check(file) {
  const source = readFileSync(file, 'utf8')
  const id = Buffer.from(file).toString('hex').slice(-8)
  const { descriptor, errors: perr } = parse(source, { filename: file })
  for (const e of perr) fail(file, e.message)
  if (perr.length) {
    checkIcons(file, descriptor)
    return
  }

  let bindings
  if (descriptor.script || descriptor.scriptSetup) {
    try {
      const r = compileScript(descriptor, { id })
      bindings = r.bindings
    } catch (e) {
      fail(file, e.message)
    }
  }

  if (descriptor.template) {
    const r = compileTemplate({
      source: descriptor.template.content,
      filename: file,
      id,
      compilerOptions: { bindingMetadata: bindings },
    })
    for (const e of r.errors) fail(file, typeof e === 'string' ? e : e.message)
  }

  for (const s of descriptor.styles) {
    try {
      let css = s.content
      if (s.lang === 'scss' || s.lang === 'sass') {
        css = sass.compileString(css, {
          syntax: s.lang === 'sass' ? 'indented' : 'scss',
          logger: sass.Logger.silent,
          importers: [{
            findFileUrl(url) {
              if (url.startsWith('@/')) return pathToFileURL(join(uiSrc, url.slice(2)))
              return pathToFileURL(resolve(dirname(file), url))
            },
          }],
        }).css
      }
      const r = compileStyle({ source: css, filename: file, id: `data-v-${id}`, scoped: s.scoped })
      for (const e of r.errors) fail(file, e.message)
    } catch (e) {
      fail(file, (e.message || String(e)).split('\n')[0])
    }
  }

  checkIcons(file, descriptor)
}

const dirs = process.argv.slice(2)
if (!dirs.length) {
  console.error('usage: check.mjs <dir>...')
  process.exit(2)
}
const files = dirs.flatMap(d => walk(d, '.vue'))
const scripts = dirs.flatMap(d => walk(d, '.js'))
for (const f of files) check(f)
for (const f of scripts) checkJs(f)
if (errors.length) {
  console.error(errors.join('\n'))
  process.exit(1)
}
console.log(`vuecheck: ${files.length} Vue files and ${scripts.length} .js files ok`)
