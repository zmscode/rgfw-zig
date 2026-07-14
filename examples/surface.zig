const software = @import("support/software.zig");

pub fn main() !void {
    try software.run("RGFW software surface", software.gradient);
}
