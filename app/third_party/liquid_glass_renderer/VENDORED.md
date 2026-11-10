# Vendored liquid_glass_renderer

A copy of `packages/liquid_glass_renderer` from
https://github.com/whynotmake-it/flutter_liquid_glass at commit
`fc00500898d35a09bb1f5423df87e2d512025cfa` (branch
`fix/fake-glass-web-shared-shader-uniforms` of the fork devilAPI/flutter_liquid_glass):
version 1.0.0-dev.2 plus the web fix of
https://github.com/whynotmake-it/flutter_liquid_glass/pull/266.

Only what the app builds with is here: `lib/`, `hook/`, the licenses and
the pubspec (without its dev_dependencies). The example and the tests are
left out: the example's reference images are in Git LFS, which GitHub does
not serve through a fork, and some of its paths are too long for Windows,
so a git dependency on the fork broke every CI build.

Licensed under the Apache License 2.0 (`LICENSE`); `third_party/` holds the
licenses of code it includes. Changes from upstream: none in `lib/` and
`hook/` beyond that commit; the pubspec's dev_dependencies are removed.

Once a release of liquid_glass_renderer contains the fix, depend on it from
pub.dev and delete this directory.
