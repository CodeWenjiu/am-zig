_default:
    @just --list

_zb platform step target feature *zig_args:
    @zig build {{ step }} -Dplatform={{ platform }} -Dtarget={{ target }} -Dfeature={{ feature }} {{ zig_args }}

build platform target feature bin *zig_args:
    @just _zb {{ platform }} build {{ target }} {{ feature }} -Dbin={{ bin }} {{ zig_args }}

dump platform target feature bin *zig_args:
    @just _zb {{ platform }} dump {{ target }} {{ feature }} -Dbin={{ bin }} {{ zig_args }}

# Native-friendly shortcut: native ignores -Dtarget/-Dfeature, so don't require them here.
run-native bin *app_args:
    @zig build run -Dplatform=native -Dbin={{ bin }} '-Darg={{ app_args }}'

# General runner (qemu/spike/nemu/etc.)
run platform target feature bin *app_args:
    @zig build run -Dplatform={{ platform }} -Dtarget={{ target }} -Dfeature={{ feature }} -Dbin={{ bin }} '-Darg={{ app_args }}'

clean:
    @rm -rf zig-out

clean-all:
    @rm -rf zig-out .zig-cache
