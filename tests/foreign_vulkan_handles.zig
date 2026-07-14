pub const InstanceOpaque = opaque {};
pub const SurfaceOpaque = opaque {};

pub const Instance = ?*InstanceOpaque;
pub const Surface = ?*SurfaceOpaque;

pub fn instanceFromAddress(address: usize) Instance {
    return @ptrFromInt(address);
}
