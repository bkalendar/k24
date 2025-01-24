const std = @import("std");
const cabi = @import("cabi");
const console = @import("console");
const log = std.log.scoped(.main_k24);

var total: u32 = 0;

const cabiEpoch = @extern(*const fn (u32) callconv(.c) u64, .{ .name = "epoch", .library_name = "$root" });
comptime {
    @export(&cabiPostParse, .{ .name = "cabi_post_parse" });
    @export(&cabiParse, .{ .name = "parse" });
}

const KV = extern struct {
    key: cabi.String,
    value: cabi.String,
};

const Event = extern struct {
    code: cabi.String,
    name: cabi.String,
    dtstart: u64,
    dtend: u64,
    location: cabi.String,
    properties: cabi.List(KV),
};

const ParseResult = extern struct {
    events: cabi.List(Event),
    src: cabi.String,

    fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        // we share the same properties for all events (lol)
        for (self.events.toSlice()) |event| {
            allocator.free(event.properties.toSlice());
            break;
        }
        allocator.free(self.events.toSlice());
        allocator.free(self.src.toSlice());
    }
};

fn cabiPostParse(res: *ParseResult) callconv(.c) void {
    res.deinit(cabi.allocator);
    cabi.allocator.destroy(res);
    std.debug.assert(!cabi.gpa.detectLeaks());
}

fn cabiParse(ptr: [*]u8, len: usize) callconv(.c) *ParseResult {
    const src = ptr[0..len];
    var res = cabi.allocator.create(ParseResult) catch |err| cabi.oom(err);
    res.src = .fromSlice(src);
    res.events = .fromSlice(parse(cabi.allocator, src) catch |err| switch (err) {
        error.OutOfMemory => cabi.oom(error.OutOfMemory),
    });
    return res;
}

fn parse(allocator: std.mem.Allocator, src: []u8) ![]Event {
    var it = std.mem.tokenizeScalar(u8, src, '\n');

    var arr: std.ArrayList(Event) = .init(allocator);
    while (it.next()) |line| {
        const row = parseRow(allocator, line) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        defer allocator.free(row.weeks);
        if (row.weeks.len == 0) continue;

        const epoch = guessEpoch(row.weeks, row.year, row.semester);
        log.info("epoch {} {}", .{ row.year, epoch });
        for (0.., row.weeks) |i, w_opt| if (w_opt) |_| {
            try arr.append(.{
                .code = .fromSlice(row.code),
                .name = .fromSlice(row.name),
                .dtstart = epoch + i * std.time.s_per_week + (row.weekday - 2) * std.time.s_per_day + row.start_sec,
                .dtend = epoch + i * std.time.s_per_week + (row.weekday - 2) * std.time.s_per_day + row.end_sec,
                .location = .fromSlice(row.location),
                .properties = .fromSlice(row.properties),
            });
        };
    }
    return try arr.toOwnedSlice();
}

const Week = std.math.IntFittingRange(0, 53);

const Row = struct {
    year: u32,
    semester: u32,
    code: []const u8,
    name: []const u8,
    weekday: u32,
    start_sec: u32,
    end_sec: u32,
    location: []const u8,
    weeks: []?Week,
    properties: []KV,
};

inline fn appendKV(properties: *std.ArrayList(KV), key: []const u8, value: []const u8) void {
    properties.appendAssumeCapacity(.{ .key = .fromSlice(key), .value = .fromSlice(value) });
}

