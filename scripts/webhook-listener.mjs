#!/usr/bin/env node
/**
 * GitHub push → deploy staging (develop) or production (stable-master-01)
 */
import crypto from "node:crypto"
import { readFileSync, existsSync } from "node:fs"
import { spawn } from "node:child_process"
import http from "node:http"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.join(__dirname, "..")

function loadDotEnv() {
  const envPath = process.env.BUILD_SERVER_ENV ?? path.join(root, ".env")
  if (!existsSync(envPath)) return envPath
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue
    const eq = trimmed.indexOf("=")
    if (eq === -1) continue
    const key = trimmed.slice(0, eq).trim()
    let val = trimmed.slice(eq + 1).trim()
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1)
    }
    if (process.env[key] == null) process.env[key] = val
  }
  return envPath
}

const envPath = loadDotEnv()

const secret = process.env.WEBHOOK_SECRET?.trim()
const port = Number(process.env.WEBHOOK_PORT ?? 9876)
const webhookPath = process.env.WEBHOOK_PATH?.trim() || "/github"

const stagingBranch = process.env.STAGING_BRANCH?.trim() || "develop"
const productionBranch = process.env.PRODUCTION_BRANCH?.trim() || "stable-master-01"

/** @type {Map<string, string>} */
const refToTarget = new Map([
  [`refs/heads/${stagingBranch}`, "staging"],
  [`refs/heads/${productionBranch}`, "production"],
])

let deploying = false
let currentTarget = null

function verifySignature(body, sigHeader) {
  if (!secret) {
    console.warn("[webhook] WEBHOOK_SECRET unset — not recommended for production")
    return true
  }
  if (!sigHeader?.startsWith("sha256=")) return false
  const digest = crypto.createHmac("sha256", secret).update(body).digest("hex")
  const expected = `sha256=${digest}`
  try {
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(sigHeader))
  } catch {
    return false
  }
}

function runDeploy(target) {
  if (deploying) {
    console.log(`[webhook] deploy already running (${currentTarget}) — skip ${target}`)
    return
  }
  deploying = true
  currentTarget = target
  const script = path.join(root, "scripts", "deploy.sh")
  const child = spawn("bash", [script, target], {
    cwd: root,
    stdio: "inherit",
    env: { ...process.env, BUILD_SERVER_ENV: envPath },
  })
  child.on("close", (code) => {
    deploying = false
    currentTarget = null
    console.log(`[webhook] ${target} deploy exited ${code}`)
  })
}

const server = http.createServer((req, res) => {
  if (req.method !== "POST" || req.url !== webhookPath) {
    res.writeHead(404)
    res.end("not found")
    return
  }

  const chunks = []
  req.on("data", (c) => chunks.push(c))
  req.on("end", () => {
    const body = Buffer.concat(chunks)
    const sig = req.headers["x-hub-signature-256"]
    if (!verifySignature(body, typeof sig === "string" ? sig : undefined)) {
      res.writeHead(401)
      res.end("invalid signature")
      return
    }

    let payload
    try {
      payload = JSON.parse(body.toString("utf8"))
    } catch {
      res.writeHead(400)
      res.end("bad json")
      return
    }

    if (payload.zen) {
      res.writeHead(200)
      res.end("pong")
      return
    }

    const ref = payload.ref ?? ""
    const target = refToTarget.get(ref)
    if (!target) {
      res.writeHead(200)
      res.end(`ignored ${ref}`)
      return
    }

    console.log(`[webhook] ${ref} → deploy ${target}`)
    runDeploy(target)
    res.writeHead(202)
    res.end(`deploy ${target} started`)
  })
})

server.listen(port, () => {
  console.log(`[webhook] ${webhookPath}:${port}`)
  console.log(`  ${stagingBranch} → staging`)
  console.log(`  ${productionBranch} → production`)
})
