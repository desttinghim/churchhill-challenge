const std = @import("std");
const Allocator = std.mem.Allocator;

/// A generic sorted linked list
pub fn ListNode(comptime Key: type, comptime Value: type, isLessThan: fn(Key, Key) bool) type {
    return struct {
        key: Key,
        value: Value,
        next: ?*@This(),
        
        fn node(key: Key, value: Value) @This() {
            return @This() {
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

        fn insert(head: *@This(), allocator: *Allocator, key: Key, value: Value) !*@This() {
            var previous = head;
            var current: ?*@This() = head.next;
            if (isLessThan(key, head.key)) {
                var moved = try head.makeCopy(allocator);
                head.* = node(key, value);
                head.next = moved;
                return head;
            }
            while (current) |curr| {
                if (isLessThan(curr.key, key)) {
                    previous = curr;
                    current = curr.next;
                } else {
                    // Move current node into new location, use current location
                    // to point towards it
                    var moved = try curr.makeCopy(allocator);
                    curr.* = node(key, value);
                    curr.next = moved;
                    return curr;
                }
            } else {
                var newNode = try makeNode(allocator, key, value);
                previous.next = newNode;
                return newNode;
            }
        }

        /// Build a linked list from 2 slices, one of the keys and one of the values.
        /// These lists should be the same size, and both sorted in the same order.
        /// Assumes there are 2 or more elements in each list.
        /// Returns the head of the list.
        fn build(allocator: *Allocator, keys: []const Key, values: []const Value) !*@This() {
            var head = try makeNode(allocator, keys[0], values[0]);
            for (keys[1..]) |key, i| {
                _ = try head.insert(allocator, key, values[i + 1]);
            }
            return head;
        }

        fn destroy(head: *@This(), allocator: *Allocator) void {
            var current: ?*@This() = head;
            while(current) |n| {
                var next = n.next;
                std.testing.allocator.destroy(n);
                current = next;
            }
        }

        fn tail(head: *@This()) *@This() {
            var current: ?*@This() = head;
            while(current) |n| {
                var next = n.next;
                if (next == null) return n;
                current = next;
            }
        }
    };
}

fn u8isLessThan(a: u8, b: u8) bool {
    return a < b;
}

test "Build Linked List" {
    const list_keys: [10]u8 = .{9, 8, 7, 6, 5, 4, 3, 2, 1, 0};
    const list_data: [10]u8 = .{'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'};
    const List = ListNode(u8, u8, u8isLessThan);
    const list = try List.build(std.testing.allocator, &list_keys, &list_data);
    defer list.destroy(std.testing.allocator);

    var current: ?*List = list;
    var i = list_keys.len;
    while(current) |n| {
        // std.log.warn("{}: {c} {}", .{n.key, n.value, n.next});
        try std.testing.expectEqual(n.key, list_keys[i - 1]);
        current = n.next;
        i -= 1;
    }
}

test "Build Linked List from unsorted slice" {
    const ordered_list_keys: [10]u8 = .{0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    const list_keys: [10]u8 = .{4, 3, 2, 1, 0, 9, 8, 7, 6, 5};
    const list_data: [10]u8 = .{'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'};
    const List = ListNode(u8, u8, u8isLessThan);
    const list = try List.build(std.testing.allocator, &list_keys, &list_data);
    defer list.destroy(std.testing.allocator);

    var current: ?*List = list;
    var i: usize = 0;
    while(current) |n| {
        // std.log.warn("{}: {c} {}", .{n.key, n.value, n.next});
        std.testing.expectEqual(n.key, ordered_list_keys[i]) catch |e| {
            std.log.warn("List out of order, expected {}, found {}", .{ordered_list_keys[i], n.key});
        };
        current = n.next;
        i += 1;
    }
}
