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

**Usage**
```
bin/lithophane [options] <input_file>
```

`<input_file>` is the picture to convert (any format supported by
[GID](https://gen-img-dec.sourceforge.io): PNG, JPEG, BMP, GIF, TGA, ...).

**Options**
```
-h --help
-v --version
-b --save-binary          (default)
-a --save-ascii
-p --save-pgm
-o<name> --output-name=<name>
-H<height> --height=<height>
-f<filter> --filter <filter> [<n>]
-c<file> --config=<file>
```

| Option | Description |
| --- | --- |
| `-h`, `--help` | print usage and exit |
| `-v`, `--version` | print the program version and exit |
| `-b`, `--save-binary` | write the lithophane as a binary STL file: `<output-name>.bin.stl` (this is the default output if no `-a`/`-b`/`-p` flag is given) |
| `-a`, `--save-ascii` | write the lithophane as an ASCII STL file: `<output-name>.ascii.stl` |
| `-p`, `--save-pgm` | also dump the grayscale-converted image as a PGM file: `<output-name>.pgm` |
| `-o<name>`, `--output-name=<name>` | base name used for every output file above (default: `test`) |
| `-H<height>`, `--height=<height>` | target height of the lithophane |
| `-f<filter>`, `--filter <filter> [<n>]` | image filter to apply before conversion; `<filter>` is one of `bartlett`, `gauss`, `square`, `sharpen`, `threshold`. The optional number `<n>` right after the filter name is the kernel size (an odd number, default `3`) for `bartlett`/`gauss`/`square`/`sharpen`, or the cut value `0..255` (default `128`) for `threshold`. |
| `-c<file>`, `--config=<file>` | read options from a config file instead of (or in addition to) the command line; when given, it overrides any previous option |

You can combine `-a`, `-b` and `-p`: each one adds its own output file, they are
not mutually exclusive.

The `<n>` argument is positional and optional, so both of these work:
```
bin/lithophane --filter gauss 5 doc/img/ada.logo.png
bin/lithophane --filter threshold 200 doc/img/ada.logo.png
bin/lithophane --filter sharpen doc/img/ada.logo.png
```

**Config file**

`-c`/`--config` points to a TOML file such as [config.toml](doc/example/config.toml):
```toml
input-name = "foo.png"
output-name = "test"
filter = "threshold"
filter_size = 3
filter_threshold = 128
save-ascii = false
save-binary = true
save-pgm = true
height = 10
```

Every key is optional; a missing key keeps its default. `filter_size` must be a
positive odd integer and `filter_threshold` must be in `0..255`, otherwise the
key is ignored. The config file is read at the point where `-c`/`--config`
appears on the command line, so options placed *after* it still take effect.

> [!NOTE]
> `-f`/`--filter` and `-c`/`--config` are wired up: the selected filter (and its
> size / threshold) is applied to the grayscale image before the STL is
> generated, and the config file overrides the matching settings. `-H`/`--height`
> is still parsed but height scaling has no effect on the generated STL for now
> (see TODO below). When no filter is selected, a threshold filter at mid-grey
> (`128`) is applied by default.

**TODO**
* add resize option
* add borders option
* add height option


Based on [GID](https://gen-img-dec.sourceforge.io)

