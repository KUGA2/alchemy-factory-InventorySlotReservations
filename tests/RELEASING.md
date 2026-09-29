# Releasing the mod

The release workflow is in `.github/workflows/release.yml`. It runs **only** for pushed version tags (`v*`), not for normal commits. A GitHub Release and its installable ZIP are published after the Lua tests, source checks, and package checks pass. There is **no Nexus Mods upload** in this workflow yet.

## Build and inspect locally

From the repository root, run the Lua tests listed in [`TESTING.md`](TESTING.md), then:

```sh
python3 tests/scripts/build-release.py --tag v0.20.0
python3 tests/test_release_package.py
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

## Nexus Mods (not yet automated)

Alchemy Factory has a [Nexus Mods game page](https://www.nexusmods.com/games/alchemyfactory/mods). Create the first mod page and upload the first ZIP there manually. The [official Nexus upload action](https://github.com/Nexus-Mods/upload-action) updates an **existing** file and requires its file ID; this is why the current GitHub workflow does not upload there. Once the first file is published and you know its file ID, store the Nexus API key as a GitHub Actions **secret**, and the file ID as a repository **variable**. Never put a key into Git, an archive, or an issue. Review the first live upload and site-specific licensing/dependency fields before enabling automated Nexus updates.
