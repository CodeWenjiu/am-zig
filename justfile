_default:
    @just --list

# Internal helper:
# - forwards any extra CLI tokens after the step name directly to `zig build`.
# - this lets you pass BOTH:
#   * runtime args (after `--`) for native, and
#   * build option `-Darg="..."` for bare-metal,

# using the same `just run ... -- ...` shape.
_zig platform target *zig_args:
    @zig build {{ target }} -Dplatform={{ platform }} {{ zig_args }}

build platform isa *zig_args:
    @just _zig {{ platform }} build -Disa={{ isa }} {{ zig_args }}

dump platform isa *zig_args:
    @just _zig {{ platform }} dump -Disa={{ isa }} {{ zig_args }}

# Unified argument passing (simplified):
# - You always pass app args after `--` and `just` converts them into `-Darg="..."`.
#
# Examples:
#   just run native ignored -- foo bar --name=Zig
#   just run spike  rv32i   -- foo bar --name=Zig
#
# Notes:
# - This is a *simple* join. It does not add quoting/escaping. Avoid spaces inside
#   a single argument (use key=value or --flag=value forms).

# - `isa` is ignored for native by the build script, but kept for a uniform CLI.
run platform isa *app_args:
    @zig build run -Dplatform={{ platform }} -Disa={{ isa }} '-Darg={{ app_args }}'

clean:
    @rm -rf zig-out

clean-all:
    @rm -rf zig-out .zig-cache
