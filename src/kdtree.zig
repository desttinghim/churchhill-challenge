const std = @import("std");
const tracy = @import("tracy");
const Heap = @import("heap.zig");
const Point = @import("main.zig").Point;
const Rect = @import("main.zig").Rect;
const MinHeap = @import("main.zig").MinHeap;

// A 2Dimensional k-d tree

pub const Axis = enum {
    Horizontal,
    Vertical,
};

pub const KDNode = struct {
    point: Point,
    left: ?*@This(),
    right: ?*@This(),
};

const NNSRes = struct {
    node: *KDNode,
    dist: f32,
};

pub const KDTree = struct {
    root: ?*KDNode,
    nodelist: std.ArrayList(KDNode),
    // area: Rect,

    pub fn deinit(self: *@This()) void {
        const t = tracy.trace(@src());
        defer t.end();
        self.root = null;
        self.nodelist.deinit();
    }

    /// Takes an allocator and a slice of KDData to make a k-d tree of. Returns
    /// a KDTree.
    pub fn kdtree(allocator: *std.mem.Allocator, datalist: []Point) !@This() {
        const t = tracy.trace(@src());
        defer t.end();
        var self = @This(){
            .root = null,
            .nodelist = try std.ArrayList(KDNode).initCapacity(allocator, datalist.len),
            // .area = .{ .lx = 0, .ly = 0, .hx = 0, .hy = 0},
        };
        self.root = try self._kdtree(datalist, 0);
        return self;
    }

    // Recursive algorithm to build the k-d tree
    fn _kdtree(self: *@This(), datalist: []Point, depth: usize) anyerror!?*KDNode {
        if (datalist.len == 0) return null;

        const axis: Axis = if (depth % 2 == 0) .Horizontal else .Vertical;

        std.sort.sort(Point, datalist, axis, Point.cmp);
        const median = datalist.len / 2;
        const mdat = datalist[median];

        // if (!self.area.contains(mdat.pos)) {
        //     self.area.low.x = std.math.min(mdat.pos.x, self.area.low.x);
        //     self.area.low.y = std.math.min(mdat.pos.y, self.area.low.y);
        //     self.area.high.x = std.math.max(mdat.pos.x, self.area.high.x);
        //     self.area.high.y = std.math.max(mdat.pos.y, self.area.high.y);
        // }

        var node = self.nodelist.addOneAssumeCapacity();
        node.* = .{
            .point = mdat,
            .left = try self._kdtree(datalist[0..median], depth + 1),
            .right = try self._kdtree(datalist[median + 1 ..], depth + 1),
        };
        return node;
    }

    /// Does a nearest neighbor search on the kdtree. Returns the id of the
    /// node that is nearest to the given point, or null if the tree is empty.
    pub fn nns(self: *@This(), x: f32, y: f32) !Point {
        const t = tracy.trace(@src());
        defer t.end();
        if (self.root) |root| {
            var nns_res = self._nns(self.root, x, y, 0);
            if (nns_res) |res| {
                return res.node.point;
            } else {
                // If there is anything in the tree, there should be a best
                // result and make it impossible to reach this code.
                unreachable;
            }
        }
        return error.EmptyTree;
    }

    // Recursive algorithm to search the k-d tree
    fn _nns(self: *@This(), node: ?*KDNode, x: f32, y: f32, depth: usize) ?NNSRes {
        if (node == null) return null;
        const axis: Axis = if (depth % 2 == 0) .Horizontal else .Vertical;
        var best_node = node.?;
        var best_dist = best_node.pos.dist_squared(x, y);

        var new: ?NNSRes = null;

        if (axis == .Horizontal) {
            new = if (pos.x < best_node.pos.x)
                self._nns(best_node.left, x, y, depth + 1)
            else
                self._nns(best_node.right, x, y, depth + 1);
        } else if (axis == .Vertical) {
            new = if (pos.y < best_node.pos.y)
                self._nns(best_node.left, x, y, depth + 1)
            else
                self._nns(best_node.right, x, y, depth + 1);
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

    pub fn range(self: *@This(), matches: *MinHeap, rect: Rect, count: usize) anyerror!void {
        const t = tracy.trace(@src());
        defer t.end();
        // if (!self.area.overlaps(rect)) {
        //     return;
        // }
        if (self.root) |root| {
            try self._query(matches, root, rect, count, 0);
            return;
        }
        return;
    }

    fn _query(self: *@This(), matches: *MinHeap, inode: ?*KDNode, rect: Rect, count: usize, depth: usize) anyerror!void {
        if (inode == null) return;
        const node = inode.?;
        if (rect.contains(node.point)) {
            if (matches.list.items.len < count) {
                try matches.insert(node.point);
            } else {
                _ = matches.insertExtract(node.point);
                // matches.insert(node.point)
            }
        }

        const axis: Axis = if (depth % 2 == 0) .Horizontal else .Vertical;
        switch (axis) {
            .Horizontal => {
                if (rect.lx < node.point.x) try self._query(matches, node.left, rect, count, depth + 1);
                if (rect.hx > node.point.x) try self._query(matches, node.right, rect, count, depth + 1);
            },
            .Vertical => {
                if (rect.ly < node.point.y) try self._query(matches, node.left, rect, count, depth + 1);
                if (rect.hy > node.point.y) try self._query(matches, node.right, rect, count, depth + 1);
            },
        }
    }
};

// test "k-d tree nearest neighbor search" {
//     const test_points: [10]Pos = .{
//         Pos{ .x = 10, .y = 10 },
//         Pos{ .x = -11, .y = -11 },
//         Pos{ .x = 11, .y = -11 },
//         Pos{ .x = 40, .y = 10 },
//         Pos{ .x = 40, .y = -10 },
//         Pos{ .x = -40, .y = 10 },
//         Pos{ .x = -40, .y = -10 },
//         Pos{ .x = 70, .y = 0 },
//         Pos{ .x = -70, .y = -70 },
//         Pos{ .x = -70, .y = 70 },
//     };

//     var datalist: [10]KDData = undefined;
//     for (test_points) |tp, i| {
//         datalist[i] = .{ .pos = .{ .x = tp.x, .y = tp.y }, .id = i };
//     }

//     var tree = try KDTree.kdtree(std.testing.allocator, &datalist);
//     defer tree.deinit();

//     // tree.print();

//     {
//         var id = try tree.nns(Pos{ .x = 0, .y = 0 });
//         var result = test_points[id];
//         std.testing.expectEqual(id, 0);
//     }

//     {
//         var id = try tree.nns(Pos{ .x = 90, .y = 0 });
//         var result = test_points[id];
//         std.testing.expectEqual(id, 7);
//     }

//     {
//         var id = try tree.nns(Pos{ .x = 25, .y = -25 });
//         var result = test_points[id];
//         std.testing.expectEqual(id, 2);
//     }
// }

// test "k-d tree range query" {
//     const t = tracy.trace(@src());
//     defer t.end();
//     const test_points: [10]Pos = .{
//         Pos{ .x = 10, .y = 10 },
//         Pos{ .x = -11, .y = -11 },
//         Pos{ .x = 11, .y = -11 },
//         Pos{ .x = 40, .y = 10 },
//         Pos{ .x = 40, .y = -10 },
//         Pos{ .x = -40, .y = 10 },
//         Pos{ .x = -40, .y = -10 },
//         Pos{ .x = 70, .y = 0 },
//         Pos{ .x = -70, .y = -70 },
//         Pos{ .x = -70, .y = 70 },
//     };

//     var datalist: [10]KDData = undefined;
//     for (test_points) |tp, i| {
//         datalist[i] = .{ .pos = .{ .x = tp.x, .y = tp.y }, .id = i };
//     }

//     var tree = try KDTree.kdtree(std.testing.allocator, &datalist);
//     defer tree.deinit();

//     // tree.print();

//     {
//         var matches = std.ArrayList(usize).init(std.testing.allocator);
//         defer matches.deinit();
//         try tree.range(&matches, Rect.init(-50, -50, 5, 5));

//         std.testing.expectEqualSlices(usize, matches.items, &[_]usize{ 6, 1 });
//     }
// }
