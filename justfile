_default:
    @just --list

_zig platform args:
    @zig build {{ args }} -Dplatform={{ platform }}

build platform isa:
    @just _zig {{ platform }} "build -Disa={{ isa }}"

dump platform isa:
    @just _zig {{ platform }} "dump -Disa={{ isa }}"

run platform isa:
    @just _zig {{ platform }} "run -Disa={{ isa }}"

clean:
    @rm -rf zig-out

clean-all:
    @rm -rf zig-out .zig-cache
