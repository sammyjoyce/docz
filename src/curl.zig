//! Libcurl-based HTTP client for Zig 0.15.1
//! Provides reliable HTTP/HTTPS with modern TLS support

const std = @import("std");

const c = @cImport({
    @cInclude("stddef.h");
    @cInclude("curl/curl.h");
});

pub const HttpError = error{
    CurlInit,
    CurlPerform,
    InvalidResponse,
    OutOfMemory,
    NetworkError,
    HttpError,
    TlsError,
    Timeout,
    InvalidUrl,
    Aborted,
};

pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const HttpRequest = struct {
    method: HttpMethod = .GET,
    url: []const u8,
    headers: []const Header = &[_]Header{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000, // 30 second default timeout
    follow_redirects: bool = false,
    max_redirects: u32 = 5,
    verify_ssl: bool = true,
    verbose: bool = false,
};

pub const HttpResponse = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *HttpResponse) void {
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.allocator.free(self.body);
    }
};

pub const StreamCallback = *const fn (chunk: []const u8, context: *anyopaque) void;

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    curl_handle: ?*c.CURL = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !HttpClient {
        // Initialize libcurl globally once
        const curl_init_result = c.curl_global_init(c.CURL_GLOBAL_ALL);
        if (curl_init_result != c.CURLE_OK) {
            return HttpError.CurlInit;
        }

        return HttpClient{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.curl_handle) |handle| {
            c.curl_easy_cleanup(handle);
        }
        c.curl_global_cleanup();
    }

    pub fn request(self: *Self, req: HttpRequest) !HttpResponse {
        // Create curl handle
        const handle = c.curl_easy_init() orelse return HttpError.CurlInit;
        defer c.curl_easy_cleanup(handle);

        // Response data collectors
        var response_body = std.ArrayListUnmanaged(u8){};
        defer response_body.deinit(self.allocator); // Will be moved to HttpResponse

        var response_headers = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            var iter = response_headers.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            response_headers.deinit();
        }

        // Configure URL
        _ = c.curl_easy_setopt(handle, c.CURLOPT_URL, req.url.ptr);

        // Configure HTTP method
        switch (req.method) {
            .GET => {
                _ = c.curl_easy_setopt(handle, c.CURLOPT_HTTPGET, @as(c_long, 1));
            },
            .POST => {
                _ = c.curl_easy_setopt(handle, c.CURLOPT_POST, @as(c_long, 1));
                if (req.body) |body| {
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDS, body.ptr);
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
                }
            },
            .PUT => {
                _ = c.curl_easy_setopt(handle, c.CURLOPT_CUSTOMREQUEST, "PUT");
                if (req.body) |body| {
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDS, body.ptr);
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
                }
            },
            .DELETE => {
                _ = c.curl_easy_setopt(handle, c.CURLOPT_CUSTOMREQUEST, "DELETE");
            },
            .PATCH => {
                _ = c.curl_easy_setopt(handle, c.CURLOPT_CUSTOMREQUEST, "PATCH");
                if (req.body) |body| {
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDS, body.ptr);
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
                }
            },
        }

        // Configure headers
        var header_list: ?*c.curl_slist = null;
        defer if (header_list) |list| c.curl_slist_free_all(list);

        for (req.headers) |header| {
            const header_str = try std.fmt.allocPrint(self.allocator, "{s}: {s}\x00", .{ header.name, header.value });
            defer self.allocator.free(header_str);

            header_list = c.curl_slist_append(header_list, header_str.ptr);
        }

        if (header_list) |list| {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_HTTPHEADER, list);
        }

        // Configure SSL/TLS
        if (req.verify_ssl) {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2));
        } else {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 0));
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 0));
        }

        // Configure redirects
        if (req.follow_redirects) {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
            _ = c.curl_easy_setopt(handle, c.CURLOPT_MAXREDIRS, @as(c_long, @intCast(req.max_redirects)));
        }

        // Configure timeout
        _ = c.curl_easy_setopt(handle, c.CURLOPT_TIMEOUT_MS, @as(c_long, @intCast(req.timeout_ms)));
        _ = c.curl_easy_setopt(handle, c.CURLOPT_CONNECTTIMEOUT_MS, @as(c_long, 10000)); // 10s connect timeout

        // Configure verbose mode
        if (req.verbose) {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_VERBOSE, @as(c_long, 1));
        }

        // Set user agent
        _ = c.curl_easy_setopt(handle, c.CURLOPT_USERAGENT, "docz/1.0 (libcurl)");

        // Configure response body callback
        const BodyCallbackContext = struct {
            response_body: *std.ArrayListUnmanaged(u8),
            allocator: std.mem.Allocator,
        };

        const body_context = BodyCallbackContext{
            .response_body = &response_body,
            .allocator = self.allocator,
        };

        _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, writeCallback);
        _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, @as(*const anyopaque, @ptrCast(&body_context)));

        // Configure response header callback
        const HeaderCallbackContext = struct {
            headers: *std.StringHashMap([]const u8),
            allocator: std.mem.Allocator,
        };

        const header_context = HeaderCallbackContext{
            .headers = &response_headers,
            .allocator = self.allocator,
        };

        _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERFUNCTION, headerCallback);
        _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERDATA, @as(*const anyopaque, @ptrCast(&header_context)));

        // Perform request
        const result = c.curl_easy_perform(handle);
        if (result != c.CURLE_OK) {
            switch (result) {
                c.CURLE_COULDNT_CONNECT => return HttpError.NetworkError,
                c.CURLE_OPERATION_TIMEDOUT => return HttpError.Timeout,
                c.CURLE_SSL_CONNECT_ERROR => return HttpError.TlsError,
                c.CURLE_URL_MALFORMAT => return HttpError.InvalidUrl,
                c.CURLE_ABORTED_BY_CALLBACK => return HttpError.Aborted,
                else => return HttpError.CurlPerform,
            }
        }

        // Get response status code
        var status_code: c_long = 0;
        _ = c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &status_code);

        return HttpResponse{
            .status_code = @intCast(status_code),
            .headers = response_headers,
            .body = try response_body.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    pub fn streamRequest(
        self: *Self,
        req: HttpRequest,
        callback: StreamCallback,
        context: *anyopaque,
    ) !u16 {
        // Create curl handle
        const handle = c.curl_easy_init() orelse return HttpError.CurlInit;
        defer c.curl_easy_cleanup(handle);

        // Configure URL and method (same as regular request)
        _ = c.curl_easy_setopt(handle, c.CURLOPT_URL, req.url.ptr);

        switch (req.method) {
            .GET => {
                _ = c.curl_easy_setopt(handle, c.CURLOPT_HTTPGET, @as(c_long, 1));
            },
            .POST => {
                _ = c.curl_easy_setopt(handle, c.CURLOPT_POST, @as(c_long, 1));
                if (req.body) |body| {
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDS, body.ptr);
                    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
                }
            },
            else => {
                // Other methods not yet supported for streaming
                return HttpError.InvalidUrl;
            },
        }

        // Configure headers
        var header_list: ?*c.curl_slist = null;
        defer if (header_list) |list| c.curl_slist_free_all(list);

        for (req.headers) |header| {
            // Debug: Check header data
            if (header.value.len == 0) {
                return HttpError.InvalidUrl;
            }

            const header_str = try std.fmt.allocPrint(self.allocator, "{s}: {s}\x00", .{ header.name, header.value });

            header_list = c.curl_slist_append(header_list, header_str.ptr);
        }

        if (header_list) |list| {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_HTTPHEADER, list);
        }

        // Configure SSL/TLS, redirects, timeout (same as regular request)
        if (req.verify_ssl) {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2));
        } else {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 0));
            _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 0));
        }

        if (req.follow_redirects) {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
            _ = c.curl_easy_setopt(handle, c.CURLOPT_MAXREDIRS, @as(c_long, @intCast(req.max_redirects)));
        }

        _ = c.curl_easy_setopt(handle, c.CURLOPT_TIMEOUT_MS, @as(c_long, @intCast(req.timeout_ms)));
        _ = c.curl_easy_setopt(handle, c.CURLOPT_CONNECTTIMEOUT_MS, @as(c_long, 10000));
        _ = c.curl_easy_setopt(handle, c.CURLOPT_USERAGENT, "docz/1.0 (libcurl)");

        if (req.verbose) {
            _ = c.curl_easy_setopt(handle, c.CURLOPT_VERBOSE, @as(c_long, 1));
        }

        // Set streaming callback context
        const StreamCallbackContext = struct {
            callback: StreamCallback,
            context: *anyopaque,
        };

        const stream_context = StreamCallbackContext{
            .callback = callback,
            .context = context,
        };

        _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, streamWriteCallback);
        _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, @as(*const anyopaque, @ptrCast(&stream_context)));

        // Perform streaming request
        const result = c.curl_easy_perform(handle);
        if (result != c.CURLE_OK) {
            switch (result) {
                c.CURLE_COULDNT_CONNECT => return HttpError.NetworkError,
                c.CURLE_OPERATION_TIMEDOUT => return HttpError.Timeout,
                c.CURLE_SSL_CONNECT_ERROR => return HttpError.TlsError,
                c.CURLE_URL_MALFORMAT => return HttpError.InvalidUrl,
                c.CURLE_ABORTED_BY_CALLBACK => return HttpError.Aborted,
                else => return HttpError.CurlPerform,
            }
        }

        // Get response status code
        var status_code: c_long = 0;
        _ = c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &status_code);

        return @intCast(status_code);
    }

    // Convenience methods
    pub fn get(self: *Self, url: []const u8, headers: []const Header) !HttpResponse {
        return self.request(HttpRequest{
            .method = .GET,
            .url = url,
            .headers = headers,
        });
    }

    pub fn post(self: *Self, url: []const u8, headers: []const Header, body: ?[]const u8) !HttpResponse {
        return self.request(HttpRequest{
            .method = .POST,
            .url = url,
            .headers = headers,
            .body = body,
        });
    }
};

