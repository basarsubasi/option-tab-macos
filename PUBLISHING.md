# Developer Guide: Publishing OptionTab

This document explains how to build OptionTab into a distributable `.dmg` and how to host it via a custom Homebrew tap. Since we are skipping paid Apple Developer signing, users will need to manually remove the quarantine flag using `xattr -cr` after downloading. 

---

## 1. Creating the DMG

We use `create-dmg` to bundle the `.app` into a professional macOS installer with an Applications folder symlink.

### Prerequisites
Make sure you have `create-dmg` installed:
```bash
brew install create-dmg
```

### Build & Package Script (`create_dmg.sh`)
Create a file named `create_dmg.sh` in the project root, make it executable (`chmod +x create_dmg.sh`), and run it:

```bash
#!/bin/bash
set -e

APP_NAME="OptionTab"
VERSION="1.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "🔨 Building Release version..."
swift build -c release

echo "📦 Assembling App bundle..."
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mkdir -p "${APP_NAME}.app/Contents/Resources"

cp .build/release/${APP_NAME} "${APP_NAME}.app/Contents/MacOS/"
cp Sources/${APP_NAME}/Resources/Info.plist "${APP_NAME}.app/Contents/"

echo "🔏 Ad-hoc Code signing..."
codesign --force --deep --sign - "${APP_NAME}.app"

echo "💿 Creating DMG..."
rm -f "$DMG_NAME"
create-dmg \
  --volname "${APP_NAME} Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 150 190 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 450 190 \
  "$DMG_NAME" \
  "${APP_NAME}.app"

echo "✅ DMG created: $DMG_NAME"
```

## 2. Hosting the Release

1. Push your code to GitHub.
2. Go to **Releases** → **Draft a new release**.
3. Create a tag (e.g., `v1.0.0`).
4. Upload the generated `OptionTab-1.0.dmg` file as an asset.
5. In the Release notes, **you MUST tell the users:**
   > **Note:** Because this app is not signed with a paid Apple Developer account, macOS will flag it as damaged. After dragging OptionTab to your Applications folder, open your Terminal and run:  
   > `xattr -cr /Applications/OptionTab.app`

6. Publish the release and copy the direct URL to the `.dmg` file.
7. Get the SHA-256 hash of your DMG:
   ```bash
   shasum -a 256 OptionTab-1.0.dmg
   ```

---

## 3. Creating a Homebrew Tap

A "Tap" is just a GitHub repository named `homebrew-<something>`. It allows users to run `brew install basarsubasi/tap/optiontab`.

### Step 1: Create the Tap Repository
1. Create a new public GitHub repository named `homebrew-tap` (e.g., `basarsubasi/homebrew-tap`).
2. Inside that repository, create a folder named `Casks`.
3. Inside the `Casks` folder, create a file named `optiontab.rb`.

### Step 2: The Cask Definition (`optiontab.rb`)
This file defines how Homebrew downloads the app, installs it, and most importantly, how it properly cleans up on uninstall (removing permissions, login items, and saved settings).

```ruby
cask "optiontab" do
  version "1.0.0"
  
  # Replace this with the output of `shasum -a 256 OptionTab-1.0.dmg`
  sha256 "YOUR_SHA256_HASH_HERE"

  # Replace this with the actual URL to your GitHub release DMG
  url "https://github.com/basarsubasi/alt-tab-macos/releases/download/v#{version}/OptionTab-#{version}.dmg"
  
  name "OptionTab"
  desc "A highly customizable and premium Alt-Tab replacement"
  homepage "https://github.com/basarsubasi/alt-tab-macos"

  depends_on macos: ">= :ventura"

  app "OptionTab.app"

  # This caveat is printed to the user's terminal immediately after installation
  caveats do
    <<~EOS
      Because OptionTab is not signed with a paid Apple Developer certificate, macOS will quarantine it.
      To allow the app to run, you MUST run this command in your terminal:
      
        xattr -cr /Applications/OptionTab.app
        
      After running that, you can open OptionTab normally.
    EOS
  end

  # ==========================================
  # UNINSTALLATION & CLEANUP LOGIC
  # ==========================================
  
  # 1. Quit the app and remove it from macOS Login Items
  uninstall quit:       "com.optiontab.app",
            login_item: "OptionTab"

  # 2. Reset Accessibility Permissions via terminal
  uninstall postflight do
    system_command "tccutil",
                   args: ["reset", "Accessibility", "com.optiontab.app"],
                   sudo: false
  end

  # 3. Trash UserDefaults and settings
  zap trash: [
    "~/Library/Preferences/com.optiontab.app.plist",
    "~/Library/Application Scripts/com.optiontab.app"
  ]
end
```

### Step 3: Installing via your Tap

Now, any user can install your app directly from their terminal using:

```bash
brew tap basarsubasi/tap
brew install --cask optiontab
```

And when they decide to uninstall it:

```bash
brew uninstall --cask optiontab
```

This uninstall command will perfectly execute your `quit`, `postflight` permission wipe, and `zap` settings cleanup automatically.
