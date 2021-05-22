const std = @import("std");
const testing = std.testing;
const kd = @import("kdtree.zig");
const tracy = @import("tracy");
const Heap = @import("heap.zig").Heap;
pub const MinHeap = Heap(Point, Point.heap_cmp);
const skiplist = @import("skiplist.zig");
const ArrayList = std.ArrayList;
const challenge = @import("challenge.zig");
const Point = challenge.Point;
const Rect = challenge.Rect;
const build_opt = @import("build_options");

usingnamespace comptime if (build_opt.algorithm == .cssl) @import("skiplist_main.zig").challenge_exports;

test "Robustness check" {
    const test_points = @import("test_data.zig").test_points;
    const tests = @import("test_data.zig").tests;

    var sc = create(&test_points, &test_points[0]);
    for (tests) |search_test, i| {
        const t1 = tracy.trace(@src());
        defer t1.end();
        var buf = try std.testing.allocator.alloc(Point, search_test.count);
        defer std.testing.allocator.free(buf);
        _ = search(sc, &search_test.rect, @intCast(i32, search_test.count), buf.ptr);
    }
    var res = destroy(sc);

    try std.testing.expectEqual(@as(?*SearchContext, null), res);
}

test "Algorithm regression test" {
    const t = tracy.trace(@src());
    defer t.end();
    const test_points = @import("test_data.zig").test_points;
    const tests = @import("test_data.zig").tests;

    var sc = create(&test_points, @intToPtr(*const Point, @ptrToInt(&test_points) + test_points.len * @sizeOf(Point)));

    for (tests) |search_test, i| {
        const t1 = tracy.trace(@src());
        defer t1.end();
        var buf = try std.testing.allocator.alloc(Point, search_test.count);
        defer std.testing.allocator.free(buf);
        var test_count = search(sc, &search_test.rect, @intCast(i32, search_test.count), buf.ptr);
        try std.testing.expectEqual(@intCast(i32, search_test.actual), test_count);
        std.testing.expectEqualSlices(Point, search_test.items, buf[0..@intCast(usize, test_count)]) catch |e| {
            std.log.warn("Search Rect: ", .{});
            search_test.rect.print();
            std.log.warn("Expected: ", .{});
            for (search_test.items) |point| {
                point.print();
            }
            std.log.warn("Results: ", .{});
            for (buf[0..@intCast(usize, test_count)]) |point| {
                point.print();
            }
            return e;
        };
    }

    var res = destroy(sc);

    try std.testing.expectEqual(@as(?*SearchContext, null), res);
}
