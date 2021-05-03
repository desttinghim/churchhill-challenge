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
    left: ?*@This() = null,
    right: ?*@This() = null,

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
        depthslice = depthbuf[0 .. i * 2];
        var leftbuf: [100]u8 = undefined;
        var leftslice: []u8 = undefined;
        var rightbuf: [100]u8 = undefined;
        var rightslice: []u8 = undefined;
        if (self.left) |left| {
            leftslice = std.fmt.bufPrint(&leftbuf, "{}", .{left.point.id}) catch unreachable;
        } else {
            leftslice = std.fmt.bufPrint(&leftbuf, "None", .{}) catch unreachable;
        }
        if (self.right) |right| {
            rightslice = std.fmt.bufPrint(&rightbuf, "{}", .{right.point.id}) catch unreachable;
        } else {
            rightslice = std.fmt.bufPrint(&rightbuf, "None", .{}) catch unreachable;
        }
        std.log.warn("|{s: <20}id: {: >4}, left: {s: >5}, right: {s: >5}, x: {d: >8.2}, y: {d: >8.2}", .{
            depthslice,
            self.point.id,
            leftslice,
            rightslice,
            self.point.x,
            self.point.y,
        });
    }
};

const NNSRes = struct {
    node: *KDNode,
    dist: f32,
};

fn super_key_compare(axis: Axis, point1: *Point, point2: *Point) f32 {
    var diff: f32 = 0;
    switch (axis) {
        .Horizontal => {
            diff = point1.x - point2.x;
            if (diff != 0) {
                return diff;
            }
            diff = point1.y - point2.y;
            if (diff != 0) {
                return diff;
            }
        },
        .Vertical => {
            diff = point1.y - point2.y;
            if (diff != 0) {
                return diff;
            }
            diff = point1.x - point2.x;
            if (diff != 0) {
                return diff;
            }
        },
    }
    return diff;
}

fn super_key_compare_sort(axis: Axis, point1: *Point, point2: *Point) bool {
    return super_key_compare(axis, point1, point2) < 0;
}

fn remove_duplicates(axis: Axis, points: []*Point) []*Point {
    var end: usize = 0;
    var i: usize = 1;
    while (i < points.len) : (i += 1) {
        const compare = super_key_compare(axis, points[i], points[i - 1]);
        if (compare < 0) {
            std.debug.panic("Sort failure! {} {} \n{}\n{}", .{ axis, compare, points[i], points[i - 1] });
        } else if (compare > 0) {
            end += 1;
            points[end] = points[i];
        }
    }
    return points[0..end];
}

