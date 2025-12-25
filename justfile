build:
    @zig build

dump: build
    @zig build dump

clean:
    @rm -rf zig-out
