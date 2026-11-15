// 每日数据采集：每 5 分钟把各账号的金币/经验/操作数写入 core/data/daily/<日期>.jsonl
const fs = require('node:fs')
const path = require('node:path')

const root = __dirname
const token = fs.readFileSync(path.join(root, 'service-token.txt'), 'utf8').trim()
const base = 'http://127.0.0.1:3007'
const headers = { 'x-admin-token': token }
const intervalMs = 5 * 60 * 1000
const dataDir = path.join(root, 'core', 'data', 'daily')
fs.mkdirSync(dataDir, { recursive: true })

function localDate(d = new Date()) {
  return d.toLocaleDateString('sv-SE', { timeZone: 'Asia/Shanghai' })
}

async function tick() {
  let accounts = []
  try {
    const r = await fetch(`${base}/api/accounts`, { headers })
    const j = await r.json()
    accounts = j?.data?.accounts || []
  } catch (e) {
    console.log(new Date().toISOString(), 'accounts error', e.message)
    return
  }

  const date = localDate()
  const file = path.join(dataDir, `${date}.jsonl`)
  let okCount = 0
  for (const a of accounts) {
    try {
      const r = await fetch(`${base}/api/status`, { headers: { ...headers, 'x-account-id': String(a.id) } })
      const j = await r.json()
      if (!j?.ok) continue
      const d = j.data || {}
      const row = {
        ts: Date.now(),
        accountId: String(a.id),
        name: a.name,
        qq: a.qq,
        connected: !!d.connection?.connected,
        gold: Number(d.status?.gold) || 0,
        goldBean: Number(d.status?.goldBean) || 0,
        exp: Number(d.status?.exp) || 0,
        level: Number(d.status?.level) || 0,
        sessionGoldGained: Number(d.sessionGoldGained) || 0,
        operations: d.operations || {},
      }
      const already = fs.existsSync(file) && fs.readFileSync(file, 'utf8').includes(`"ts":${row.ts},"accountId":"${row.accountId}"`)
      if (!already) fs.appendFileSync(file, `${JSON.stringify(row)}\n`)
      okCount++
    } catch (e) {
      // 单个账号采样失败不影响其他账号
    }
  }
  console.log(new Date().toISOString(), `sampled ${okCount}/${accounts.length} -> ${date}.jsonl`)
}

tick()
setInterval(tick, intervalMs)
