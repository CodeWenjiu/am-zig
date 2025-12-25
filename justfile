# Default to building native
default: build

# Build the project.
build platform="native":
    @zig build -Dplatform={{ platform }} -Disa=rv32i

# Generate assembly dump
dump platform="nemu":
    @zig build dump -Dplatform={{ platform }} -Disa=rv32i

# Run the native application
run:
    @zig build run -Dplatform=native

clean:
    @rm -rf zig-out .zig-cache
