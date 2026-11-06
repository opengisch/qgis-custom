#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Compose a version of QGIS: merge the PRs and branches of versions/<name>.toml onto its base.

Usage: ./compose.py <name>. It makes the branch qgis-custom/<name> in work/QGIS, and the manifest work/<name>.md.
"""

import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORK = ROOT / "work" / "QGIS"
# The other repos are fetched by URL: only this one is cloned without its blobs.
ORIGIN = "qgis/QGIS"


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(["git", "-C", str(WORK), *args], check=False, text=True, capture_output=True)
    if check and result.returncode:
        sys.exit(f"git {' '.join(args)} failed:\n{result.stderr}")
    return result


def fetch(repo: str, ref: str) -> str:
    remote = "origin" if repo == ORIGIN else f"https://github.com/{repo}.git"
    git("fetch", "--no-tags", remote, ref)
    return git("rev-parse", "FETCH_HEAD").stdout.strip()


def merging() -> bool:
    return git("rev-parse", "-q", "--verify", "MERGE_HEAD", check=False).returncode == 0


def main(name: str) -> None:
    version = tomllib.loads((ROOT / "versions" / f"{name}.toml").read_text())
    base = version["base"]

    if not WORK.exists():
        subprocess.run(
            ["git", "clone", "--filter=blob:none", "--no-tags", f"https://github.com/{ORIGIN}.git", str(WORK)],
            check=True,
        )
    # rerere writes the resolutions through this link, into the repo, so CI can replay them
    (ROOT / "rr-cache").mkdir(exist_ok=True)
    rr_cache = WORK / ".git" / "rr-cache"
    if not rr_cache.is_symlink():
        rr_cache.symlink_to(ROOT / "rr-cache")
    git("config", "rerere.enabled", "true")
    git("config", "rerere.autoUpdate", "true")

    if merging() or git("status", "--porcelain", "--untracked-files=no").stdout:
        sys.exit(f"{WORK} has a merge in progress or changes: finish it with git commit, or git merge --abort.")

    sha = fetch(base["repo"], base["ref"])
    git("checkout", "--no-track", "-B", f"qgis-custom/{name}", sha)
    manifest = [f"# {name}", "", f"Base: {base['repo']} {base['ref']} ({base['repo']}@{sha})", ""]

    for entry in version.get("merge", []):
        if "pr" in entry:
            label, repo = f"{base['repo']}#{entry['pr']}", base["repo"]
            sha = fetch(repo, f"pull/{entry['pr']}/head")
        else:
            label, repo = f"{entry['repo']} {entry['branch']}", entry["repo"]
            sha = fetch(repo, entry["branch"])
        print(f"merging {label}")
        result = git("merge", "--no-ff", "--no-edit", "-m", f"merge {label}", sha, check=False)
        if result.returncode:
            if not merging():
                sys.exit(f"{label}: the merge failed.\n{result.stdout}{result.stderr}")
            unmerged = git("diff", "--name-only", "--diff-filter=U").stdout
            if unmerged:
                sys.exit(f"{label} conflicts in:\n{unmerged}Resolve in {WORK}, git commit, and run again.")
            print("  conflicts resolved by rerere")
            git("commit", "--no-edit")
        note = f": {entry['note']}" if "note" in entry else ""
        manifest.append(f"- {label} ({repo}@{sha}){note}")

    manifest += ["", f"Composed: {git('rev-parse', 'HEAD').stdout.strip()}", ""]
    (ROOT / "work" / f"{name}.md").write_text("\n".join(manifest))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
