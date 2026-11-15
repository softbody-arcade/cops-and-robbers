import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { homedir } from 'node:os'
import { pathToFileURL } from 'node:url'
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

function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name)
    if (e.isDirectory()) {
      if (e.name !== 'node_modules') walk(p, out)
    } else if (e.name.endsWith('.vue')) out.push(p)
  }
  return out
}

function iconNames(text) {
  const names = new Set()
  for (const m of text.matchAll(/\bicons\.(\w+)/g)) names.add(m[1])
  for (const tag of text.matchAll(/<(Bng\w+)\b((?:[^>"']|"[^"]*"|'[^']*')*)>/g)) {
    const attr = tag[1] === 'BngIcon' ? 'type' : 'icon'
    for (const m of tag[2].matchAll(new RegExp(`(?<![\\w-])${attr}=(?:"([^"]*)"|'([^']*)')`, 'g'))) {
      const v = m[1] ?? m[2]
      const q = v.match(/^'([^']+)'$/)
      if (q) names.add(q[1])
      else if (/^\w+$/.test(v)) names.add(v)
    }
  }
  return names
}

function checkIcons(file, text) {
  if (!icons) return
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
    checkIcons(file, (descriptor.template?.content || '') + '\n' + (descriptor.scriptSetup?.content || '') + '\n' + (descriptor.script?.content || ''))
    return
  }

  let bindings
  let scriptText = ''
  if (descriptor.script || descriptor.scriptSetup) {
    try {
      const r = compileScript(descriptor, { id })
      bindings = r.bindings
      scriptText = (descriptor.script?.content || '') + '\n' + (descriptor.scriptSetup?.content || '')
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

  checkIcons(file, (descriptor.template?.content || '') + '\n' + scriptText)
}

const dirs = process.argv.slice(2)
if (!dirs.length) {
  console.error('usage: check.mjs <dir>...')
  process.exit(2)
}
const files = dirs.flatMap(d => walk(d))
for (const f of files) check(f)
if (errors.length) {
  console.error(errors.join('\n'))
  process.exit(1)
}
console.log(`vuecheck: ${files.length} files ok`)
