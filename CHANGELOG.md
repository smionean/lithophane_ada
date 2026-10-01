# Changelog

## [Unreleased]

### Added
- `-H`/`--height` option (and `height` config key): maximum relief height in
  millimetres. The brightest pixel is raised to exactly `Z = height`, the others
  proportionally to their grey level; the flat base sits at `Z = -2`, so the
  part is `height + 2` thick.
- Warning when a depth in `--dimensions` overrides an explicit `--height` in
  the 3MF output.
- `-t`/`--threshold` option: grey level (`0.0 .. 1.0`, default `0.5`) below
  which pixels are cut to `0.0`. The threshold is now always applied.
- `-M`/`--max_size` option (and `max_size` config key): maximum image dimension
  in pixels (default `1500`, `0` = no limit). Larger images are shrunk
  (nearest-neighbour, aspect ratio preserved) before the mesh is built.
- Clear error messages for unreadable or unsupported input files, invalid
  option values and output write failures, instead of raw exception traces.
- Build instructions in the README and the Alire manifest.

### Changed
- The image is now converted to a normalised greyscale height map
  (`0.0 .. 1.0`) instead of `0 .. 255` colour values.
- `filter_threshold` in the config file is now a float in `0.0 .. 1.0`.
- The `threshold` filter is replaced by `none`; thresholding is handled by
  `-t`/`--threshold`.
- 3MF output: a depth left empty or `0` in `--dimensions` no longer follows the
  X/Y scale; `Z` is left unscaled so the relief keeps the height set by
  `--height`, in millimetres. A non-zero depth still sets the total thickness.
- 3MF output is streamed in small chunks, so the model XML is never held in
  memory as a whole.

## [1.0.0] - 2026-09-02

### Added
- Image filters: Bartlett, Gauss, Square and Sharpen, with a configurable
  odd kernel size (`--filter <name> [<n>]`).

### Removed
- Unused height option from the settings.

## [0.1.2] - 2026-09-02

### Added
- 3MF output (`-m`/`--save-3mf`): a welded, watertight mesh with optional
  physical size in millimetres (`--dimensions=<W>x<H>x<D>`).
- `-B`/`--border` option (and `border_size` config key): white margin added
  around the image.
- Filter support (first version) and filter options in the README and
  example config.
- TOML configuration file (`-c`/`--config`).

## [0.1.1] - 2026-08-25

### Fixed
- Mirrored image in the generated STL.
- Grey level conversion.

### Added
- Detailed usage instructions in the README and Alire manifest, logo images.

## [0.1.0] - 2026-08-23

### Added
- First version: convert an image into a lithophane STL (binary or ASCII).
