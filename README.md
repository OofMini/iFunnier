# iFunnier ( Work in progress, currently unstable. 

**iFunnier** is a tweak for iFunny that removes ads, removes watermarks, and allows saving of any content (images and videos).

This version has been updated to support **Sideloading** (Non-Jailbroken devices) via AltStore, SideStore, or TrollStore.

## Features
* **No Ads**: Banner, Native, and Reward ads are disabled.
* **No Watermarks**: Automatically crops watermarks when saving images.
* **Save Anything**: Adds the ability to save videos and images that normally cannot be saved.
* **Privacy**: Bearer tokens are saved to the app's Documents folder for debugging (optional).

## How to Build (Sideloadable IPA)

You do not need a computer or a Mac to build this. You can use the GitHub Actions workflow included in this repository.

1.  **Fork** this repository.
2.  Go to the **Actions** tab in your forked repo.
3.  Select the **Build iFunnier IPA** workflow.
4.  Click **Run workflow**.
5.  Paste a direct download link to an **iFunny IPA** in the input box.
    * *Note: Using a decrypted IPA is recommended for best compatibility, but standard IPAs often work.*
6.  Wait for the build to finish, then download the `iFunnier-Patched-IPA` artifact.

## Installation
Install the downloaded `.ipa` using:
* AltStore
* SideStore
* TrollStore
* Esign / Scarlet

## Credits
* **Eamon Tracey** - Original Creator
* **Theos** - Build System
* **Azule** - IPA Injection Tool