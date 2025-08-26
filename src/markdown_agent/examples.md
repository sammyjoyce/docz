# MarkDown Master - Usage Examples

This document demonstrates common usage patterns for the specialized markdown CLI agent, showcasing how the tools work together for complex document editing tasks.

## Example 1: Creating a Technical Documentation Site

### Initial Setup
```json
{
  "tool": "document_transformer", 
  "command": "create_from_template",
  "template_options": {
    "template_name": "documentation",
    "output_path": "/docs/api-reference.md",
    "template_variables": {
      "title": "API Reference Guide",
      "description": "Complete API documentation for the service",
      "version": "2.1.0"
    }
  }
}
```

### Adding Structured Content
```json
{
  "tool": "content_editor",
  "command": "add_section", 
  "file_path": "/docs/api-reference.md",
  "heading_text": "Authentication",
  "heading_level": 2,
  "location": "after_section:description"
}
```

### Inserting API Endpoint Table
```json
{
  "tool": "content_editor",
  "command": "create_table",
  "file_path": "/docs/api-reference.md", 
  "location": "after_section:authentication",
  "table_data": {
    "headers": ["Method", "Endpoint", "Description", "Auth Required"],
    "rows": [
      ["GET", "/api/users", "List all users", "Yes"],
      ["POST", "/api/users", "Create new user", "Yes"], 
      ["GET", "/api/users/{id}", "Get specific user", "Yes"]
    ],
    "alignment": ["center", "left", "left", "center"]
  }
}
```

### Generating Table of Contents
```json
{
  "tool": "content_editor",
  "command": "generate_toc",
  "file_path": "/docs/api-reference.md"
}
```

## Example 2: Refactoring a Long Academic Paper

### Analyzing Current Structure
```json
{
  "tool": "document_io", 
  "command": "get_workspace_tree",
  "directory_path": "/papers/"
}
```

### Moving Literature Review Section
```json
{
  "tool": "content_editor",
  "command": "move_section",
  "file_path": "/papers/research-paper.md",
  "heading_text": "Literature Review", 
  "location": "after_section:introduction"
}
```

### Batch Find-Replace for Terminology Updates
```json
{
  "tool": "content_editor",
  "command": "batch_replace",
  "file_path": "/papers/research-paper.md",
  "batch_operations": [
    {
      "search": "machine learning algorithm",
      "replace": "ML algorithm", 
      "is_regex": false
    },
    {
      "search": "artificial intelligence", 
      "replace": "AI",
      "is_regex": false
    },
    {
      "search": "\\bcitation\\s+\\((\\d{4})\\)", 
      "replace": "citation [@author$1]",
      "is_regex": true
    }
  ]
}
```

### Validating Citations and Links
```json
{
  "tool": "document_validator",
  "command": "validate_links", 
  "file_paths": ["/papers/research-paper.md"]
}
```

### Academic Formatting Validation
```json
{
  "tool": "document_validator",
  "command": "full_validation",
  "file_paths": ["/papers/research-paper.md"],
  "output_format": "markdown"
}
```

## Example 3: Multi-Document Blog Series Management  

### Creating Consistent Blog Post Structure
```json
{
  "tool": "document_transformer",
  "command": "create_from_template", 
  "template_options": {
    "template_name": "blog_post",
    "output_path": "/blog/part-1-getting-started.md",
    "template_variables": {
      "title": "Getting Started with Advanced Markdown - Part 1",
      "author": "Technical Writer",
      "categories": ["Tutorial", "Documentation"],
      "tags": ["markdown", "writing", "tools"],
      "excerpt": "Learn the foundations of professional markdown writing"
    }
  }
}
```

### Adding Navigation Links Between Posts
```json
{
  "tool": "document_validator",
  "command": "add_link",
  "file_paths": ["/blog/part-1-getting-started.md"],
  "link_validation": {
    "link_text": "Next: Advanced Formatting Techniques",
    "target_url": "./part-2-advanced-formatting.md"
  }
}
```

### Synchronizing Metadata Across Series
```json
{
  "tool": "content_editor",
  "command": "update_metadata",
  "file_path": "/blog/part-1-getting-started.md",
  "metadata_updates": {
    "series": "Advanced Markdown Guide",
    "part": 1,
    "total_parts": 5,
    "last_updated": "2024-01-15"
  }
}
```

