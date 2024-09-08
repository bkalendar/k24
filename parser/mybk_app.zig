const std = @import("std");

extern "host" fn beginCalendar() void;
extern "host" fn endCalendar() void;

extern "host" fn beginRecurrence() void;
extern "host" fn doRecurrence(year: u16, week: u8, weekday: u8) void;
extern "host" fn endRecurrence() void;

extern "host" fn endEvent() void;
extern "host" fn discardEvent() void;
extern "host" fn log(ptr: [*]const u8, size: usize) void;

/// Get UTC year:week:weekday UNIX time.
///
/// Year 2038 problem goes brrr.
extern "host" fn getUTC(year: u16, week: u8, weekday: u8) u32;

const wa = std.heap.wasm_allocator;

export fn alloc(size: usize) [*]u8 {
    return @ptrCast(wa.alloc(u8, size) catch null);
}

export fn parse(ptr: [*]const u8, size: usize) void {
    const buf = ptr[0..size];
    defer wa.free(buf);

    beginCalendar();
    var tokenizer = std.mem.tokenizeAny(u8, buf, "\r\n");
    while (tokenizer.next()) |line| {
        if (std.mem.count(u8, line, "\t") != comptime std.mem.count(u8, "HỌC KỲ\tMÃ MH\tTÊN MÔN HỌC\tTÍN CHỈ\tTC HỌC PHÍ\tNHÓM - TỔ\tTHỨ\tTIẾT\tGIỜ HỌC\tPHÒNG\tCƠ SỞ\tTUẦN HỌC", "\t"))
            continue;
        _ = parseEntry(wa, line) catch unreachable;
    }
    endCalendar();
}

const Error = error{
    ParseFailed,
    OutOfMemory,
};

const Semester = struct {
    year: u16,
    semester: u8,
};

const Entry = struct {
    sem: Semester,
    date_spec: DateSpec,
    time_spec: TimeSpec,
    @"ma mh": []const u8,
    @"ten mon hoc": []const u8,
    @"tin chi": []const u8,
    @"tc hoc phi": []const u8,
    @"nhom - to": []const u8,
    @"ma phong": []const u8,
    @"co so": []const u8,
};

fn parseEntry(allocator: std.mem.Allocator, line: []const u8) Error!?Entry {
    var tokenizer = std.mem.tokenizeScalar(u8, line, '\t');

    var entry: Entry = undefined;
    entry.sem = try parseSemester(tokenizer.next().?);
    entry.@"ma mh" = tokenizer.next().?;
    entry.@"ten mon hoc" = tokenizer.next().?;
    entry.@"tin chi" = tokenizer.next().?;
    entry.@"tc hoc phi" = tokenizer.next().?;
    entry.@"nhom - to" = tokenizer.next().?;
    const weekday = try parseWeekday(tokenizer.next().?);
    _ = tokenizer.next().?;
    entry.time_spec = try parseTime(tokenizer.next().?);
    entry.@"ma phong" = tokenizer.next().?;
    entry.@"co so" = tokenizer.next().?;
    const weeks = try parseWeeks(allocator, tokenizer.next().?);
    entry.date_spec = DateSpec.init(entry.sem, weekday, weeks) orelse {
        return null;
    };

    return entry;
}

/// 5-digit semester code, starting with 20---
fn parseSemester(src: []const u8) !Semester {
    var res: Semester = undefined;
    if (src.len != 5)
        return Error.ParseFailed;
    res.year = try parseInt(u16, src[0..4]);
    res.semester = try parseInt(u8, src[4..5]);
    return res;
}

fn parseWeekday(src: []const u8) !u8 {
    if (src.len == 0 or src.len > 2)
        return Error.ParseFailed;

    if (src.len == 2) {
        if (std.mem.eql(u8, src, "CN")) {
            return 8;
        } else {
            return Error.ParseFailed;
        }
    }

    std.debug.assert(src.len == 1);
    return try parseInt(u8, src);
}

const TimeSpec = struct {
    hour: u8,
    minute: u8,
    s_duration: u16,
};

