const std = @import("std");

pub fn point_cmp(ctx: u0, lhs: Point, rhs: Point) bool {
    return lhs.rank < rhs.rank;
}

pub const Point = packed struct {
    id: i8,
    rank: i32,
    x: f32,
    y: f32,

    pub fn print(self: @This()) void {
        std.log.warn("id: {: >4}, rank: {: >4}, x: {d: >8.2}, y: {d: >8.2}", .{ self.id, self.rank, self.x, self.y });
    }

    fn dist_squared_point(p1: @This(), p2: @This()) f32 {
        const a = p2.x - p1.x;
        const b = p2.y - p1.y;
        return a * a + b * b;
    }

    pub fn dist_squared(p1: @This(), x: f32, y: f32) f32 {
        const a = x - p1.x;
        const b = y - p1.y;
        return a * a + b * b;
    }

    pub fn cmp(axis: kd.Axis, lhs: @This(), rhs: @This()) bool {
        return switch (axis) {
            .Horizontal => lhs.x < rhs.x,
            .Vertical => lhs.y < rhs.y,
        };
    }

    pub fn heap_cmp(lhs: @This(), rhs: @This()) bool {
        return lhs.rank < rhs.rank;
    }
};

pub const Rect = packed struct {
    lx: f32,
    ly: f32,
    hx: f32,
    hy: f32,

    pub fn print(self: @This()) void {
        std.log.warn("lx: {d}, ly: {d}, hx: {d}, hy: {d}", .{ self.lx, self.ly, self.hx, self.hy });
    }

    pub fn contains_point(self: Rect, pos: Point) bool {
        return pos.x > self.lx and
            pos.x < self.hx and
            pos.y > self.ly and
            pos.y < self.hy;
    }

    pub fn contains(self: Rect, x: f32, y: f32) bool {
        return x > self.lx and
            x < self.hx and
            y > self.ly and
            y < self.hy;
    }

    pub fn overlaps(self: Rect, other: Rect) bool {
        return self.contains(other.lx, other.ly) or
            self.contains(other.hx, other.hy) or
            other.contains(self.lx, self.ly) or
            other.contains(self.hx, self.hy);
    }
};