## Example 4: Converting Documentation Formats

### Converting to HTML with Custom Styling
```json
{
  "tool": "document_transformer",
  "command": "to_html",
  "conversion_options": {
    "input_path": "/docs/user-manual.md",
    "output_path": "/dist/user-manual.html",
    "preserve_metadata": true
  },
  "style_options": {
    "theme": "professional",
    "include_toc": true,
    "syntax_highlighting": true
  }
}
```

### Generating PDF for Distribution
```json
{
  "tool": "document_transformer", 
  "command": "to_pdf",
  "conversion_options": {
    "input_path": "/docs/user-manual.md",
    "output_path": "/dist/user-manual.pdf"
  },
  "pdf_options": {
    "page_size": "A4",
    "margin": "1in", 
    "include_page_numbers": true,
    "header_footer": true
  }
}
```

## Example 5: Large Document Quality Assurance

### Comprehensive Document Health Check
```json
{
  "tool": "document_validator",
  "command": "full_validation",
  "file_paths": [
    "/docs/api-guide.md",
    "/docs/user-manual.md", 
    "/docs/troubleshooting.md"
  ],
  "output_format": "json"
}
```

### Fixing Formatting Issues in Bulk
```json
{
  "tool": "content_editor",
  "command": "normalize_markdown",
  "file_path": "/docs/api-guide.md",
  "formatting_options": {
    "normalization_rules": [
      "whitespace",
      "heading_spacing", 
      "list_indentation",
      "code_fence_languages",
      "table_alignment"
    ]
  }
}
```

### Standardizing Table Formats
```json
{
  "tool": "content_editor",
  "command": "format_table",
  "file_path": "/docs/api-guide.md",
  "scope": "section:parameters",
  "table_data": {
    "alignment": ["left", "center", "left", "right"]
  }
}
```

## Example 6: Working with Complex Tables

### Creating Parameter Documentation Table
```json
{
  "tool": "content_editor",
  "command": "create_table",
  "file_path": "/api-docs/endpoints.md",
  "location": "after_section:request-parameters",
  "table_data": {
    "headers": ["Parameter", "Type", "Required", "Default", "Description"],
    "rows": [
      ["user_id", "integer", "Yes", "-", "Unique identifier for the user"],
      ["include_profile", "boolean", "No", "false", "Include full profile data"],
      ["format", "string", "No", "json", "Response format (json, xml)"]
    ]
  }
}
```

### Adding New Parameter Row
```json
{
  "tool": "content_editor", 
  "command": "add_table_row",
  "file_path": "/api-docs/endpoints.md",
  "scope": "section:request-parameters",
  "table_data": {
    "row_index": -1,
    "rows": [["limit", "integer", "No", "10", "Maximum number of results"]]
  }
}
```

### Updating Cell Content
```json
{
  "tool": "content_editor",
  "command": "update_table_cell",
  "file_path": "/api-docs/endpoints.md", 
  "scope": "section:request-parameters",
  "table_data": {
    "row_index": 1,
    "column_index": 4,
    "cell_content": "Whether to include complete user profile information"
  }
}
```

## Common Workflow Patterns

### 1. Document Creation Workflow
1. `document_transformer` → Create from template
2. `content_editor` → Add/organize sections  
3. `content_editor` → Insert main content
4. `content_editor` → Add structured data
5. `document_validator` → Add references
6. `document_validator` → Quality check

### 2. Document Refactoring Workflow  
1. `document_io` → Analyze current structure
2. `content_editor` → Reorganize sections
3. `content_editor` → Update/move content blocks
4. `content_editor` → Normalize formatting
5. `document_validator` → Update references
6. `document_validator` → Validate changes

### 3. Multi-Document Management
1. `document_transformer` → Standardize structure
2. `content_editor` → Sync metadata  
3. `document_validator` → Cross-document references
4. `content_editor` → Consistent updates
5. `document_validator` → Batch quality checks

### 4. Publishing Preparation
1. `document_validator` → Final quality check
2. `content_editor` → Final formatting pass
3. `content_editor` → Generate final TOC
4. `content_editor` → Update publication metadata
5. `document_transformer` → Export to target formats

These examples demonstrate how the specialized tools work together to handle complex markdown document workflows efficiently while maintaining quality and consistency.