fn parseTime(src: []const u8) !TimeSpec {
    var nums: [4]i16 = undefined;
    var tokenizer = std.mem.tokenize(u8, src, ": -");
    for (&nums) |*num| {
        const field = tokenizer.next() orelse return Error.ParseFailed;
        if (field.len == 0 or field.len > 2) return Error.ParseFailed;
        num.* = try parseInt(i16, field);
    }

    return .{
        .hour = @intCast(nums[0]),
        .minute = @intCast(nums[1]),
        .s_duration = @intCast((nums[2] - nums[0]) * std.time.s_per_hour +
            (nums[3] - nums[1]) * std.time.s_per_min),
    };
}

fn parseWeeks(allocator: std.mem.Allocator, src: []const u8) !std.ArrayListUnmanaged(?u8) {
    var res = try std.ArrayListUnmanaged(?u8).initCapacity(allocator, 20);
    errdefer res.deinit(allocator);

    var tokenizer = std.mem.tokenizeScalar(u8, src, '|');
    while (tokenizer.next()) |week| {
        if (week.len != 2)
            return Error.ParseFailed;

        if (std.mem.allEqual(u8, week, '-')) {
            try res.append(allocator, null);
        } else {
            try res.append(allocator, try parseInt(u8, week));
        }
    }

    return res;
}

const DateSpec = struct {
    weeks: std.ArrayListUnmanaged(?u8),
    unix0: u32,

    pub fn init(sem: Semester, weekday: u8, weeks: std.ArrayListUnmanaged(?u8)) ?DateSpec {
        var spec = DateSpec{
            .weeks = weeks,
            .unix0 = undefined,
        };
        spec.resolveUnix0(sem, weekday) orelse return null;
        return spec;
    }

    pub fn deinit(self: *DateSpec, allocator: std.mem.Allocator) void {
        self.weeks.deinit(allocator);
    }

    fn resolveUnix0(self: *DateSpec, sem: Semester, weekday: u8) ?void {
        // Find week 1 and index 0 for semester to year conversion.
        //
        // For example:
        //
        // --|--|--|--|02|--|--|--
        //          ^^ we know week 01 should be here, so indexOfWeek1=3
        // ^^ we don't know the week at index 0
        //
        // --|33|--|--|--|--|38|--
        // ^^ we know week 32 should be at index 0, so weekOfIndex0=32
        //
        // --|--|49|--|--|--|--|--|--|03
        // ^^ weekOfIndex0=47   ^^ indexOfWeek1=7
        var index0: ?u8 = null;
        var week1: ?usize = null;
        for (0.., self.weeks.items) |i, week| {
            const w = week orelse continue;
            // for example, week 2 at index 2 means new year's at index 1
            if (w <= i) {
                week1 = i - w + 1;
                break;
            }

            // else, we should know what week is at index 0
            index0 = @intCast(w - i);
        }

        if (index0 == null and week1 == null)
            return null;

        // if we somehow have week 1, then it should be between year break
        if (week1) |w1| {
            self.unix0 = getUTC(sem.year + 1, 1, weekday) - w1 * std.time.s_per_week;
            return;
        }

        const idx0 = index0.?;

        // we don't have year break, it is guesswork from now on
        //
        // my heuristic is:
        //
        // - if semester == 1, it should start on year
        // - if semester == 2, which ever year index 0 closer to wins
        // - if semester == 3, it should start on (year + 1)
        //
        const year = switch (sem.semester) {
            1 => sem.year,
            2 => if (idx0 >= 26) sem.year else sem.year + 1,
            else => sem.year + 1,
        };

        self.unix0 = getUTC(year, idx0, weekday);
    }
};

fn parseInt(comptime T: type, buf: []const u8) !T {
    if (std.fmt.parseInt(T, buf, 10)) |parsed| {
        return parsed;
    } else |err| switch (err) {
        // T should be picked to avoid this
        error.Overflow => unreachable,
        error.InvalidCharacter => return Error.ParseFailed,
    }
}