// libcurl callback for response body data
fn writeCallback(
    contents: [*c]u8,
    size: usize,
    nmemb: usize,
    user_data: ?*anyopaque,
) callconv(.c) usize {
    const real_size = size * nmemb;
    const BodyCallbackContext = struct {
        response_body: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
    };
    const context: *const BodyCallbackContext = @ptrCast(@alignCast(user_data.?));

    const data_slice = contents[0..real_size];
    context.response_body.appendSlice(context.allocator, data_slice) catch return 0; // Signal error by returning 0

    return real_size;
}

// libcurl callback for response headers
fn headerCallback(
    buffer: [*c]u8,
    size: usize,
    nitems: usize,
    user_data: ?*anyopaque,
) callconv(.c) usize {
    const real_size = size * nitems;
    const HeaderCallbackContext = struct {
        headers: *std.StringHashMap([]const u8),
        allocator: std.mem.Allocator,
    };
    const context: *const HeaderCallbackContext = @ptrCast(@alignCast(user_data.?));

    const header_slice = buffer[0..real_size];
    const header_str = std.mem.trim(u8, header_slice, " \t\r\n");

    if (header_str.len == 0) return real_size; // Skip empty headers

    // Parse "Name: Value" header format
    if (std.mem.indexOf(u8, header_str, ":")) |colon_pos| {
        const name = std.mem.trim(u8, header_str[0..colon_pos], " \t");
        const value = std.mem.trim(u8, header_str[colon_pos + 1 ..], " \t");

        // Store header (allocate owned strings)
        const owned_name = context.allocator.dupe(u8, name) catch return 0;
        const owned_value = context.allocator.dupe(u8, value) catch {
            context.allocator.free(owned_name);
            return 0;
        };

        context.headers.put(owned_name, owned_value) catch {
            context.allocator.free(owned_name);
            context.allocator.free(owned_value);
            return 0;
        };
    }

    return real_size;
}

// libcurl callback for streaming response data
fn streamWriteCallback(
    contents: [*c]u8,
    size: usize,
    nmemb: usize,
    user_data: ?*anyopaque,
) callconv(.c) usize {
    const real_size = size * nmemb;
    const StreamCallbackContext = struct {
        callback: StreamCallback,
        context: *anyopaque,
    };
    const context: *const StreamCallbackContext = @ptrCast(@alignCast(user_data.?));

    const data_slice = contents[0..real_size];
    context.callback(data_slice, context.context);

    return real_size;
}
