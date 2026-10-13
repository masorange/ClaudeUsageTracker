# 🚀 Publishing Guide - Claude Usage Tracker

This guide walks you through publishing a new release of Claude Usage Tracker to GitHub.

---

## 📋 Pre-Release Checklist

Before creating a release, make sure you've:

- [ ] Tested the app thoroughly on your Mac
- [ ] Verified all features work correctly
- [ ] `swift test` passes
- [ ] Committed all changes to git
- [ ] Updated CHANGELOG (if you have one)

### ⚠️ Important: Version Number

`create_release.sh X.Y.Z` passes the version to `build.sh` (`VERSION=X.Y.Z`), which writes it to
`CFBundleShortVersionString`. It **must match** the release tag for auto-update to work correctly:

```bash
./create_release.sh 2.0.0   # → tag v2.0.0
```

This version is used by the auto-update system to compare with GitHub releases.

---

## 🏷️ Creating a Release

### Step 1: Create the Release Build

Run the release script with a version number:

```bash
./create_release.sh 1.0.0
```

Replace `1.0.0` with your desired version number (e.g., `1.1.0`, `2.0.0`, etc.)

This will:
- Clean previous builds
- Build the app
- Create a versioned ZIP file
- Generate SHA-256 checksum
- Create a release notes template

**Output:**
```
release/
├── ClaudeUsageTracker.app
├── ClaudeUsageTracker-v1.0.0.zip
├── ClaudeUsageTracker-v1.0.0.zip.sha256
└── RELEASE_NOTES.md
```

### Step 2: Test the Release Build

Before publishing, test the packaged app:

```bash
# Open the app
open release/ClaudeUsageTracker.app

# Verify checksum
cd release && shasum -a 256 -c ClaudeUsageTracker-v1.0.0.zip.sha256
```

Make sure:
- App opens correctly
- Menu bar icon appears
- Data loads properly
- All features work
- No crashes or errors

### Step 3: Update Release Notes

Edit `release/RELEASE_NOTES.md` and fill in:

- **What's New**: New features and improvements
- **Bug Fixes**: Issues that were resolved
- **Known Issues**: Any current limitations

Example:
```markdown
## 🎉 What's New

- Accurate turn grouping for tool calls
- Configurable pricing for different Claude models
- Support for Long Context pricing (>200K tokens)
- Multi-language support (English/Spanish)

## 🐛 Bug Fixes

- Fixed double-counting of tool calls
- Corrected cache pricing calculations
- Improved timestamp parsing for turn detection

## ⚠️ Known Issues

- First launch may show $0.00 for a few seconds
```

### Step 4: Push to GitHub

If you haven't already:

```bash
# Initialize git (if needed)
git init
git add .
git commit -m "Initial release v1.0.0"

# Add remote (replace with your repo URL)
git remote add origin https://github.com/masorange/ClaudeUsageTracker.git

# Push to GitHub
git branch -M main
git push -u origin main
```

### Step 5: Create GitHub Release

1. **Go to your repository** on GitHub
2. **Click "Releases"** in the right sidebar
3. **Click "Create a new release"**

4. **Fill in the details:**
   - **Tag version**: `v1.0.0` (must start with `v`)
   - **Release title**: `Claude Usage Tracker v1.0.0`
   - **Description**: Copy from `release/RELEASE_NOTES.md`

5. **Upload the ZIP file:**
   - Drag and drop `ClaudeUsageTracker-v1.0.0.zip`
   - Optionally upload `ClaudeUsageTracker-v1.0.0.zip.sha256`

6. **Check options:**
   - ✅ Set as the latest release (if it's the newest)
   - ⬜ Set as a pre-release (only if it's a beta/RC)

7. **Click "Publish release"**

---

## 📝 After Publishing

### Update README Links

Make sure the README has the correct GitHub repository URL:

1. Search for `masorange` in README.md
2. Replace with your actual GitHub username
3. Commit and push:
   ```bash
   git add README.md
   git commit -m "Update repository links"
   git push
   ```

### Announce the Release

Consider announcing on:
- GitHub Discussions
- Twitter/X
- Reddit (r/ClaudeAI or similar)
- Your blog/website

### Monitor Issues

Keep an eye on:
- GitHub Issues for bug reports
- Release download stats
- User feedback

---

## 🔄 Creating Updates

When releasing an update:

### 1. Update Version Number

**In `create_release.sh`:**
```bash
./create_release.sh 1.1.0  # Increment version
```

**Version numbering guide:**
- **Major** (1.x.x): Breaking changes, major new features
- **Minor** (x.1.x): New features, backward compatible
- **Patch** (x.x.1): Bug fixes only

### 2. Create Release Notes

Document what changed since the last version:

```markdown
## 🎉 What's New in v1.1.0

- Added export to CSV feature
- Improved performance for large projects
- New dark mode support

## 🐛 Bug Fixes

- Fixed crash when no projects exist
- Corrected total calculation rounding

## ⬆️ Upgrading from v1.0.0

Simply download and replace the app in your Applications folder.
```

### 3. Tag and Release

```bash
# Commit your changes
git add .
git commit -m "Release v1.1.0"

# Create tag
git tag -a v1.1.0 -m "Version 1.1.0"

# Push
git push origin main
git push origin v1.1.0

# Create GitHub release (follow Step 5 above)
```

---

## 🛡️ Security Best Practices

### Code Signing (Optional but Recommended)

For better macOS integration:

1. Get an Apple Developer certificate
2. Sign the app:
   ```bash
   codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name" ClaudeUsageTracker.app
   ```

3. Notarize with Apple:
   ```bash
   xcrun notarytool submit ClaudeUsageTracker.zip --apple-id your@email.com --wait
   ```

**Benefits:**
- No Gatekeeper warnings
- Better user trust
- Required for Mac App Store

### Checksum Verification

Always include SHA-256 checksums:

```bash
# Users can verify with:
shasum -a 256 -c ClaudeUsageTracker-v1.0.0.zip.sha256
```

This ensures the download wasn't tampered with.

---

## 📊 Release Metrics

Track your release success:

- **Download count**: Check GitHub release stats
- **Issues reported**: Monitor GitHub Issues
- **Stars/Forks**: Track repository growth
- **User feedback**: Read comments and discussions

---

## 🐞 Hotfix Releases

For critical bugs:

1. Create fix in a new branch:
   ```bash
   git checkout -b hotfix/1.0.1
   ```

2. Make the fix and commit:
   ```bash
   git commit -m "Fix critical bug in cost calculation"
   ```

3. Merge and release:
   ```bash
   git checkout main
   git merge hotfix/1.0.1
   ./create_release.sh 1.0.1
   git tag -a v1.0.1 -m "Hotfix 1.0.1"
   git push origin main --tags
   ```

4. Create GitHub release marked as a hotfix

---

## 📞 Getting Help

If you need help with publishing:

1. Check [GitHub Docs on Releases](https://docs.github.com/en/repositories/releasing-projects-on-github)
2. Ask in [GitHub Discussions](https://github.com/masorange/ClaudeUsageTracker/discussions)
3. Open an issue for build/release problems

---

## ✅ Final Checklist

Before clicking "Publish release":

- [ ] Version number is correct and incremented
- [ ] Release notes are complete and accurate
- [ ] ZIP file is attached
- [ ] Checksum file is attached
- [ ] Tag follows format `vX.Y.Z`
- [ ] App has been tested
- [ ] No sensitive data in release
- [ ] README links are updated
- [ ] License is included

**Ready? Click "Publish release"!** 🎉
