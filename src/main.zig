const std = @import("std");
const testing = std.testing;
const kd = @import("kdtree.zig");
const tracy = @import("tracy");
const Heap = @import("heap.zig").Heap;

pub const MinHeap = Heap(Point, Point.heap_cmp);

pub const Point = packed struct {
    id: i8,
    rank: i32,
    x: f32,
    y: f32,

    pub fn print(self: @This()) void {
        std.log.warn("id: {: >4}, rank: {: >4}, x: {d: >8.2}, y: {d: >8.2}", .{ self.id, self.rank, self.x, self.y });
    }

    fn dist_squared_point(p1: @This(), p2: @This()) f32 {
        const a = p2.x - p1.x;
        const b = p2.y - p1.y;
        return a * a + b * b;
    }

    pub fn dist_squared(p1: @This(), x: f32, y: f32) f32 {
        const a = x - p1.x;
        const b = y - p1.y;
        return a * a + b * b;
    }

    pub fn cmp(axis: kd.Axis, lhs: @This(), rhs: @This()) bool {
        return switch (axis) {
            .Horizontal => lhs.x < rhs.x,
            .Vertical => lhs.y < rhs.y,
        };
    }

    pub fn heap_cmp(lhs: @This(), rhs: @This()) bool {
        return lhs.rank < rhs.rank;
    }
};

pub const Rect = packed struct {
    lx: f32,
    ly: f32,
    hx: f32,
    hy: f32,

    pub fn print(self: @This()) void {
        std.log.warn("lx: {d}, ly: {d}, hx: {d}, hy: {d}", .{ self.lx, self.ly, self.hx, self.hy });
    }

    pub fn contains_point(self: Rect, pos: Point) bool {
        return pos.x > self.lx and
            pos.x < self.hx and
            pos.y > self.ly and
            pos.y < self.hy;
    }

    pub fn contains(self: Rect, x: f32, y: f32) bool {
        return x > self.lx and
            x < self.hx and
            y > self.ly and
            y < self.hy;
    }

    pub fn overlaps(self: Rect, other: Rect) bool {
        return self.contains(other.lx, other.ly) or
            self.contains(other.hx, other.hy) or
            other.contains(self.lx, self.ly) or
            other.contains(self.hx, self.hy);
    }
};

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

const SearchContext = struct {
    // points: []Point,
    // pointlist: std.ArrayList(Point),
    kdtree: kd.KDTree,
    heap: MinHeap,
};

pub export fn create(points_begin: [*]const Point, points_end: *const Point) callconv(.C) *SearchContext {
    const t = tracy.trace(@src());
    defer t.end();
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var len = (@ptrToInt(points_end) - @ptrToInt(points_begin)) / @sizeOf(Point);
    var sc = gpa.allocator.create(SearchContext) catch |e| @panic("Out of memory!");
    var points = gpa.allocator.dupe(Point, points_begin[0..len]) catch |e| @panic("Out of memory!");
    defer gpa.allocator.free(points);

    sc.heap = MinHeap.init(&gpa.allocator);

    sc.kdtree = kd.KDTree.kdtree(&gpa.allocator, points) catch |e| @panic("Couldn't init k-d tree");

    return sc;
}

fn point_cmp(ctx: u0, lhs: Point, rhs: Point) bool {
    return lhs.rank < rhs.rank;
}

pub export fn search(sc: *SearchContext, rect: *const Rect, count: i32, out_points: [*]Point) callconv(.C) i32 {
    const t = tracy.trace(@src());
    defer t.end();

    sc.kdtree.range(&sc.heap, rect.*, @intCast(usize, count)) catch |e| std.debug.panic("Couldn't query! {}", .{e});
    // sc.heap.print();
    defer sc.heap.clear();
    sc.kdtree.print();

    const mincount = std.math.min(@intCast(usize, count), sc.heap.list.items.len);
    std.mem.copy(Point, out_points[0..mincount], sc.heap.list.items[0..mincount]);
    std.sort.sort(Point, out_points[0..mincount], @as(u0, 0), point_cmp);
    return @intCast(i32, mincount);
}

pub export fn destroy(sc: *SearchContext) callconv(.C) ?*SearchContext {
    const t = tracy.trace(@src());
    defer t.end();
    sc.heap.deinit();
    sc.kdtree.deinit();
    gpa.allocator.destroy(sc);
    _ = gpa.deinit();
    return null;
}

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
        search_test.rect.print();
        std.log.warn("Expected: ", .{});
        for (search_test.items) |point| {
            point.print();
        }
        std.log.warn("Results: ", .{});
        for (buf[0..@intCast(usize, test_count)]) |point| {
            point.print();
        }
        try std.testing.expectEqual(@intCast(i32, search_test.actual), test_count);
        try std.testing.expectEqualSlices(Point, search_test.items, buf[0..@intCast(usize, test_count)]);
    }

    var res = destroy(sc);

    try std.testing.expectEqual(@as(?*SearchContext, null), res);
}
