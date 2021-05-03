const std = @import("std");
const tracy = @import("tracy");

pub fn Heap(comptime T: type, comptime less_than: fn (T, T) bool) type {
    return struct {
        list: std.ArrayList(T),

        pub fn init(allocator: *std.mem.Allocator) @This() {
            return @This(){
                .list = std.ArrayList(T).init(allocator),
            };
        }

        pub fn print(self: *@This()) void {
            var perline: usize = 1;
            var sofar: usize = 0;
            for (self.list.items) |hi, a| {
                std.io.getStdOut().writer().print(" {} ", .{hi.rank}) catch @panic("lol");
                sofar += 1;
                if (sofar >= perline) {
                    perline *= 2;
                    sofar = 0;
                    std.io.getStdOut().writer().print("\n", .{}) catch @panic("lol");
                }
            }
            std.io.getStdOut().writer().print("\n", .{}) catch @panic("lol");
        }

        pub fn clear(self: *@This()) void {
            self.list.shrinkRetainingCapacity(0);
        }

        pub fn deinit(self: *@This()) void {
            self.list.deinit();
        }

        pub fn initCapacity(allocator: *std.mem.Allocator, size: usize) @This() {
            return @This(){
                .list = std.ArrayList(T).initCapacity(allocator, size),
            };
        }

        /// Returns a copy of the minimum element
        pub fn peek(self: *@This()) ?T {
            return if (self.list.len >= 1) self.list.items[0] else null;
        }

        pub fn insert(self: *@This(), item: T) !void {
            try self.list.append(item);
            self.bubble_up(self.list.items.len - 1);
        }

        fn bubble_up(self: *@This(), index: usize) void {
            if (parent(index)) |p| {
                if (less_than(self.list.items[p], self.list.items[index])) {
                    self.swap(index, p);
                    self.bubble_up(p);
                }
            }
        }

        /// Extracts the root of the tree, which will be the min or
        /// max depending on the sort function provided
        pub fn extract(self: *@This()) ?T {
            if (self.list.items.len == 0) return null;
            const min = self.list.swapRemove(0);
            self.bubble_down(0);
            return min;
        }

        pub fn insertExtract(self: *@This(), item: T) T {
            if (self.list.items.len == 0) return item;
            if (less_than(item, self.list.items[0])) {
                const min = self.list.items[0];
                self.list.items[0] = item;
                self.bubble_down(0);
                return min;
            } else {
                return item;
            }
        }

        fn bubble_down(self: *@This(), index: usize) void {
            var min_index = index;

            var cleft = child_left(index);
            if (cleft < self.list.items.len) {
                if (less_than(self.list.items[min_index], self.list.items[cleft]))
                    min_index = cleft;
            }
            var cright = child_right(index);
            if (cright < self.list.items.len) {
                if (less_than(self.list.items[min_index], self.list.items[cright]))
                    min_index = cright;
            }

            if (min_index != index) {
                self.swap(index, min_index);
                self.bubble_down(min_index);
            }
        }

        fn swap(self: *@This(), idx1: usize, idx2: usize) void {
            var a = self.list.items[idx1];
            self.list.items[idx1] = self.list.items[idx2];
            self.list.items[idx2] = a;
        }

        fn parent(i: usize) ?usize {
            return if (i == 0) null else (i - 1) / 2;
        }

        fn child_left(i: usize) usize {
            return 2 * i + 1;
        }

        fn child_right(i: usize) usize {
            return 2 * i + 2;
        }
    };
}
