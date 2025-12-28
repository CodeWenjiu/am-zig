_default:
    @just --list

_zig platform args:
    @ZIG_LOCAL_CACHE_DIR=.zig-cache/{{ platform }} zig build {{ args }} -Dplatform={{ platform }}

build platform isa:
    @just _zig {{ platform }} "build -Disa={{ isa }}"

dump platform isa:
    @just _zig {{ platform }} "dump -Disa={{ isa }}"

run:
    @just _zig native "run"

clean:
    @rm -rf zig-out

clean-all:
    @rm -rf zig-out .zig-cache
