# 📥 Installation Guide - Claude Usage Tracker

This guide will walk you through installing Claude Usage Tracker on your Mac.

---

## ⚡ Quick Install with Homebrew (Easiest)

**This is the recommended installation method** - one command, and Homebrew handles macOS security settings.

### Prerequisites

You need Homebrew installed. If you don't have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Install or update (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/masorange/homebrew-claudeusagetracker/main/install.sh | bash
```

Run it again any time to update. It also moves installations made from the old taps (`masmovil/…`,
`SergioBanuls/…`) to `masorange/claudeusagetracker` and replaces a manual DMG install, keeping your settings.

### After Installation

1. The app is installed to `/Applications` and opens automatically
2. Look for the **💰** icon in your menu bar (top-right corner)
3. Click it, press **Sign in** and log in with your corporate account (SSO). The window closes by itself.
4. No need to run `xattr` or deal with security warnings!

### Plain Homebrew commands

```bash
# Install
brew install --cask masorange/claudeusagetracker/claudeusagetracker
open -a ClaudeUsageTracker

# Update
brew update && brew upgrade --cask masorange/claudeusagetracker/claudeusagetracker

# Uninstall (add --zap to also remove settings, cache and sign-in data)
brew uninstall --cask claudeusagetracker
```

If Homebrew says `Cask claudeusagetracker exists in multiple taps`, you still have an old tap: run the one command
above (or `brew untap masmovil/claudeusagetracker`).

**🎉 That's it! Skip to the [Usage section](#-next-steps)**

---

## 📦 Manual Install (Alternative Method)

If you prefer not to use Homebrew, you can install manually:

### Step 1: Download the App

1. Go to the [**Releases page**](https://github.com/masorange/ClaudeUsageTracker/releases/latest)
2. Download the latest `ClaudeUsageTracker-vX.X.X.dmg` file
3. The file will download to your `Downloads` folder

### Step 2: Open the DMG

1. Find the downloaded `.dmg` file in your `Downloads` folder
2. Double-click the `.dmg` file to open it
3. A new window will appear showing the app and an Applications folder shortcut

### Step 3: Install to Applications

1. In the DMG window, **drag** `ClaudeUsageTracker.app` to the `Applications` folder shortcut
2. Wait for the copy to complete
3. Close the DMG window
4. You can eject the DMG from Finder sidebar (click the eject button next to "ClaudeUsageTracker")

### Step 4: Remove macOS Security Block

**IMPORTANT:** Since this app is not signed with an Apple Developer certificate, macOS will block it by default.

1. Open **Terminal** (Applications > Utilities > Terminal)
2. Run this command to remove the security block:
   ```bash
   xattr -cr /Applications/ClaudeUsageTracker.app
   ```
3. Press Enter

### Step 5: Open the App

1. Go to your **Applications** folder (⌘ + Shift + A)
2. Find `ClaudeUsageTracker.app`
3. **Right-click** (or Control-click) on the app
4. Select **"Open"** from the menu
5. If you see a security warning, click **"Open"** again
   - This is normal for unsigned apps
   - You only need to do this the first time

### Step 6: Find the Menu Bar Icon

1. Look at the top-right corner of your screen (menu bar)
2. You should see a **💰** icon
3. Click the icon to open the app panel

**🎉 That's it! You're all set!**

### Update (Manual Method)

1. Download the latest release
2. Quit the current app (click 💰 → Quit)
3. Replace the old app in Applications with the new one
4. Open the new version

### Uninstall (Manual Method)

```bash
# Quit the app
killall ClaudeUsageTracker 2>/dev/null || true

# Delete the app
rm -rf /Applications/ClaudeUsageTracker.app

# (Optional) Remove preferences
defaults delete com.claudeusage.tracker
```

---

## 🔧 Alternative: Build from Source

If you prefer to build the app yourself from source code:

### Prerequisites

You'll need:
- **macOS 13.0** (Ventura) or later
- **Xcode 15 or later** (the universal build uses `swift build --arch arm64 --arch x86_64`, which needs full Xcode)

### Step 1: Install Xcode Command Line Tools

Open **Terminal** and run:

```bash
xcode-select --install
```

Click **"Install"** when prompted.

### Step 2: Download the Source Code

```bash
# Clone the repository
git clone https://github.com/masorange/ClaudeUsageTracker.git

# Navigate to the folder
cd ClaudeUsageTracker
```

### Step 3: Build the App

```bash
# Make the build script executable
chmod +x build.sh

