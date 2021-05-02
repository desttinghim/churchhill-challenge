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

    fn print(self: *@This(), depth: usize) void {
        std.log.warn("depth: {}, id: {}, pos: {}", .{ depth, self.id, self.pos });
        if (self.left) |left| left.print(depth + 1);
        if (self.right) |right| right.print(depth + 1);
    }
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
            root.print(0);
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

    // Does a nearest neighbor search on the kdtree. Returns the id of the
    // node that is nearest to the given point.
    // pub fn nns(self: *@This(), pos: Pos) usize {}

    // Recursive algorithm to search the k-d tree
    // pub fn _nns() {}
};

// const KDNode = struct {
//     point: Point,
//     left: ?*@This(),
//     right: ?*@This(),
// };

// fn kd_cmp(axis: usize, lhs: KDNode, rhs: KDNode) bool {
//     return if (axis == 0) lhs.point.x < rhs.point.x else lhs.point.y < lhs.point.y;
// }

// fn kdtree(point_list: []KDNode, depth: usize) ?*KDNode {
//     if (point_list.len == 0) return null;

//     const axis = depth % 2;

//     std.sort.sort(KDNode, point_list, axis, kd_cmp);
//     const median = point_list.len / 2;

//     point_list[median].left = kdtree(point_list[0..median], depth + 1);
//     if (point_list[median + 1 ..].len >= 1) {
//         point_list[median].right = kdtree(point_list[median + 1 ..], depth + 1);
//     }
//     return &point_list[median];
// }

// const NNSRes = struct { node: *KDNode, dist: f32 };

// // TODO: Move into KDTree struct, use indices instead of pointers
// fn nns(node: ?*KDNode, point: Point, depth: usize) ?NNSRes {
//     if (node == null) return null;
//     const axis = depth % 2;
//     var best_node = node.?;
//     var best_dist = dist_squared(point, best_node.point);

//     var new: ?NNSRes = null;

//     if (axis == 0) {
//         new = if (point.x > best_node.point.x)
//             nns(best_node.left, point, depth + 1)
//         else
//             nns(best_node.right, point, depth + 1);
//     } else {
//         new = if (point.y > best_node.point.y)
//             nns(best_node.left, point, depth + 1)
//         else
//             nns(best_node.right, point, depth + 1);
//     }

//     if (new) |n| {
//         if (n.dist < best_dist) {
//             best_dist = n.dist;
//             best_node = n.node;
//         }
//     }

//     return NNSRes{
//         .node = best_node,
//         .dist = best_dist,
//     };
// }

// const KDTree = struct {
//     nodes: []KDNode,
//     allocator: *std.mem.Allocator,
//     root: *KDNode,

//     fn init(allocator: *std.mem.Allocator, pointlist: []const Point) !@This() {
//         var nodes = try allocator.alloc(KDNode, pointlist.len);

//         for (pointlist) |point, i| {
//             nodes[i].point = point;
//             nodes[i].left = null;
//             nodes[i].right = null;
//         }

//         // if (pointlist.len <= 1) return @This(){ .nodes = nodes, .allocator = allocator, .root = .nodes[0] };

//         std.sort.sort(KDNode, nodes, @as(usize, 0), kd_cmp);
//         const median = nodes.len / 2;
//         nodes[median].left = kdtree(nodes[0..median], 1);
//         nodes[median].right = kdtree(nodes[median + 1 ..], 1);

//         return @This(){
//             .nodes = nodes,
//             .allocator = allocator,
//             .root = &nodes[median],
//         };
//     }

//     fn print(self: *@This()) void {
//         const ptr = @ptrToInt(self.nodes.ptr) - 1;
//         std.log.warn("\n{}", .{ptr});
//         for (self.nodes) |node, i| {
//             const left_ptr = @ptrToInt(node.left);
//             const left_i = if (node.left != null)
//                 ((left_ptr - ptr) / @sizeOf(KDNode)) + 1
//             else
//                 0;

//             const right_ptr = @ptrToInt(node.right);
//             const right_i = if (node.right != null)
//                 ((right_ptr - ptr) / @sizeOf(KDNode)) + 1
//             else
//                 0;
//             std.log.warn("{}: point {}, left {}, right {}", .{ i + 1, node.point, left_i, right_i });
//         }
//     }

//     fn nearest_neighbor(self: *@This(), point: Point) Point {
//         self.print();
//         if (nns(self.root, point, 0)) |res| {
//             return res.node.point;
//         } else {
//             return self.root.point;
//         }
//     }

//     fn deinit(self: @This()) void {
//         self.allocator.free(self.nodes);
//     }
// };
