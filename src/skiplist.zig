const std = @import("std");
const ListNode = @import("linked_list.zig").ListNode;
const LinkedList = @import("linked_list.zig").LinkedList;
const Allocator = std.mem.Allocator;

// A simplified Cache Sensitive Skip List data structure.

pub fn ProxyItem(comptime Key: type, comptime Value: type, isLessThan: fn(Key, Key) bool) type {
    const List = LinkedList(Key, Value, isLessThan);
    return struct {
        key: Key,
        ptr: *List.Node,
    };
}

pub fn CSSL(comptime Key: type, comptime Value: type, isLessThan: fn(Key, Key) bool, comptime levels: usize, comptime skip: usize) type {
    return struct {
        pub const List = LinkedList(Key, Value, isLessThan);
        pub const Proxy = ProxyItem(Key, Value, isLessThan);
        // How many elements are skipped per level
        pub const SkipLen = init: {
            var initial_value: [levels]usize = undefined;
            for (initial_value) |*len, i| {
                len.* = (i + 1) * skip;
            }
            break :init initial_value;
        };
        allocator: *Allocator,
        proxies: []Proxy,
        list: List,
        fastLanes: [levels][]?Key,
        
        pub fn initFromSlices(allocator: *Allocator, keys: []const Key, values: []const Value) !@This() {
            std.debug.assert(keys.len == values.len);
            var self = @This() {
                .allocator = allocator,
                .proxies = try allocator.alloc(Proxy, keys.len),
                .list = try List.initFromSlices(allocator, keys, values),
                .fastLanes = init: {
                    var initial_value: [levels][]?Key = undefined;
                    for (initial_value) |*lane, i| {
                        lane.* = try allocator.alloc(?Key, @divTrunc(keys.len, SkipLen[i]) + 1);
                        for (lane.*) |_, a| {
                            lane.*[a] = null;
                        }
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
                        self.fastLanes[lvl][index] = curr.key;
                    }
                }
                self.proxies[i].key = curr.key;
                self.proxies[i].ptr = curr;
                current = curr.next;
            }

            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.list.deinit();
            self.allocator.free(self.proxies);
            for (self.fastLanes) |lane| {
                self.allocator.free(lane);
            }
        }

        // pub fn search(self: *@This(), key: Key) ?
    };
}

fn u8isLessThan(a: u8, b: u8) bool {
    return a < b;
}

test "Cache Sensitive Skip List" {
    const ordered_list_keys: [10]u8 = .{0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    const list_keys: [10]u8 = .{4, 3, 2, 1, 0, 9, 8, 7, 6, 5};
    const list_data: [10]u8 = .{'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'};
    const SkipList = CSSL(u8, u8, u8isLessThan, 2, 2);
    var cssl = try SkipList.initFromSlices(std.testing.allocator, &list_keys, &list_data);
    defer cssl.deinit();

    for (cssl.fastLanes) |lane, i| {
        std.log.warn("lane {}: {any}", .{i, lane});
    }
    for (cssl.proxies) |proxy, i| {
        std.log.warn("proxy {}: {any}", .{i, proxy.key});
    }
    var current: ?*SkipList.List.Node = cssl.list.head;
    var i: usize = 0;
    while (current) |curr| : (i += 1) {
        std.log.warn("List node {}: {} {c}", .{i, curr.key, curr.value});
        current = curr.next;
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
