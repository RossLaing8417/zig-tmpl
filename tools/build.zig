const std = @import("std");

const Tmpl = @This();

const PathList = std.ArrayList([]const u8);
const PathBuffer = std.BoundedArray(u8, std.fs.max_path_bytes);

const Options = struct {
    extentions: []const []const u8 = &[_][]const u8{ ".tmpl", ".zhtml" },
    search_paths: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn build(b: *std.Build, compile: *std.Build.Step.Compile, options: Options) void {
    _build(b, compile, options) catch |err| @panic(@errorName(err));
}

fn _build(b: *std.Build, compile: *std.Build.Step.Compile, options: Options) !void {
    var template_paths = PathList.init(b.allocator);
    defer template_paths.deinit();

    const cwd = std.fs.cwd();

    var path_buffer = try PathBuffer.init(0);

    for (options.search_paths) |sub_path| {
        try path_buffer.resize(0);
        try path_buffer.appendSlice(sub_path);

        var root_dir = try cwd.openDir(sub_path, .{ .iterate = true });
        defer root_dir.close();

        try recurseDirectory(b, &template_paths, &root_dir, &path_buffer, options.extentions);
    }

    const tmpl_parser = b.addExecutable(.{
        .name = "tmpl_parser",
        .root_source_file = b.path("tools/tmpl_parser.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    var source_buffer = std.ArrayList(u8).init(b.allocator);
    defer source_buffer.deinit();

    for (template_paths.items) |path| {
        try path_buffer.resize(0);
        try path_buffer.appendSlice(path);
        try path_buffer.appendSlice(".zig");

        const step = b.addRunArtifact(tmpl_parser);
        step.addFileArg(b.path(path));
        const output = step.addOutputFileArg(path_buffer.slice());

        const len = path_buffer.len;

        try path_buffer.appendSlice("tmpl.");
        try path_buffer.appendSlice(path[0 .. std.mem.lastIndexOfScalar(u8, path, '.') orelse path.len]);

        std.mem.replaceScalar(u8, path_buffer.slice(), '/', '.');
        std.mem.replaceScalar(u8, path_buffer.slice(), '\\', '.');

        compile.root_module.addAnonymousImport(path_buffer.slice()[len..], .{
            .root_source_file = output,
            .target = options.target,
            .optimize = options.optimize,
        });
    }
}

fn recurseDirectory(b: *std.Build, paths: *PathList, parent_dir: *std.fs.Dir, path_buffer: *PathBuffer, extentions: []const []const u8) !void {
    var itr = parent_dir.iterate();

    const length = path_buffer.len;

    while (try itr.next()) |entry| {
        switch (entry.kind) {
            .file => {
                for (extentions) |ext| {
                    if (std.mem.endsWith(u8, entry.name, ext)) {
                        try path_buffer.resize(length);
                        try path_buffer.append('/');
                        try path_buffer.appendSlice(entry.name);

                        try paths.append(b.dupe(path_buffer.slice()));
                    }
                }
            },
            .directory => {
                var dir = try parent_dir.openDir(entry.name, .{ .iterate = true });
                defer dir.close();

                try path_buffer.resize(length);
                try path_buffer.append('/');
                try path_buffer.appendSlice(entry.name);

                try recurseDirectory(b, paths, &dir, path_buffer, extentions);
            },
            else => {},
        }
    }
}
