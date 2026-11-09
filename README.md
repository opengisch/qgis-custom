# qgis-custom

Custom builds of QGIS for Windows: a base of qgis/QGIS, usually master, with PRs and branches merged onto it that
qgis/QGIS does not have yet.

- A **version** is a file of [`versions/`](versions). It names a base and what is merged onto it, in order.
- [`compose.py`](compose.py) merges a version into the branch `qgis-custom/<version>`.
- The workflow [`build`](.github/workflows/build.yml) pushes that branch to
  [opengisch/QGIS](https://github.com/opengisch/QGIS) and builds it, for Windows and as a Docker image.
- The workflow [`release`](.github/workflows/release.yml) publishes a build as a release.
- `rr-cache/` keeps the resolutions of merge conflicts. All versions share them.

Each build takes the current heads of the base and of the PRs. Its manifest records their commits.

## A version

```toml
[base]
repo = "qgis/QGIS"
ref = "master"            # a branch or a tag
follow = false            # see below

[[merge]]
pr = 68084                # a PR of the base repo
note = "why we need it"

[[merge]]
repo = "opengisch/QGIS"   # a branch of any repo
branch = "my-fix"
```

To add a version, add its file and add its name to the `version` options in
[`release.yml`](.github/workflows/release.yml).

A source, the base or an entry, is **followed** unless it sets `follow = false`. Each night at midnight in Paris,
the workflow [`follow`](.github/workflows/follow.yml) runs the workflow build when a followed source has commits that
the last build lacks. A base on master is usually not followed: it moves each day, and each build takes its head
anyway. To check by hand which followed sources the last build lacks: `./compose.py --check <version>`, which needs
[gh](https://cli.github.com/).

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

## Build

- **Pull request:** composes every version, without a build.
- **Push to main:** composes every version, pushes each one to opengisch/QGIS, and builds it: a zip for Windows, kept
  as an artifact for 90 days, and a [Docker image](#docker-image). A push that changes only this README,
  `release.yml` or `follow.yml` builds nothing. To build again without a commit, for example to take a newer master,
  run the workflow by hand: Actions → build → Run workflow.
- **A followed source moves:** the workflow `follow` runs the build, as a run by hand.

A push while a build runs does not cancel it: the new build waits, and starts from the head of main.

The Windows build follows `windows-qt6.yml` of qgis/QGIS. The head of [`build.yml`](.github/workflows/build.yml) names
the upstream commit it follows. When upstream changes its steps or its flags, copy the change.

The dependencies come from the vcpkg binary cache of qgis/QGIS. ccache keeps the objects that are already compiled.
The first build, or a build after a big jump of master, can take longer than the 6 h limit of a job. The build step
stops at 5 h 30, and the cache is saved. Click "Re-run failed jobs": the run builds the same commit, and continues
where it stopped.

## Docker image

The image `ghcr.io/opengisch/qgis-custom` has QGIS with its desktop and its Python, for Linux amd64. The
[`Dockerfile`](Dockerfile) builds the composed commit as
[qgis/qgis-slim](https://github.com/qgis/qgis-docker/tree/main/slim) is built, with the desktop on top: Ubuntu 26.04,
GDAL with Arrow and Parquet, without 3D, GRASS, PDAL or server. Its head names the upstream commit it copies. When
upstream changes `slim/Dockerfile`, copy the change. The job saves its ccache even when the build or its test fails.
The test starts the desktop, and the image is pushed only when it passes. Its tags:

- `<version>`, for example `qgis-dmav`: the last build of the version on main.
- `<version>-<tag>`, for example `qgis-dmav-1`: a release.
- The composed commit, for each build.

```sh
docker run --rm ghcr.io/opengisch/qgis-custom:qgis-dmav python3 -c "from qgis.core import Qgis; print(Qgis.version())"
```

`qgis` starts the desktop on the display of `DISPLAY`. The head of the `Dockerfile` says how to build it locally.

## Release

The workflow `release` makes the releases. Do not create a release on the Releases page: it gets no zip.

1. In Actions → build, check that the last run on main succeeded, and that no run is in progress.
2. Actions → release → Run workflow. Choose the version, and type a tag, for example `1`.
3. When the run is done, the release `<version>-<tag>`, for example `qgis-dmav-1`, is on the Releases page. Its
   asset is the zip `qgis-custom-<version>-<tag>-win64.zip`, and its notes are the manifest. The Docker image of the
   build has the tag `<version>-<tag>` too.

From a terminal:

```sh
gh workflow run release.yml -R opengisch/qgis-custom -f version=qgis-dmav -f tag=1
```

The release does not build: it publishes the zip and the image of the last build of that version on main, in a few
minutes. It also tags the composed commit `qgis-custom/<version>-<tag>` in opengisch/QGIS, so that the commit stays
when the branch moves on. The run fails, and changes nothing, while a build of main is running, when no build of the
version on main is left, when that build has no image, or when the release exists already.

To redo a release, delete it, with its tag here and its tag in opengisch/QGIS, and run the workflow again:

```sh
gh release delete qgis-dmav-1 -R opengisch/qgis-custom --cleanup-tag --yes
gh api -X DELETE repos/opengisch/QGIS/git/refs/tags/qgis-custom/qgis-dmav-1
```

## Setup

The secret `QGIS_FORK_TOKEN` pushes the branches and tags to opengisch/QGIS. It is a fine-grained token or a GitHub
App token, on opengisch/QGIS only, with **Contents** and **Workflows** write. Workflows write is necessary because
the commits of master change `.github/workflows/`. The Docker image needs no secret: the workflows push it with
their `GITHUB_TOKEN`.
