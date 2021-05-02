const std = @import("std");
const testing = std.testing;
const kd = @import("kdtree.zig");
const tracy = @import("tracy");

pub const Point = packed struct {
    id: i8,
    rank: i32,
    x: f32,
    y: f32,

    pub fn print(self: @This()) void {
        std.log.warn("id: {: >4}, rank: {: >4}, x: {d: >8.2}, y: {d: >8.2}", .{ self.id, self.rank, self.x, self.y });
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
};

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

const SearchContext = struct {
    points: []Point,
    pointlist: std.ArrayList(Point),
    kdtree: kd.KDTree,
    querylist: std.ArrayList(usize),
};

pub export fn create(points_begin: [*]const Point, points_end: *const Point) callconv(.C) *SearchContext {
    const t = tracy.trace(@src());
    defer t.end();
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var len = (@ptrToInt(points_end) - @ptrToInt(points_begin)) / @sizeOf(Point);
    var sc = gpa.allocator.create(SearchContext) catch |e| @panic("Out of memory!");

    sc.points = gpa.allocator.dupe(Point, points_begin[0..len]) catch |e| @panic("Out of memory!");
    sc.pointlist = std.ArrayList(Point).init(&gpa.allocator);
    sc.querylist = std.ArrayList(usize).init(&gpa.allocator);

    var datalist = gpa.allocator.alloc(kd.KDData, sc.points.len) catch |e| @panic("Out of memory!");
    defer gpa.allocator.free(datalist);
    for (sc.points) |point, i| {
        const ti = tracy.trace(@src());
        defer ti.end();
        datalist[i] = .{ .pos = .{ .x = point.x, .y = point.y }, .id = i };
    }

    sc.kdtree = kd.KDTree.kdtree(&gpa.allocator, datalist) catch |e| @panic("Couldn't init k-d tree");
    // sc.kdtree.print();

    return sc;
}

fn point_cmp(ctx: u0, lhs: Point, rhs: Point) bool {
    return lhs.rank < rhs.rank;
}

// fn point_is_inside(p: Point, rect: Rect) bool {
//     return p.x > rect.lx and
//         p.x < rect.hx and
//         p.y > rect.ly and
//         p.y < rect.hy;
// }

pub export fn search(sc: *SearchContext, rect: *const Rect, count: i32, out_points: [*]Point) callconv(.C) i32 {
    const t = tracy.trace(@src());
    defer t.end();
    var pointlist = &sc.pointlist;
    defer pointlist.shrinkRetainingCapacity(0);
    var querylist = &sc.querylist;
    defer querylist.shrinkRetainingCapacity(0);

    // for (sc.points) |point| {
    //     if (point_is_inside(point, rect.*)) {
    //         pointlist.append(point) catch |e| @panic("Out of memory!");
    //     }
    // }

    sc.kdtree.range(querylist, kd.Rect.init(rect.lx, rect.ly, rect.hx, rect.hy)) catch |e| @panic("Couldn't query");

    for (querylist.items) |match, i| {
        // std.log.warn("{: >2}: {: >5}", .{ i, match });
        pointlist.append(sc.points[match]) catch |e| @panic("Couldn't append to pointlist");
    }

    std.sort.sort(Point, pointlist.items, @as(u0, 0), point_cmp);
    const mincount = std.math.min(@intCast(usize, count), pointlist.items.len);
    std.mem.copy(Point, out_points[0..mincount], pointlist.items[0..mincount]);
    return @intCast(i32, mincount);
}

pub export fn destroy(sc: *SearchContext) callconv(.C) ?*SearchContext {
    const t = tracy.trace(@src());
    defer t.end();
    sc.pointlist.deinit();
    sc.querylist.deinit();
    sc.kdtree.deinit();
    gpa.allocator.free(sc.points);
    gpa.allocator.destroy(sc);
    _ = gpa.deinit();
    return null;
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
        // search_test.rect.print();
        // std.log.warn("test_data", .{});
        // for (search_test.items) |point, idx| {
        //     const t2 = tracy.trace(@src());
        //     defer t2.end();
        //     point.print();
        // }
        // std.log.warn("k-d tree query", .{});
        // for (buf) |res, idx| {
        //     const t2 = tracy.trace(@src());
        //     defer t2.end();
        //     res.print();
        // }
        std.testing.expectEqual(@intCast(i32, search_test.actual), test_count);
        std.testing.expectEqualSlices(Point, search_test.items, buf[0..@intCast(usize, test_count)]);
    }

    var res = destroy(sc);

    std.testing.expectEqual(@as(?*SearchContext, null), res);
}
