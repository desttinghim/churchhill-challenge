const std = @import("std");

// A 2Dimensional k-d tree

pub const Pos = struct {
    x: f32,
    y: f32,

    fn dist_squared(p1: Pos, p2: Pos) f32 {
        const a = p2.x - p1.x;
        const b = p2.y - p1.y;
        return a * a + b * b;
    }
};

pub const KDData = struct {
    id: usize,
    pos: Pos,

    fn cmp(axis: Axis, lhs: @This(), rhs: @This()) bool {
        return switch (axis) {
            .Horizontal => lhs.pos.x < rhs.pos.x,
            .Vertical => lhs.pos.y < lhs.pos.y,
        };
    }
};

pub const Axis = enum {
    Horizontal,
    Vertical,
};

pub const KDNode = struct {
    pos: Pos,
    id: usize,
    left: ?*@This(),
    right: ?*@This(),

    fn deinit(self: *@This(), allocator: *std.mem.Allocator) void {
        if (self.left) |left| left.deinit(allocator);
        if (self.right) |right| right.deinit(allocator);
        allocator.destroy(self);
    }

    fn printAll(self: *@This(), depth: usize) void {
        self.print(depth);
        if (self.left) |left| left.printAll(depth + 1);
        if (self.right) |right| right.printAll(depth + 1);
    }

    fn print(self: *@This(), depth: usize) void {
        var depthbuf: [100]u8 = undefined;
        var depthslice: []u8 = undefined;
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            depthbuf[i * 2] = '-';
            depthbuf[i * 2 + 1] = '-';
        }
        depthslice = depthbuf[0..i];
        var leftbuf: [100]u8 = undefined;
        var leftslice: []u8 = undefined;
        var rightbuf: [100]u8 = undefined;
        var rightslice: []u8 = undefined;
        if (self.left) |left| {
            leftslice = std.fmt.bufPrint(&leftbuf, "{}", .{left.id}) catch unreachable;
        } else {
            leftslice = std.fmt.bufPrint(&leftbuf, "None", .{}) catch unreachable;
        }
        if (self.right) |right| {
            rightslice = std.fmt.bufPrint(&rightbuf, "{}", .{right.id}) catch unreachable;
        } else {
            rightslice = std.fmt.bufPrint(&rightbuf, "None", .{}) catch unreachable;
        }
        std.log.warn("|{s}id: {}, left: {s}, right: {s}, x: {d}, y: {d}", .{
            depthslice,
            self.id,
            leftslice,
            rightslice,
            self.pos.x,
            self.pos.y,
        });
    }
};

const NNSRes = struct {
    node: *KDNode,
    dist: f32,
};

pub const KDTree = struct {
    root: ?*KDNode,
    allocator: *std.mem.Allocator,

    pub fn deinit(self: @This()) void {
        if (self.root) |root| {
            root.deinit(self.allocator);
        }
    }

    pub fn print(self: *@This()) void {
        if (self.root) |root| {
            root.printAll(0);
        }
    }

    /// Takes an allocator and a slice of KDData to make a k-d tree of. Returns
    /// a KDTree.
    pub fn kdtree(allocator: *std.mem.Allocator, datalist: []KDData) !@This() {
        var self = @This(){
            .root = null,
            .allocator = allocator,
        };
        self.root = try self._kdtree(datalist, 0);
        return self;
    }

    // Recursive algorithm to build the k-d tree
    fn _kdtree(self: *@This(), datalist: []KDData, depth: usize) anyerror!?*KDNode {
        if (datalist.len == 0) return null;

        const axis: Axis = if (depth % 2 == 0) .Horizontal else .Vertical;

        std.sort.sort(KDData, datalist, axis, KDData.cmp);
        const median = datalist.len / 2;

        var node = try self.allocator.create(KDNode);
        node.* = .{
            .pos = datalist[median].pos,
            .id = datalist[median].id,
            .left = try self._kdtree(datalist[0..median], depth + 1),
            .right = try self._kdtree(datalist[median + 1 ..], depth + 1),
        };
        return node;
    }

    /// Does a nearest neighbor search on the kdtree. Returns the id of the
    /// node that is nearest to the given point, or null if the tree is empty.
    pub fn nns(self: *@This(), pos: Pos) !usize {
        if (self.root) |root| {
            var nns_res = self._nns(self.root, pos, 0);
            if (nns_res) |res| {
                return res.node.id;
            } else {
                // If there is anything in the tree, there should be a best
                // result and make it impossible to reach this code.
                unreachable;
            }
        }
        return error.EmptyTree;
    }

    // Recursive algorithm to search the k-d tree
    fn _nns(self: *@This(), node: ?*KDNode, pos: Pos, depth: usize) ?NNSRes {
        if (node == null) return null;
        const axis: Axis = if (depth % 2 == 0) .Horizontal else .Vertical;
        var best_node = node.?;
        var best_dist = best_node.pos.dist_squared(pos);

        var new: ?NNSRes = null;

        if (axis == .Horizontal) {
            new = if (pos.x < best_node.pos.x)
                self._nns(best_node.left, pos, depth + 1)
            else
                self._nns(best_node.right, pos, depth + 1);
        } else if (axis == .Vertical) {
            new = if (pos.y < best_node.pos.y)
                self._nns(best_node.left, pos, depth + 1)
            else
                self._nns(best_node.right, pos, depth + 1);
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
};

test "k-d tree functionality test" {
    const test_points: [10]Pos = .{
        Pos{ .x = 10, .y = 10 },
        Pos{ .x = -11, .y = -11 },
        Pos{ .x = 11, .y = -11 },
        Pos{ .x = 40, .y = 10 },
        Pos{ .x = 40, .y = -10 },
        Pos{ .x = -40, .y = 10 },
        Pos{ .x = -40, .y = -10 },
        Pos{ .x = 70, .y = 0 },
        Pos{ .x = -70, .y = -70 },
        Pos{ .x = -70, .y = 70 },
    };

    var datalist: [10]KDData = undefined;
    for (test_points) |tp, i| {
        datalist[i] = .{ .pos = .{ .x = tp.x, .y = tp.y }, .id = i };
    }

    var tree = try KDTree.kdtree(std.testing.allocator, &datalist);
    defer tree.deinit();

    // tree.print();

    {
        var id = try tree.nns(Pos{ .x = 0, .y = 0 });
        var result = test_points[id];
        std.testing.expectEqual(id, 0);
    }

    {
        var id = try tree.nns(Pos{ .x = 90, .y = 0 });
        var result = test_points[id];
        std.testing.expectEqual(id, 7);
    }

    {
        var id = try tree.nns(Pos{ .x = 25, .y = -25 });
        var result = test_points[id];
        std.testing.expectEqual(id, 2);
    }
}
