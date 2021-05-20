const std = @import("std");
const ListNode = @import("linked_list.zig").ListNode;
const LinkedList = @import("linked_list.zig").LinkedList;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// A simplified Cache Sensitive Skip List data structure.
pub fn CompareFns(comptime Key: type) type {
    return struct {
        isLessThan: fn(Key, Key) bool,
        isEqual: fn(Key, Key) bool,
        isGreaterThan: fn(Key, Key) bool,
    };
}

pub fn ProxyItem(comptime Key: type, comptime Value: type, cmp: CompareFns(Key), comptime skip: usize) type {
    const List = LinkedList(Key, Value, cmp.isLessThan);
    return struct {
        // We store  multiple keys so that the index in the proxy list is the same as the
        // index in the lowest level of the fast lane
        keys: [skip]Key,
        ptr: [skip]*List.Node,
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
        
        pub fn initFromSlices(allocator: *Allocator, keys: []const Key, values: []const Value) !@This() {
            std.debug.assert(keys.len == values.len);
            var self = @This() {
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

            var current: ?*List.Node = self.list.head;
            var i: usize = 0;
            while (current) |curr| : (i += 1) {
                for (self.fastLanes) |lane, lvl| {
                    if (i % SkipLen[lvl] == 0) {
                        var index = @divTrunc(i, SkipLen[lvl]);
                        // std.log.warn("{} {}", .{i, index});
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

            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.list.deinit();
            self.proxies.deinit();
            for (self.fastLanes) |lane| {
                lane.deinit();
            }
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
                    } else if(cmp.isGreaterThan(array[middle], key)) {
                        right = middle - 1;
                    } else {
                        break :binSearch middle;
                    }
                }
                break :binSearch left; // unsuccessful search in top, start from nearest point
            };

            var lvl = levels - 1;
            while (lvl > 0) : (lvl -= 1) {
                // var rPos = pos - level_start_pos[level];
                while (cmp.isLessThan(key, self.fastLanes[lvl].items[pos])){
                    // rPos += 1;
                    pos += 1;
                }
                if (lvl == 1) break;
                pos = skip * pos;
            }
            // This line is in the original, but I want the value and not the key
            // if (cmp.isEqual(key, self.fastLanes[1].items[pos])) return key;
            var proxy = self.proxies.items[pos];
            // Search through proxy
            for (proxy.keys) |k, i| {
                if (cmp.isEqual(key, k)) return proxy.ptr[i].value;
            }
            return null;
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
    return a < b;
}

test "Cache Sensitive Skip List" {
    const ordered_list_keys: [10]u8 = .{0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    const list_keys: [10]u8 = .{4, 3, 2, 1, 0, 9, 8, 7, 6, 5};
    const list_data: [10]u8 = .{'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'};
    const cmp = CompareFns(u8) {
        .isLessThan = u8isLessThan,
        .isEqual = u8isEqual,
        .isGreaterThan = u8isGreaterThan,
    };
    const SkipList = CSSL(u8, u8, cmp, 2, 2);
    var cssl = try SkipList.initFromSlices(std.testing.allocator, &list_keys, &list_data);
    defer cssl.deinit();

    for (cssl.fastLanes) |lane, i| {
        std.log.warn("lane {} | {any}", .{i, lane.items});
    }
    for (cssl.proxies.items) |proxy, i| {
        std.log.warn("proxy {} | keys: {any}", .{i, proxy.keys});
    }
    var current: ?*SkipList.List.Node = cssl.list.head;
    var i: usize = 0;
    while (current) |curr| : (i += 1) {
        std.log.warn("List node {} | {} {c}", .{i, curr.key, curr.value});
        current = curr.next;
    }

    if (cssl.lookup(6)) |val| {
        try std.testing.expectEqual(val, 'i');
    } else {
        return error.TestFailed;
    }
}

// fn SkipList(comptime T: type, cmp: fn (T, T) bool) type {
//     return struct {
//         allocator: *std.mem.Allocator,
//         max_level: u8,
//         skip: u8,
//         num_elements: usize,
//         head: *DataNode(T),
//         tail: *DataNode(T),
//         items_per_level: []u32,
//         fast_lane_items: []u32,
//         start_of_fast_lanes: []u32,
//         fast_lanes: []T,
//         fast_lane_pointers: []?[]ProxyNode(T),

//         fn init(allocator: *std.mem.Allocator, maxLevel: u8, skip: ?u8) @This() {
//             var self = @This(){
//                 .allocator = allocator,
//                 // .max_level = maxLevel,
//                 .num_elements = 0,
//                 .data = std.ArrayList(DataNode).init(allocator),
//                 .skip = skip orelse 2,
//                 .items_per_level = allocator.alloc(u32, maxLevel),
//                 .fast_lane_items = allocator.alloc(u32, maxLevel),
//                 .start_of_fast_lanes = allocator.alloc(u32, maxLevel),
//                 .fast_lanes = undefined,
//                 .fast_lane_pointers = undefined,
//             };
//             var i: usize = 0;
//             while (i < maxLevel) : (i += 1) {
//                 self.fast_lane_items[i] = 0;
//             }

//             self.buildFastLanes();

//             return self;
//         }
//         // Figure out how to build. Specifically figure out how to make the fast lanes the correct size
//         // fn buildFromSlice(allocator: *std.mem.Allocator, maxLevel: u8, skip: ?u8, items: []T) void {
//         //     var self = @This(){
//         //         .allocator = allocator,
//         //         .max_level = maxLevel,
//         //         .num_elements = 0,
//         //         .data = std.ArrayList(DataNode).initCapacity(allocator, items.len),
//         //         .skip = skip orelse 2,
//         //         .items_per_level = allocator.alloc(u32, maxLevel),
//         //         .fast_lane_items = allocator.alloc(u32, maxLevel),
//         //         .start_of_fast_lanes = allocator.alloc(u32, maxLevel),
//         //         .fast_lanes = undefined,
//         //         .fast_lane_pointers = undefined,
//         //     };
//         //     var i: usize = 0;
//         //     while (i < maxLevel) : (i += 1) {
//         //         self.fast_lane_items[i] = 0;
//         //     }

//         //     self.buildFastLanes();

//         //     return self;
//         // }
//         fn deinit(self: *@This()) void {
//             self.allocator.free(self.items_per_level);
//             self.allocator.free(self.start_of_fast_lanes);
//             self.allocator.free(self.fast_lane_items);
//             self.data.deinit();
//         }
//         fn insert(self: *@This(), key: u32) !void {
//             var new_node = try self.allocator.create(DataNode(T));
//             var nodeInserted = true;
//             var fastLaneInserted = false;

//             self.tail.next = new_node;
//             self.tail = new_node;

//             var level: usize = 0;
//             while (level < self.max_level) : (level += 1) {
//                 if (self.num_elements % std.math.pow(self.skip, level + 1) == 0 and nodeInserted) {
//                     nodeInserted = try self.insertItemIntoFastLane(level, new_node);
//                 } else {
//                     break;
//                 }
//                 fastLaneInserted = true;
//             }

//             if (!fastLaneInserted)
//                 try self.findAndInsertProxyNode(new_node);

//             self.num_elements += 1;

//             if (self.num_elements % (TOP_LANE_BLOCK * std.math.pow(self.skip, self.max_level)) == 0)
//                 try self.resizeFastLanes();
//         }
//         fn insertItemIntoFastLane(self: *@This(), level: u8, newNode: *DataNode) !?u32 {
//             var curPos = self.starts_of_fast_lanes[level] + self.fast_lane_items[level];
//             var levelLimit = curPos + self.items_per_level[level];

//             if (curPos > levelLimit)
//                 curPos = levelLimit;

//             while (newNode.key > self.fast_lanes[curPos] and curPos < levelLimit)
//                 curPos += 1;

//             if (self.fast_lanes[curPos] == null) {
//                 sefl.fast_lanes[curPos] = newNode.key;
//                 if (level == 0) {
//                     self.fast_lane_pointers[curPos - self.starts_of_fast_lanes[0]] = self.newProxyNode(node);
//                 }
//                 self.fast_lane_items[level] += 1;
//             } else {
//                 return null;
//             }

//             return curPos;
//         }
//         fn newProxyNode(self: *@This(), node: *DataNode) *ProxyNode {
//             var newProxy = self.allocator.create(ProxyNode);
//             newProxy.keys[0] = node.key;
//             newProxy.updated = false;
//             var i: u8 = 1;
//             while (i < self.skip) : (i += 1) {
//                 newProxy.keys[i] = null;
//             }
//             newProxy.pointers[0] = node;

//             return newProxy;
//         }
//         fn findAndInsertIntoProxyNode(self: *@This(), node: *DataNode) void {
//             var proxy = self.fast_lane_pointers[self.fast_lane_items[0] - 1];
//             var i: u8 = 1;
//             while (i < self.skip) : (i += 1) {
//                 if (proxy.keys[i] == null) {
//                     proxy.keys[i] == node.key;
//                     proxy.pointers[i] = node;
//                     return;
//                 }
//             }
//         }
//         fn buildFastLanes(self: *@This()) void {
//             var fast_lane_size = TOP_LANE_BLOCK;

//             self.items_per_level[self.max_level - 1] = fast_lane_size;
//             self.start_of_fast_lanes[self.max_level - 1] = 0;

//             var level: u8 = self.max_level - 2;
//             while (level >= 0) : (level -= 1) {
//                 self.items_per_level[level] = self.items_per_level[level + 1] * self.skip;
//                 self.start_of_fast_lanes[level] = self.start_of_fast_lanes[level + 1] + self.items_per_level[level + 1];
//                 fast_lane_size += self.items_per_level[level];
//             }

//             self.fast_lanes = self.allocator.alloc(u32, fast_lane_size);
//             self.fast_lane_pointers = self.allocator.alloc(*ProxyNode, self.items_per_level[0]);

//             // Placeholder values
//             for (self.fast_lanes) |_, i| {
//                 self.fast_lanes[i] = std.math.maxInt(u32);
//             }
//             for (self.fast_lane_pointers) |_, i| {
//                 self.fast_lane_pointers[i] = null;
//             }
//         }
//         fn resizeFastLanes(self: *@This()) void {
//             var new_size = self.
//         }
//         fn searchElement(self: *@This(), key: u32) ?u32 {
//             var curPos: usize = 0;
//             var first: usize = 0;
//             var last: usize = self.items_per_level[self.max_level - 1] - 1;
//             var middle: usize = 0;

//             // scan highest fast lane with binary search
//             while (first < last) {
//                 middle = (first + last) / 2;
//                 if (self.fast_lanes[middle] < key) {
//                     first = middle + 1;
//                 } else if (self.fast_lanes[middle] == key) {
//                     curPos = middle;
//                     break;
//                 } else {
//                     last = middle;
//                 }
//             }

//             // if first is greater than last, it was an incrementing error, use last instead
//             if (first > last) curPos = last;

//             // traverse fast lanes
//             var level: usize = self.max_level - 1;
//             while (level >= 0) : (level -= 1) {
//                 var rPos = curPos - self.start_of_fast_lanes[level];
//                 curPos += 1;
//                 // linear search through fast lane while key is gt/eq
//                 while (rPos < self.items_per_level[level] and key >= self.fast_lanes[curPos]) {
//                     rPos += 1;
//                 }
//                 // if we are at the lowest fast lane, go to next step
//                 if (level == 0) break;
//                 // otherwise, go down a level, multiplying by skip amount
//                 curPos = self.start_of_fast_lanes[level - 1] + rPos * self.skip;
//             }

//             // algorithm overshoots, bring it down by one
//             curPos -= 1;
//             //
//             if (key == self.fast_lanes[curPos]) return key;

//             var proxy = self.fast_lane_pointers[curPos - @ptrToInt(self.start_of_fast_lanes[0])];
//             var i: usize = 1;
//             while (i < self.skip) : (i += 1) {
//                 if (proxy.keys[i] == key)
//                     return key;
//             }

//             return null;
//         }
//         fn searchRange(self: *@This(), startKey: u32, endKey: u32) []DataNode {}
//     };
// }
