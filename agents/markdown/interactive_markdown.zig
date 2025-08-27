//! Interactive Markdown Preview and Editing System
//! Uses the Enhanced Markdown Editor for rich editing experience

const std = @import("std");
const Allocator = std.mem.Allocator;
const enhanced_editor = @import("enhanced_markdown_editor");
const agent_interface = @import("agent_interface");

// Editor configuration
pub const EditorConfig = struct {
    enable_live_preview: bool = true,
    enable_syntax_highlight: bool = true,
    enable_word_wrap: bool = true,
    tab_size: u8 = 4,
    auto_save: bool = false,
    show_line_numbers: bool = true,
    split_position: f32 = 0.5,
    auto_save_interval: u32 = 30,
    max_preview_width: usize = 80,
    enable_mouse: bool = true,
    enable_hyperlinks: bool = true,
    theme: []const u8 = "default",
};

// Launch the interactive markdown editor
pub fn launchInteractiveEditor(
    allocator: Allocator,
    file_path: ?[]const u8,
    config: EditorConfig,
) !void {
    // Create a basic agent interface for the editor
    const agent_config = agent_interface.Config{
        .base_config = .{
            .agent_info = .{
                .name = "Markdown Editor",
                .version = "1.0.0",
                .description = "Interactive Markdown Editor",
                .author = "DocZ",
            },
            .defaults = .{
                .max_concurrent_operations = 1,
                .default_timeout_ms = 30000,
                .enable_debug_logging = false,
                .enable_verbose_output = false,
            },
            .features = .{
                .enable_custom_tools = true,
                .enable_file_operations = true,
                .enable_network_access = false,
                .enable_system_commands = false,
            },
            .limits = .{
                .max_input_size = 1048576,
                .max_output_size = 1048576,
                .max_processing_time_ms = 60000,
            },
            .model = .{
                .default_model = "claude-3-sonnet-20240229",
                .max_tokens = 4096,
                .temperature = 0.7,
                .stream_responses = true,
            },
        },
        .ui_settings = .{
            .enable_dashboard = false,
            .enable_mouse = config.enable_mouse,
            .enable_graphics = true,
            .enable_notifications = true,
            .enable_command_palette = true,
            .enable_animations = true,
            .theme = config.theme,
            .render_quality = .auto,
            .layout_mode = .adaptive,
        },
        .session_settings = .{
            .enable_persistence = true,
            .session_dir = "~/.docz/markdown-sessions",
            .auto_save_interval = config.auto_save_interval,
            .max_sessions = 10,
            .encrypt_sessions = false,
        },
        .interactive_features = .{
            .enable_chat = false,
            .enable_history = true,
            .enable_autocomplete = true,
            .enable_syntax_highlighting = config.enable_syntax_highlight,
            .enable_inline_docs = true,
            .enable_quick_actions = true,
        },
        .performance = .{
            .render_buffer_size = 8192,
        },
    };

    // Create the agent interface
    const agent = try agent_interface.createAgent(allocator, agent_config);
    defer agent.deinit();

    // If a file path is provided, load it
    if (file_path) |path| {
        // Create editor instance
        const editor = try enhanced_editor.EnhancedMarkdownEditor.init(allocator, agent, .{
            .base_config = agent_config,
            .editor_settings = .{
                .syntax_highlighting = config.enable_syntax_highlight,
                .auto_complete = true,
                .smart_indent = true,
                .tab_size = config.tab_size,
                .word_wrap = config.enable_word_wrap,
                .multi_cursor = false,
                .auto_save_interval = if (config.auto_save) config.auto_save_interval else 0,
            },
            .preview_settings = .{
                .live_preview = config.enable_live_preview,
                .update_delay_ms = 300,
                .enable_mermaid = false,
                .enable_math = false,
                .code_highlighting = config.enable_syntax_highlight,
            },
            .export_settings = .{
                .default_format = .markdown,
                .include_toc = true,
                .include_metadata = true,
            },
            .session_settings = .{
                .max_undo_history = 100,
                .enable_recovery = true,
                .backup_interval_s = 60,
                .max_recent_files = 10,
            },
        });
        defer editor.deinit();

        // Load the file
        try editor.loadFile(path);

        // Run the editor
        try editor.run();
    } else {
        // Create new document
        const editor = try enhanced_editor.EnhancedMarkdownEditor.init(allocator, agent, .{
            .base_config = agent_config,
            .editor_settings = .{
                .syntax_highlighting = config.enable_syntax_highlight,
                .auto_complete = true,
                .smart_indent = true,
                .tab_size = config.tab_size,
                .word_wrap = config.enable_word_wrap,
                .multi_cursor = false,
                .auto_save_interval = if (config.auto_save) config.auto_save_interval else 0,
            },
            .preview_settings = .{
                .live_preview = config.enable_live_preview,
                .update_delay_ms = 300,
                .enable_mermaid = false,
                .enable_math = false,
                .code_highlighting = config.enable_syntax_highlight,
            },
            .export_settings = .{
                .default_format = .markdown,
                .include_toc = true,
                .include_metadata = true,
            },
            .session_settings = .{
                .max_undo_history = 100,
                .enable_recovery = true,
                .backup_interval_s = 60,
                .max_recent_files = 10,
            },
        });
        defer editor.deinit();

        // Run the editor with empty document
        try editor.run();
    }
}
