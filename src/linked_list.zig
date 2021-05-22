const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generic Linked List Node 
pub fn ListNode(comptime Key: type, comptime Value: type, isLessThan: fn (Key, Key) bool) type {
    return struct {
        key: Key,
        value: Value,
        next: ?*@This(),

        fn node(key: Key, value: Value) @This() {
            return @This(){
                .key = key,
                .value = value,
                .next = null,
            };
        }

        fn makeNode(allocator: *Allocator, key: Key, value: Value) !*@This() {
            var newNode = try allocator.create(@This());
            newNode.* = node(key, value);
            return newNode;
        }

        fn makeCopy(self: *@This(), allocator: *Allocator) !*@This() {
            var newNode = try allocator.create(@This());
            newNode.* = self.*;
            return newNode;
        }

        fn makeNext(self: *@This(), allocator: *Allocator, key: Key, value: Value) !*@This() {
            self.next = try allocator.create(@This());
            self.next.* = node(key, value);
            return self.next;
        }

        fn tail(self: *@This()) *Node {
            var current: ?*Node = head;
            while (current) |n| {
                var next = n.next;
                if (next == null) return n;
                current = next;
            }
        }
    };
}

/// Generic Linked List
pub fn LinkedList(comptime Key: type, comptime Value: type, isLessThan: fn (Key, Key) bool) type {
    return struct {
        pub const Node = ListNode(Key, Value, isLessThan);
        head: *Node,
        tail: *Node,
        allocator: *Allocator,

        /// Build a linked list from 2 slices, one of the keys and one of the values.
        /// These lists should be the same size, and both sorted in the same order.
        /// Assumes there are 2 or more elements in each list.
        /// Returns the head of the list.
        pub fn initFromSlices(allocator: *Allocator, keys: []const Key, values: []const Value) !@This() {
            var head = try Node.makeNode(allocator, keys[0], values[0]);
            var self = @This(){
                .head = head,
                .tail = head,
                .allocator = allocator,
            };
            for (keys[1..]) |key, i| {
                try self.insert(key, values[i + 1]);
            }
            return self;
        }

        pub fn deinit(self: *@This()) void {
            var current: ?*Node = self.head;
            while (current) |n| {
                current = n.next;
                self.allocator.destroy(n);
            }
        }

        pub fn insert(self: *@This(), key: Key, value: Value) !void {
            var allocator = self.allocator;
            var newNode = try Node.makeNode(allocator, key, value);
            if (isLessThan(key, self.head.key)) {
                newNode.next = self.head;
                self.head = newNode;
                return;
            }
            var previous = self.head;
            var current: ?*Node = self.head.next;
            while (current) |curr| {
                if (isLessThan(curr.key, key)) {
                    previous = curr;
                    current = curr.next;
                } else {
                    previous.next = newNode;
                    newNode.next = curr;
                    return; //newNode;
                }
            } else {
                previous.next = newNode;
                return; // newNode;
            }
        }
    };
}

fn u8isLessThan(a: u8, b: u8) bool {
    return a < b;
}

test "Build Linked List" {
    const list_keys: [10]u8 = .{ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };
    const list_data: [10]u8 = .{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j' };
    const List = LinkedList(u8, u8, u8isLessThan);
    var list = try List.initFromSlices(std.testing.allocator, &list_keys, &list_data);
    defer list.deinit();

    var current: ?*ListNode(u8, u8, u8isLessThan) = list.head;
    var i = list_keys.len;
    while (current) |n| {
        // std.log.warn("{*} {}: {c} {}", .{n, n.key, n.value, n.next});
        try std.testing.expectEqual(n.key, list_keys[i - 1]);
        current = n.next;
        i -= 1;
    }
}

test "Build Linked List from unsorted slice" {
    const ordered_list_keys: [10]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const list_keys: [10]u8 = .{ 4, 3, 2, 1, 0, 9, 8, 7, 6, 5 };
    const list_data: [10]u8 = .{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j' };
    const List = LinkedList(u8, u8, u8isLessThan);
    var list = try List.initFromSlices(std.testing.allocator, &list_keys, &list_data);
    defer list.deinit();

    var current: ?*ListNode(u8, u8, u8isLessThan) = list.head;
    var i: usize = 0;
    while (current) |n| {
        // std.log.warn("{}: {c} {}", .{n.key, n.value, n.next});
        std.testing.expectEqual(n.key, ordered_list_keys[i]) catch |e| {
            std.log.warn("List out of order, expected {}, found {}", .{ ordered_list_keys[i], n.key });
            return e;
        };
        current = n.next;
        i += 1;
    }
}
