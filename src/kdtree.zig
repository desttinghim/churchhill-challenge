const std = @import("std");
const tracy = @import("tracy");

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

pub const Rect = struct {
    low: Pos,
    high: Pos,

    pub fn init(lx: f32, ly: f32, hx: f32, hy: f32) @This() {
        const low = Pos{ .x = std.math.min(lx, hx), .y = std.math.min(ly, hy) };
        const high = Pos{ .x = std.math.max(lx, hx), .y = std.math.max(ly, hy) };
        return @This(){
            .low = low,
            .high = high,
        };
    }

    fn print(self: *const @This()) void {
        std.log.warn("rect {d} {d} {d} {d}", .{ self.low.x, self.low.y, self.high.x, self.high.y });
    }

    fn contains(self: Rect, pos: Pos) bool {
        return pos.x > self.low.x and
            pos.x < self.high.x and
            pos.y > self.low.y and
            pos.y < self.high.y;
    }

    fn overlaps(self: Rect, other: Rect) bool {
        return self.contains(other.low) or
            self.contains(other.high) or
            other.contains(self.low) or
            other.contains(self.high);
    }
};

pub const KDData = struct {
    id: usize,
    pos: Pos,

    fn cmp(axis: Axis, lhs: @This(), rhs: @This()) bool {
        return switch (axis) {
            .Horizontal => lhs.pos.x < rhs.pos.x,
            .Vertical => lhs.pos.y < rhs.pos.y,
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

    // fn deinit(self: *@This(), allocator: *std.mem.Allocator) void {
    //     if (self.left) |left| left.deinit(allocator);
    //     if (self.right) |right| right.deinit(allocator);
    //     allocator.destroy(self);
    // }

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
            leftslice = std.fmt.bufPrint(&leftbuf, "{}", .{left.id}) catch unreachable;
        } else {
            leftslice = std.fmt.bufPrint(&leftbuf, "None", .{}) catch unreachable;
        }
        if (self.right) |right| {
            rightslice = std.fmt.bufPrint(&rightbuf, "{}", .{right.id}) catch unreachable;
        } else {
            rightslice = std.fmt.bufPrint(&rightbuf, "None", .{}) catch unreachable;
        }
        std.log.warn("|{s: <20}id: {: >4}, left: {s: >5}, right: {s: >5}, x: {d: >8.2}, y: {d: >8.2}", .{
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
    nodelist: std.ArrayList(KDNode),
    area: Rect,

    pub fn deinit(self: *@This()) void {
        const t = tracy.trace(@src());
        defer t.end();
        self.root = null;
        self.nodelist.deinit();
        // if (self.root) |root| {
        //     root.deinit(self.allocator);
        // }
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
    pub fn kdtree(allocator: *std.mem.Allocator, datalist: []KDData) !@This() {
        const t = tracy.trace(@src());
        defer t.end();
        var self = @This(){
            .root = null,
            .nodelist = try std.ArrayList(KDNode).initCapacity(allocator, datalist.len),
            .area = .{ .low = .{ .x = 0, .y = 0 }, .high = .{ .x = 0, .y = 0 } },
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
        const mdat = datalist[median];

        if (!self.area.contains(mdat.pos)) {
            self.area.low.x = std.math.min(mdat.pos.x, self.area.low.x);
            self.area.low.y = std.math.min(mdat.pos.y, self.area.low.y);
            self.area.high.x = std.math.max(mdat.pos.x, self.area.high.x);
            self.area.high.y = std.math.max(mdat.pos.y, self.area.high.y);
        }

        var node = self.nodelist.addOneAssumeCapacity();
        node.* = .{
            .pos = mdat.pos,
            .id = mdat.id,
            .left = try self._kdtree(datalist[0..median], depth + 1),
            .right = try self._kdtree(datalist[median + 1 ..], depth + 1),
        };
        return node;
    }

    /// Does a nearest neighbor search on the kdtree. Returns the id of the
    /// node that is nearest to the given point, or null if the tree is empty.
    pub fn nns(self: *@This(), pos: Pos) !usize {
        const t = tracy.trace(@src());
        defer t.end();
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

    pub fn range(self: *@This(), matches: *std.ArrayList(usize), rect: Rect) anyerror!void {
        const t = tracy.trace(@src());
        defer t.end();
        if (!self.area.overlaps(rect)) {
            return;
        }
        if (self.root) |root| {
            // try self._query(matches, root, rect, self.area, 0);
            try self._query(matches, root, rect, 0);
            return;
        }
        return error.EmptyTree;
    }

    // fn _query(self: *@This(), matches: *std.ArrayList(usize), inode: ?*KDNode, rect: Rect, area: Rect, depth: usize) anyerror!void {
    fn _query(self: *@This(), matches: *std.ArrayList(usize), inode: ?*KDNode, rect: Rect, depth: usize) anyerror!void {
        if (inode == null) return;
        const node = inode.?;
        if (rect.contains(node.pos)) {
            const t2 = tracy.trace(@src());
            defer t2.end();
            try matches.append(node.id);
        }

        const axis: Axis = if (depth % 2 == 0) .Horizontal else .Vertical;
        switch (axis) {
            .Horizontal => {
                if (rect.low.x < node.pos.x) try self._query(matches, node.left, rect, depth + 1);
                if (rect.high.x > node.pos.x) try self._query(matches, node.right, rect, depth + 1);
            },
            .Vertical => {
                if (rect.low.y < node.pos.y) try self._query(matches, node.left, rect, depth + 1);
                if (rect.high.y > node.pos.y) try self._query(matches, node.right, rect, depth + 1);
            },
        }
        // const leftrect = switch (axis) {
        //     .Horizontal => Rect.init(area.low.x, area.low.y, node.pos.x, area.high.y),
        //     .Vertical => Rect.init(area.low.x, area.low.y, area.high.x, node.pos.y),
        // };
        // const rightrect = switch (axis) {
        //     .Horizontal => Rect.init(node.pos.x, area.low.y, area.high.x, area.high.y),
        //     .Vertical => Rect.init(area.low.x, node.pos.y, area.high.x, area.high.y),
        // };

        // if (leftrect.overlaps(rect)) try self._query(matches, node.left, rect, leftrect, depth + 1);
        // if (rightrect.overlaps(rect)) try self._query(matches, node.right, rect, rightrect, depth + 1);
    }
};

test "k-d tree nearest neighbor search" {
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

test "k-d tree range query" {
    const t = tracy.trace(@src());
    defer t.end();
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
        var matches = std.ArrayList(usize).init(std.testing.allocator);
        defer matches.deinit();
        try tree.range(&matches, Rect.init(-50, -50, 5, 5));

        std.testing.expectEqualSlices(usize, matches.items, &[_]usize{ 6, 1 });
    }
}
