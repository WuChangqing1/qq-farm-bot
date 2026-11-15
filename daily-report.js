// 每日报表：汇总 core/data/daily/<日期>.jsonl 与 core/data/stats/<账号>.json，输出 Markdown
const fs = require('node:fs')
const path = require('node:path')

const root = __dirname
const dataDir = path.join(root, 'core', 'data', 'daily')
const statsDir = path.join(root, 'core', 'data', 'stats')

function localDate(d = new Date()) {
  return d.toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
}

const date = (process.argv[2] || localDate()).trim()
const accountsFile = path.join(root, 'core', 'data', 'accounts.json')
const accounts = fs.existsSync(accountsFile)
  ? (JSON.parse(fs.readFileSync(accountsFile, 'utf8')).accounts || [])
  : []
const accountIds = accounts.map(a => String(a.id))

const jsonlFile = path.join(dataDir, `${date}.jsonl`)
const samples = []
if (fs.existsSync(jsonlFile)) {
  for (const line of fs.readFileSync(jsonlFile, 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue
    try { samples.push(JSON.parse(line)) } catch {}
  }
}

const byAccount = new Map()
for (const s of samples) {
  const id = String(s.accountId)
  if (!byAccount.has(id)) byAccount.set(id, [])
  byAccount.get(id).push(s)
}

function readStats(id) {
  const file = path.join(statsDir, `${id}.json`)
  if (!fs.existsSync(file)) return null
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'))
    return data.date === date ? data : null
  } catch { return null }
}

const fmt = n => Number(n || 0).toLocaleString('zh-CN')
const signed = n => `${n > 0 ? '+' : ''}${fmt(n)}`

const rows = []
const totals = { steal: 0, harvest: 0, plant: 0, helpFarming: 0, fertilize: 0, sell: 0, taskClaim: 0, gold: 0, bean: 0, exp: 0 }

for (const id of accountIds) {
  const acc = accounts.find(a => String(a.id) === id) || {}
  const list = (byAccount.get(id) || []).slice().sort((a, b) => a.ts - b.ts)
  const online = list.filter(s => s.connected)
  const first = online[0] || null
  const last = online[online.length - 1] || null
  const stats = readStats(id)
  const ops = stats?.operations || {}

  const goldDelta = first && last ? last.gold - first.gold : 0
  const hasBeanPair = first && last && typeof first.goldBean === 'number' && typeof last.goldBean === 'number'
  const goldBeanDelta = hasBeanPair ? last.goldBean - first.goldBean : 0
  const goldBean = last?.goldBean || 0
  const expDelta = first && last ? last.exp - first.exp : 0
  const level = last?.level || 0

  rows.push({
    id,
    name: acc.name || id,
    qq: acc.qq || '',
    samples: list.length,
    steal: Number(ops.steal) || 0,
    harvest: Number(ops.harvest) || 0,
    plant: Number(ops.plant) || 0,
    helpFarming: Number(ops.helpFarming) || 0,
    fertilize: Number(ops.fertilize) || 0,
    sell: Number(ops.sell) || 0,
    taskClaim: Number(ops.taskClaim) || 0,
    goldStart: first?.gold ?? 0,
    goldEnd: last?.gold ?? 0,
    goldDelta,
    goldBean,
    goldBeanDelta,
    expDelta,
    sessionGold: last?.sessionGoldGained ?? 0,
    level,
    online: !!last,
  })

  totals.steal += Number(ops.steal) || 0
  totals.harvest += Number(ops.harvest) || 0
  totals.plant += Number(ops.plant) || 0
  totals.helpFarming += Number(ops.helpFarming) || 0
  totals.fertilize += Number(ops.fertilize) || 0
  totals.sell += Number(ops.sell) || 0
  totals.taskClaim += Number(ops.taskClaim) || 0
  totals.gold += goldDelta
  totals.bean += goldBeanDelta
  totals.exp += expDelta
}

const lines = []
lines.push(`# QQ 农场日报 ${date}`)
lines.push('')
lines.push(`生成时间：${new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Shanghai' })}`)
lines.push('')
lines.push('## 每账号汇总')
lines.push('')
lines.push('| 账号 | QQ | 偷菜(块) | 收获(块) | 种植(块) | 帮务农 | 施肥 | 出售次数 | 任务 | 金币(起 → 止) | 金币变化 | 金豆豆(当前) | 金豆豆变化 | 本次登录金币 | 经验变化 | 等级 | 采样 |')
lines.push('|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|')
for (const r of rows) {
  lines.push(`| ${r.name} | ${r.qq} | ${r.steal} | ${r.harvest} | ${r.plant} | ${r.helpFarming} | ${r.fertilize} | ${r.sell} | ${r.taskClaim} | ${fmt(r.goldStart)} → ${fmt(r.goldEnd)} | ${signed(r.goldDelta)} | ${fmt(r.goldBean)} | ${signed(r.goldBeanDelta)} | ${signed(r.sessionGold)} | ${signed(r.expDelta)} | ${r.level} | ${r.samples} |`)
}
lines.push(`| **合计** |  | **${totals.steal}** | **${totals.harvest}** | **${totals.plant}** | **${totals.helpFarming}** | **${totals.fertilize}** | **${totals.sell}** | **${totals.taskClaim}** |  | **${signed(totals.gold)}** |  | **${signed(totals.bean)}** |  | **${signed(totals.exp)}** |  |  |`)
lines.push('')
lines.push('## 说明')
lines.push('')
lines.push('- 数据来源：每 5 分钟采样一次账号状态（金币/金豆豆/经验/等级），操作次数来自 `core/data/stats/<账号>.json`。')
lines.push('- “偷菜(块)”是偷到的土地块数，不是果实数量或金币。')
lines.push('- “金币变化”= 当天最后一次在线采样 − 第一次在线采样，**已包含买种子/化肥等支出**，是净变化；当天刚开始采样时可能为 0。')
lines.push('- “金豆豆变化”= 当天最后一次在线采样 − 第一次在线采样；升级蓝晶土地、买高级商品会消耗金豆豆，所以净变化可能为负。')
lines.push('- “本次登录金币”= 当前账号自本次登录以来的金币增量（面板里的“本次 +X”），重启账号会重新计算。')
lines.push('- 账号离线期间的采样不计入首末值；当天没在线过则显示 0。')
lines.push('- 采样从本报表功能启用后开始，启用当天数据可能不完整。')
lines.push('')

const md = lines.join('\n')
fs.mkdirSync(dataDir, { recursive: true })
const mdFile = path.join(dataDir, `${date}.md`)
fs.writeFileSync(mdFile, md, 'utf8')

console.log(md)
console.log(`\n已写入：${mdFile}`)
