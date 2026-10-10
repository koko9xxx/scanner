# Port Scanner (iOS)

A simple iOS app that scans a range of IP addresses and ports and lists the open ones. Built entirely on GitHub Actions — no Mac required.

## Project layout

- `Sources/PortScannerApp.swift` — the whole app (SwiftUI)
- `project.yml` — project description consumed by [XcodeGen](https://github.com/xcpretty/xcodegen)
- `.github/workflows/build.yml` — CI workflow that generates the Xcode project, builds the app, and uploads an unsigned `.ipa` as an artifact

## Step 1 — Build the IPA on GitHub Actions

1. Create a new repository on GitHub (make it **public** — public repos get free macOS runner minutes; private repos consume paid minutes at a 10x rate).
2. Upload all the files from this folder to the repo (via the web "Add file → Upload files", or with git).
3. Go to the **Actions** tab, click **Build iOS IPA** on the left, then **Run workflow**.
4. Wait a few minutes (installing XcodeGen + compiling takes ~5–10 min).
5. Open the finished run and download the **PortScanner-ipa** artifact. Unzip it — you get `PortScanner.ipa`. Send it to your iPad (AirDrop, email, Google Drive, etc.).

## Step 2 — Install on your iPad (sideloading)

Apple does not allow installing apps outside the App Store without signing them. The free way is **AltStore** (or **SideStore**) with a free Apple ID. The app expires after 7 days, but AltStore refreshes it automatically in the background while your iPad and PC are on the same Wi-Fi.

### One-time setup (needs your Windows PC once)

1. On your Windows PC install **iTunes** and **iCloud** from Apple's website (apple.com/itunes / apple.com/icloud) — **not** the Microsoft Store versions.
2. Download **AltServer** from [altstore.io](https://altstore.io) and install it.
3. Connect your iPad by USB, unlock it, trust the computer.
4. Click the AltServer tray icon → *Install AltStore* → your iPad. Enter a **free Apple ID** when asked.

### Installing the IPA

1. On the iPad, open **AltStore** (you must open it once so it can finish setup).
2. Put `PortScanner.ipa` somewhere the Files app can reach (iCloud Drive, etc.).
3. In AltStore go to **My Apps**, tap **+** (top left), and pick the `PortScanner.ipa` file.
4. Wait for it to sign and install, then launch it from the home screen.
5. If iOS says "untrusted developer": *Settings → General → VPN & Device Management* → trust your Apple ID.

> Jailbroken or TrollStore-compatible iPad? Then just install the IPA directly — no AltStore needed.

## Step 3 — Use the app

1. Connect the iPad to the Wi-Fi of the network you want to scan.
2. The app shows your own IP at the top (e.g. `192.168.1.7`) to make choosing a range easy.
3. Enter a start/end IP (e.g. `192.168.1.1` → `192.168.1.50`) and a port range (e.g. `1` → `1000`).
4. Tap **Start Scan**. Open ports appear in the list as they are found.
5. The first scan triggers the iOS *Local Network* permission prompt — tap **Allow**.

## Notes

- The scan uses TCP connect checks with a 1-second timeout and 64 parallel connections.
- Total probes per scan are capped at 100,000. Scanning wide ranges on slow networks takes a while.
- Only scan networks you own or have permission to test — scanning other people's networks may be illegal where you live.
- With a **paid** Apple Developer account ($99/yr) you can skip AltStore: add your signing certificate/profile as repo secrets and sign the IPA in the workflow, or upload to TestFlight directly.
