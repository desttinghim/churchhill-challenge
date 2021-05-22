const std = @import("std");
const ListNode = @import("linked_list.zig").ListNode;
const LinkedList = @import("linked_list.zig").LinkedList;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// A simplified Cache Sensitive Skip List data structure.
pub fn CompareFns(comptime Key: type) type {
    return struct {
        isLessThan: fn (Key, Key) bool,
        isEqual: fn (Key, Key) bool,
        isGreaterThan: fn (Key, Key) bool,
    };
}

pub fn ProxyItem(comptime Key: type, comptime Value: type, cmp: CompareFns(Key), comptime skip: usize) type {
    const List = LinkedList(Key, Value, cmp.isLessThan);
    return struct {
        // We store  multiple keys so that the index in the proxy list is the same as the
        // index in the lowest level of the fast lane
        keys: [skip]?Key,
        ptr: [skip]?*List.Node,
    };
}

pub fn CSSL(comptime Key: type, comptime Value: type, cmp: CompareFns(Key), comptime levels: usize, comptime skip: usize) type {
    std.debug.assert(levels > 0);
    return struct {
        pub const List = LinkedList(Key, Value, cmp.isLessThan);
        pub const Proxy = ProxyItem(Key, Value, cmp, skip);
        // How many elements are skipped per level
        pub const SkipLen = init: {
            var initial_value: [levels]usize = undefined;
            for (initial_value) |*len, i| {
                len.* = (i + 1) * skip;
            }
            break :init initial_value;
        };
        allocator: *Allocator,
        proxies: ArrayList(Proxy),
        list: List,
        fastLanes: [levels]ArrayList(Key),

        pub fn init(allocator: *Allocator) !@This() {
            return @This(){
                .allocator = allocator,
                .proxies = ArrayList(Proxy).init(allocator),
                .list = try List.init(allocator),
                .fastLanes = init: {
                    var initial_value: [levels]ArrayList(Key) = undefined;
                    for (initial_value) |*lane, i| {
                        lane.* = ArrayList(Key).init(allocator);
                        // std.log.warn("SkipLen {} {}", .{i, SkipLen[i]});
                    }
                    break :init initial_value;
                },
            };
        }

        pub fn initFromSlices(allocator: *Allocator, keys: []const Key, values: []const Value) !@This() {
            std.debug.assert(keys.len == values.len);
            var self = @This(){
                .allocator = allocator,
                .proxies = try ArrayList(Proxy).initCapacity(allocator, @divTrunc(keys.len, SkipLen[0]) + 1),
                .list = try List.initFromSlices(allocator, keys, values),
                .fastLanes = init: {
                    var initial_value: [levels]ArrayList(Key) = undefined;
                    for (initial_value) |*lane, i| {
                        lane.* = ArrayList(Key).init(allocator);
                        // std.log.warn("SkipLen {} {}", .{i, SkipLen[i]});
                    }
                    break :init initial_value;
                },
            };

            try self.rebuildFastLanes();

            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.list.deinit();
            self.proxies.deinit();
            for (self.fastLanes) |lane| {
                lane.deinit();
            }
        }

        fn rebuildFastLanes(self: *@This()) !void {
            try self.proxies.resize(@divTrunc(self.list.len, SkipLen[0]) + 1);
            for (self.fastLanes) |*lane, i| {
                lane.shrinkRetainingCapacity(0);
            }
            var current: ?*List.Node = self.list.head;
            var i: usize = 0;
            while (current) |curr| : (i += 1) {
                for (self.fastLanes) |lane, lvl| {
                    if (i % SkipLen[lvl] == 0) {
                        var index = @divTrunc(i, SkipLen[lvl]);
                        try self.fastLanes[lvl].append(curr.key);
                        if (lvl == 0) {
                            try self.proxies.append(.{
                                .keys = undefined,
                                .ptr = undefined,
                            });
                        }
                    }
                }
                const index = @divTrunc(i, skip);
                const p_index = i % skip;
                self.proxies.items[index].keys[p_index] = curr.key;
                self.proxies.items[index].ptr[p_index] = curr;
                current = curr.next;
            }
        }

        pub fn insert(self: *@This(), key: Key, value: Value) !void {
            try self.list.insert(key, value);
            try self.rebuildFastLanes();
        }

        pub fn lookup(self: *@This(), key: Key) ?Value {
            var pos = binSearch: {
                var array = self.fastLanes[levels - 1].items;
                var left: usize = 0;
                var right: usize = array.len - 1;
                while (left <= right) {
                    var middle = @divTrunc(left + right, 2);
                    if (cmp.isLessThan(array[middle], key)) {
                        left = middle + 1;
                    } else if (cmp.isGreaterThan(array[middle], key)) {
                        right = middle - 1;
                    } else {
                        break :binSearch middle;
                    }
                }
                break :binSearch right; // unsuccessful search in top, start from nearest point
            };

            var lvl = levels - 1;
            while (lvl >= 0) : (lvl -= 1) {
                var fastLane = self.fastLanes[lvl].items;
                var prev = pos;
                while (pos < fastLane.len and
                    (cmp.isGreaterThan(key, fastLane[pos]) or cmp.isEqual(key, fastLane[pos])))
                {
                    prev = pos;
                    pos += 1;
                }
                if (lvl == 0) {
                    pos = prev;
                    break;
                }
                pos = prev * skip;
            }
            // Item is not in skiplist
            if (pos >= self.fastLanes[0].items.len) return null;
            // This line is in the original, but I want the value and not the key
            var proxy = self.proxies.items[pos];
            // Search through proxy
            for (proxy.keys) |kOpt, i| {
                if (kOpt) |k| {
                    if (cmp.isEqual(key, k)) return proxy.ptr[i].?.value;
                }
            }
            // TODO: scan through linked list if something has been inserted since last rebuild
            return null;
        }

        pub fn searchRange(self: *@This(), start: Key, end: Key) ?[2]*List.Node {
            var pos = binSearch: {
                var array = self.fastLanes[levels - 1].items;
                var left: usize = 0;
                var right: usize = array.len - 1;
                while (left <= right) {
                    var middle = @divTrunc(left + right, 2);
                    if (cmp.isLessThan(array[middle], start)) {
                        left = middle + 1;
                    } else if (cmp.isGreaterThan(array[middle], start)) {
                        right = middle - 1;
                    } else {
                        break :binSearch middle;
                    }
                }
                break :binSearch right; // unsuccessful search in top, start from nearest point
            };

            var lvl = levels - 1;
            while (lvl >= 0) : (lvl -= 1) {
                var fastLane = self.fastLanes[lvl].items;
                var prev = pos;
                while (pos < fastLane.len and
                    (cmp.isGreaterThan(start, fastLane[pos]) or cmp.isEqual(start, fastLane[pos])))
                {
                    prev = pos;
                    pos += 1;
                }
                if (lvl == 0) {
                    pos = prev;
                    break;
                }
                pos = prev * skip;
            }
            // Item is not in skiplist
            if (pos >= self.fastLanes[0].items.len) return null;
            // This line is in the original, but I want the value and not the key
            var proxy = self.proxies.items[pos];
            // Search through proxy
            var resStart: ?*List.Node = null;
            var resEnd: ?*List.Node = null;
            for (proxy.keys) |kOpt, i| {
                if (kOpt) |k| {
                    if (cmp.isEqual(start, k) or (cmp.isGreaterThan(k, start)) and cmp.isLessThan(k, end)) {
                        resStart = proxy.ptr[i];
                        break;
                    }
                }
            } else {
                return null; // start doesn't exist
            }

            var fastLane = self.fastLanes[0].items;
            while (pos < fastLane.len) : (pos += 1) {
                if (cmp.isEqual(fastLane[pos], end)) break;
                if (cmp.isGreaterThan(fastLane[pos], end)) {
                    pos -= 1;
                    break;
                }
            }
            proxy = self.proxies.items[pos];
            var prev: usize = 0;
            for (proxy.keys) |kOpt, i| {
                if (kOpt) |k| {
                    if (cmp.isGreaterThan(k, end)) {
                        resEnd = proxy.ptr[prev];
                        break;
                    }
                    prev = i;
                }
            } else {
                resEnd = self.list.tail;
            }

            var res = .{ resStart.?, resEnd.? };
            return res;
        }
    };
}

