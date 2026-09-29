# Releasing the mod

The release workflow is in `.github/workflows/release.yml`. It runs **only** for pushed version tags (`v*`), not for normal commits. A GitHub Release with its installable ZIP is published after the Lua tests, source checks, package checks and PNG validation pass. The Nexus step uploads **only the mod ZIP** for future tags as described below.

## Build and inspect locally

From the repository root, run the Lua tests listed in [`TESTING.md`](TESTING.md), then:

```sh
python3 tests/scripts/build-release.py --tag v0.20.0
python3 tests/test_release_package.py
python3 tests/test_gallery.py
unzip -l dist/InventorySlotReservations-0.20.0.zip
```

Replace `v0.20.0` with the version in `mod.json`. The builder rejects a mismatched tag and packages **only** `mod.json`, `LICENSE`, and the Lua files in `Scripts/`, all under `InventorySlotReservations/`. It does not include screenshots, tests, saves, game files, UE4SS binaries, logs, or local configuration. `dist/` is ignored by Git. The ZIP is deterministic for identical inputs. A user extracts that folder to `AlchemyFactory/Binaries/Win64/ue4ss/Mods/` and enables it in `mods.txt` as described in the README.

## Publish to GitHub

1. Update `mod.json` to the release version and review/test the changes. Commit and push to `master`.
2. Make sure the release commit is on `origin/master` and the tag does **not** already exist. Then push a matching tag:

   ```sh
   git tag v0.20.0
   git push origin v0.20.0
   ```

3. Check the [GitHub Actions run](https://github.com/KUGA2/alchemy-factory-InventorySlotReservations/actions) and inspect the [release ZIP](https://github.com/KUGA2/alchemy-factory-InventorySlotReservations/releases). A failed check does not publish a new release. The workflow uses GitHub's built-in `GITHUB_TOKEN`; no third-party credential is needed.

Tagging is an intentional public release action. **Do not push a tag** until the mod and documentation are ready for public distribution. If the workflow fails, fix the issue on `master` and choose a new version/tag rather than silently replacing an already published version.

## Nexus Mods (opt-in updates)

The [Nexus listing for this mod](https://www.nexusmods.com/alchemyfactory/mods/26) has **mod ID 26**. Its first main file (`0.20.0`) was uploaded through the Nexus API while the mod was still a draft. The **parent File ID is `8048907`**; the game's scoped version ID `68` and the mod ID `26` are **not** the `file_id` required by the [official Nexus upload action](https://github.com/Nexus-Mods/upload-action). This action adds versions to an existing file. Publishing the draft mod page may still require a separate action on Nexus Mods.

When ready, set these in **GitHub → repository Settings → Secrets and variables → Actions**:

- Secret `NEXUSMODS_API_KEY`: create a personal key in [Nexus API settings](https://www.nexusmods.com/settings/api-keys). Enter it in the GitHub secret form; never paste it into chat, Git, an issue, an archive, or a command that prints it.
- Variable `NEXUSMODS_FILE_ID`: `8048907`, the parent **File ID** of the initial main file on mod 26.

Both the secret and variable were configured in GitHub Actions after the initial upload; secret values are not readable back from GitHub. Future version tags will upload the ZIP as a new version of that file. The workflow uses a pinned revision of the official Nexus action and passes the version from the tag, without the `v` prefix. A missing/invalid key or wrong ID makes the Nexus step fail **after** the GitHub Release has already been published. It does not retroactively upload the existing `v0.20.0` release. Review the first live update and Nexus-specific licensing/dependency fields before relying on unattended uploads. Never commit the local `.nexus.key` file.

The Nexus Upload API key can publish **files**, not the mod page's description or images. The workflow does not upload screenshots to Nexus or attach them to the release ZIP. `images/title.png` is the banner in the GitHub README; the gallery PNGs remain in this repository for documentation. Edit the Nexus page description in its website editor; uploading a new ZIP does **not** update that text. Do not put a Nexus website session cookie in GitHub Secrets.
