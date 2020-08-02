const Builder = @import("std").build.Builder;
const std = @import("std");

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .abi = .gnu,
        },
    });
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("pingpong", "example-src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    const hzzp = std.build.Pkg{
        .name = "hzzp",
        .path = "./lib/hzzp/src/main.zig",
    };

    exe.addPackage(.{
        .name = "zigcord",
        .path = "./src/zigcord.zig",
        .dependencies = &[_]std.build.Pkg{
            .{
                .name = "zig-network",
                .path = "./lib/zig-network/network.zig",
            },
            .{
                .name = "bearssl",
                .path = "./lib/zig-bearssl/bearssl.zig",
            }, 
            hzzp,
            .{
                .name = "wz",
                .path = "./lib/wz/src/main.zig",
                .dependencies = &[_]std.build.Pkg{hzzp},
            },
        },
    });

    @import("/lib/zig-bearssl/bearssl.zig").linkBearSSL("./lib/zig-bearssl", exe, target);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