// 20232 \t MT1005 \t Giải tích 2 \t 4 \t 4 \t L18 \t 6 \t 7 - 10 \t 12:00 - 14:50 \t H3-301 \t BK-DAn \t 02|03|04|05|--|--|08|09|10|--|--|--|--|--|16|17|18|19|20|21|22|23|
fn parseRow(allocator: std.mem.Allocator, src: []const u8) !Row {
    const n_cols = std.mem.count(u8, src, "\t") + 1;
    if (n_cols != 12) return error.ParseError;

    log.debug("parse row: {s}", .{src});

    var properties: std.ArrayList(KV) = try .initCapacity(allocator, 12);
    errdefer properties.deinit();

    var cols_it = std.mem.tokenizeScalar(u8, src, '\t');

    const year, const semester = blk: {
        const col = cols_it.next().?;
        errdefer log.err("failed to parse semester: {s}", .{col});

        appendKV(&properties, "học kỳ", col);

        if (col.len != 5) return error.ParseError;

        break :blk .{
            try std.fmt.parseInt(u32, col[0..4], 10),
            try std.fmt.parseInt(u32, col[4..5], 10),
        };
    };

    const code = cols_it.next().?;
    appendKV(&properties, "mã môn học", code);

    const name = cols_it.next().?;
    appendKV(&properties, "tên môn học", name);

    appendKV(&properties, "tín chỉ", cols_it.next().?);
    appendKV(&properties, "tc học phí", cols_it.next().?);
    appendKV(&properties, "nhóm - tổ", cols_it.next().?);

    const weekday = blk: {
        const col = cols_it.next().?;
        errdefer log.err("failed to parse weekday: {s}", .{col});

        appendKV(&properties, "thứ", col);

        break :blk try std.fmt.parseInt(u32, col, 10);
    };

    appendKV(&properties, "tiết", cols_it.next().?);

    const start_hour, const start_minute, const end_hour, const end_minute = blk: {
        const col = cols_it.next().?;
        errdefer log.err("failed to parse time: {s}", .{col});

        appendKV(&properties, "giờ học", col);

        var col_it = std.mem.tokenizeAny(u8, col, " :-");
        break :blk .{
            try std.fmt.parseInt(u32, col_it.next() orelse return error.ParseError, 10),
            try std.fmt.parseInt(u32, col_it.next() orelse return error.ParseError, 10),
            try std.fmt.parseInt(u32, col_it.next() orelse return error.ParseError, 10),
            try std.fmt.parseInt(u32, col_it.next() orelse return error.ParseError, 10),
        };
    };

    const location = cols_it.next().?;
    appendKV(&properties, "phòng", location);

    appendKV(&properties, "cơ sở", cols_it.next().?);

    var weeks = blk: {
        const col = cols_it.next().?;
        errdefer log.err("failed to parse weeks: {s}", .{col});

        appendKV(&properties, "tuần học", col);

        var weeks: std.ArrayList(?Week) = try .initCapacity(allocator, 20);
        errdefer weeks.deinit();

        var weeks_it = std.mem.tokenizeScalar(u8, col, '|');
        while (weeks_it.next()) |token| {
            errdefer log.err("failed to parse week: {s}", .{token});
            const week: ?Week = if (std.mem.eql(u8, token, "--"))
                null
            else
                try std.fmt.parseUnsigned(Week, token, 10);
            try weeks.append(week);
        }

        break :blk weeks;
    };

    return Row{
        .year = year,
        .semester = semester,
        .code = code,
        .name = name,
        .weekday = weekday,
        .start_sec = start_hour * std.time.s_per_hour + start_minute * std.time.s_per_min,
        .end_sec = end_hour * std.time.s_per_hour + end_minute * std.time.s_per_min,
        .location = location,
        .weeks = try weeks.toOwnedSlice(),
        .properties = try properties.toOwnedSlice(),
    };
}

fn guessEpoch(weeks: []?Week, year: u32, semester: u32) u64 {
    const index0: ?Week, const week1: ?usize = blk: {
        var index0: ?Week = null;
        for (0.., weeks) |i, w_opt| {
            const w = w_opt orelse continue;
            // for example, week 2 at index 2 means new year's at index 1
            if (w <= i) {
                break :blk .{ null, i - w + 1 };
            } else {
                index0 = @intCast(w - i);
            }
        }
        break :blk .{ index0, null };
    };

    // if we have a year break, work backwards from the year break
    if (week1) |i|
        return cabiEpoch(year + 1) -| i * std.time.s_per_week;

    //if we don't, base on the semester to guess the start year
    const index0_year = if (semester == 1 or (semester == 2 and index0.? >= 26))
        year
    else
        year + 1;

    return cabiEpoch(index0_year) + (@as(u64, @intCast(index0.?)) - 1) * std.time.s_per_week;
}

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logFn,
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(cabi.allocator, "[{s}] " ++ format, .{@tagName(scope)} ++ args) catch return;
    defer cabi.allocator.free(msg);
    console.log(level, msg);
}

pub const Panic = struct {
    pub fn call(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
        @branchHint(.cold);
        log.err("{s}", .{msg});
        @trap();
    }
    pub const sentinelMismatch = std.debug.FormattedPanic.sentinelMismatch;
    pub const unwrapError = std.debug.FormattedPanic.unwrapError;
    pub const outOfBounds = std.debug.FormattedPanic.outOfBounds;
    pub const startGreaterThanEnd = std.debug.FormattedPanic.startGreaterThanEnd;
    pub const inactiveUnionField = std.debug.FormattedPanic.inactiveUnionField;
    pub const messages = std.debug.FormattedPanic.messages;
};
