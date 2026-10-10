# lithophane
[![Static Badge](https://img.shields.io/badge/Ada-2022-blue)](https://ada-lang.io/docs/arm)
[![Alire](https://img.shields.io/endpoint?url=https://alire.ada.dev/badges/lithophane.json)](https://alire.ada.dev/crates/lithophane)

Create [lithophane](https://en.wikipedia.org/wiki/Lithophane) of your favourite picture with Ada.

<img src="./doc/img/ada.logo.png" alt="Lithophane_Logo" width="200">
<img src="./doc/img/lithophane_stl.png" alt="Lithophane_STL" width="200">


**Build**
```
alr build
```

**Tests**
```
alr test
```

Builds and runs the regression tests of the [tests](tests) crate
([AUnit](https://github.com/AdaCore/aunit)); the report is written to
`alire/alr_test_local.log`. To see it on the terminal, run them from the crate
itself:
```
cd tests
alr run
```

The tests cover the filters, the image resizing, the mesh, the STL and 3MF
writers, the config file, the whole command line and the interactive mode (the
program is run on a tiny generated picture). The files it writes are also
compared with the ones kept in [tests/golden](tests/golden); when a change of
the output is intended, regenerate them and review their diff:
```
cd tests
LITHOPHANE_UPDATE_GOLDEN=1 alr run
```

**Usage**
```
bin/lithophane [options] <input_file>
```

`<input_file>` is the picture to convert (any format supported by
[GID](https://gen-img-dec.sourceforge.io): PNG, JPEG, BMP, GIF, TGA, ...).

**Options**
```
-h --help                 (also -?)
-v --version
-b --save-stl-binary      (default; also --save-binary)
-a --save-stl-ascii       (also --save-ascii)
-m --save-3mf
-p --save-pgm
-C --colour
-o<name> --output-name=<name>
-H<height> --height=<height>
-B<border> --border=<border>
-d<W>x<H>x<D> --dimensions=<W>x<H>x<D>
-f<filter> --filter <filter> [<n>]
-t<threshold> --threshold=<threshold>
-M<max_size> --max-size=<max_size>
-c<file> --config=<file>
-i --interactive
```

| Option | Description |
| --- | --- |
| `-h`, `--help`, `-?` | print usage and exit |
| `-v`, `--version` | print the program version and exit |
| `-b`, `--save-stl-binary`, `--save-binary` | write the lithophane as a binary STL file: `<output-name>.bin.stl` (this is the default output if no `-a`/`-b`/`-p` flag is given) |
| `-a`, `--save-stl-ascii`, `--save-ascii` | write the lithophane as an ASCII STL file: `<output-name>.ascii.stl` |
| `-m`, `--save-3mf` | write the lithophane as a 3MF file: `<output-name>.3mf` (a ZIP/OPC package with a welded, watertight mesh as `3D/3dmodel.model`) |
| `-p`, `--save-pgm` | also dump the grayscale-converted image as a PGM file: `<output-name>.pgm` |
| `-C`, `--colour` | write a colour lithophane as a 3MF file, `<output-name>.3mf`, **instead of** the outputs above (STL cannot hold it; `-a`, `-b` and `-m` are ignored, `-p` still works). See [Colour lithophane](#colour-lithophane). |
| `-o<name>`, `--output-name=<name>` | base name used for every output file above (default: `test`) |
| `-H<height>`, `--height=<height>` | maximum relief height, in millimetres (a positive number, default `10.0`): the highest point of the relief lies at `Z = <height>`, i.e. the brightest pixel is raised to exactly this height and the others proportionally to their grey level. The flat base sits below `Z = 0` (from `Z = -2`), so the total thickness of the part is `<height> + 2`. In the 3MF output, a non-zero depth in `--dimensions` overrides it (a warning is printed). |
| `-B<border>`, `--border=<border>` | width, in pixels, of the border added around the image (default: `20`) |
| `-d<W>x<H>x<D>`, `--dimensions=<W>x<H>x<D>` | target physical size **of the 3MF output**, in millimetres (3MF is unit-aware, STL is not). Each axis with a non-zero value is scaled to it exactly. A width or height left empty or `0` follows the first constrained axis, so the picture keeps its aspect ratio. A depth left empty or `0` leaves `Z` unscaled: the relief keeps the height set by `--height`, in millimetres. A non-zero depth is the total thickness (base + relief) and overrides `--height`. `X`/`Y` are centred on the origin. Example: `--dimensions=100x100x1.5`, or `--dimensions=120x0x0` to set the width, let the height follow and keep the relief from `--height`. |
| `-f<filter>`, `--filter <filter> [<n>]` | image filter to apply before conversion; `<filter>` is one of `bartlett`, `gauss`, `square`, `sharpen`, `none`. The optional number `<n>` right after the filter name is the kernel size (an odd number, `3` or more, default `3`). |
| `-t<threshold>`, `--threshold=<threshold>` | grey level, from `0.0` to `1.0` (default `0.5`), below which pixels are cut to `0.0`. The threshold is always applied; use `0` to keep every pixel. |
| `-M<max_size>`, `--max-size=<max_size>` | maximum image dimension, in pixels, border included (default `1500`, `0` = no limit). When the image is wider or taller than this, it is shrunk (nearest-neighbour, aspect ratio preserved) so its larger side equals `<max_size>` before the mesh is built. |
| `-c<file>`, `--config=<file>` | read options from a config file instead of (or in addition to) the command line; every key it holds overrides the matching command line argument, input file included, wherever `-c` stands on the command line. |
| `-i`, `--interactive` | ask for the settings one by one on the standard input instead of reading them from the command line; the other options and the input file given with it are ignored. See [Interactive mode](#interactive-mode). |

You can combine `-a`, `-b`, `-m` and `-p`: each one adds its own output file,
they are not mutually exclusive. `-C` is the exception: it writes the colour
3MF file only (and the PGM file with `-p`).

The value of a short option may be attached or separate (`-H5`, `-H 5`), and
the value of a long option may follow `=` or be the next argument
(`--height=5`, `--height 5`). An unknown option, an invalid value or a second
input file is reported as an error and nothing is generated. The same goes
for a config file that cannot be found or is not valid TOML.

The `<n>` argument is positional and optional, so both of these work:
```
bin/lithophane --filter gauss 5 doc/img/ada.logo.png
bin/lithophane --filter sharpen doc/img/ada.logo.png
```

**Interactive mode**

```
bin/lithophane -i
```

`-i`/`--interactive` asks for the settings one question at a time. The rest of
the command line is not used: the input file is the first answer.

| Question | Answer |
| --- | --- |
| Input file | the picture to convert; the blanks around the name are removed, and so is what a terminal adds to a file dropped on it: a pair of quotes around the name, or the backslashes that escape its characters (`my\ picture.png`; not on Windows, where they separate directories) |
| Threshold | a grey level from `0.0` to `1.0`, as `--threshold` |
| Filter | Bartlett, Gauss, Square, Sharpen or none (default); a filter is followed by its size, an odd number, `3` or more |
| Border | its width in pixels, `0` for none, as `--border` |
| Colour mode | black and white (default) or colour, as `--colour` |
| File type | black and white only: STL binary, STL ASCII or 3MF (default); a colour lithophane is always a 3MF file |
| Dimensions | 3MF and colour only: a metric standard size (`90 x 130`, `100 x 150` (default), `130 x 180` or `150 x 200` mm), an imperial one (`3.5 x 5`, `4 x 6` (default), `5 x 7` or `8 x 10` inch) or a custom width, height and depth in millimetres, as `--dimensions`. A standard size is `1.5` mm thick. |
| Maximum image dimension | in pixels (default `1500`, `0` = no limit), as `--max-size` |
| Output filename | base name of the output file (default `test`), as `--output-name`; blanks, quotes and backslashes are removed as for the input file |

An empty answer picks the default where there is one; the threshold and the
border have none. In a menu, `0` leaves the program. An answer that is not
valid, or a standard input that ends before the last question, is reported as
an error. In all these cases nothing is generated and the exit status is a
failure.

Exactly one file is written. The relief height (`--height`), the PGM dump
(`--save-pgm`) and the config file (`--config`) have no question: use the
command line for them.

Since the answers are read from the standard input, they can also come from a
file, one per line:
```
bin/lithophane -i < answers.txt
```

**Colour lithophane**

`-C`/`--colour` keeps the colours of the picture. The 3MF file then holds one
object made of five parts, to print with four filaments (a multi-material
printer); from the flat back to the front:

| Part | Filament | Shape |
| --- | --- | --- |
| `white back` | white | a flat sheet `0.2` mm thick, the first layers on the bed (two layers of `0.1` mm), under the inks |
| `cyan`, `magenta`, `yellow` | one translucent filament each | a layer as thick, at each pixel, as the picture holds of that ink there: up to `0.4` mm, nothing where there is none. A part is left out when the picture holds none of its ink at all. |
| `white` | white | the lithophane itself (base and relief), lying on top of the three layers |

The three inks give the hue, the white relief gives the darkness, as in a
plain lithophane. The picture is split the CMYK way: the relief follows the
black of each pixel (`1 - max(R, G, B)`) instead of its grey level, and the
inks are what is left of each channel once that black is taken out. The
border holds no ink.

Each part carries its name and its colour (a colour group of the 3MF
materials extension), and slicers load them as the parts of one object. For Bambu Studio (and the
slicers derived from it) the file also holds `Metadata/model_settings.config`,
which gives each part its filament: **1 cyan, 2 magenta, 3 yellow, 4 white**
(both white parts).
Set up these four filaments, in that order, in the project before opening the
file. Bambu Studio still says that the 3MF is not from Bambu Lab and that it
loads the geometry only: that is expected, the print settings stay yours. In
another slicer, assign a filament to each part by hand.

```
bin/lithophane -C -t 0 -H 1.5 -d 100x0x0 -M 500 -o colour photo.jpg
```

- `-H`, `-B`, `-f`, `-t` and `-M` work as usual, on the relief. The default
  threshold (`0.5`) flattens every pixel whose brightest channel is above
  half: `-t 0` is usually what you want here.
- In `--dimensions`, the width and height are those of the whole model. A
  non-zero depth is the thickness of the `white` part (base + relief); the
  white sheet and the ink layers keep their thickness and come on top of it
  (`0.2` mm, and up to `1.2` mm where the three inks are full).
- Every part is a mesh at the resolution of the picture, so the file grows
  about four times as fast as a plain 3MF: lower `-M` (a few hundred pixels
  is plenty for a print).

**Config file**

`-c`/`--config` points to a TOML file such as [config.toml](doc/example/config.toml):
```toml
input-name = "foo.png"
output-name = "test"
filter = "sharpen"
filter_size = 3
filter_threshold = 0.5
border_size = 20
save-ascii = false
save-binary = true
save-3mf = false
save-pgm = true
colour = false
height = 10.0
max_size = 1500
dimensions = { width = 100.0, height = 100.0, depth = 1.5 }
```

Every key is optional; a missing key keeps its default. `filter_size` must be a
positive odd integer, `filter_threshold` must be a float in `0.0..1.0`, `height` must be a
positive number, and `border_size` and `max_size`
must be non-negative integers (`max_size = 0` means no limit), otherwise the key is ignored. `dimensions` is an
inline table (`width` / `height` / `depth`, in millimetres, applied to the 3MF
output); `width` or `height` may be omitted or set to `0` to leave that axis
proportional, and `depth` may be omitted or set to `0` to keep the relief
height given by `height`. `colour = true` is the same as `-C`/`--colour`.
The config file always has the last word: a key it
holds overrides the matching command line argument (`input-name` included),
whether that argument stands before or after `-c`/`--config`. The command line
only decides what the config file leaves out.

> [!NOTE]
> `-f`/`--filter` and `-c`/`--config` are wired up: the selected filter (and its
> size) is applied to the grayscale image before the STL is
> generated, and the config file overrides the matching settings.
> `-B`/`--border` is wired up too: it sets the white margin added around the
> image before conversion. A threshold filter is always applied after
> conversion; its cut level (`0.5`, mid-grey, by default) is set with
> `-t`/`--threshold` or `filter_threshold`.

Based on [GID](https://gen-img-dec.sourceforge.io)

