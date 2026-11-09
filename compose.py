#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Compose a version of QGIS: merge the PRs and branches of versions/<name>.toml onto its base.

Usage: ./compose.py <name>. It makes the branch qgis-custom/<name> in work/QGIS, and the manifest work/<name>.md.
       ./compose.py --check <name>. It prints, through gh, the followed sources that have commits the branch
       qgis-custom/<name> of opengisch/QGIS lacks. A source is followed unless it sets follow = false.
"""

import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORK = ROOT / "work" / "QGIS"
# The other repos are fetched by URL: only this one is cloned without its blobs.
ORIGIN = "qgis/QGIS"
# Where the workflow build pushes the composed branches
FORK = "opengisch/QGIS"


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(["git", "-C", str(WORK), *args], check=False, text=True, capture_output=True)
    if check and result.returncode:
        sys.exit(f"git {' '.join(args)} failed:\n{result.stderr}")
    return result


def gh(path: str, jq: str) -> str:
    result = subprocess.run(["gh", "api", path, "--jq", jq], check=False, text=True, capture_output=True)
    if result.returncode:
        sys.exit(f"gh api {path} failed:\n{result.stderr}")
    return result.stdout.strip()


def fetch(repo: str, ref: str) -> str:
    remote = "origin" if repo == ORIGIN else f"https://github.com/{repo}.git"
    git("fetch", "--no-tags", remote, ref)
    return git("rev-parse", "FETCH_HEAD").stdout.strip()


def merging() -> bool:
    return git("rev-parse", "-q", "--verify", "MERGE_HEAD", check=False).returncode == 0


def sources(version: dict) -> list[tuple[str, str, str, dict]]:
    """The base, then the entries to merge: the label, repo and ref of each, and its table."""
    base = version["base"]
    result = [(f"{base['repo']} {base['ref']}", base["repo"], base["ref"], base)]
    for entry in version.get("merge", []):
        if "pr" in entry:
            result.append((f"{base['repo']}#{entry['pr']}", base["repo"], f"pull/{entry['pr']}/head", entry))
        else:
            result.append((f"{entry['repo']} {entry['branch']}", entry["repo"], entry["branch"], entry))
    return result


def check(name: str, version: dict) -> None:
    for label, repo, ref, source in sources(version):
        if source.get("follow", True):
            head = gh(f"repos/{repo}/commits/{ref}", ".sha")
            # ahead or identical: the head is among the commits of the composed branch
            if gh(f"repos/{FORK}/compare/{head}...qgis-custom/{name}", ".status") not in ("ahead", "identical"):
                print(label)


def compose(name: str, version: dict) -> None:
    (base_label, base_repo, base_ref, _), *entries = sources(version)

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

    sha = fetch(base_repo, base_ref)
    git("checkout", "--no-track", "-B", f"qgis-custom/{name}", sha)
    manifest = [f"# {name}", "", f"Base: {base_label} ({base_repo}@{sha})", ""]

    for label, repo, ref, entry in entries:
        sha = fetch(repo, ref)
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
    args = sys.argv[1:]
    if not args or args[:-1] not in ([], ["--check"]):
        sys.exit(__doc__)
    version = tomllib.loads((ROOT / "versions" / f"{args[-1]}.toml").read_text())
    (check if args[0] == "--check" else compose)(args[-1], version)
