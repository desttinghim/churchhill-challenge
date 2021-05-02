const search = @import("main.zig");
const std = @import("std");
const tracy = @import("tracy");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var rng: std.rand.DefaultPrng = undefined;
var rand: *std.rand.Random = undefined;

pub fn main() !void {
    const t = tracy.trace(@src());
    defer t.end();

    rng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    rand = &rng.random;

    const test_width = rand.float(f32) * @intToFloat(f32, rand.intRangeLessThan(i32, 100, 9000));
    const test_height = rand.float(f32) * @intToFloat(f32, rand.intRangeLessThan(i32, 100, 9000));
    const lx = -(test_width / 2);
    const ly = -(test_height / 2);
    const hx = (test_width / 2);
    const hy = (test_height / 2);
    const test_rect = search.Rect{ .lx = lx, .ly = ly, .hx = hx, .hy = hy };

    const test_points = try get_test_points(test_rect, 1_000_000);
    defer gpa.allocator.free(test_points);
    const tests = try get_tests(test_rect, 1_000);
    defer gpa.allocator.free(tests);

    var sc = search.create(test_points.ptr, @intToPtr(*const search.Point, @ptrToInt(test_points.ptr) + test_points.len * @sizeOf(search.Point)));

    for (tests) |search_test, i| {
        const t1 = tracy.trace(@src());
        defer t1.end();
        var buf = try gpa.allocator.alloc(search.Point, search_test.count);
        defer gpa.allocator.free(buf);
        var test_count = search.search(sc, &search_test.rect, @intCast(i32, search_test.count), buf.ptr);
        // search_test.rect.print();
        // std.log.warn("k-d tree query", .{});
        // for (buf) |res, idx| {
        //     const t2 = tracy.trace(@src());
        //     defer t2.end();
        //     res.print();
        // }
    }

    var res = search.destroy(sc);
}

fn get_test_points(test_rect: search.Rect, num_points: usize) ![]search.Point {
    var points = try gpa.allocator.alloc(search.Point, num_points);
    const width = test_rect.hx - test_rect.lx;
    const height = test_rect.hy - test_rect.ly;

    for (points) |point, i| {
        points[i] = .{
            .id = rand.intRangeLessThan(i8, std.math.minInt(i8), std.math.maxInt(i8)),
            .rank = rand.intRangeLessThan(i32, 0, 100),
            .x = rand.float(f32) * width - test_rect.lx,
            .y = rand.float(f32) * height - test_rect.ly,
        };
    }

    return points;
}

const Test = struct {
    rect: search.Rect,
    count: usize,
};

fn get_tests(test_rect: search.Rect, num_tests: usize) ![]Test {
    var tests = try gpa.allocator.alloc(Test, num_tests);
    const width = test_rect.hx - test_rect.lx;
    const height = test_rect.hy - test_rect.ly;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const twidth = ((rand.float(f32) + 0.25) * 0.5) * width;
        const theight = ((rand.float(f32) + 0.25) * 0.5) * height;
        const x = rand.float(f32) * (width - twidth);
        const y = rand.float(f32) * (height - theight);
        tests[i] = .{
            .rect = search.Rect{ .lx = x, .ly = y, .hx = x + twidth, .hy = y + theight },
            .count = 20,
        };
    }

    return tests;
}
