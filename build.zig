const Builder = @import("std").build.Builder;
const deps = @import("deps.zig");

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .glibc_version = .{
                .major = 2,
                .minor = 18,
            },
        },
    });
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("benchmark", "src/benchmark.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    const lib = b.addSharedLibrary("zig_louis", "src/main.zig", .unversioned);
    lib.setTarget(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    });
    lib.setBuildMode(mode);
    lib.addPackagePath("tracy", "src/tracy_dummy.zig");
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.setTarget(target);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const run_cmd = exe.run();
    const run_step = b.step("run", "Run benchmark");
    run_step.dependOn(&run_cmd.step);

    const tracy = b.option(bool, "tracy", "Enable Tracy integration. Supply path to Tracy Source") orelse false;
    if (tracy) {
        exe.linkSystemLibraryName("c++");
        deps.addAllTo(exe);
        main_tests.linkSystemLibraryName("c++");
        deps.addAllTo(main_tests);
    } else {
        exe.addPackagePath("tracy", "src/tracy_dummy.zig");
        main_tests.addPackagePath("tracy", "src/tracy_dummy.zig");
    }
}
