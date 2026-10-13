<p align="center">
  <img src="logo.png" alt="Claude Usage Tracker" width="200"/>
</p>

<h1 align="center">Claude Usage Tracker</h1>

<p align="center">
  A native macOS menu bar app that shows your personal AI spend at MasOrange — the same data as
  <a href="https://ai-platform.cloud.masorange.es">AI Platform</a>, one click away.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013.0+-blue" alt="Platform"/>
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift"/>
  <img src="https://img.shields.io/badge/license-Personal%20Use%20Only-green" alt="License"/>
  <img src="https://img.shields.io/badge/author-Sergio%20Ba%C3%B1uls-blue" alt="Author"/>
</p>

---

## ✨ What it shows

- **💰 Month-to-date spend** in the menu bar (configurable: spend, spend + %, % of budget, or icon only).
- **🥉 Your tier and monthly budget** (Iron / Bronze / Silver / Gold) with a progress bar, available amount,
  days until the budget renews and the month-end forecast.
- **📊 Tokens per day** for the current month (hover a bar to see tokens and spend for that day).
- **🤖 Most used models** with their cost. When a model is on a **campaign** (free or discounted), the list
  price is shown struck through with the discount, e.g. `0,00 US$  ~~159,94 US$~~  −100 %`.
- **🧠 Models tab**: every model your LiteLLM key can call (Claude, GPT, Gemini, Llama, Mistral, DeepSeek…),
  grouped by vendor in collapsible sections with their logos, newest version first, with context window and the
  **price the proxy charges today per 1M tokens** (input, output, cache). Campaigns are read from the proxy's own
  pricing, so they are current: the list price is struck through and the model is tagged `Gratis` / `−50 %`.
  Expand a row to copy the exact model id.
- Spanish / English, USD / EUR, auto-refresh (5–60 min), open at login, update notifications.

Only the **LiteLLM** provider is shown — it is the one that consumes your budget. Usage covered by a
Claude Enterprise seat is not billed and is not included.

## 📦 Install

```bash
brew tap masorange/claudeusagetracker
brew install --cask claudeusagetracker
```

Upgrade with `brew upgrade --cask claudeusagetracker`. See [INSTALL.md](INSTALL.md) for manual installation.

## 🔐 First launch

1. Click the **💰** icon in the menu bar (it shows `💰 ⚠︎` until you sign in).
2. Press **Sign in** and log in with your **corporate account (SSO)** in the window that opens.
3. The window closes by itself and your data appears.

You won't be asked again while your corporate Google session is valid: when the AI Platform session cookie
expires the app renews it silently in the background.

## 🔎 Where the data comes from

The app calls the read-only personal endpoints of AI Platform (`/api/v1/me`, `/me/month-glance`,
`/spend/daily`, `/spend/by-model`) with your own SSO session — exactly what the web does. Figures therefore
match the web, including its **~1 hour delay** (the footer shows when the data was last updated).

- **Privacy:** the session lives only in the app's WebKit storage on your Mac. Nothing is sent anywhere else.
- **No API key needed.** LiteLLM keys can no longer read spend, so 1.x stopped working; 2.0 replaces that
  integration (and the Looker / local log estimation) with AI Platform.

## 🔑 LiteLLM key (Models tab only)

Listing the models needs your personal LiteLLM key (the one Claude Code uses as `ANTHROPIC_AUTH_TOKEN`).
The app picks it up automatically from your Claude Code `settings.json` or a literal `export` in your shell profile;
otherwise paste it once in the tab. It is stored in the macOS Keychain and only sent to `llm.tools.cloud.masorange.es`.
After an app update macOS may ask once to let the new version read it — choose **Always Allow**.
Prices come from the proxy's public cost map: its per-deployment entries carry the price actually charged
(`claude-X` → campaign deployment, `claude-X-vertex` → list-price deployment), the public entries the list price.

## ⚙️ Settings

Click ⚙︎ in the popover: menu bar text, language, currency, refresh interval, open at login and sign out.

## 🛠️ Development

```bash
swift test                   # unit tests (UsageCore: API client, models, aggregation)
./build.sh                   # builds ClaudeUsageTracker.app (universal arm64 + x86_64)
open ClaudeUsageTracker.app
./create_release.sh 2.0.0    # app + DMG + SHA-256 in release/
```

```
Package.swift
Sources/
  UsageCore/            # UI-free: APIClient, models, MonthReport aggregation, cache
  ClaudeUsageTracker/   # AppKit status item, SwiftUI views, WebKit SSO session
Tests/UsageCoreTests/   # XCTest with anonymized real API responses
```

Release process: [PUBLISHING.md](PUBLISHING.md). Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).

## 🧰 Troubleshooting

- **`💰 ⚠︎` in the menu bar** — your corporate session expired; open the popover and press *Sign in*.
- **"AI Platform changed its data format"** — the web API changed; update the app
  (`brew upgrade --cask claudeusagetracker`).
- **Numbers differ from the web** — the data is refreshed roughly every hour on the server; press ⟳ and
  compare the "Data updated" time in the footer.
- **Logs:** `log show --predicate 'subsystem == "com.claudeusage.tracker"' --last 1h`

## 📄 License

Personal Use License (Non-Commercial). See [LICENSE](LICENSE).
Provider logos: [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT), see `Resources/ProviderIcons/LICENSE`.
