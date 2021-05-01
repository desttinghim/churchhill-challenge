const std = @import("std");
const testing = std.testing;

pub const Point = packed struct {
    id: i8,
    rank: i32,
    x: f32,
    y: f32,

    fn print(self: @This()) void {
        std.log.warn("id: {}, rank: {}, x: {d}, y: {d}", .{ self.id, self.rank, self.x, self.y });
    }
};

pub const Rect = packed struct {
    lx: f32,
    ly: f32,
    hx: f32,
    hy: f32,

    fn print(self: @This()) void {
        std.log.warn("lx: {d}, ly: {d}, hx: {d}, hy: {d}", .{ self.lx, self.ly, self.hx, self.hy });
    }
};

const KDNode = struct {
    point: Point,
    left: ?*@This(),
    right: ?*@This(),
};

fn kd_cmp(axis: usize, lhs: KDNode, rhs: KDNode) bool {
    return if (axis == 0) lhs.point.x < rhs.point.x else lhs.point.y < lhs.point.y;
}

fn kdtree(point_list: []KDNode, depth: usize) ?*KDNode {
    if (point_list.len == 0) return null;

    const axis = depth % 2;

    std.sort.sort(KDNode, point_list, axis, kd_cmp);
    const median = point_list.len / 2;

    point_list[median].left = kdtree(point_list[0..median], depth + 1);
    if (point_list[median + 1 ..].len >= 1) {
        point_list[median].right = kdtree(point_list[median + 1 ..], depth + 1);
    }
    return &point_list[median];
}

fn dist_squared(p1: Point, p2: Point) f32 {
    const a = p2.x - p1.x;
    const b = p2.y - p1.y;
    return a * a + b * b;
}

const NNSRes = struct { node: *KDNode, dist: f32 };

// TODO: Move into KDTree struct, use indices instead of pointers
fn nns(node: ?*KDNode, point: Point, depth: usize) ?NNSRes {
    if (node == null) return null;
    const axis = depth % 2;
    var best_node = node.?;
    var best_dist = dist_squared(point, best_node.point);

    var new: ?NNSRes = null;

    if (axis == 0) {
        new = if (point.x > best_node.point.x)
            nns(best_node.left, point, depth + 1)
        else
            nns(best_node.right, point, depth + 1);
    } else {
        new = if (point.y > best_node.point.y)
            nns(best_node.left, point, depth + 1)
        else
            nns(best_node.right, point, depth + 1);
    }

    if (new) |n| {
        if (n.dist < best_dist) {
            best_dist = n.dist;
            best_node = n.node;
        }
    }

    return NNSRes{
        .node = best_node,
        .dist = best_dist,
    };
}

const KDTree = struct {
    nodes: []KDNode,
    allocator: *std.mem.Allocator,
    root: *KDNode,

    fn init(allocator: *std.mem.Allocator, pointlist: []const Point) !@This() {
        var nodes = try allocator.alloc(KDNode, pointlist.len);

        for (pointlist) |point, i| {
            nodes[i].point = point;
            nodes[i].left = null;
            nodes[i].right = null;
        }

        // if (pointlist.len <= 1) return @This(){ .nodes = nodes, .allocator = allocator, .root = .nodes[0] };

        std.sort.sort(KDNode, nodes, @as(usize, 0), kd_cmp);
        const median = nodes.len / 2;
        nodes[median].left = kdtree(nodes[0..median], 1);
        nodes[median].right = kdtree(nodes[median + 1 ..], 1);

        return @This(){
            .nodes = nodes,
            .allocator = allocator,
            .root = &nodes[median],
        };
    }

    fn print(self: *@This()) void {
        const ptr = @ptrToInt(self.nodes.ptr) - 1;
        std.log.warn("\n{}", .{ptr});
        for (self.nodes) |node, i| {
            const left_ptr = @ptrToInt(node.left);
            const left_i = if (node.left != null)
                ((left_ptr - ptr) / @sizeOf(KDNode)) + 1
            else
                0;

            const right_ptr = @ptrToInt(node.right);
            const right_i = if (node.right != null)
                ((right_ptr - ptr) / @sizeOf(KDNode)) + 1
            else
                0;
            std.log.warn("{}: point {}, left {}, right {}", .{ i + 1, node.point, left_i, right_i });
        }
    }

    fn nearest_neighbor(self: *@This(), point: Point) Point {
        self.print();
        if (nns(self.root, point, 0)) |res| {
            return res.node.point;
        } else {
            return self.root.point;
        }
    }

    fn deinit(self: @This()) void {
        self.allocator.free(self.nodes);
    }
};

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