fn u8isLessThan(a: u8, b: u8) bool {
    return a < b;
}

fn u8isEqual(a: u8, b: u8) bool {
    return a == b;
}

fn u8isGreaterThan(a: u8, b: u8) bool {
    return a > b;
}

test "Cache Sensitive Skip List" {
    const ordered_list_keys: [10]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const ordered_list_data: [10]u8 = .{ 'e', 'd', 'c', 'b', 'a', 'j', 'i', 'h', 'g', 'f' };
    const list_keys: [10]u8 = .{ 4, 3, 2, 1, 0, 9, 8, 7, 6, 5 };
    const list_data: [10]u8 = .{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j' };
    const cmp = CompareFns(u8){
        .isLessThan = u8isLessThan,
        .isEqual = u8isEqual,
        .isGreaterThan = u8isGreaterThan,
    };
    const SkipList = CSSL(u8, u8, cmp, 2, 2);
    var cssl = try SkipList.initFromSlices(std.testing.allocator, &list_keys, &list_data);
    defer cssl.deinit();

    if (cssl.lookup(6)) |val| {
        try std.testing.expectEqual(val, 'i');
    } else {
        std.log.warn("Could not find 6", .{});
        return error.LookupFailed;
    }
    if (cssl.lookup(11)) |val| {
        std.log.warn("val {c}", .{val});
        return error.LookupReturnedWrongValue;
    }
    for (ordered_list_keys) |key, idx| {
        if (cssl.lookup(key)) |val| {
            try std.testing.expectEqual(val, ordered_list_data[idx]);
        } else {
            std.log.warn("key {}, val {c}", .{ key, ordered_list_data[idx] });
            return error.LookupFailed;
        }
    }

    var rqOpt = cssl.searchRange(2, 7);
    if (rqOpt) |rq| {
        // std.log.warn("{}, {}", .{ rq[0].key, rq[1].key });
    } else {
        return error.RangeFailed;
    }
    rqOpt = cssl.searchRange(0, 10);
    if (rqOpt) |rq| {
        // std.log.warn("{}, {}", .{rq[0], rq[1]});
    } else {
        return error.RangeFailed;
    }
}

test "Insert" {
    const cmp = CompareFns(u8){
        .isLessThan = u8isLessThan,
        .isEqual = u8isEqual,
        .isGreaterThan = u8isGreaterThan,
    };
    const SkipList = CSSL(u8, u8, cmp, 2, 2);
    var cssl = try SkipList.init(std.testing.allocator);
    defer cssl.deinit();

    try cssl.insert(0, 'a');
    try cssl.insert(1, 'b');
    try cssl.insert(2, 'c');
    try cssl.insert(3, 'd');
    try cssl.insert(4, 'e');

    try std.testing.expectEqual(cssl.lookup(0), 'a');
    try std.testing.expectEqual(cssl.lookup(3), 'd');
}

test "Skip List in Skip List" {
    const cmp = CompareFns(u8){
        .isLessThan = u8isLessThan,
        .isEqual = u8isEqual,
        .isGreaterThan = u8isGreaterThan,
    };
    const SkipListY = CSSL(u8, u8, cmp, 2, 2);
    const SkipListX = CSSL(u8, SkipListY, cmp, 2, 2);
}
