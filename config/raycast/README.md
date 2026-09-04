# Raycast Configuration

Raycast stores application data, extensions, hotkeys, and quicklinks in a proprietary database (`com.raycast.macos`). To keep these synced across machines via this repository:

## 1. Exporting Settings (Current Machine)
To export your settings to a portable `.rayconfig` archive:
1. Open Raycast and run **Export Settings & Data** (or run: `open "raycast://extensions/raycast/raycast/export-settings-data"` in your terminal).
2. Save the file as:
   ```text
   ~/code/daman/dotfiles/config/raycast/settings.rayconfig
   ```
3. *Note*: If this repository is public, make sure to uncheck sensitive credentials/tokens during export or rely on Raycast Cloud Sync.
4. Commit the file to Git:
   ```sh
   git add config/raycast/settings.rayconfig
   git commit -m "feat(raycast): update exported raycast settings"
   ```

## 2. Importing Settings (New Machine)
On a new machine, after running `./scripts/bootstrap.sh`, restore your Raycast configuration by opening the file:

```sh
open ~/code/daman/dotfiles/config/raycast/settings.rayconfig
```
Raycast will launch and present an interactive import confirmation dialog.

## 3. Raycast Cloud Sync (Alternative / Complementary)
If you are logged into Raycast with an account:
1. Open **Raycast Settings** (`Cmd + ,`).
2. Go to **Account** → enable **Sync Data**.
3. All extensions, hotkeys, snippets, and quicklinks will automatically sync across your Macs in real-time.
