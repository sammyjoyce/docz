#!/usr/bin/env python3
import re

# Read the file
with open('src/curl.zig', 'r') as f:
    lines = f.readlines()

# Find the line with "defer if (header_list)"
for i, line in enumerate(lines):
    if 'defer if (header_list)' in line:
        # Insert header_strings management after this line
        lines.insert(i + 1, '\n')
        lines.insert(i + 2, '        var header_strings = std.ArrayList([]const u8).init(self.allocator);\n')
        lines.insert(i + 3, '        defer {\n')
        lines.insert(i + 4, '            for (header_strings.items) |header_str| {\n')
        lines.insert(i + 5, '                self.allocator.free(header_str);\n')
        lines.insert(i + 6, '            }\n')
        lines.insert(i + 7, '            header_strings.deinit();\n')
        lines.insert(i + 8, '        }\n')
        break

# Find the line with "header_list = c.curl_slist_append"
for i, line in enumerate(lines):
    if 'header_list = c.curl_slist_append' in line:
        # Insert try header_strings.append before this line
        lines.insert(i, '            try header_strings.append(header_str);\n')
        break

# Write back
with open('src/curl.zig', 'w') as f:
    f.writelines(lines)

print('Header management fixed successfully')
