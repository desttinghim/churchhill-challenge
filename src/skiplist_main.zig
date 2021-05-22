const std = @import("std");
const tracy = @import("tracy");
const Heap = @import("heap.zig").Heap;
pub const MinHeap = Heap(Point, Point.heap_cmp);
const challenge = @import("challenge.zig");
const Point = challenge.Point;
const Rect = challenge.Rect;
const skiplist = @import("skiplist.zig");
const ArrayList = std.ArrayList;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

const PointList = skiplist.CSSL(f32, ArrayList(Point), skiplist.f32cmp, 5, 5);

pub const challenge_exports = struct {
    pub const SearchContext = struct {
        heap: MinHeap,
        list: PointList,
    };

    pub export fn create(points_begin: [*]const Point, points_end: *const Point) callconv(.C) *SearchContext {
        const t = tracy.trace(@src());
        defer t.end();
        gpa = std.heap.GeneralPurposeAllocator(.{}){};
        var allocator = &gpa.allocator;
        var len = (@ptrToInt(points_end) - @ptrToInt(points_begin)) / @sizeOf(Point);
        var sc = allocator.create(SearchContext) catch |e| @panic("Couldn't init search context");

        sc.heap = MinHeap.init(allocator);

        sc.list = PointList.init(allocator) catch |e| @panic("Couldn't init skiplist");

        for (points_begin[0..len]) |point, i| {
            if (sc.list.lookup(point.x)) |*a| {
                a.append(point) catch |e| @panic("Couldn't append to array");
            } else {
                var a = ArrayList(Point).init(allocator);
                a.append(point) catch |e| @panic("Failed to append to new arraylist");
                sc.list.insert(point.x, a) catch |e| @panic("Failed to insert into skiplist");
            }
        }
        // Keeping variables from cluttering function
        {
            // Sort all points by rank
            var current: ?*PointList.List.Node = sc.list.list.head;
            var i: usize = 0;
            while (current) |curr| : (i += 1) {
                std.sort.sort(Point, curr.value.items, @as(u0, 0), challenge.point_cmp);
                current = curr.next;
            }
        }
        return sc;
    }

    pub export fn search(sc: *SearchContext, rect: *const Rect, count: i32, out_points: [*]Point) callconv(.C) i32 {
        const t = tracy.trace(@src());
        defer t.end();
        sc.heap.clear();

        const rqOpt = sc.list.searchRange(rect.lx, rect.hx);
        if (rqOpt) |rq| {
            var current: ?*PointList.List.Node = rq[0];
            while (current) |curr| {
                for (curr.value.items) |point| {
                    if (!rect.contains_point(point)) continue;
                    if (sc.heap.list.items.len < count) {
                        sc.heap.insert(point) catch |e| @panic("Couldn't insert into heap");
                    } else {
                        var res = sc.heap.insertExtract(point);
                        if (res.id == point.id) {
                            break;
                        }
                    }
                }
                current = curr.next;
                if (current == rq[1]) break;
            }
        }

        const mincount = std.math.min(@intCast(usize, count), sc.heap.list.items.len);
        std.mem.copy(Point, out_points[0..mincount], sc.heap.list.items[0..mincount]);
        std.sort.sort(Point, out_points[0..mincount], @as(u0, 0), challenge.point_cmp);
        return @intCast(i32, mincount);
    }

    pub export fn destroy(sc: *SearchContext) callconv(.C) ?*SearchContext {
        const t = tracy.trace(@src());
        defer t.end();
        sc.heap.deinit();
        {
            // Sort all points by rank
            var current: ?*PointList.List.Node = sc.list.list.head;
            var i: usize = 0;
            while (current) |curr| : (i += 1) {
                curr.value.deinit();
                current = curr.next;
            }
        }
        sc.list.deinit();
        gpa.allocator.destroy(sc);
        _ = gpa.deinit();
        return null;
    }
};