# Run the build
./build.sh
```

Wait for the build to complete. You should see:
```
✅ App compilada en: ClaudeUsageTracker.app
```

### Step 4: Run the App

```bash
# Open the app
open ClaudeUsageTracker.app
```

### Step 5: (Optional) Install to Applications

```bash
# Copy to Applications folder
cp -r ClaudeUsageTracker.app /Applications/

# Open from Applications
open /Applications/ClaudeUsageTracker.app
```

---

## ✅ Verifying the Installation

### Check if the App is Running

1. Look for the **💰** icon in your menu bar (top-right)
2. If you don't see it:
   - Open **Activity Monitor** (Applications > Utilities > Activity Monitor)
   - Search for "ClaudeUsageTracker"
   - If it's running, you should see it in the list

### Check if Data is Loading

1. Click the **💰** icon in the menu bar
2. If you see **Sign in**, log in with your corporate account (SSO)
3. You should see your month-to-date spend, tier, budget, tokens per day and most used models
4. The data comes from https://ai-platform.cloud.masorange.es and can lag ~1 hour behind real usage

---

## 🐛 Troubleshooting

### "App is damaged and can't be opened"

This is a macOS security feature called Gatekeeper.

**IMPORTANT:** You must run the `xattr` command AFTER copying the app to Applications, not while it's still in the DMG (the DMG is read-only).

**Solution:**
1. First, drag the app to Applications folder
2. Open **Terminal**
3. Run this command:
   ```bash
   xattr -cr /Applications/ClaudeUsageTracker.app
   ```
4. Now right-click the app in Applications and select "Open"

### App doesn't appear in menu bar

1. **Quit the app completely:**
   - Open **Activity Monitor**
   - Find "ClaudeUsageTracker"
   - Click "✖️" to quit

2. **Reopen the app:**
   - Go to Applications
   - Open ClaudeUsageTracker.app

3. **Check System Preferences:**
   - Go to **System Settings** > **Privacy & Security**
   - Make sure ClaudeUsageTracker has necessary permissions

### Menu bar shows 💰 ⚠︎

Your corporate session expired. Click the icon and press **Sign in**. If the sign-in window keeps
reappearing, use ⚙︎ → **Sign out** and sign in again.

### Numbers differ from the web

Both read the same AI Platform data, refreshed about every hour. Press ⟳ in the popover and compare the
"Data updated" time in the footer with the web.

### Build fails with error

**Error: `xcode-select: error: tool 'xcodebuild' requires Xcode`**

Install Xcode Command Line Tools:
```bash
xcode-select --install
```

**Error: `No such file or directory`**

Make sure you're in the correct folder:
```bash
cd ClaudeUsageTracker
ls -la  # Should show build.sh
```

---

## 🔄 Updating the App

### From Releases (Recommended)

1. Download the latest release
2. Quit the current app:
   - Click **💰** in menu bar
   - Click the **✖️** button
3. Replace the old app in Applications with the new one
4. Open the new version

### From Source

```bash
cd ClaudeUsageTracker
git pull origin main
./build.sh
open ClaudeUsageTracker.app
```

---

## 🗑️ Uninstalling

To completely remove the app:

1. **Quit the app:**
   - Click **💰** in menu bar
   - Click **✖️**

2. **Delete the app:**
   ```bash
   rm -rf /Applications/ClaudeUsageTracker.app
   ```

3. **Remove preferences (optional):**
   ```bash
   defaults delete com.claudeusage.tracker
   ```

**Note:** This does NOT delete your Claude Code data or conversation history. It only removes the tracker app.

---

## 📞 Getting Help

If you're still having issues:

1. Check the [**Troubleshooting section**](README.md#-troubleshooting) in the README
2. Search [**existing issues**](https://github.com/masorange/ClaudeUsageTracker/issues) on GitHub
3. [**Open a new issue**](https://github.com/masorange/ClaudeUsageTracker/issues/new) with:
   - Your macOS version (`sw_vers`)
   - The problem you're experiencing
   - Steps you've already tried
   - Any error messages from Console.app

---

## ✨ Next Steps

Now that you have the app installed:

1. **Explore the interface:**
   - Switch between **By Month** and **By Project** tabs
   - Check detailed token breakdowns

2. **Configure pricing (if needed):**
   - Click the **⚙️ gear icon**
   - Adjust pricing to match your Claude API plan

3. **Switch language:**
   - Click the **🇺🇸** flag to toggle between English and Spanish

Enjoy tracking your Claude Code usage! 🎉