const SearchContext = struct {
    points: []Point,
    pointlist: std.ArrayList(Point),
    // kdtree: KDTree,
};

export fn create(points_begin: [*]const Point, points_end: *const Point) callconv(.C) *SearchContext {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var len = (@ptrToInt(points_end) - @ptrToInt(points_begin)) / @sizeOf(Point);
    var sc = gpa.allocator.create(SearchContext) catch |e| @panic("Out of memory!");

    sc.points = gpa.allocator.dupe(Point, points_begin[0..len]) catch |e| @panic("Out of memory!");
    sc.pointlist = std.ArrayList(Point).init(&gpa.allocator);
    // sc.kdtree = KDTree.init(&gpa.allocator, sc.points) catch |e| @panic("Out of memory!");

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
    var pointlist = &sc.pointlist;
    defer pointlist.shrinkRetainingCapacity(0);
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
    sc.pointlist.deinit();
    gpa.allocator.free(sc.points);
    gpa.allocator.destroy(sc);
    _ = gpa.deinit();
    return null;
}

test "Algorithm regression test" {
    const test_points = @import("test_data.zig").test_points;
    const tests = @import("test_data.zig").tests;

    var sc = create(&test_points, @intToPtr(*const Point, @ptrToInt(&test_points) + test_points.len * @sizeOf(Point)));

    for (tests) |search_test, i| {
        var buf = try std.testing.allocator.alloc(Point, search_test.count);
        defer std.testing.allocator.free(buf);
        var test_count = search(sc, &search_test.rect, @intCast(i32, search_test.count), buf.ptr);
        std.testing.expectEqual(@intCast(i32, search_test.actual), test_count);
        std.testing.expectEqualSlices(Point, search_test.items, buf[0..@intCast(usize, test_count)]);
    }

    var res = destroy(sc);

    std.testing.expectEqual(@as(?*SearchContext, null), res);
}

test "kdtree functionality test" {
    const test_points: [10]Point = .{
        Point{ .id = 0, .rank = 0, .x = 10, .y = 10 },
        Point{ .id = 0, .rank = 0, .x = -11, .y = -11 },
        Point{ .id = 0, .rank = 0, .x = 11, .y = -11 },
        Point{ .id = 0, .rank = 0, .x = 40, .y = 10 },
        Point{ .id = 0, .rank = 0, .x = 40, .y = -10 },
        Point{ .id = 0, .rank = 0, .x = -40, .y = 10 },
        Point{ .id = 0, .rank = 0, .x = -40, .y = -10 },
        Point{ .id = 0, .rank = 0, .x = 70, .y = 0 },
        Point{ .id = 0, .rank = 0, .x = -70, .y = -70 },
        Point{ .id = 0, .rank = 0, .x = -70, .y = 70 },
    };

    var tree = try KDTree.init(std.testing.allocator, &test_points);
    defer tree.deinit();

    std.testing.expectEqual(test_points[0], tree.nearest_neighbor(Point{ .x = 0, .y = 0, .rank = 0, .id = 0 }));
    const nn = tree.nearest_neighbor(Point{ .x = 90, .y = 0, .rank = 0, .id = 0 });
    std.log.warn("{}", .{nn});
}
