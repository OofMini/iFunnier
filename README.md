# iFunnier Remastered

![Banner](https://via.placeholder.com/1200x300?text=iFunnier+Remastered)

**iFunnier Remastered** is a comprehensive, open-source tweak for the iFunny iOS app. It unlocks client-side Premium features, removes all advertisements, enables native media downloading without watermarks, and provides a cleaner, user-friendly interface.

> [!NOTE]
> This tweak is optimized for **iFunny v10.31.11+**. Older versions may not be fully supported due to significant changes in the app's internal Swift structure.

---

## Features

### 🔓 Premium Experience
- **Ads Removed:** Completely blocks banner ads, interstitial video ads, and native feed ads by intercepting ad network SDKs (AppLovin, AdMob, IronSource) at the source.
- **Premium Status Spoofing:** Forces the app to recognize the user as a Premium subscriber, unlocking client-side perks.
- **Premium Features Unlocked:** Enables specific feature flags such as custom app icons, profile customization options, and exclusive UI themes.

### 💾 Enhanced Media Saving
- **Native Video Downloading:** Unlocks the built-in "Save Video" button for all content, bypassing the "Premium only" restriction.
- **No Watermarks:** Automatically removes the iFunny watermark from saved images and videos.
- **Share Sheet Downloader:** Adds a custom "Download Video" action to the iOS Share Sheet as a reliable backup method for saving content.

### 🧹 UI & Quality of Life
- **Clean Interface:** Removes "Get Premium" upsell banners, subscription pop-ups, and other clutter.
- **Custom Settings Menu:** Includes a dedicated **iFunnier Control** menu (accessible via the gear icon in the sidebar) to toggle specific features:
    - Block Ads
    - No Watermark
    - Block Upsells

---

## Installation

### Method 1: Building with GitHub Actions (Recommended)
You can build the IPA directly from this repository without needing a computer or a Mac.

> [!IMPORTANT]
> **Prerequisites:** You must have a **Decrypted IPA** of iFunny v10.31.11+. You cannot use an encrypted IPA from the App Store.

1.  **Fork this repository** by clicking the fork button in the top right corner.
2.  Go to your forked repository's **Settings** > **Actions** > **General**, and ensure **Read and write permissions** are enabled under "Workflow permissions".
3.  Navigate to the **Actions** tab.
4.  Select the **Build iFunnier IPA** workflow from the sidebar.
5.  Click the **Run workflow** button.
6.  Paste the **Direct Download URL** to your decrypted iFunny IPA in the input field.
7.  Click **Run workflow**.
8.  Once the build finishes, go to the **Releases** page of your fork to download the patched `iFunnier.ipa`.

### Method 2: Sideloading
If you already have the `.ipa` file:
-   **SideStore / AltStore:** Open the `.ipa` in SideStore or AltStore to install it.
-   **TrollStore:** If your device is compatible, install via TrollStore for permanent signing and better performance.
-   **Esign / Scarlet:** Sign and install the IPA using your preferred signing service.

---

## How It Works

**iFunnier Remastered** utilizes **Logos** and the **Objective-C Runtime** to hook into internal Swift classes and modify their behavior dynamically.

### Premium Spoofing & Feature Flags
The tweak identifies and hooks into key service classes responsible for managing user entitlements. By overriding methods such as `isActive` in `PremiumStatusServiceImpl` and `isFeatureAvailable` in `PremiumFeaturesServiceImpl`, the tweak forces the app to return `YES` (True) for all entitlement checks.

### The "Nuclear" Ad Blocker
Rather than simply hiding ad views (which can leave empty spaces), iFunnier Remastered neutralizes the ad SDKs themselves. It hooks into major ad networks—including **AppLovin (ALAdService)**, **Google AdMob (GADBannerView)**, and **IronSource**—intercepting the `loadAd` and `loadRequest` methods to prevent any ad data from ever being requested or downloaded.

### Dynamic Safety
To ensure stability across different app versions, the tweak uses **dynamic class lookups** (`objc_getClass`). Instead of hardcoding class names that might change, the tweak searches for these classes at runtime. If a class is renamed or missing in a future update, the tweak gracefully skips that hook instead of crashing the app.

---

## Support

This project is open-source and free. If you encounter crashes or bugs:

1.  Check the **Issues** tab to see if the problem has already been reported.
2.  Open a new Issue and include:
    -   iFunny App Version
    -   iOS Version
    -   Device Model
    -   A crash log (if available)