pub const KDTree = struct {
    root: ?*KDNode,
    nodelist: std.ArrayList(KDNode),
    area: Rect,

    pub fn deinit(self: *@This()) void {
        const t = tracy.trace(@src());
        defer t.end();
        self.root = null;
        self.nodelist.deinit();
    }

    pub fn print(self: *@This()) void {
        const t = tracy.trace(@src());
        defer t.end();
        if (self.root) |root| {
            root.printAll(0);
        }
    }

    /// Takes an allocator and a slice of KDData to make a k-d tree of. Returns
    /// a KDTree.
    pub fn kdtree(allocator: *std.mem.Allocator, datalist: []Point) !@This() {
        const t = tracy.trace(@src());
        defer t.end();
        var self = @This(){
            .root = null,
            .nodelist = try std.ArrayList(KDNode).initCapacity(allocator, datalist.len),
            .area = .{ .lx = 0, .ly = 0, .hx = 0, .hy = 0 },
        };
        var xsort = try allocator.alloc(*Point, datalist.len);
        defer allocator.free(xsort);
        var ysort = try allocator.alloc(*Point, datalist.len);
        defer allocator.free(ysort);
        for (datalist) |_, i| {
            xsort[i] = &datalist[i];
            ysort[i] = &datalist[i];
        }
        // const mdat = datalist[median];

        // if (!self.area.contains_point(mdat)) {
        //     self.area.lx = std.math.min(mdat.x, self.area.lx);
        //     self.area.ly = std.math.min(mdat.y, self.area.ly);
        //     self.area.hx = std.math.max(mdat.x, self.area.hx);
        //     self.area.hy = std.math.max(mdat.y, self.area.hy);
        // }

        std.sort.sort(*Point, xsort, Axis.Horizontal, super_key_compare_sort);
        var xsort_dedup = remove_duplicates(Axis.Horizontal, xsort);
        std.sort.sort(*Point, ysort, Axis.Vertical, super_key_compare_sort);
        var ysort_dedup = remove_duplicates(Axis.Vertical, ysort);

        var temp = try allocator.alloc(*Point, xsort_dedup.len);
        defer allocator.free(temp);

        std.log.warn("{s:-^100}", .{"xsort"});
        for (xsort) |x| {
            x.print();
        }
        std.log.warn("{s:-^100}", .{"ysort"});
        for (ysort) |y| {
            y.print();
        }

        self.root = try self._kdtree(temp, xsort_dedup, ysort_dedup, 0);
        return self;
    }

    // Recursive algorithm to build the k-d tree
    fn _kdtree(self: *@This(), temp: []*Point, xsort: []*Point, ysort: []*Point, depth: usize) anyerror!?*KDNode {
        if (xsort.len == 0) return null;
        std.debug.assert(xsort.len == ysort.len);

        const axis: Axis = if (depth % 2 == 0) .Horizontal else .Vertical;

        var node = self.nodelist.addOneAssumeCapacity();
        std.log.warn("depth: {} -------------", .{depth});
        std.log.warn("{s:-^100}", .{"xsort"});
        for (xsort) |x| {
            x.print();
        }
        std.log.warn("{s:-^100}", .{"ysort"});
        for (ysort) |y| {
            y.print();
        }

        if (xsort.len == 1) {
            std.log.warn("1 node case", .{});
            node.* = .{
                .point = xsort[0].*,
            };
        } else if (xsort.len == 2) {
            std.log.warn("2 node case", .{});
            var node2 = self.nodelist.addOneAssumeCapacity();
            node2.* = .{
                .point = xsort[1].*,
            };
            node.* = .{
                .point = xsort[0].*,
                .right = node2,
            };
        } else if (xsort.len == 3) {
            std.log.warn("3 node case", .{});
            var node2 = self.nodelist.addOneAssumeCapacity();
            var node3 = self.nodelist.addOneAssumeCapacity();
            node2.* = .{
                .point = xsort[0].*,
            };
            node3.* = .{
                .point = xsort[2].*,
            };
            node.* = .{
                .point = xsort[1].*,
                .left = node2,
                .right = node3,
            };
        } else if (xsort.len > 3) {
            const median = xsort.len / 2;
            node.* = .{
                .point = xsort[median].*,
            };

            std.mem.copy(*Point, temp, xsort);

            var lower: usize = 0;
            var upper: usize = median;
            var j: usize = 0;
            std.log.warn("Splitting, len {} median: {} axis: {}", .{ xsort.len, median, axis });
            node.point.print();
            while (j < ysort.len) : (j += 1) {
                var compare = super_key_compare(axis, ysort[j], &node.point);
                // ysort[j].print();
                // node.point.print();
                if (compare < 0) {
                    std.log.warn("lower compare {:8.2} {}", .{ compare, j });
                    xsort[lower] = ysort[j];
                    lower += 1;
                } else if (compare > 0) {
                    std.log.warn("upper compare {:8.2} {}", .{ compare, j });
                    xsort[upper] = ysort[j];
                    upper += 1;
                }
            }
            // std.log.warn("depth: {} lower {} upper {} -------------", .{ depth, lower, upper });

            std.mem.copy(*Point, ysort, temp);

            node.left = try self._kdtree(
                temp[0..lower],
                xsort[0..lower],
                ysort[0..lower],
                depth + 1,
            );
            node.right = try self._kdtree(
                temp[median + 1 .. upper],
                xsort[median + 1 .. upper],
                ysort[median + 1 .. upper],
                depth + 1,
            );
        }

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
        if (rect.contains_point(node.point)) {
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
