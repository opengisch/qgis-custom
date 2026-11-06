# qgis-custom

Custom builds of QGIS for Windows: a base of qgis/QGIS, usually master, with PRs and branches merged onto it that
qgis/QGIS does not have yet.

- A **version** is a file of [`versions/`](versions). It names a base and what is merged onto it, in order.
- [`compose.py`](compose.py) merges a version into the branch `qgis-custom/<version>`.
- The workflow [`build`](.github/workflows/build.yml) pushes that branch to
  [opengisch/QGIS](https://github.com/opengisch/QGIS) and builds it.
- The workflow [`release`](.github/workflows/release.yml) publishes a build as a release.
- `rr-cache/` keeps the resolutions of merge conflicts. All versions share them.

Each build takes the current heads of the base and of the PRs. Its manifest records their commits.

## A version

```toml
[base]
repo = "qgis/QGIS"
ref = "master"            # a branch or a tag

[[merge]]
pr = 68084                # a PR of the base repo
note = "why we need it"

[[merge]]
repo = "opengisch/QGIS"   # a branch of any repo
branch = "my-fix"
```

To add a version, add its file and add its name to the `version` options in
[`release.yml`](.github/workflows/release.yml).

## Compose locally

```sh
./compose.py qgis-dmav
```

The script needs [uv](https://docs.astral.sh/uv/). The first run clones qgis/QGIS without its blobs into
`work/QGIS`. All versions share that clone. The result is the branch `qgis-custom/qgis-dmav` there, and the
manifest `work/qgis-dmav.md`.

## Conflicts

A conflict cannot be resolved in CI. You resolve it once, and git
[rerere](https://git-scm.com/book/en/v2/Git-Tools-Rerere) replays it for all later builds:

1. Run `./compose.py <version>`. It stops on the entry that conflicts and lists the files.
2. Resolve them in `work/QGIS`, then `git add` and `git commit`. rerere records the resolution in `rr-cache/`.
3. Run `./compose.py <version>` again, until it gets through.
4. Commit `rr-cache/` and push. CI replays the resolution for every version that has the same conflict.

To redo a bad resolution, run `git rerere forget <path>` during the conflict. rerere cannot help with a
delete/modify conflict, or with a merge that is clean but does not compile. In that case, push a fix branch to
opengisch/QGIS and add it as an entry.

## Build and release

- **Pull request:** composes every version, without a build.
- **Push to main:** composes every version, pushes each one to opengisch/QGIS, and builds it. The zip is kept as an
  artifact for 90 days. A push that changes only this README or `release.yml` builds nothing. To build again without
  a commit, for example to take a newer master, run the workflow by hand: Actions → build → Run workflow.
- **Release:** Actions → release → Run workflow, with a version and a tag. It takes the last build of that version
  on main, and publishes it as the release `<version>-<tag>`, with the zip and the manifest. While a build of main
  is running, it refuses: wait until the build is done. It does not build again: the release is the zip that was
  built. It also tags the composed commit `qgis-custom/<version>-<tag>` in opengisch/QGIS, so that the commit stays
  when the branch moves on.

The build follows `windows-qt6.yml` of qgis/QGIS. The head of [`build.yml`](.github/workflows/build.yml) names the
upstream commit it follows. When upstream changes its steps or its flags, copy the change.

The dependencies come from the vcpkg binary cache of qgis/QGIS. ccache keeps the objects that are already compiled.
The first build, or a build after a big jump of master, can take longer than the 6 h limit of a job. The build step
stops at 5 h 30, and the cache is saved. Click "Re-run failed jobs": the run builds the same commit, and continues
where it stopped.

## Setup

The secret `QGIS_FORK_TOKEN` pushes the branches and tags to opengisch/QGIS. It is a fine-grained token or a GitHub
App token, on opengisch/QGIS only, with **Contents** and **Workflows** write. Workflows write is necessary because
the commits of master change `.github/workflows/`.
