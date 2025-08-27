#!/bin/bash
# Insert the header strings array management before the for loop
sed -i '/for (req.headers) |header| {/i\
        var header_strings = std.ArrayList([]const u8).init(self.allocator);\
        defer {\
            for (header_strings.items) |header_str| {\
                self.allocator.free(header_str);\
            }\
            header_strings.deinit();\
        }' src/curl.zig

# Add the try statement to append the header string
sed -i '/header_list = c.curl_slist_append(header_list, header_str.ptr);/a\
            try header_strings.append(header_str);' src/curl.zig
