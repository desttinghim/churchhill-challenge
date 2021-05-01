const std = @import("std");
const testing = std.testing;

const Point = packed struct {
    id: i8,
    rank: i32,
    x: f32,
    y: f32,

    fn print(self: @This()) void {
        std.log.debug("id: {}, rank: {}, x: {d}, y: {d}", .{ self.id, self.rank, self.x, self.y });
    }
};

const Rect = packed struct {
    lx: f32,
    ly: f32,
    hx: f32,
    hy: f32,

    fn print(self: @This()) void {
        std.log.debug("lx: {d}, ly: {d}, hx: {d}, hy: {d}", .{ self.lx, self.ly, self.hx, self.hy });
    }
};

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

const SearchContext = struct {
    points: []Point,
};

export fn create(points_begin: [*]Point, points_end: *Point) callconv(.C) *SearchContext {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var len = (@ptrToInt(points_end) - @ptrToInt(points_begin)) / @sizeOf(Point);
    var sc = gpa.allocator.create(SearchContext) catch |e| @panic("Out of memory!");

    sc.points = gpa.allocator.dupe(Point, points_begin[0..len]) catch |e| @panic("Out of memory!");

    return sc;
}

fn point_cmp(ctx: u0, lhs: Point, rhs: Point) bool {
    return lhs.rank < rhs.rank;
}

fn point_is_inside(p: Point, rect: Rect) bool {
    return p.x > rect.lx and
        p.x < rect.hx and
        p.y > rect.ly and
        p.y < rect.hy;
}

export fn search(sc: *SearchContext, rect: *const Rect, count: i32, out_points: [*]Point) callconv(.C) i32 {
    var pointlist = std.ArrayList(Point).init(&gpa.allocator);
    defer pointlist.deinit();
    for (sc.points) |point| {
        if (point_is_inside(point, rect.*)) {
            pointlist.append(point) catch |e| @panic("Out of memory!");
        }
    }
    std.sort.sort(Point, pointlist.items, @as(u0, 0), point_cmp);
    const mincount = std.math.min(@intCast(usize, count), pointlist.items.len);
    std.mem.copy(Point, out_points[0..mincount], pointlist.items[0..mincount]);
    return @intCast(i32, mincount);
}

export fn destroy(sc: *SearchContext) callconv(.C) ?*SearchContext {
    gpa.allocator.free(sc.points);
    gpa.allocator.destroy(sc);
    _ = gpa.deinit();
    return null;
}
