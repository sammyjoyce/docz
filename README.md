# docz

## CLI agent for writing and refining markdown documents

### Usage

#### Executable

- Build from source:

```sh
git clone https://github.com/sammyjoyce/docz.git
cd docz/
zig build exe -- -h
```

- Download latest release:

```sh
wget https://github.com/sammyjoyce/docz/releases/latest/download/<archive>
tar -xf <archive> # Unix
unzip <archive> # Windows
./<binary> -h
```

#### Module

1. Add `docz` dependency to `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/sammyjoyce/docz.git
```

2. Use `docz` dependency in `build.zig`:

```zig
const docz_dep = b.dependency("docz", .{
    .target = target,
    .optimize = optimize,
});
const docz_mod = docz_dep.module("docz");
<std.Build.Step.Compile>.root_module.addImport("docz", docz_mod);
```
